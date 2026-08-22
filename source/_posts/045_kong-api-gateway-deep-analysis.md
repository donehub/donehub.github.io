---
title: Kong API 网关深度解析
date: 2024-05-28
tags: 网关
categories: 后端
---

## 背景

做微服务架构的人，基本绕不开 API 网关这个东西。不管你用 Spring Cloud Gateway、Envoy 还是 Nginx 手搓，总得有个统一的入口把请求转发给后端服务。

Kong 是这个领域里做得最成熟的开源方案之一，GitHub 上 40K+ Stars，背后有商业公司维护，插件生态完善，大厂用得也多。但很多开发者对 Kong 的理解停留在"哦，就是个网关"这个层面，对其架构设计、插件系统、配置模式这些核心东西没深入过。这篇文章从架构、插件、配置、负载均衡等多个维度做一次系统拆解。

<!-- more -->

## Kong 是什么

Kong 是一个基于 Nginx + OpenResty（LuaJIT）的开源 API 网关，核心能力覆盖路由转发、认证鉴权、流量控制和可观测性。它解决的根本问题是：把认证、限流、日志这些横切关注点（Cross-Cutting Concerns）从各个业务服务中抽出来，统一收口到网关层，让业务服务只管业务逻辑。

| 场景 | 没有网关 | 有了 Kong |
|------|---------|-----------|
| 10 个微服务都要做认证 | 每个服务自己实现一遍 | Kong 统一做，服务只管业务 |
| 要对某个接口限流 | 在代码里写限流逻辑 | Kong 配个插件就搞定 |
| 要记录所有请求日志 | 每个服务加日志代码 | Kong 统一采集，不影响业务 |
| 要做灰度发布 | 改代码或改 Nginx 配置 | Kong 按权重分流，配置即生效 |

传统做法每个服务都要重复造轮子，Kong 把这些公共能力集中到网关层统一处理，服务数量越多，这种架构的优势越明显。

## 架构深度拆解

### 整体架构

Kong Gateway 的架构分为四层。最上面是 Nginx 反向代理层，负责接收和处理所有入站请求。第二层是 OpenResty/LuaJIT 运行时，提供 Lua 脚本的执行环境。第三层是 Kong Core，包含路由匹配引擎和插件系统（认证、限流、日志、转换等插件都在这里运行）。Kong Core 还暴露了 Admin API 用于配置管理。底层是数据存储层，支持 PostgreSQL、Cassandra 或声明式配置文件。数据平面的最终目标是把请求转发到后端的各个上游服务（User Service、Order Service 等）。

### 为什么选 Nginx + OpenResty

Kong 没有用 Java、没用 Go，选了 Lua 这个相对小众的语言，核心原因在于 OpenResty。OpenResty 是 Nginx 的增强版，把 LuaJIT 嵌入到 Nginx 的请求处理生命周期里，带来了三个关键能力：

1. 性能极高：Nginx 本身就以高并发著称，LuaJIT 的执行速度接近 C
2. 非阻塞 I/O：OpenResty 把所有网络操作都封装成非阻塞的，一个请求在等数据库返回的时候不会阻塞其他请求
3. 生命周期钩子：Nginx 的各个处理阶段（rewrite、access、content、log）都能用 Lua 来扩展

Kong 本质上就是一个用 Lua 写的、运行在 OpenResty 上的 Nginx 配置生成器加插件执行引擎。

### 核心抽象模型

Kong 的配置管理围绕五个核心概念展开。Service 是对一个上游后端服务的抽象，包含 URL、协议、超时等配置。Route 是请求的匹配规则，定义哪些请求应该被路由到哪个 Service，匹配维度包括路径、Host、HTTP Method，一个 Service 可以挂多个 Route。Upstream 是一组 Target（后端实例地址）的集合，负责负载均衡策略和健康检查。Consumer 代表 API 的调用方身份，通过 API Key、JWT 等方式标识。Plugin 则是对横切逻辑的抽象，可以挂载到 Service、Route 或 Consumer 上。

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

这套模型的设计思路很清晰：Service 抽象后端服务，Route 抽象匹配规则，Plugin 抽象横切逻辑，三者解耦，各司其职。

### 请求生命周期

一个请求到达 Kong 之后，会按顺序经历以下阶段：

1. SSL/TLS 握手（certificate 阶段）：可以执行 mTLS 插件
2. URI 重写（rewrite 阶段）：可以执行 URL 重写插件
3. 路由匹配：Kong 根据 Host/Path/Method 找到对应的 Route
4. 认证和鉴权（access 阶段）：执行 key-auth、jwt、oauth2 等插件
5. 限流和配额（access 阶段）：执行 rate-limiting、quota 等插件
6. 请求转换（access 阶段）：执行 request-transformer 插件
7. 转发请求到上游服务
8. 接收上游响应
9. 响应头处理（header_filter 阶段）：执行 cors、response-transformer 等插件
10. 响应体处理（body_filter 阶段）：可以修改响应内容
11. 日志记录（log 阶段）：执行 tcp-log、http-log、file-log 等插件
12. 返回响应给客户端

access 阶段是整个生命周期的核心，大部分插件都在这个阶段执行。每个插件有优先级（priority），priority 越高越先执行。

## 插件系统

插件系统是 Kong 区别于其他网关的最大优势。理解插件系统，才算真正理解 Kong。

### 插件的作用域

Kong 的插件支持分层配置，从宽到窄分为四个层级：全局插件对所有请求生效；服务级插件对某个 Service 的所有请求生效；路由级插件对匹配某个 Route 的请求生效；消费者级插件对某个 Consumer 的请求生效。

这种分层设计在实际使用中非常灵活。比如全局开启 CORS 插件处理跨域，对支付服务单独开启更严格的限流策略，对 VIP 消费者放宽配额限制，这些场景都可以通过不同层级的插件组合来实现。

### 插件执行机制

每个插件本质上是一个 Lua 模块，实现了特定的钩子函数：

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

Kong 提供了 PDK（Plugin Development Kit），封装了所有常用操作：

| PDK 函数 | 用途 |
|---------|------|
| `kong.request.get_header()` | 获取请求头 |
| `kong.request.get_body()` | 获取请求体 |
| `kong.response.exit()` | 直接返回响应 |
| `kong.service.request.set_header()` | 修改转发给上游的请求头 |
| `kong.client.get_consumer()` | 获取当前消费者信息 |
| `kong.ip.get_source()` | 获取客户端真实 IP |

### 内置插件分类

Kong 的内置插件覆盖了几大类场景。

认证类：

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

流量控制类：

| 插件 | 说明 |
|------|------|
| rate-limiting | 基于 IP/Consumer/Service 的速率限制 |
| request-size-limiting | 限制请求体大小 |
| proxy-cache | 响应缓存 |
| canary | 金丝雀发布，按权重分流 |

转换类：

| 插件 | 说明 |
|------|------|
| request-transformer | 修改请求头、Body、URL 参数 |
| response-transformer | 修改响应头、Body |
| request-validator | JSON Schema 请求验证 |
| correlation-id | 生成请求唯一标识 |
| cors | 跨域配置 |

可观测性类：

| 插件 | 说明 |
|------|------|
| prometheus | 暴露 Prometheus 指标 |
| datadog | 集成 Datadog APM |
| zipkin | 分布式链路追踪 |
| tcp-log | TCP 方式发送日志 |
| http-log | HTTP 方式发送日志 |
| file-log | 写入本地文件 |
| kafka-log | 发送到 Kafka |

### 插件开发实战

官方内置插件覆盖了大部分场景，但有时候你得写自己的插件。比如给所有经过网关的请求加上公司内部的审计日志，这就需要开发一个自定义插件。

目录结构：

```
kong-plugin-audit-log/
├── kong/
│   └── plugins/
│       └── audit-log/
│           ├── handler.lua    # 插件逻辑
│           └── schema.lua     # 配置校验
└── kong-plugin-audit-log-0.1.0-1.rockspec
```

handler.lua 是插件的主逻辑，在 log 阶段收集请求信息并发送到审计系统：

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

schema.lua 负责定义插件的配置校验规则：

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

安装和启用插件：

```bash
# 打包
luarocks make

# 在 kong.conf 中启用
plugins = bundled,audit-log

# 或者通过环境变量
KONG_PLUGINS=bundled,audit-log
```

### 多语言插件支持

Lua 不是所有人都熟，Kong 后来加了 External Plugins 机制，支持用其他语言写插件：

| 语言 | 方式 | 说明 |
|------|------|------|
| Go | Go PDK | 通过 gRPC 和 Kong 通信 |
| Python | Python PDK | 同样走 gRPC |
| JavaScript | JS PDK | 同样走 gRPC |
| WebAssembly | WASM | 新一代扩展方式 |

原理是一样的：Kong 在插件执行阶段通过 gRPC 调用外部插件服务，外部服务处理完返回结果。性能比原生 Lua 插件差一些，但开发门槛低很多，团队不需要掌握 Lua 也能扩展 Kong 的能力。

## 配置管理

Kong 支持三种配置管理模式，适应不同的部署场景。

#### 传统数据库模式（DB Mode）

所有配置（Service、Route、Plugin、Consumer）存在 PostgreSQL 或 Cassandra 里，通过 Admin API 管理。配置变更实时生效，不需要重启，多个 Kong 节点共享同一份配置，适合动态环境中服务频繁上下线的场景。代价是依赖数据库这个额外的运维组件，数据库挂了虽然不影响已有请求的转发（Kong 有本地缓存），但配置变更就无法进行了。

#### DB-less 声明式模式

所有配置写在一个 YAML 文件里，启动时加载：

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

启动时指定配置文件：

```bash
kong start -c kong.conf --declarative-config kong.yml
```

这种模式不需要数据库，部署更简单，配置即代码可以 Git 管理，天然适合 GitOps 和 CI/CD 流程，也能直接放到 Kubernetes 的 ConfigMap 里。局限是配置变更需要 reload 才能生效，不支持 Consumer 的动态注册。

#### 混合模式（Hybrid Mode）

Kong 把控制平面和数据平面分离。控制平面负责配置管理，连接数据库，暴露 Admin API；数据平面只做代理转发，不连数据库，不暴露 Admin API。控制平面通过 mTLS 把配置推送到数据平面，数据平面在本地缓存配置，即使控制平面暂时不可用也能继续处理请求。

| 组件 | 职责 | 特点 |
|------|------|------|
| 控制平面 | 配置管理，连接数据库 | 暴露 Admin API，集中管理所有配置 |
| 数据平面 | 代理转发请求 | 无数据库，无 Admin API，本地缓存配置 |

这种模式安全性更高（数据平面不暴露管理接口），数据平面部署更轻量（不需要数据库），还能跨机房集中管理。代价是架构复杂度增加，需要管理 mTLS 证书。

## 负载均衡与服务发现

Kong 通过 Upstream 对象实现负载均衡，支持多种算法：

| 算法 | 说明 | 适用场景 |
|------|------|---------|
| round-robin | 轮询 | 通用场景，最常用 |
| consistent-hashing | 一致性哈希 | 需要会话保持的场景 |
| least-connections | 最少连接数 | 后端实例性能不均 |
| latency | 最低延迟 | 对延迟敏感的场景 |

一致性哈希值得单独说一下，它可以基于不同的维度做哈希，灵活度很高：

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

### 健康检查

Kong 提供两种健康检查机制，通常配合使用。主动检查是 Kong 定期向后端实例发送探测请求，根据返回的 HTTP 状态码判断实例是否健康。被动检查是基于实际请求的失败情况来判断，也叫熔断机制，当连续出现 TCP 失败、超时或 HTTP 错误达到阈值时，将后端实例标记为不健康。

```bash
# 主动检查配置
curl -X POST http://localhost:8001/upstreams/my-upstream/healthcheck \
  --data active.healthy.interval=5 \
  --data active.unhealthy.interval=2 \
  --data active.http_path=/health \
  --data active.http_statuses=200,302

# 被动检查配置（熔断）
curl -X POST http://localhost:8001/upstreams/my-upstream/healthcheck \
  --data passive.healthy.successes=5 \
  --data passive.unhealthy.tcp_failures=3 \
  --data passive.unhealthy.timeouts=3 \
  --data passive.unhealthy.http_failures=5
```

### 服务发现

Kong 支持与服务发现系统集成：

| 方式 | 说明 |
|------|------|
| DNS SRV | 通过 DNS 记录发现服务 |
| Consul | 集成 HashiCorp Consul |
| Kubernetes | 直接使用 K8s Service 名称 |

Kubernetes 集成用得最多。在 K8s 环境里，Kong 直接用 Service 名称做 upstream，自动解析 ClusterIP，不需要手动维护后端实例列表：

```yaml
services:
  - name: user-service
    url: http://user-service.default.svc.cluster.local:8080
```

## 快速上手

#### Docker 一键启动

最简单的方式是用 Docker Compose 拉起一套完整的 Kong 环境：

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

#### 配置第一个 API

用 Admin API 注册一个服务和路由，然后验证转发是否生效：

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

#### 加上认证和限流

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

#### DB-less 模式启动

如果不想用数据库，直接用声明式配置文件启动：

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

## 企业级场景

#### 多环境管理

实际项目里通常有开发、测试、生产多套环境，用不同的 Kong 实例配合不同的端口来隔离：

```bash
# 开发环境 Kong
KONG_PROXY_LISTEN=0.0.0.0:8000
KONG_ADMIN_LISTEN=0.0.0.0:8001

# 生产环境 Kong
KONG_PROXY_LISTEN=0.0.0.0:9000
KONG_ADMIN_LISTEN=0.0.0.0:9001
```

#### 灰度发布

Kong 的 Canary 插件支持按权重分流，实现灰度发布：

```bash
# 90% 流量打到 v1，10% 打到 v2
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=canary" \
  --data "config.upstream_host=v2.internal" \
  --data "config.upstream_port=8080" \
  --data "config.percentage=10"
```

#### API 版本管理

用 Route 的优先级来做 API 版本管理，高优先级的路由先匹配：

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

#### 跨域处理

微服务架构下跨域问题很常见，用 CORS 插件在网关层统一处理，不用在每个后端服务里单独配置：

```bash
curl -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=cors" \
  --data "config.origins=https://app.example.com" \
  --data "config.methods=GET,POST,PUT,DELETE" \
  --data "config.headers=Content-Type,Authorization" \
  --data "config.max_age=3600"
```

## Kong vs 其他方案

市面上 API 网关的选择不少，几个主流方案的对比：

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

选型建议：Java 技术栈为主选 Spring Cloud Gateway，Service Mesh 架构选 Envoy，通用场景对插件生态要求高选 Kong 或 APISIX。对于中大型微服务架构，Kong 是一个成熟可靠的选择；服务数量上了规模之后，统一网关带来的收益会远超它的运维成本。小团队或者简单场景，Nginx 手搓配置可能就够用了。

## 注意事项与局限性

### 性能考量

Kong 本身的延迟开销通常在 1-5ms（不含插件处理时间），但插件数量增多后延迟会明显上升。实际压测数据表明，无插件状态下延迟约 1ms，吞吐量可达 50K+ RPS；挂载 3 个插件后延迟约 3ms，吞吐量降到 30K+ RPS；5 个以上插件延迟会到 5-10ms，吞吐量降到 20K+ RPS。建议只启用真正需要的插件，不要为了"以防万一"开启一堆用不上的东西。

### Admin API 安全

Admin API 是 Kong 的管理接口，默认监听 8001 端口，拥有对 Kong 配置的完全控制权。生产环境必须限制访问，要么只允许内网访问，要么加上认证机制：

```bash
# 只允许内网访问
KONG_ADMIN_LISTEN=127.0.0.1:8001

# 或者加认证
KONG_ADMIN_GUI_AUTH=basic-auth
```

### 配置备份与日志监控

用 DB 模式时要定期备份 PostgreSQL 数据库，用 DB-less 模式时确保 kong.yml 在 Git 里有版本管理，避免配置丢失。生产环境的日志和监控也需要提前配好，推荐组合是 Prometheus 插件暴露指标、Grafana 做可视化、http-log 或 kafka-log 做请求日志持久化。

## 参考资料

- [Kong 官方文档](https://docs.konghq.com/)
- [Kong GitHub 仓库](https://github.com/Kong/kong)
- [Kong 插件文档](https://docs.konghq.com/hub/)
- [OpenResty 官方文档](https://openresty.org/en/)
