---
title: Kong API 网关深度解析
date: 2024-05-28
tags: 网关
categories: 后端
---

## 一、背景

做微服务架构的人，基本绕不开 API 网关这个东西。不管你用 Spring Cloud Gateway、Envoy 还是 Nginx 手搓，总得有个统一的入口把请求转发给后端服务。

Kong 是这个领域里做得最成熟的开源方案之一，GitHub 上 40K+ Stars，背后有商业公司维护，插件生态完善，大厂用得也多。但很多开发者对 Kong 的理解停留在"哦，就是个网关"这个层面，对其架构设计、插件系统、配置模式这些核心东西没深入过。

---

## 二、Kong 是什么

一句话定义：Kong 是一个基于 **Nginx + OpenResty（LuaJIT）** 的开源 API 网关，核心能力是**路由转发、认证鉴权、流量控制、可观测性**。

打个比方理解它的定位：

| 场景 | 没有网关 | 有了 Kong |
|------|---------|-----------|
| 10 个微服务都要做认证 | 每个服务自己实现一遍 | Kong 统一做，服务只管业务 |
| 要对某个接口限流 | 在代码里写限流逻辑 | Kong 配个插件就搞定 |
| 要记录所有请求日志 | 每个服务加日志代码 | Kong 统一采集，不影响业务 |
| 要做灰度发布 | 改代码或改 Nginx 配置 | Kong 按权重分流，配置即生效 |

核心区别在于：传统做法每个服务都要重复造轮子，Kong 把这些**横切关注点（Cross-Cutting Concerns）** 统一收口到网关层。

---

## 三、架构深度拆解

### 3.1 整体架构图

```
                    客户端请求
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                      Kong Gateway                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Nginx (反向代理层)                        │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │              OpenResty / LuaJIT                       │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │                Kong Core                              │   │
│  │  ┌───────────────────────────────────────────────┐   │   │
│  │  │           Plugin System (插件系统)              │   │   │
│  │  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐  │   │   │
│  │  │  │ 认证    │ │ 限流   │ │ 日志   │ │ 转换   │  │   │   │
│  │  │  └────────┘ └────────┘ └────────┘ └────────┘  │   │   │
│  │  └───────────────────────────────────────────────┘   │   │
│  ├─────────────────────────────────────────────────────┤   │
│  │              Admin API (管理接口)                      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │   数据存储层          │
              │  PostgreSQL /        │
              │  Cassandra / 声明式   │
              └─────────────────────┘
                        │
                        ▼
              ┌─────────────────────┐
              │   上游服务集群        │
              │  (User Service,     │
              │   Order Service...) │
              └─────────────────────┘
```

这个架构有几个关键点值得拆开说。

### 3.2 为什么是 Nginx + OpenResty

Kong 没有用 Java、没用 Go，选了 Lua 这个相对小众的语言，原因在于 **OpenResty**。

OpenResty 是 Nginx 的一个增强版，把 LuaJIT 嵌入到 Nginx 的请求处理生命周期里。这意味着：

1. **性能极高**：Nginx 本身就以高并发著称，LuaJIT 的执行速度接近 C
2. **非阻塞 I/O**：OpenResty 把所有网络操作都封装成非阻塞的，一个请求在等数据库返回的时候不会阻塞其他请求
3. **生命周期钩子**：Nginx 的各个处理阶段（rewrite、access、content、log）都能用 Lua 来扩展

Kong 本质上就是一个**用 Lua 写的、运行在 OpenResty 上的 Nginx 配置生成器 + 插件执行引擎**。

### 3.3 核心抽象模型

Kong 的配置管理围绕几个核心概念展开：

```
Consumer (消费者)
    │
    ├── 某个调用方的身份（API Key、JWT 等标识）
    │
    ▼
Route (路由)
    │
    ├── 匹配规则：路径、Host、HTTP Method
    ├── 一个 Service 可以挂多个 Route
    │
    ▼
Service (服务)
    │
    ├── 一个上游服务的抽象（URL、协议、超时配置）
    ├── 指向 Upstream
    │
    ▼
Upstream (上游)
    │
    ├── 一组 Target 的集合
    ├── 负载均衡策略、健康检查
    │
    ▼
Target (目标)
    │
    └── 具体的后端实例地址（IP:Port）
```

举个实际例子：

```yaml
# 定义一个服务
Service:
  name: user-service
  url: http://user-api.internal:8080

# 给这个服务定义路由
Route:
  name: user-route
  paths: ["/api/v1/users"]
  methods: ["GET", "POST"]
  service: user-service

# 给路由加认证插件
Plugin:
  name: key-auth
  route: user-route
```

这个模型的设计很清晰：**Service 是对后端服务的抽象，Route 是对请求匹配规则的抽象，Plugin 是对横切逻辑的抽象**。

### 3.4 请求生命周期

一个请求到达 Kong 之后，会经历这些阶段：

```
1. 客户端发送请求
   │
   ▼
2. SSL/TLS 握手（certificate 阶段）
   │  ← 这里可以执行 mTLS 插件
   ▼
3. URI 重写（rewrite 阶段）
   │  ← 这里可以执行 URL 重写插件
   ▼
4. 路由匹配
   │  ← Kong 根据 Host/Path/Method 找到对应的 Route
   ▼
5. 认证 & 鉴权（access 阶段）
   │  ← 执行 key-auth、jwt、oauth2 等插件
   ▼
6. 限流 & 配额（access 阶段）
   │  ← 执行 rate-limiting、quota 等插件
   ▼
7. 请求转换（access 阶段）
   │  ← 执行 request-transformer 插件
   ▼
8. 转发请求到上游服务
   │
   ▼
9. 接收上游响应
   │
   ▼
10. 响应头处理（header_filter 阶段）
    │  ← 执行 cors、response-transformer 等插件
    ▼
11. 响应体处理（body_filter 阶段）
    │  ← 可以修改响应内容
    ▼
12. 日志记录（log 阶段）
    │  ← 执行 tcp-log、http-log、file-log 等插件
    ▼
13. 返回响应给客户端
```

注意 **access 阶段**是核心，大部分插件都在这个阶段执行。每个插件有优先级（priority），priority 越高越先执行。

---

## 四、插件系统：Kong 的核心竞争力

插件系统是 Kong 区别于其他网关的最大优势。理解插件系统，才算真正理解 Kong。

### 4.1 插件的作用域

Kong 的插件不是全局一把梭，而是可以分层配置：

```
全局插件（Global Plugin）
    │
    ├── 对所有请求生效
    │
    ▼
服务级插件（Service-level Plugin）
    │
    ├── 对某个 Service 的所有请求生效
    │
    ▼
路由级插件（Route-level Plugin）
    │
    ├── 对匹配某个 Route 的请求生效
    │
    ▼
消费者级插件（Consumer-level Plugin）
    │
    └── 对某个 Consumer 的请求生效
```

这种分层设计很实用。比如：
- 全局开启 CORS 插件
- 对支付服务单独开启更严格的限流
- 对 VIP 消费者放宽配额限制

### 4.2 插件执行机制

每个插件本质上是一个 **Lua 模块**，实现了特定的钩子函数：

```lua
-- 一个最简单的 Kong 插件示例
local MyPlugin = {
  PRIORITY = 1000,  -- 优先级，越大越先执行
  VERSION = "1.0.0",
}

-- access 阶段执行的逻辑
function MyPlugin:access(conf)
  -- 从请求中获取某个 header
  local request_id = kong.request.get_header("X-Request-ID")
  
  if not request_id then
    -- 如果没有 request_id，直接返回 400
    return kong.response.exit(400, {
      message = "Missing X-Request-ID header"
    })
  end
  
  -- 把 request_id 传给上游服务
  kong.service.request.set_header("X-Request-ID", request_id)
end

return MyPlugin
```

Kong 提供了 **PDK（Plugin Development Kit）**，这是一组 Lua 函数，封装了所有常用操作：

| PDK 函数 | 用途 |
|---------|------|
| `kong.request.get_header()` | 获取请求头 |
| `kong.request.get_body()` | 获取请求体 |
| `kong.response.exit()` | 直接返回响应 |
| `kong.service.request.set_header()` | 修改转发给上游的请求头 |
| `kong.client.get_consumer()` | 获取当前消费者信息 |
| `kong.ip.get_source()` | 获取客户端真实 IP |

### 4.3 内置插件分类

Kong 的内置插件可以分成这几大类：

**认证类**

| 插件 | 说明 |
|------|------|
| key-auth | API Key 认证，最简单常用 |
| jwt | JWT Token 认证 |
| oauth2 | 完整的 OAuth 2.0 流程 |
| basic-auth | HTTP Basic 认证 |
| hmac-auth | HMAC 签名认证 |
| ldap-auth | LDAP 目录认证 |
| openid-connect | OIDC 认证（对接 Okta、Auth0 等） |
| mtls-auth | 双向 TLS 认证 |

**流量控制类**

| 插件 | 说明 |
|------|------|
| rate-limiting | 基于 IP/Consumer/Service 的速率限制 |
| request-size-limiting | 限制请求体大小 |
| proxy-cache | 响应缓存 |
| canary | 金丝雀发布，按权重分流 |

**转换类**

| 插件 | 说明 |
|------|------|
| request-transformer | 修改请求头、Body、URL 参数 |
| response-transformer | 修改响应头、Body |
| request-validator | JSON Schema 请求验证 |
| correlation-id | 生成请求唯一标识 |
| cors | 跨域配置 |

**可观测性类**

| 插件 | 说明 |
|------|------|
| prometheus | 暴露 Prometheus 指标 |
| datadog | 集成 Datadog APM |
| zipkin | 分布式链路追踪 |
| tcp-log | TCP 方式发送日志 |
| http-log | HTTP 方式发送日志 |
| file-log | 写入本地文件 |
| kafka-log | 发送到 Kafka |

### 4.4 插件开发实战

官方内置插件覆盖了大部分场景，但有时候你得写自己的插件。比如：给所有经过网关的请求加上公司内部的审计日志。

**目录结构**

```
kong-plugin-audit-log/
├── kong/
│   └── plugins/
│       └── audit-log/
│           ├── handler.lua    # 插件逻辑
│           └── schema.lua     # 配置校验
└── kong-plugin-audit-log-0.1.0-1.rockspec
```

**handler.lua - 插件主逻辑**

```lua
local AuditLog = {
  PRIORITY = 10,
  VERSION = "1.0.0",
}

function AuditLog:log(conf)
  -- 获取请求信息
  local request = {
    method = kong.request.get_method(),
    path = kong.request.get_path(),
    query = kong.request.get_raw_query(),
    headers = kong.request.get_headers(),
    client_ip = kong.client.get_ip(),
    consumer = kong.client.get_consumer(),
    service = kong.router.get_service(),
    response_status = kong.response.get_status(),
    request_id = kong.request.get_header("X-Request-ID"),
  }
  
  -- 序列化后发送到审计系统
  local cjson = require("cjson")
  local log_data = cjson.encode(request)
  
  -- 发送到 Kafka 或 HTTP 端点
  local http = require("resty.http")
  local httpc = http.new()
  httpc:request_uri(conf.audit_endpoint, {
    method = "POST",
    body = log_data,
    headers = {
      ["Content-Type"] = "application/json",
    },
  })
end

return AuditLog
```

**schema.lua - 配置校验**

```lua
return {
  name = "audit-log",
  fields = {
    { consumer = typedefs.no_consumer },
    { config = {
        type = "record",
        fields = {
          { audit_endpoint = { type = "string", required = true } },
          { include_headers = { type = "boolean", default = true } },
        },
      },
    },
  },
}
```

**安装插件**

```bash
# 打包
luarocks make

# 在 kong.conf 中启用
plugins = bundled,audit-log

# 或者通过环境变量
KONG_PLUGINS=bundled,audit-log
```

### 4.5 多语言插件支持

Lua 不是所有人都熟，Kong 后来加了 **External Plugins** 机制，支持用其他语言写插件：

| 语言 | 方式 | 说明 |
|------|------|------|
| Go | Go PDK | 通过 gRPC 和 Kong 通信 |
| Python | Python PDK | 同样走 gRPC |
| JavaScript | JS PDK | 同样走 gRPC |
| WebAssembly | WASM | 新一代扩展方式 |

原理是一样的：Kong 在插件执行阶段通过 gRPC 调用外部插件服务，外部服务处理完返回结果。性能比原生 Lua 插件差一点，但开发门槛低很多。

---

## 五、配置管理：三种模式

Kong 支持三种配置管理模式，适应不同的部署场景。

### 5.1 传统数据库模式（DB Mode）

```
Kong 节点 ──→ PostgreSQL / Cassandra
    │
    └── Admin API 操作配置
```

这是最经典的模式。所有配置（Service、Route、Plugin、Consumer）都存在数据库里，通过 Admin API 管理。

**优点**：
- 配置变更实时生效，不需要重启
- 多个 Kong 节点共享同一份配置
- 适合动态环境，服务频繁上下线

**缺点**：
- 依赖数据库，多了一个运维组件
- 数据库挂了 Kong 就废了（虽然有缓存，但配置变更就没了）

### 5.2 DB-less 声明式模式

```yaml
# kong.yml
_format_version: "3.0"

services:
  - name: user-service
    url: http://user-api:8080
    routes:
      - name: user-route
        paths: ["/api/users"]
    plugins:
      - name: key-auth
      - name: rate-limiting
        config:
          minute: 100
          policy: local

  - name: order-service
    url: http://order-api:8080
    routes:
      - name: order-route
        paths: ["/api/orders"]
```

启动时加载配置文件：

```bash
kong start -c kong.conf --declarative-config kong.yml
```

**优点**：
- 不需要数据库，部署更简单
- 配置即代码，可以 Git 管理
- 适合 GitOps、CI/CD 流程
- 适合 Kubernetes ConfigMap/Secret

**缺点**：
- 配置变更需要重新加载（不是重启，是 reload）
- 不支持 Consumer 的动态注册

### 5.3 混合模式（Hybrid Mode）

这是 Kong 比较新的部署模式，把控制平面和数据平面分离：

```
┌─────────────────────┐         ┌─────────────────────┐
│    Control Plane     │         │     Data Plane       │
│    (控制平面)         │         │     (数据平面)        │
│                      │         │                      │
│  ┌───────────────┐   │   mTLS   │   ┌───────────────┐  │
│  │  Admin API    │   │◄────────►│   │  Proxy Only   │  │
│  │  配置管理      │   │   同步    │   │  只做代理      │  │
│  └───────────────┘   │   配置    │   └───────────────┘  │
│                      │         │                      │
│  ┌───────────────┐   │         │   无 Admin API        │
│  │  PostgreSQL   │   │         │   无数据库             │
│  └───────────────┘   │         │                      │
└─────────────────────┘         └─────────────────────┘
```

**工作原理**：
1. 控制平面负责配置管理，连接数据库
2. 数据平面只做代理，不连数据库
3. 控制平面通过 mTLS 把配置推送到数据平面
4. 数据平面本地缓存配置，即使控制平面挂了也能继续工作

**优点**：
- 数据平面不暴露 Admin API，安全性更高
- 数据平面不需要数据库，部署更轻量
- 可以跨机房部署，控制平面集中管理
- 适合大规模微服务架构

**缺点**：
- 架构复杂度增加
- 需要管理 mTLS 证书

---

## 六、负载均衡与服务发现

### 6.1 负载均衡算法

Kong 支持多种负载均衡算法：

| 算法 | 说明 | 适用场景 |
|------|------|---------|
| round-robin | 轮询 | 通用场景，最常用 |
| consistent-hashing | 一致性哈希 | 需要会话保持的场景 |
| least-connections | 最少连接数 | 后端实例性能不均 |
| latency | 最低延迟 | 对延迟敏感的场景 |

**一致性哈希**特别值得说一下。它可以基于不同的维度做哈希：

```bash
# 基于 Consumer 做哈希，同一个消费者的请求总是打到同一个后端
curl -X POST http://localhost:8001/upstreams/my-upstream \
  --data name=my-upstream \
  --data hash_on=consumer

# 基于 IP 做哈希
curl -X POST http://localhost:8001/upstreams/my-upstream \
  --data name=my-upstream \
  --data hash_on=ip

# 基于某个 Header 做哈希
curl -X POST http://localhost:8001/upstreams/my-upstream \
  --data name=my-upstream \
  --data hash_on=header \
  --data hash_on_header=X-User-ID
```

### 6.2 健康检查

Kong 支持两种健康检查机制：

**主动检查（Active Health Checks）**

Kong 定期向后端实例发送探测请求：

```bash
curl -X POST http://localhost:8001/upstreams/my-upstream/healthcheck \
  --data active.healthy.interval=5 \
  --data active.unhealthy.interval=2 \
  --data active.http_path=/health \
  --data active.http_statuses=200,302
```

**被动检查（Passive Health Checks）**

基于实际请求的失败情况来判断后端是否健康（也叫熔断）：

```bash
curl -X POST http://localhost:8001/upstreams/my-upstream/healthcheck \
  --data passive.healthy.successes=5 \
  --data passive.unhealthy.tcp_failures=3 \
  --data passive.unhealthy.timeouts=3 \
  --data passive.unhealthy.http_failures=5
```

两种方式通常配合使用：主动检查发现故障，被动检查在故障发生时快速熔断。

### 6.3 服务发现

Kong 支持与服务发现系统集成：

| 方式 | 说明 |
|------|------|
| DNS SRV | 通过 DNS 记录发现服务 |
| Consul | 集成 HashiCorp Consul |
| Kubernetes | 直接使用 K8s Service 名称 |

Kubernetes 集成最常用。在 K8s 里，Kong 直接用 Service 名称做 upstream：

```yaml
services:
  - name: user-service
    url: http://user-service.default.svc.cluster.local:8080
```

Kong 会自动解析 K8s Service 的 ClusterIP，不需要手动维护后端实例列表。

---

## 七、实战：快速上手

### 7.1 Docker 一键启动

最简单的方式是用 Docker Compose：

```yaml
# docker-compose.yml
version: "3.8"

services:
  kong-database:
    image: postgres:15
    environment:
      POSTGRES_USER: kong
      POSTGRES_DB: kong
      POSTGRES_PASSWORD: kong
    volumes:
      - kong-db-data:/var/lib/postgresql/data

  kong-migrations:
    image: kong:3.6
    command: kong migrations bootstrap
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
    depends_on:
      - kong-database

  kong:
    image: kong:3.6
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
    ports:
      - "8000:8000"   # Proxy
      - "8443:8443"   # Proxy SSL
      - "8001:8001"   # Admin API
    depends_on:
      - kong-database
      - kong-migrations

volumes:
  kong-db-data:
```

启动：

```bash
docker-compose up -d
```

### 7.2 配置第一个 API

用 Admin API 注册一个服务和路由：

```bash
# 1. 创建服务
curl -X POST http://localhost:8001/services \
  --data "name=httpbin" \
  --data "url=https://httpbin.org"

# 2. 创建路由
curl -X POST http://localhost:8001/services/httpbin/routes \
  --data "name=httpbin-route" \
  --data "paths[]=/httpbin"

# 3. 测试
curl http://localhost:8000/httpbin/get
```

### 7.3 加上认证和限流

```bash
# 1. 启用 key-auth 插件
curl -X POST http://localhost:8001/services/httpbin/plugins \
  --data "name=key-auth"

# 2. 创建消费者
curl -X POST http://localhost:8001/consumers \
  --data "username=app-001"

# 3. 给消费者分配 API Key
curl -X POST http://localhost:8001/consumers/app-001/key-auth \
  --data "key=my-secret-api-key"

# 4. 测试（不带 Key）
curl http://localhost:8000/httpbin/get
# 返回 401 Unauthorized

# 5. 测试（带 Key）
curl http://localhost:8000/httpbin/get \
  -H "apikey: my-secret-api-key"
# 返回正常数据

# 6. 启用限流插件
curl -X POST http://localhost:8001/services/httpbin/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=10" \
  --data "config.policy=local"
```

### 7.4 DB-less 模式启动

如果不想用数据库，直接用声明式配置：

```yaml
# kong.yml
_format_version: "3.0"

services:
  - name: httpbin
    url: https://httpbin.org
    routes:
      - name: httpbin-route
        paths: ["/httpbin"]
    plugins:
      - name: rate-limiting
        config:
          minute: 100
          policy: local

consumers:
  - username: app-001
    keyauth_credentials:
      - key: my-secret-api-key
```

```bash
# DB-less 模式启动
KONG_DATABASE=off kong start -c kong.conf --declarative-config kong.yml
```

---

## 八、企业级场景

### 8.1 多环境管理

实际项目里通常有开发、测试、生产多套环境。Kong 的命名空间（Namespaces）或者用不同的 Kong 实例来隔离：

```bash
# 开发环境 Kong
KONG_PROXY_LISTEN=0.0.0.0:8000
KONG_ADMIN_LISTEN=0.0.0.0:8001

# 生产环境 Kong
KONG_PROXY_LISTEN=0.0.0.0:9000
KONG_ADMIN_LISTEN=0.0.0.0:9001
```

### 8.2 灰度发布

Kong 的 Canary 插件支持按权重分流：

```bash
# 90% 流量打到 v1，10% 打到 v2
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=canary" \
  --data "config.upstream_host=v2.internal" \
  --data "config.upstream_port=8080" \
  --data "config.percentage=10"
```

### 8.3 API 版本管理

用 Route 的优先级来做 API 版本管理：

```bash
# v1 路由（低优先级）
curl -X POST http://localhost:8001/services/user-v1/routes \
  --data "name=user-v1" \
  --data "paths[]=/api/v1/users" \
  --data "priority=1"

# v2 路由（高优先级，覆盖 v1）
curl -X POST http://localhost:8001/services/user-v2/routes \
  --data "name=user-v2" \
  --data "paths[]=/api/v2/users" \
  --data "priority=10"
```

### 8.4 跨域处理

微服务架构下跨域问题很常见，用 CORS 插件统一处理：

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=cors" \
  --data "config.origins=https://app.example.com" \
  --data "config.methods=GET,POST,PUT,DELETE" \
  --data "config.headers=Content-Type,Authorization" \
  --data "config.max_age=3600"
```

---

## 九、Kong vs 其他方案

市面上 API 网关不少，简单对比一下：

| 维度 | Kong | Spring Cloud Gateway | Envoy | APISIX |
|------|------|---------------------|-------|--------|
| 语言 | Lua | Java | C++ | Lua |
| 性能 | 极高 | 中等 | 极高 | 极高 |
| 插件生态 | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ |
| 动态配置 | ✅ | ✅ | ✅ | ✅ |
| 管理界面 | 企业版有 | 需自己开发 | 无 | 有 |
| 学习成本 | 中等 | 低（Java 生态） | 高 | 中等 |
| K8s 集成 | Ingress Controller | 较弱 | 原生支持 | Ingress Controller |
| 适用场景 | 通用 | Spring Cloud 体系 | Service Mesh | 通用 |

**选型建议**：
- Java 技术栈为主 → Spring Cloud Gateway
- Service Mesh 架构 → Envoy
- 通用场景、插件生态要求高 → Kong 或 APISIX
- 已经在用 OpenResty → Kong 或 APISIX

---

## 十、注意事项与局限性

### 10.1 性能考量

Kong 的延迟开销通常在 1-5ms（不含插件处理时间），但插件用多了会明显增加延迟。实际压测数据：

```
无插件：~1ms 延迟，50K+ RPS
3 个插件：~3ms 延迟，30K+ RPS
5+ 个插件：~5-10ms 延迟，20K+ RPS
```

**建议**：只启用真正需要的插件，不要为了"以防万一"开启一堆不用的插件。

### 10.2 Admin API 安全

Admin API 是 Kong 的管理接口，默认监听 8001 端口。**生产环境必须限制访问**：

```bash
# 只允许内网访问
KONG_ADMIN_LISTEN=127.0.0.1:8001

# 或者加认证
KONG_ADMIN_GUI_AUTH=basic-auth
```

### 10.3 配置备份

用 DB 模式时，定期备份 PostgreSQL 数据库。用 DB-less 模式时，确保 `kong.yml` 文件在 Git 里有版本管理。

### 10.4 日志与监控

生产环境一定要配好日志和监控。推荐组合：
- **Prometheus 插件** → 暴露指标
- **Grafana** → 可视化
- **http-log 或 kafka-log** → 请求日志持久化

---

## 十一、总结

Kong 的核心价值可以概括为三点：

1. **统一收口**：把认证、限流、日志这些横切关注点统一到网关层，业务服务只管业务
2. **插件化架构**：功能按需启用，支持 Lua/Go/Python/JS 多语言扩展
3. **部署灵活**：DB 模式、DB-less 模式、Hybrid 模式，适应不同规模和场景

对于中大型微服务架构，Kong 是一个成熟可靠的选择。小团队或者简单场景，可能 Nginx 手搓配置就够了，没必要上 Kong。但当服务数量上了规模，统一网关的价值就体现出来了。

---

## 参考资料

- [Kong 官方文档](https://docs.konghq.com/)
- [Kong GitHub 仓库](https://github.com/Kong/kong)
- [Kong 插件文档](https://docs.konghq.com/hub/)
- [OpenResty 官方文档](https://openresty.org/en/)
