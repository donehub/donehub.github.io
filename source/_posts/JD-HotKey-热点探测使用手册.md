---
title: JD-HotKey 使用手册
date: 2026-06-15
tags: [JD-HotKey]
categories: 中间件
---

# 一、组件介绍

JD-HotKey 是京东开源的**实时热点 key 探测与缓存中间件**（[开源地址](https://gitee.com/jd-platform-opensource/hotkey)），它做了一件事：在高并发场景下，**自动发现热点 key，毫秒级推送到所有应用节点的 JVM 内存中**，让热点请求直接在本地内存响应，不再打到 Redis 和数据库。

经典场景：某明星突然官宣，相关商品瞬间涌入海量请求。你事先根本不知道这个商品 ID 会变热，Redis 某个节点被这些请求打得 CPU 飙升——这就是典型的**不可预知突发热点**。

这时候你就需要 JD-HotKey：它能自动发现这类热点，把数据"镜像"到每台应用服务器的本地内存里，后续请求直接从内存读，**RT 从几十毫秒降到 < 1ms**。

和直接用本地缓存（比如 Caffeine）比，JD-HotKey 的核心优势：

|能力|Caffeine 本地缓存|JD-HotKey|
|---|---|---|
|热点发现|**手动配置**，你得提前知道哪些 key 要缓存|**自动探测**，根据访问量实时判定|
|动态性|静态的，配了就一直在|**自动加入 / 退出热点**，冷了自动释放内存|
|多节点一致性|各节点独立，互不知情|**全局统一判定**，所有节点同步感知|
|适用场景|已知高频数据（如字典、配置）|**不可预知的突发热点**（如秒杀、热搜）|
|部署复杂度|低（纯 SDK）|中等（需要 etcd + worker）|
|热用户 / 热接口探测|不支持|**支持**（不只限 key，接口、用户也能探）|

简单总结：**已知的热点用本地缓存就够了，不可预知的热点用 JD-HotKey**。

# 二、核心架构

## 2.1 整体架构
### 2.1.1 综合架构
![alt text](/img/jdhotkey1.png)
### 2.1.2 分层架构
![alt text](/img/jdhotkey2.png)
系统由四个核心组件构成：

|组件|职责|说明|
|---|---|---|
|**etcd 集群**|配置中心 + 注册中心|存储热点规则、worker 节点注册、热点 key 的推送中转|
|**worker**|聚合计算节点|接收所有客户端的访问统计，执行热点判定，推送热点通知|
|**client SDK**|嵌入业务应用的客户端|收集访问数据、上报统计、接收热点通知、本地缓存热点数据|
|**dashboard**|可视化管理控制台|配置规则、查看热点、管理应用|

## 2.2 数据流转过程

整个热点探测的过程就像一条流水线：

```txt
1. 业务请求打到 app，client SDK 对 key 做访问计数
        ↓
   ┌─────────────────────────────────────────────┐
   │  TurnKeyCollector（双 Map 无锁化收集）       │
   │                                             │
   │  Map[0]  ← 偶数次调用写入                    │
   │  Map[1]  ← 奇数次调用写入                    │
   │  AtomicLong 递增 → % 2 → 决定写哪个 Map     │
   │  读写完全隔离，不阻塞业务线程                  │
   └─────────────────────────────────────────────┘
        ↓
2. client 每隔 500ms 将其中一个 Map 的数据批量上报给 worker
   （读一个 Map 时，写操作在另一个 Map 进行，互不影响）
        ↓
3. worker 汇聚所有 app 节点的数据，执行热点判定算法
        ↓
4. 某 key 在时间窗口内的总访问次数 >= 阈值 → 判定为热点
        ↓
5. worker 通过 etcd watch 机制，将热点 key 实时推送给所有客户端
        ↓
6. 客户端收到通知，将热点数据缓存到本地内存（Caffeine）
        ↓
7. 后续请求直接走本地缓存，不再访问 Redis / DB
        ↓
8. 当 key 不再热门 → worker 通知客户端移除本地缓存，释放内存
```

**关键设计：集中计算**。你可能会想，为什么不直接在每个客户端本地判断热点？因为分布式场景下，单机请求是分散的——一个 key 在 100 台机器上每台只被访问了 5 次，单看任何一台都不算热，但汇总起来有 500 次。**必须由 worker 集中汇总计算，才能准确识别全局热点**。

**Worker 内部处理流程**：worker 收到 client 上报的数据后，经过一条**责任链**处理：

```txt
Netty 收到消息
    ↓
HeartBeatFilter（心跳消息直接处理）
    ↓
AppNameFilter（解析客户端 App 名称）
    ↓
HotKeyFilter（排除白名单 key，有效数据入队）
    ↓
KeyCounterFilter（统计数据处理）
    ↓
LinkedBlockingQueue（容量 200 万，削峰缓冲）
    ↓
KeyConsumer 多线程消费 → SlidingWindow.addCount() → 判定热点
    ↓
热点 key → 写入 etcd + 推送到所有 Client（每 10ms 批量推送）
```

Worker 内部还有一个 `hotCache`（Caffeine 实现，**5 秒 TTL**），用来**防抖**——同一个 key 在 5 秒内不会重复推送，避免热点持续触发时产生大量无效推送。

## 2.3 etcd 的角色

etcd 在这个系统里承担了三个职责：

1. **规则存储**：你在 dashboard 配置的热点规则（哪个 key 前缀、阈值多少、窗口多大），都持久化在 etcd 中。worker 和 client 通过 watch etcd 来感知规则变化。

2. **worker 注册**：每个 worker 启动时把自己的 IP 注册到 etcd，client 通过读 etcd 知道该连哪些 worker。

3. **热点推送中转**：worker 判定出热点 key 后，写入 etcd 并设置 TTL 过期时间；客户端 watch 对应的 etcd 路径，收到变更事件后立即更新本地缓存。

**一个巧妙的设计**：etcd 原生支持 key 的 TTL 自动过期删除。热点 key 写入 etcd 时设一个过期时间（比如 60 秒），过期后 etcd 自动删除，删除事件通过 watch 回调通知所有 client 清除本地缓存。这样就实现了**热点 key 的自动淘汰**，不需要额外的清理逻辑。

**为什么选 etcd 而不是 ZooKeeper？** etcd 原生支持 key TTL 自动删除（ZooKeeper 不支持），性能更高，资源占用更少，API 风格也更现代（基于 gRPC）。

**etcd 版本要求**：3.4.x 及以上。

## 2.4 滑动窗口算法

这是热点判定的核心算法。JD-HotKey 用的是**双缓冲 Map**实现滑动窗口：

```txt
Worker 内部的双 Map 机制：

  ┌─────────────────────────────────────────────────┐
  │  Map[0]（写 Map） ← 当前时间片，接收新 key 上报   │
  │  Map[1]（读 Map） ← 上一时间片，被消费线程读取统计 │
  │                                                 │
  │  AtomicLong 递增 → % 2 → 决定当前写哪个 Map      │
  │  读写分离 → 永不阻塞 → 高并发吞吐                 │
  └─────────────────────────────────────────────────┘
```

- **双 Map 交替**：一个 Map 负责写入新上报的数据，另一个负责读取统计和清理。通过 `AtomicLong` 取模 2 切换读写对象，完全无锁设计
- **读写不阻塞**：消费线程在统计 Map[0] 时，写入线程往 Map[1] 写数据，互不干扰
- **演进历史**：最初用的是 Disruptor，但在实际高并发中发现会导致个别数据延迟且空耗 CPU，后来换成了 `LinkedBlockingQueue` + 读写分离锁的方案，性能反而更稳定

**Key 的 Hash 分发**：client 上报数据时，会对 key 做 Hash 计算（`hash(key) % workerCount`），**同一个 key 始终路由到同一个 worker**。这样保证了某个 key 的所有统计数据集中在一个 worker 上，不需要跨 worker 聚合。worker 之间也互不通信，各自独立计算。

## 2.5 JdHotKeyStore — 核心 API

`JdHotKeyStore` 是 client SDK 提供的核心操作类，只有 4 个静态方法：

|方法|作用|使用场景|
|---|---|---|
|`isHotKey(key)`|判断 key 是否热点，**同时上报该 key 的访问**|最常用，适用于只需拦截或限流的场景|
|`get(key)`|从本地内存读取热点 key 缓存的**值**|配合 `smartSet` 使用|
|`smartSet(key, value)`|为热点 key 设置本地缓存值|key 已被判定为热点时，存入真实数据|
|`getValue(key)`|综合查询：本地有值返回值，无值返回 null **并自动上报**|一步到位的查询方式|

**注意区分这几个方法的行为差异**，很多人刚接触时会搞混：

```txt
isHotKey(key)  → 返回 true/false，同时上报 key 的访问量（计数 +1）
get(key)       → 只从本地缓存读值，不上报
smartSet(key, value) → 只在该 key 是热点时才写入本地缓存（非热点写入会被忽略）
getValue(key)  → 读值 + 上报（如果本地没值，返回 null，同时上报）
```

**一个内部细节**：当 worker 推送热点通知到 client 时，client 会先在 Caffeine 中存入一个**魔术值**（`0x12fcf76`）作为占位标记，表示"这个 key 已经是热点了，但还没填入实际业务数据"。所以 `get(key)` 可能返回这个魔术值或者 null——说明热点标记已生效，但数据还没被 `smartSet` 填进去，你需要自己加载数据并写入。

**Caffeine 分桶设计**：client 内部不是用一个 Caffeine 实例存所有热点 key，而是按**过期时间（duration）分桶**——相同过期时间的 key 共享同一个 Caffeine 实例。这样不同规则下的热点 key 可以有不同的 TTL，互不干扰。

---

# 三、快速接入（Spring Boot）

## 第一步：部署基础环境

JD-HotKey 依赖 etcd，部署前需要先准备好 etcd 集群。

### 安装 etcd（开发环境）

```bash
# Docker 方式（快速启动单节点）
docker run -d --name etcd \
  -p 2379:2379 \
  -e ALLOW_NONE_AUTHENTICATION=yes \
  bitnami/etcd:3.4

# 验证连接
docker exec etcd etcdctl endpoint health
```

### 部署 worker

worker 是独立部署的 Java 进程，负责聚合计算。

```bash
# 从源码编译
cd worker
mvn clean package -DskipTests

# 启动 worker（关键参数）
java -jar worker/target/worker.jar \
  --etcd=http://127.0.0.1:2379 \
  --threads=16 \
  --workerPath=/jd/hotkey/worker
```

|参数|说明|
|---|---|
|`etcd`|etcd 集群地址|
|`threads`|工作线程数，建议根据 CPU 核数调整|
|`workerPath`|worker 在 etcd 中的注册路径|

### 部署 dashboard

dashboard 是 Web 管理控制台，需要连接 MySQL 和 etcd。

```bash
# 1. 创建数据库，执行 db.sql 初始化脚本
# 2. 修改 application.yml 中的数据库和 etcd 配置
# 3. 启动
java -jar dashboard.jar

# 访问 http://localhost:8081
# 默认管理员账号按 README 说明配置
```

## 第二步：引入 Maven 依赖

```xml
<dependency>
    <groupId>com.jd.platform.hotkey</groupId>
    <artifactId>hotkey-client</artifactId>
    <version>0.0.4-SNAPSHOT</version>
</dependency>
```

**依赖冲突注意**：
- 如果项目中有 guava，需要升级到 **28.2-jre** 以上
- 如果项目中有 fastjson，需要降到 **1.2.70**（hotkey-client 内部使用的版本）
- 通信协议用的 **protobuf**，注意版本兼容

## 第三步：初始化客户端

在 Spring Boot 启动时初始化 client，连接到 etcd 并启动数据管道：

```java
@Component
public class HotKeyConfig {

    @Value("${etcd.server}")
    private String etcdServer;

    @Value("${spring.application.name}")
    private String appName;

    @PostConstruct
    public void init() {
        ClientStarter starter = new ClientStarter.Builder()
                .setAppName(appName)          // 应用名，和 dashboard 中的配置对应
                .setEtcdServer(etcdServer)    // etcd 集群地址
                .build();
        starter.startPipeline();
    }
}
```

`ClientStarter.Builder` 支持的配置项：

|方法|默认值|说明|
|---|---|---|
|`setAppName`|无（必填）|应用名称，用于匹配 dashboard 中的规则|
|`setEtcdServer`|无（必填）|etcd 集群地址，多个用逗号分隔|
|`setCaffeineSize`|200000|本地 Caffeine 缓存最大容量|
|`setPushPeriod`|500ms|批量上报统计数据的时间间隔（最小 50ms）|

## 第四步：配置热点规则

在 dashboard 中配置你的热点规则。规则以 JSON 格式存储，支持以下参数：

```json
{
    "desc": "商品信息热点规则",
    "key": "goods:",
    "prefix": true,
    "threshold": 100,
    "duration": 5,
    "interval": 1
}
```

|字段|类型|说明|
|---|---|---|
|`key`|String|key 匹配规则。`prefix = true` 时作为前缀匹配|
|`prefix`|boolean|是否前缀匹配。`true` 表示匹配 `key` 开头的所有 key|
|`threshold`|int|热点阈值——时间窗口内总访问次数超过此值判定为热点|
|`duration`|int|滑动窗口大小（秒）|
|`interval`|int|窗口滑动步长（秒）|
|`desc`|String|规则描述，方便管理|

上面的配置含义：**以 `goods:` 开头的 key，在 5 秒内被访问超过 100 次，判定为热点**。

---

# 四、使用介绍

## 4.1 场景一：热点拦截 + 限流

最简单的用法——判断是否热点，是的话做特殊处理（降级、限流或直接返回）：

```java
@RestController
public class GoodsController {

    @GetMapping("/goods/{id}")
    public Object getGoods(@PathVariable String id) {
        String key = "goods:" + id;

        // isHotKey 会同时上报 key 的访问量
        if (JdHotKeyStore.isHotKey(key)) {
            // 热点 key 的降级处理：直接返回缓存数据或友好提示
            return "当前访问量大，请稍后再试";
        }

        // 非热点 key 走正常流程
        return goodsService.getGoodsDetail(id);
    }
}
```

## 4.2 场景二：热点数据本地缓存（推荐）

更实用的方式——检测到热点后，把数据缓存到本地内存，后续请求直接从内存读：

```java
@Service
public class GoodsService {

    @Autowired
    private RedisTemplate<String, Object> redisTemplate;

    @Autowired
    private GoodsMapper goodsMapper;

    public GoodsDetail getGoodsDetail(String goodsId) {
        String key = "goods:" + goodsId;

        // 1. 判断是否热点
        if (JdHotKeyStore.isHotKey(key)) {
            // 2. 先尝试从本地缓存读取
            GoodsDetail cached = (GoodsDetail) JdHotKeyStore.get(key);
            if (cached != null) {
                return cached;
            }
            // 3. 本地没有，从 Redis 加载
            GoodsDetail goods = loadFromRedis(goodsId);
            if (goods != null) {
                // 4. 写入本地热点缓存（只有 key 是热点时才会写入成功）
                JdHotKeyStore.smartSet(key, goods);
            }
            return goods;
        }

        // 5. 非热点 key，正常走 Redis
        return loadFromRedis(goodsId);
    }

    private GoodsDetail loadFromRedis(String goodsId) {
        GoodsDetail goods = (GoodsDetail) redisTemplate.opsForValue().get("goods:" + goodsId);
        if (goods == null) {
            goods = goodsMapper.selectById(goodsId);
            if (goods != null) {
                redisTemplate.opsForValue().set("goods:" + goodsId, goods, 300, TimeUnit.SECONDS);
            }
        }
        return goods;
    }
}
```

**这里的 `smartSet` 很巧妙**：它只在 key 已被判定为热点时才写入本地缓存。如果 key 不是热点，写入会被忽略——不用担心内存被非热点数据撑爆。

## 4.3 场景三：用 getValue 简化逻辑

`getValue` 把"查本地缓存 + 上报"合并成了一步，代码更简洁：

```java
public GoodsDetail getGoodsDetail(String goodsId) {
    String key = "goods:" + goodsId;

    // getValue 自动处理：本地有值返回值 + 上报访问量
    GoodsDetail cached = (GoodsDetail) JdHotKeyStore.getValue(key);
    if (cached != null) {
        return cached;
    }

    // 本地没有（可能刚变热点还没缓存数据），从 Redis 加载并写入
    GoodsDetail goods = loadFromRedis(goodsId);
    if (goods != null) {
        JdHotKeyStore.smartSet(key, goods);
    }
    return goods;
}
```

## 4.4 场景四：热用户 / 热接口探测

JD-HotKey 不只局限于数据 key，也能探测热用户和热接口：

```java
// 热用户探测（防爬虫 / 防刷子）
public void handleRequest(String userId) {
    if (JdHotKeyStore.isHotKey("hot:user:" + userId)) {
        // 该用户访问频率异常，触发限流或验证码
        log.warn("检测到异常高频用户: {}", userId);
        throw new RateLimitException("访问过于频繁，请稍后再试");
    }
    // 正常业务逻辑...
}

// 热接口探测
public void handleApiCall(String apiPath) {
    if (JdHotKeyStore.isHotKey("hot:api:" + apiPath)) {
        // 接口被大量请求，触发熔断或降级
        log.warn("接口被高频访问: {}", apiPath);
        return fallbackResponse;
    }
    // 正常业务逻辑...
}
```

在 dashboard 中配置对应的规则就行：`key = "hot:user:"` 和 `key = "hot:api:"`。

---

# 五、性能数据

## 5.1 Worker 性能演进

JD-HotKey 的性能不是一蹴而就的，从初版到最终版经历了 **17 倍** 的提升：

|版本|QPS|CPU|关键优化|
|---|---|---|---|
|V1（初版）|~2 万|>20%|Disruptor + Fastjson，遇到 JDK 线程 bug 导致大量线程创建|
|V2|~10 万|7-10%|换掉 Disruptor，改用 `LinkedBlockingQueue`|
|V3|~16 万|~40%|8 核单机调优|
|V4|25-30 万|~70%|8 生产 + 8 消费线程|
|**V5（最终版）**|**稳定 30 万，极限 37 万**|**~50%**|序列化从 Fastjson 换为 **Protobuf**，16 核|

**最大的性能跃升来自序列化方案的切换**：从 Fastjson 换为 Protobuf 后，序列化效率显著提升，CPU 使用率反而下降了。

## 5.2 推送性能

|推送速率|延迟表现|
|---|---|
|10-12 万/秒|**即时送达，无延迟**|
|20 万/秒|约 1 秒延迟|
|40-60 万/秒（8 IO 线程）|稳定推送|
|**70 万/秒（16 IO 线程）**|**稳定推送**|
|80 万/秒（极限）|频繁 GC，最终 OOM|

## 5.3 生产实战数据

|指标|数据|
|---|---|
|大促期间集群总吞吐|**1500 万/秒**|
|本地缓存命中占总流量|**>50%**|
|日探测 Key 数量|**数十亿**|
|1 台 Worker（16 核）可支撑|**~1000 台业务服务**|
|扛住百万级热 key 所需 Worker|**~30 台**|

**对比一下**：普通请求访问 Redis 的 RT 通常在 1-5ms，访问数据库 5-50ms。JD-HotKey 让热点请求直接从 JVM 内存读取，**RT 降到纳秒级**。

---

# 六、与同类方案对比

|维度|JD-HotKey|Caffeine 本地缓存|Redis 热点 key 探测|JetCache BOTH|
|---|---|---|---|---|
|热点发现|**自动探测**|手动配置|`redis-cli --hotkeys`（采样）|手动配置|
|实时性|秒级自动感知|静态，需手动更新|实时但精度受限|广播通知|
|动态性|**自动加入 / 退出**|不变化，配了就一直有|需手动清理|广播失效|
|多节点一致性|**全局统一判定**|各节点独立|Redis 层面|广播通知|
|探测范围|key / 用户 / 接口|仅配置的 key|仅 Redis key|仅配置的 key|
|部署复杂度|中等（etcd + worker）|低（纯 SDK）|低（Redis 自带）|低（纯 SDK）|
|运维成本|中（etcd 集群维护）|无|无|无|
|适用场景|**不可预知的突发热点**|已知高频数据|Redis 热点节点排查|已知高频读数据|

### 什么时候该用 JD-HotKey？

- **突发热点**：热搜、突发新闻、秒杀商品——你没法提前知道哪些 key 会变热
- **大促场景**：618、双11，热点模式不可预测
- **全站热点保护**：不想人工分析哪些 key 是热点，交给系统自动发现
- **热用户 / 热接口探测**：防爬虫、防刷子

### 什么时候不需要 JD-HotKey？

- **热点数据固定且已知**：直接用 Caffeine 或 JetCache BOTH 就够了
- **数据量不大，Redis 压力不大**：没必要引入额外组件
- **团队运维能力有限**：etcd 集群的部署和维护有学习成本

---

# 七、最佳实践与注意事项

## 7.1 阈值调优

阈值设太低 → 太多 key 被判定为热点 → 本地内存撑爆；阈值设太高 → 热点漏判 → Redis 被打。

**建议**：
- 核心业务（如商品详情）：阈值设低一点（如 5 秒内 50 次）
- 边缘业务：阈值设高一点（如 5 秒内 200 次）
- 通过 dashboard 配置**分级阈值**，不同业务用不同规则

## 7.2 内存控制

`smartSet` 存入的热点数据占用的是应用 JVM 内存。注意：

- `CaffeineSize` 默认 200000，根据单机内存和数据大小调整
- 大对象场景下（如完整的商品详情 JSON），适当减小容量
- 热点 key 过期后会自动从本地缓存移除，不需要手动清理

## 7.3 etcd 集群容灾

etcd 是核心依赖，但 client 有容灾设计：

- etcd 短暂不可用时，**已推送的热点数据仍然在本地缓存中正常工作**
- 只是新的热点判定和规则变更无法生效
- 建议 etcd 至少 3 节点部署，保证高可用

## 7.4 依赖冲突处理

这是接入时最常踩的坑：

|冲突依赖|解决方案|
|---|---|
|guava|升级到 **28.2-jre** 以上|
|fastjson|降到 **1.2.70**（hotkey-client 内部使用的版本）|
|protobuf|注意版本兼容，参考 hotkey-client 的 pom|
|Netty|确保不与业务中的 Netty 版本冲突|
|JDK 版本|建议使用 **JDK 1.8.0_191+**（早期版本在容器环境下 `availableProcessors()` 返回宿主机核数而非容器限制核数，导致线程配置异常）|

**建议**：引入依赖后先跑一遍单元测试，确认没有类冲突。特别注意 guava 和 fastjson 版本，这两个最容易出问题。

## 7.5 配合降级策略

热点探测不是万能的，建议配合降级策略：

```java
public GoodsDetail getGoodsDetail(String goodsId) {
    String key = "goods:" + goodsId;

    try {
        if (JdHotKeyStore.isHotKey(key)) {
            GoodsDetail cached = (GoodsDetail) JdHotKeyStore.get(key);
            if (cached != null) {
                return cached;
            }
        }
    } catch (Exception e) {
        // hotkey 组件异常时降级到普通流程
        log.warn("hotkey 判断异常，降级处理", e);
    }

    // 正常流程：Redis → DB
    return loadFromRedis(goodsId);
}
```

## 7.6 监控告警

建议监控以下指标：

- **热点 key 数量**：突增可能意味着异常流量
- **热点 key 变化趋势**：发现异常模式
- **worker 健康状态**：etcd 中 worker 注册是否正常
- **client 上报延迟**：是否因为网络问题导致上报积压

---

# 八、FAQ

## Q: worker 和 server 是什么关系？

JD-HotKey 中，worker 就是实际干活的服务节点。有些文章叫它"server"，其实是一个东西。worker 接收 client 上报的数据，执行热点判定，推送结果。它独立部署，不依赖 Spring Boot，是个纯 Java 进程。

## Q: 一个 etcd 集群可以支撑多少个应用？

理论上不限，但建议按业务域隔离。不同应用用不同的 `appName`，规则互不影响。大规模场景下建议 etcd 独立集群部署。

## Q: isHotKey 每次调用都会上报吗？

是的，`isHotKey` 每次调用都会在 client 本地的双 Map 中计数 +1。client 每隔 `pushPeriod`（默认 500ms）将聚合后的数据批量上报给 worker。所以不是每次调用都发网络请求，是**批量聚合后上报**，开销很小。

## Q: worker 的吞吐量怎么评估？

worker 内部用 `LinkedBlockingQueue`（容量 **200 万**）做消息缓冲，多线程消费。经验数据：**1 台 16 核 worker 可以支撑约 1000 台业务服务**。大促期间如果需要扛百万级热 key，大约需要 30 台 worker。

## Q: smartSet 和直接用 Caffeine 存有什么区别？

`smartSet` 内部用的也是 Caffeine，但它有个关键区别：**只有 key 被判定为热点时才会写入成功**。如果你直接用 Caffeine，所有 key 都会缓存，内存可能被非热点数据占满。`smartSet` 帮你做了这个过滤。

另外还有个 `forceSet` 方法可以强制设置缓存值（不管 key 是否热点），一般用不到。

## Q: 热点 key 被判定后，数据怎么填充到本地缓存？

JD-HotKey **只负责告诉你"这个 key 是热点"和"管理本地缓存的存取"**，不负责帮你从数据库加载数据。你需要在代码中自己实现数据加载逻辑（见场景二的示例代码）。

完整流程是这样的：
1. worker 判定热点 → 推送通知到所有 client
2. client 在 Caffeine 中存入**魔术值**（`0x12fcf76`）作为占位
3. 业务代码调用 `isHotKey(key)` 返回 `true`
4. 业务代码调用 `get(key)` → 返回 null（因为是魔术值占位，还没填实际数据）
5. 业务代码从 Redis / DB 加载真实数据
6. 调用 `smartSet(key, value)` 写入本地缓存
7. 后续请求直接命中本地缓存

## Q: 和 Redis Cluster 的热点 key 问题有什么关系？

Redis Cluster 的热点 key 问题是：某个 key 的访问量集中到一个分片节点，导致该节点 CPU / 带宽打满。JD-HotKey 的解决思路是**在应用层就把热点请求拦截掉**——数据缓存在 JVM 内存中，根本不会打到 Redis。两者是不同层面的解决方案。

## Q: 生产环境怎么部署？

推荐架构：
- **etcd**：3 节点集群（奇数，容忍 1 节点故障）
- **worker**：至少 2 个实例（worker 之间不通信，各自独立计算。client 通过 Hash 将不同 key 路由到不同 worker，天然负载均衡）
- **dashboard**：1-2 个实例（Web 控制台，不承载核心流量）
- **client**：嵌入每个业务应用实例

## Q: 和 JetCache 的两级缓存（BOTH）怎么配合？

它们不冲突，可以一起用：

- **JetCache BOTH**：适用于已知的高频读数据，提供 L1 + L2 两级缓存 + 自动刷新
- **JD-HotKey**：适用于不可预知的突发热点，自动发现并缓存

配合方式：JetCache 负责常规缓存，JD-HotKey 负责突发热点保护。当 JD-HotKey 判定某 key 为热点时，数据直接走 JVM 内存，连 JetCache 的 L2（Redis）都不需要访问。

---

# 九、总结

JD-HotKey 的核心价值在于**自动发现热点**——这是它区别于其他缓存方案的最大优势。你不需要提前知道哪些 key 会变热，系统会根据实际访问量自动判定、自动推送、自动过期释放。

|场景|推荐方案|
|---|---|
|已知的固定高频数据|Caffeine 或 JetCache BOTH|
|不可预知的突发热点|**JD-HotKey**|
|Redis 热点节点保护|JD-HotKey（应用层拦截）或 Redis 热点分片|
|热用户 / 热接口探测|**JD-HotKey**|

如果你的业务中存在"不知道什么时候会突然变热"的场景（电商秒杀、热搜话题、突发新闻），JD-HotKey 能帮你自动识别并保护这些热点 key，将请求拦截在 JVM 内存中，避免打垮 Redis 和数据库。

但它也不是万能的——etcd 的部署运维、依赖冲突的处理、阈值的调优，都需要一定的投入。建议先在非核心业务上试水，验证效果后再推广到核心链路。
