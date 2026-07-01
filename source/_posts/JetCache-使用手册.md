---
title: JetCache 使用手册
date: 2026-06-17
tags: [JetCache]
categories: 中间件
---

# 一、组件介绍

JetCache 是阿里巴巴开源的通用缓存访问框架（[开源地址](https://github.com/alibaba/jetcache)），它做了一件事：**用统一的 ****`Cache<K, V>`**** 接口，把本地内存缓存和远程 Redis 缓存无缝组合起来**，再通过注解、API 两种方式定义出标准的缓存协议接入层，让业务代码以最简洁的方式使用缓存。

和 Spring Cache 比，JetCache 的核心优势：

|能力|Spring Cache|JetCache|
|---|---|---|
|TTL（超时时间）|不原生支持，需自定义|**原生支持**，注解上直接写 `expire`|
|两级缓存|不支持|**原生支持** `CacheType.BOTH`（本地 \+ 远程）|
|缓存自动刷新|不支持|**支持** `@CacheRefresh`，分布式全局唯一刷新|
|穿透保护|不支持|**支持** `@CachePenetrationProtect`|
|分布式锁|不支持|**内置** `tryLock` / `tryLockAndRun`|
|异步 API|不支持|**支持**（Lettuce 客户端下真正非阻塞）|
|统计监控|需第三方|**内置** 命中率、加载次数等统计|
|更新/删除缓存注解|有但功能弱|`@CacheUpdate` / `@CacheInvalidate` 支持 SpEL|

# 二、核心概念

## 2\.1 Cache\<K, V\> 接口

不管你底层用的是 Caffeine（本地内存）、Redis（远程）还是两级缓存组合，业务代码面对的都是同一个接口：

```Java
public interface Cache<K, V> {
    V get(K key);
    void put(K key, V value);
    boolean remove(K key);
    V computeIfAbsent(K key, Function<K, V> loader);
    // ... 更多方法
}
```

用起来就像一个 `Map`，非常直观。

## 2\.2 CacheType — 缓存类型

|类型|含义|适用场景|备注|
|---|---|---|---|
|`CacheType.LOCAL`|纯本地内存缓存<br>（Caffeine 或 LinkedHashMap）|字典数据、配置项等变化少的数据|目前没有使用本地缓存的诉求<br>|
|`CacheType.REMOTE`|纯远程缓存（Redis）|一般业务场景，数据统一存 Redis|我们目前的使用场景<br>|
|`CacheType.BOTH`|两级缓存：本地 \+ 远程|高频读取，本地扛量 \+ Redis 兜底|目前没有使用多级缓存的诉求|

## 2\.3 Key 的生成规则

最终在 Redis 里存的 key 格式是：

```Java
Redis key = keyPrefix + keyConvertor(K)；
```

- **keyPrefix**：来自 `@Cached(name = "toc:user:info:")` 中的 `name`，或 `QuickConfig.newBuilder("toc:user:info:")` 中的参数。它的作用就是给不同业务的缓存加个"门牌号"，避免 key 冲突。

- **keyConvertor**：把 Java 对象转成 String。默认用 `fastjson2`，对 String 类型的 key 直接透传，对复杂对象做 JSON 序列化。

举个例子：`@Cached(name = "toc:user:info:", key = "#userId")` ，userId = 12345，最终 Redis 里的 key 就是 `toc:user:info:12345`。

## 2\.4 Area — 缓存区域

Area 是 JetCache 的多租户机制。默认有一个 `"default"` area，对应配置里的 `jetcache.local.default` 和 `jetcache.remote.default`。如果你的项目需要连多个 Redis 实例，可以配多个 area，然后在注解里通过 `area = "otherArea"` 指定。大多数场景用默认的就行。

---

# 三、快速接入（Spring Boot）

## 第一步：添加 Maven 依赖

根据业务应用的 Redis 客户端，选择对应的 starter（**三选一**）：

```XML
<!-- 方式一：Lettuce（推荐，支持异步 API） -->
<dependency>
    <groupId>com.alicp.jetcache</groupId>
    <artifactId>jetcache-starter-redis-lettuce</artifactId>
    <version>2.8.0</version>
</dependency>

<!-- 方式二：Jedis（经典选择） -->
<dependency>
    <groupId>com.alicp.jetcache</groupId>
    <artifactId>jetcache-starter-redis</artifactId>
    <version>2.8.0</version>
</dependency>

<!-- 方式三：Redisson（功能丰富） -->
<dependency>
    <groupId>com.alicp.jetcache</groupId>
    <artifactId>jetcache-starter-redisson</artifactId>
    <version>2.8.0</version>
</dependency>
```

**版本说明**：JetCache 2\.8\+ 需要 **JDK 17\+**、**Spring Boot 3\.x\+**、**Spring Framework 6\.x\+**。如果你的项目还在 JDK 8，请用 2\.7\.x 版本。

## 第二步：配置 application\.yml

```YAML
jetcache:
  # 统计间隔（分钟），0 表示不统计，生产建议 15
  statIntervalMinutes: 15
  # key 前缀是否包含 areaName，新项目建议 false
  areaInCacheName: false
  # 反序列化白名单（2.8+ 必须配置）
  decodeFilterAllowPatterns:
    - com.remotecarter.

  # 本地缓存配置
  local:
    default:
      type: caffeine                        # 推荐 caffeine，也可用 linkedhashmap
      limit: 100                            # 每个缓存实例最大元素数
      keyConvertor: fastjson2               # key 转换方式
      expireAfterWriteInMillis: 60000       # 本地缓存默认超时（毫秒）

  # 远程缓存配置
  remote:
    default:
      type: redis.redisson                   # redis / redis.lettuce / redis.redisson
      keyConvertor: fastjson2
      # 广播 channel，用于两级缓存跨节点同步失效
      # 多个服务共用 Redis 时，不同服务用不同 channel，避免广播风暴
      broadcastChannel: crm-user
      valueEncoder: java                    # 序列化：java / kryo / kryo5
      valueDecoder: java
      poolConfig:
        minIdle: 5
        maxIdle: 20
        maxTotal: 50
      host: ${REDIS_HOST:127.0.0.1}
      port: ${REDIS_PORT:6379}
      # 如果用 lettuce，也可以用 uri 方式
      # uri: redis://127.0.0.1:6379/0
```

## 第三步：启动类加注解

```Java
@SpringBootApplication
@EnableMethodCache(basePackages = "com.remotecarter")// 激活 @Cached 等注解
@EnableCreateCacheAnnotation                      // 激活 @CreateCache 注解(Deprecated可以不加）
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}
```

- **`@EnableMethodCache(basePackages = "...")`**：告诉 JetCache 去扫描哪些包下的 Spring Bean，对其中的 `@Cached`、`@CacheUpdate`、`@CacheInvalidate` 等注解做 AOP 代理。**basePackages 要覆盖你所有用了缓存注解的包**。

- **`@EnableCreateCacheAnnotation`**：激活 `@CreateCache` 注解支持，用于在字段上直接注入 Cache 实例，源码标记 Deprecated 了，可以不加。

至此，接入完成。下面开始介绍怎么用。

# 四、使用介绍

## 4\.1 注解驱动缓存（声明式）

这是最常用的方式。在 Service 接口（或实现类）的方法上加注解，JetCache 通过 Spring AOP 代理自动处理缓存的读、写、删。

**注意**：注解可以加在接口方法上，也可以加在类方法上，但被注解的类必须是 **Spring Bean**。

### @Cached — 缓存读取

```Java
public interface UserService {

    // 指定 name 和 key
    @Cached(name = "toc:user:info:", key = "#uuid", expire = 3600, cacheType = CacheType.REMOTE)
    User getUserById(String uuid);

    // 缓存 null 值（防止缓存穿透）
    @Cached(name = "toc:user:info:", key = "#uuid", expire = 300, cacheNullValue = true)
    User getUserById(String uuid);
}
```

### **@Cached**** — ****属性详解**

|属性|默认值|说明|
|---|---|---|
|`area`|`"default"`|缓存区域，一般不用改|
|`name`|自动生成（类名\.方法名）|缓存唯一名称，**会作为 Redis key 的前缀**|
|`key`|自动生成（根据所有参数）|SpEL 表达式指定 key，如 `"#userId"` 或 `"args[0]"`|
|`expire`|跟随全局配置|超时时间|
|`timeUnit`|`TimeUnit.SECONDS`|expire 的时间单位|
|`cacheType`|`CacheType.REMOTE`|LOCAL / REMOTE / BOTH|
|`localLimit`|100|本地缓存最大元素数（LOCAL/BOTH 时生效）|
|`localExpire`|同 expire|本地缓存单独的超时时间（仅 BOTH 时生效）|
|`syncLocal`|false|更新时广播失效其他 JVM 的本地缓存（仅 BOTH 时生效）|
|`serialPolicy`|`java`|序列化方式：`SerialPolicy.JAVA` 或 `SerialPolicy.KRYO`|
|`keyConvertor`|`fastjson2`|key 转换方式|
|`enabled`|true|是否启用缓存，false 时不走缓存，可通过 `CacheContext.enableCache` 临时激活|
|`cacheNullValue`|false|方法返回 null 时是否缓存|
|`condition`|无|SpEL 表达式，返回 true 才查缓存（方法执行前评估）|
|`postCondition`|无|SpEL 表达式，返回 true 才更新缓存（方法执行后评估，可用 `#result`）|

### @CacheUpdate — 更新缓存

当数据被修改时，用这个注解直接更新缓存，避免等 TTL 过期：

```Java
public interface UserService {

    @Cached(name = "toc:user:info:", key = "#uuid", expire = 3600)
    User getUserById(String uuid);

    // 更新缓存：key 和 name 必须和 @Cached 对应
    @CacheUpdate(name = "toc:user:info:", key = "#user.uuid", value = "#user")
    void updateUser(User user);
}
```

### @CacheInvalidate — 删除缓存

数据被删除时，从缓存中也移除：

```Java
@CacheInvalidate(name = "toc:user:info:", key = "#uuid")
void deleteUser(String uuid);
```

**@CacheUpdate 和 @CacheInvalidate 的共同注意点**：它们的 `name` 和 `area` 必须和对应的 `@Cached` 完全一致，这样 JetCache 才知道操作的是哪个缓存。

### @CacheRefresh — 自动刷新

这是 JetCache 的特色功能之一。对于加载开销大、实时性要求不高的数据（比如报表汇总），配置自动刷新，**防止缓存过期瞬间的并发请求打爆数据库（缓存雪崩）**：

```Java
public interface SummaryService {

    @Cached(expire = 3600, cacheType = CacheType.REMOTE)
    @CacheRefresh(refresh = 1800, stopRefreshAfterLastAccess = 3600, timeUnit = TimeUnit.SECONDS)
    BigDecimal salesVolumeSummary(int timeId, long categoryId);
}
```

|属性|默认值|说明|
|---|---|---|
|`refresh`|无|刷新间隔|
|`timeUnit`|`TimeUnit.SECONDS`|时间单位|
|`stopRefreshAfterLastAccess`|无（一直刷新）|该 key 多久没访问就停止刷新|
|`refreshLockTimeout`|60 秒|刷新时在 Redis 放的分布式锁超时时间|

**关键特性**：当 `cacheType` 为 REMOTE 或 BOTH 时，**刷新行为是集群全局唯一的**——不管有多少台服务器，同时只有一个节点在刷新某个 key，通过分布式锁实现。

### @CachePenetrationProtect — 穿透保护

```Java
@Cached(expire = 3600, cacheType = CacheType.REMOTE)
@CachePenetrationProtect
User getUserById(long userId);
```

当缓存未命中时，**同一个 JVM 内同一个 key 只有一个线程去加载**，其他线程等待结果。防止高并发场景下大量请求同时穿透到数据库。

当前实现是 **单机的保护**，不是分布式级别的。如果多个节点同时遇到同一个 key 的缓存未命中，各节点会各自加载一次。

**我们可以这样组合：自动刷新 \+ 穿透保护**

```Java
@Cached(name = "toc:user:info:", key = "#uuid", expire = 3600)
@CacheRefresh(refresh = 1800, stopRefreshAfterLastAccess = 3600, timeUnit = TimeUnit.SECONDS)
@CachePenetrationProtect
User getUserById(String uuid);
```

每 30 分钟自动刷新（集群唯一），30 分钟没人访问就停止刷新，万一缓存未命中还有穿透保护。

## 4\.2 编程式缓存（Cache API）

注解方式虽然简洁，但灵活性有限——比如你需要在运行时动态决定 key，或者想在非 Spring 管理的类中使用缓存。这时候就用 **Cache API**。

### CacheManager \+ QuickConfig 创建缓存实例

```Java
@Component
public class OrderService implements InitializingBean {

    @Autowired
    private CacheManager cacheManager;

    private Cache<String, OrderDO> orderCache;

    @Override
    public void afterPropertiesSet() {
        QuickConfig qc = QuickConfig.newBuilder("userCache")
            .expire(Duration.ofSeconds(300))
            .cacheType(CacheType.BOTH)    // 两级缓存
            .syncLocal(true)              // 更新时广播失效其他节点本地缓存
            .localLimit(200)              // 本地缓存最大元素数
            .build();
        orderCache = cacheManager.getOrCreateCache(qc);
    }
}
```

`QuickConfig` 支持的配置项：

|方法|说明|
|---|---|
|`expire(Duration)`|超时时间|
|`localExpire(Duration)`|本地缓存单独超时（BOTH 时）|
|`localLimit(Integer)`|本地缓存最大元素数|
|`cacheType(CacheType)`|LOCAL / REMOTE / BOTH|
|`syncLocal(Boolean)`|是否跨节点同步失效本地缓存|
|`keyConvertor(Function)`|key 转换器|
|`valueEncoder / valueDecoder`|序列化/反序列化|
|`cacheNullValue(Boolean)`|是否缓存 null|
|`penetrationProtect(Boolean)`|是否开启穿透保护|
|`penetrationProtectTimeout(Duration)`|穿透保护超时时间|
|`refreshPolicy(RefreshPolicy)`|自动刷新策略|
|`loader(CacheLoader)`|缓存未命中时的加载函数|

### 基本操作

```Java
// 读取
UserDO user = userCache.get("toc:user:info:12345");

// 写入
userCache.put("toc:user:info:12345", user);

// 写入并指定超时
userCache.put("toc:user:info:12345", user, 10, TimeUnit.MINUTES);

// 删除
userCache.remove("toc:user:info:12345");

// 批量读取
Map<String, UserDO> users = userCache.getAll(Set.of("toc:user:info:1", "toc:user:info:2", "toc:user:info:3"));

// 批量写入
userCache.putAll(Map.of("toc:user:info:1", o1, "toc:user:info:2", o2));

// 批量删除
userCache.removeAll(Set.of("toc:user:info:1", "toc:user:info:2"));
```

### computeIfAbsent — 缓存未命中时自动加载

这个方法非常实用，相当于 `get` \+ `put` 的原子操作：

```Java
// 缓存命中直接返回，未命中则调用 loader 加载并写入缓存
OrderDO order = userCache.computeIfAbsent("toc:user:info:12345", key -> {
    return userMapper.selectById(key);  // 从数据库加载
});
```

也可以在创建缓存时就设置好 loader，这样每次 `get` 都会自动加载：

```Java
// 创建时设置 loader
QuickConfig qc = QuickConfig.newBuilder("userCache")
    .expire(Duration.ofSeconds(300))
    .loader(key -> userMapper.selectById(key))
    .build();
userCache = cacheManager.getOrCreateCache(qc);

// 之后直接 get 就行，未命中会自动调 loader
UserDO user = userCache.get("toc:user:info:12345");
```

### 大写 API — 带完整状态码的操作

小写的 `get()` 返回 null 时，你分不清是"缓存中没有"还是"缓存出错了"。大写 API 返回 `CacheGetResult`，提供了完整的状态信息：

```Java
CacheGetResult<UserDO> r = userCache.GET("toc:user:info:12345");
if (r.isSuccess()) {
    UserDO user = r.getValue();
    // 处理业务
} else if (r.getResultCode() == CacheResultCode.NOT_EXISTS) {
    // 缓存不存在
} else if (r.getResultCode() == CacheResultCode.EXPIRED) {
    // 缓存已过期
} else {
    // 缓存访问出错（网络异常等）
}
```

其他大写 API：`GET_ALL`、`PUT`、`PUT_ALL`、`REMOVE`、`REMOVE_ALL`、`PUT_IF_ABSENT`。

### 异步 API

当使用 **Lettuce** 客户端时，大写 API 支持真正的异步非阻塞：

```Java
CacheGetResult<UserDO> r = userCache.GET("toc:user:info:12345");
// 此时操作可能还没完成
CompletionStage<ResultData> future = r.future();
future.thenRun(() -> {
    if (r.isSuccess()) {
        System.out.println(r.getValue());
    }
});
```

注意：小写的 `put()` 和 `removeAll()` 没有返回值，在 Lettuce 下会被自动优化为异步调用，减少 RT。但 `get()` 需要等待结果，所以仍然会阻塞。

# 五、Key 类型与策略

JetCache 的 key 是怎么生成和处理的，搞清楚这个才能在 Redis 里看到符合预期的 key。

## 5\.1 Redis Key 的拼接规则

```Java
Redis 中的 key = keyPrefix + keyConvertor(Java Key 对象)
```

举个例子：

- `@Cached(name = "``toc:user:info:``", key = "#``userId``")` \+ userId= `12345`（long 类型）

- keyConvertor 把 long 转成 `"Long12345"`

- 最终 Redis key = `toc:user:info:Long12345`

如果 key 是 String 类型：

- `@Cached(name = "``toc:user:info:``", key = "#uuid")` \+ uuid = `"``X123456``"`

- keyConvertor 对 String 直接透传

- 最终 Redis key = `toc:user:info:X123456`

## 5\.2 支持的 Key 类型

从 `ExternalKeyUtil.buildKeyAfterConvert` 源码可知，JetCache 支持以下 key 类型：

|Java 类型|转换规则|示例|
|---|---|---|
|`String`|**直接使用**，不转换|`"abc"` → `abc`|
|`Number`（Long、Integer 等）|类名 \+ 值|`12345L` → `Long12345`|
|`Date`|类名 \+ yyyyMMddHHmmss,SSS|`new Date()` → `Date20260617100000,000`|
|`Boolean`|toString|`true` → `true`|
|`byte[]`|直接使用|—|
|其他 `Serializable` 对象|Java 序列化|复杂对象 → 序列化字节|

**实践建议**：**推荐使用 String 类型的 key**。如果你用 Long/Integer 类型的 key，最终 Redis 里会带个 `Long`/`Integer` 前缀，虽然不影响功能，但看起来不直观。在 SpEL 里做一下转换就行：`key = "'' + #userId"` 或 `key = "#userId.toString()"`。

## 5\.3 keyConvertor 机制

keyConvertor 负责把 Java 对象转成 Redis 能存的 String：

|值|说明|
|---|---|
|`fastjson2`|**默认推荐**。String 直接透传，其他对象用 `JSON.toJSONString()` 转|
|`jackson`|用 Jackson 转 JSON|
|`jackson3`|Jackson 3\.x 版本|
|`none`|不转换，直接 `equals` 比较。仅用于 `@CreateCache` 且 `cacheType = LOCAL` 的场景|

## 5\.4 SpEL 表达式指定 Key

`@Cached` 的 `key` 属性支持 Spring 的 SpEL 表达式：

```Java
// 直接用参数名（需 javac -parameters 编译）
@Cached(name = "toc:user:info:", key = "#uuid", expire = 3600)
User getUserById(String uuid);

// 按下标访问（不需要 -parameters）
@Cached(name = "toc:user:info:", key = "args[0]", expire = 3600)
User getUserById(String uuid);

// 访问对象属性
@Cached(name = "toc:user:info:", key = "#user.uuid", expire = 3600)
User getUser(User user);

// 字符串拼接
@Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid", expire = 1800)
List<Archives> getArchives(String appId, String uuid);
```

**注意**：使用参数名（如 `#userId`）需要编译时加 `-parameters` 参数，否则只能用 `args[0]` 按下标访问。

**Maven 配置：**

```XML
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <compilerArgument>-parameters</compilerArgument>
    </configuration>
</plugin>
```

**IntelliJ IDEA 配置**：Settings → Build → Compiler → Java Compiler → Additional command\-line parameters，填入 `-parameters`。

## 5\.5 单值 vs 多值缓存场景

JetCache 是纯 KV 模型（底层用 Redis STRING 类型），**不支持 Redis HASH 的子字段操作**（HGET/HSET）。如果你之前用 Redisson 的 `RMap` 做过 Hash 缓存，迁移到 JetCache 时需要调整思路。

**场景：****`toc:u`****`ser:archives:{uuid}`**** 一个用户对应多条 KYC 记录**

Redisson 的做法（Hash 粒度操作）：

```Java
// Redisson：可以按 kycType 单独读写
RMap<String, String> map = redissonClient.getMap("user:archives:" + uuid);
map.put("archive_real", jsonString);           // HSET
String json = map.get("archive_real");         // HGET
```

JetCache 的做法（整体缓存）：

```Java
// 方案一：整个 List 作为 value
@Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid", expire = 30, timeUnit = TimeUnit.MINUTES)
List<ApiArchivesStatus> getAllArchives(String appId, String uuid);

// 按 kycType 查：整体取出后在内存中过滤
public ApiArchivesStatus getByKycType(String appId, String uuid, String kycType) {
    return getAllArchives(appId, uuid).stream()
        .filter(s -> kycType.equals(s.getKycType()))
        .findFirst().orElse(null);
}

// 方案二：Map 作为 value（kycType 作为 Map 的 key）
@Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid", expire = 30, timeUnit = TimeUnit.MINUTES)
Map<String, ApiArchivesStatus> getArchivesMap(String appId, String uuid);
```

JetCache 无法做 Hash 字段级操作，需要把「uuid 对应的全部数据」作为一个完整的 value 来缓存。如果业务对子字段粒度读写要求很高，建议保留 Redisson RMap；如果整体读写为主，JetCache 的两级缓存、自动刷新等能力更有价值。

---

# 六、两级缓存（BOTH）

两级缓存是 JetCache 的一大亮点，虽然我们暂时用不到。简单来说就是：**本地内存缓存（L1）\+ Redis（L2）组合使用，读的时候先查 L1 再查 L2，写的时候两级都写。**

## 6\.1 工作原理

```Plaintext
读取流程：
  1. 查本地缓存（Caffeine/LinkedHashMap）
  2. 本地命中 → 直接返回
  3. 本地未命中 → 查 Redis
  4. Redis 命中 → 回填本地缓存 → 返回
  5. Redis 也未命中 → 返回 NOT_EXISTS

写入流程：
  1. 同时写入本地缓存和 Redis

删除流程：
  1. 同时删除本地缓存和 Redis 中的 key
```

## 6\.2 配置使用

### 注解方式：

```Java
@Cached(name = "toc:user:info:", key = "#uuid", expire = 3600,
    cacheType = CacheType.BOTH,     // 两级缓存
    syncLocal = true,               // 更新时广播失效其他节点本地缓存
    localLimit = 100,               // 本地最大元素数
    localExpire = 60                // 本地缓存 60 秒超时（通常小于远程的 expire）
)
User getUserById(String uuid);
```

### 编程方式：

```Java
QuickConfig qc = QuickConfig.newBuilder("userCache")
    .expire(Duration.ofSeconds(3600))
    .cacheType(CacheType.BOTH)
    .syncLocal(true)
    .localLimit(100)
    .localExpire(Duration.ofSeconds(60))
    .build();
Cache<Long, User> userCache = cacheManager.getOrCreateCache(qc);
```

## 6\.3 syncLocal — 跨节点同步失效

这是两级缓存的关键配置。加入你有 3 台服务器，每台都有本地缓存。如果节点 A 更新了某个用户数据，节点 B 和 C 的本地缓存还是旧值，这就出现了不一致。

`syncLocal = true` 的解决方式：

1. 节点 A 更新缓存时，向 Redis 的 `broadcastChannel` 发一条失效消息

2. 节点 B 和 C 订阅了这个 channel，收到消息后清除本地对应的缓存

3. 下次读取时，B 和 C 会从 Redis 拉取最新数据

**前提条件**：yml 中必须配置了 `broadcastChannel`。

```YAML
jetcache:
  remote:
    default:
      broadcastChannel: crm-user  # 必须有这个配置
```

**注意**：多个服务共用同一个 Redis 时，不同服务请使用不同的 `broadcastChannel`，否则一个服务的缓存更新会触发其他服务的本地缓存全部失效，造成广播风暴。

## 6\.4 localExpire — 本地和远程过期时间分离

两级缓存场景下，本地缓存的过期时间通常应该 **小于** 远程缓存。比如远程设 1 小时，本地设 1 分钟，这样即使广播消息丢失，本地最多 1 分钟后也会自动过期重新从 Redis 拉取。

|场景|推荐 CacheType|理由|
|---|---|---|
|字典数据、配置项|`LOCAL`|变化少，本地内存就够了|
|一般业务数据|`REMOTE`|统一存 Redis，简单可靠|
|高频读 \+ 可接受秒级不一致|`BOTH` \+ `syncLocal = true`|本地扛读压力，Redis 兜底|
|高频读 \+ 数据量特别大|`BOTH` \+ `localLimit` 控制大小|避免本地内存撑爆|

---

# 七、序列化配置

远程缓存（Redis）里的数据是字节流，存入时需要 **序列化（encode）**，取出时需要 **反序列化（decode）**。JetCache 提供了三种序列化方式：

## 7\.1 valueEncoder / valueDecoder 选择

|方式|优点|缺点|
|---|---|---|
|`java`（默认）|兼容性最好，Java 原生|性能最差，字节数最大|
|`kryo` / `kryo5`|性能好，字节数小|需要注册类，升级时注意兼容|

```YAML
jetcache:
  remote:
    default:
      valueEncoder: java    # 或 kryo / kryo5
      valueDecoder: java
```

这里不建议自定义编解码实现，存在造成多级缓存不一致的风险。因为编解码器不一致，会导致 jetcache 广播 start 异常。

## 7\.2 反序列化安全过滤器（2\.8\+）

JetCache 2\.8\.x 默认开启了反序列化安全过滤器，**只允许白名单中的类被反序列化**。这是为了防止反序列化漏洞攻击。默认白名单包含：`java.lang`、`java.util.`、`java.time.`、`java.math`、`com.alicp.jetcache.`。

如果你的缓存值包含自定义类（比如 `UserDO`、`OrderDO`），**必须添加白名单**，否则反序列化会报错：

```YAML
jetcache:
  decodeFilterAllowPatterns:
    - com.remotecarter.                    # 前缀匹配：该包及子包下所有类
    - com.remotecarter.UserDto             # 精确匹配：仅这一个类
```

**模式匹配规则：**

|模式|匹配方式|示例|
|---|---|---|
|`com.``remotecarter``.`<br>|前缀匹配（以 `.` 结尾）|匹配 `com.remotecarter.Foo`、`com.remotecarter.sub.Bar`|
|`com.``remotecarter`|包名匹配（不以 `.` 结尾）|仅匹配 `com.remotecarter.Foo`，不含子包|
|`com.``remotecarter``.``User``Dto`|精确匹配（完整类名）|仅匹配 `com.remotecarter.UserDto`|

拒绝列表（内置）包含已知反序列化攻击 gadget chain（Commons Collections、Spring AOP、Hibernate 等），以及 `Runtime`、`ProcessBuilder` 等危险类。**拒绝列表不可被允许列表覆盖。**

也可以通过编程方式配置：

```Java
DecodeFilter.getDefault().addAllowPatterns("com.yourcompany.");
```

# 八、业务接入实战

## 场景一：单值缓存（用户信息）

最常见的场景——按 ID 查用户，缓存到 Redis。

```Java
public interface UserService {

    @Cached(name = "toc:user:info:", key = "#uuid", expire = 3600, cacheType = CacheType.REMOTE)
    User getUserById(String uuid);

    @CacheUpdate(name = "toc:user:info:", key = "#user.uuid", value = "#user")
    void updateUser(User user);

    @CacheInvalidate(name = "toc:user:info:", key = "#uuid")
    void deleteUser(String uuid);
}
```

Redis 里的 key 长这样：`toc:user:info:X12345`。

## 场景二：多值缓存（Hash 替代方案）

一个用户对应多条 KYC 记录，之前在 Redisson 中用 `RMap`（Hash）实现，迁移到 JetCache 后用 **整体缓存** 替代：

```Java
// 整个 List 作为一条缓存
public interface ArchivesCacheService {

    @Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid",
            expire = 30, timeUnit = TimeUnit.MINUTES, cacheType = CacheType.REMOTE)
    List<ApiArchivesStatus> getAllArchives(String appId, String uuid);

    @CacheUpdate(name = "toc:user:archives:", key = "#appId + ':' + #uuid", value = "#list")
    void saveAllArchives(String appId, String uuid, List<ApiArchivesStatus> list);

    @CacheInvalidate(name = "toc:user:archives:", key = "#appId + ':' + #uuid")
    void deleteArchives(String appId, String uuid);
}

// 按 kycType 查询
@Service
public class ArchivesServiceImpl {
    @Autowired
    private ArchivesCacheService archivesCacheService;

    public ApiArchivesStatus getByKycType(String appId, String uuid, String kycType) {
        List<ApiArchivesStatus> list = archivesCacheService.getAllArchives(appId, uuid);
        return list.stream()
            .filter(s -> kycType.equals(s.getKycType()))
            .findFirst()
            .orElse(null);
    }
    
    // 也可以使用 Map
}
```

## 场景三：高频读 \+ 自动刷新（报表汇总）

```Java
public interface ReportService {
    @Cached(expire = 7200, cacheType = CacheType.BOTH, syncLocal = true)
    @CacheRefresh(refresh = 1800, stopRefreshAfterLastAccess = 3600, timeUnit = TimeUnit.SECONDS)
    @CachePenetrationProtect
    ReportSummary getReportSummary(String reportId);
}
```

缓存 2 小时，每 30 分钟自动刷新一次（集群唯一），30 分钟没人访问就停止刷新。本地 \+ Redis 两级缓存，万一未命中还有穿透保护。

## 场景四：条件缓存

**普通场景下需要根据条件决定是否使用缓存：**

```Java
// 只有 type 为 1 的时候才走缓存
@Cached(name = "data-", key = "#id", expire = 3600, condition = "#type == 1")
DataObject getData(long id, int type);

// 只有结果不为空才缓存
@Cached(name = "data-", key = "#id", expire = 3600, postCondition = "#result != null")
DataObject getData(long id);

// 某个场景下临时禁用缓存（比如数据导出时不能用缓存）
@Cached(name = "data-", key = "#id", expire = 3600, enabled = false)
DataObject getData(long id);

// 在需要缓存的地方激活
public void exportData() {
    CacheContext.enableCache(() -> {
        // 这里的 getData 会走缓存
        DataObject data = getData(123L);
        return data;
    });
}
```

**如果需要通过配置热部署开启 / 关闭缓存：**

```Java
package com.remotecarter.appuser.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.stereotype.Component;

@Component
@RefreshScope
public class SwitchCache {

    private static volatile boolean *CACHE_ON *= true;

    @Value("${nacos.user.info.cacheOn:true}")
    public void setCacheOn(boolean cacheOn) {
        *CACHE_ON *= cacheOn;
    }

    public static boolean isCacheOn() {
        return *CACHE_ON*;
    }
}

@Cached(name = "toc:user:info:",
        key = "#uuid",
        expire = 3600,
        condition = "T(com.remotecarter.appuser.config.SwitchCache).isCacheOn()")
interface UserInfoDetailDTO queryUserDetail(String uuid);
```

## 最佳实践与注意事项

### 1\. TTL 必须设置

`@CacheUpdate` 和 `@CacheInvalidate` 可能因为网络波动失败。如果没有设置 TTL，失败的删除/更新操作就会导致缓存永远不一致。**一定要设置合理的 expire 作为最终一致性的兜底**。

### 2\. 序列化选择

- **开发阶段 / 不确定选啥**：用 `java`，兼容性最好;

- **追求性能**：用 `kryo`，体积小、速度快，但需要注册类;

- **JSON 序列化**：不推荐。JSON 不是专门的 Java 序列化工具，反射无法识别类型时会反序列化为 JSONObject，兼容性差;

### 3\. broadcastChannel 隔离

多个服务共用同一个 Redis 实例时，不同服务一定要用不同的 `broadcastChannel`。否则 A 服务更新了缓存，广播消息会触发 B 服务的本地缓存失效——虽然看起来没啥问题，但当广播量大的时候就是灾难。

### 4\. AOP 代理陷阱

JetCache 的注解通过 Spring AOP 代理实现。**同一个类内部的方法调用不经过代理，缓存不会生效**：

```Java
@Service
public class UserServiceImpl implements UserService {

    public User getUser(long userId) {
        // 这里调用了 getUserById，但缓存不会生效！
        // 因为 this.getUserById() 不经过代理
        return getUserById(userId);
    }

    @Cached(expire = 3600)
    public User getUserById(long userId) {
        return userMapper.selectById(userId);
    }
}
```

**解决办法**：通过 `@Autowired` 注入自己，用注入的实例调用：

```Java
@Service
public class UserServiceImpl implements UserService {

    @Autowired
    private UserService self;  // 注入代理实例

    public User getUser(long userId) {
        return self.getUserById(userId);  // 经过代理，缓存生效
    }
}
```

### 5\. \-parameters 编译参数

如果想在 SpEL 中用参数名（如 `#uuid`），编译时必须加 `-parameters` 参数。否则只能用 `args[0]` 按下标访问。

### 6\. name 命名规范

`name` 会作为 Redis key 的前缀，建议：

- 用业务含义明确的名称，如 `"toc:user:info:"`;

- 末尾加 `-` 或 `:` 作为分隔符，如 `"userCache-12345"`

- 不要给不同的 `@Cached` 注解分配相同的 `name + area`

### 7\. 本地缓存的内存控制

`localLimit` 是**每个缓存实例**的限制，不是全部。如果有 10 个 `@CreateCache` 创建的缓存实例，每个 limit 100，那本地总共可能有 1000 个元素。大对象场景下要注意控制。

# 九、FAQ

## Q: @Cached 注解加在同类的另一个方法上，为什么没生效？

Spring AOP 基于代理实现，同类内部的方法调用不经过代理。解决方案见上面"最佳实践"第 4 条。

## Q: 用了参数名做 key，但缓存没生效？

检查是否配置了 `-parameters` 编译参数。没有配置的话改用 `args[0]` 按下标访问。

## Q: 升级到 2\.8 后反序列化报错？

2\.8\+ 默认开启了反序列化安全过滤器。需要在 yml 中配置 `decodeFilterAllowPatterns` 添加你的自定义类所在的包。

## Q: 如何同时连接多个 Redis 实例？

配置多个 area：

```YAML
jetcache:
  remote:
    default:
      host: redis-host-1
      port: 6379
    second:
      host: redis-host-2
      port: 6380
```

然后在注解中指定 area：`@Cached(area = "second", ...)`。

## Q: @CacheUpdate / @CacheInvalidate 操作失败了怎么办？

这两个操作可能因网络问题失败。JetCache 不会抛异常，只是静默失败。所以 **设置合理的 TTL 是必须的**——即使更新/删除失败，缓存也会在 TTL 后自动过期，从数据库重新加载。

## Q: 本地缓存和 Redis 数据不一致怎么办？

确保配置了 `syncLocal = true` 和 `broadcastChannel`。另外设置一个比 Redis expire 更小的 `localExpire`，作为兜底——即使广播消息丢失，本地缓存也会在 localExpire 后自动过期。

## Q: JetCache 的分布式锁能用吗？

JetCache 的锁是基于 Redis `SETNX` \+ TTL 实现的**非严格分布式锁**，适用于"防止重复执行"的场景。可以用。但目前了解到各域都有自己的分布式锁，建议还是用自己的吧，毕竟 JetCache 核心职责是定义缓存框架协议。

## Q：完整配置参考列表

```YAML
jetcache:
  # ============ 全局配置 ============
  statIntervalMinutes: 15                    # 统计间隔（分钟），0 = 不统计
  areaInCacheName: false                     # key 前缀是否包含 area，新项目建议 false
  hidePackages: com.remotecarter                # 自动生成 name 时截掉的包名前缀
  useDefaultLocalExpireInMultiLevelCache: false  # BOTH 时是否用本地 builder 的超时

  # ============ 反序列化安全（2.8+） ============
  decodeFilterEnabled: true                  # 总开关
  decodeFilterAllowPatterns:                 # 允许列表
    - com.remotecarter.
  decodeFilterDenyPatterns:                  # 拒绝列表（始终优先于允许列表）
    - com.dangerous.

  # ============ 本地缓存配置 ============
  local:
    default:                                 # area 名称
      type: caffeine                         # caffeine 或 linkedhashmap
      limit: 100                             # 每个缓存实例最大元素数
      keyConvertor: fastjson2                # fastjson2 / jackson / jackson3 / none
      expireAfterWriteInMillis: 60000        # 默认超时（毫秒）
      expireAfterAccessInMillis: 0           # 访问后超时（0 = 不使用）

    # 可以配多个 area
    otherArea:
      type: linkedhashmap
      limit: 50
      keyConvertor: none

  # ============ 远程缓存配置 ============
  remote:
    default:                                 # area 名称
      type: redis.redisson                   # redis / redis.lettuce / redis.redisson / redis.springdata
      keyConvertor: fastjson2                # key 转换
      valueEncoder: java                     # 序列化：java / kryo / kryo5
      valueDecoder: java                     # 反序列化：java / kryo / kryo5
      broadcastChannel: crm-user             # 两级缓存广播 channel（未配置则不开启）

      # --- Jedis / Redisson 连接池配置 ---
      poolConfig:
        minIdle: 5
        maxIdle: 20
        maxTotal: 50
      host: 127.0.0.1
      port: 6379
      # password: xxx                       # 有密码时配置

      # --- Lettuce 连接（二选一） ---
      # uri: redis://127.0.0.1:6379/0

      expireAfterWriteInMillis: 300000       # 默认超时（毫秒）
```



