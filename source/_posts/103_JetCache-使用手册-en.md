---
title: "JetCache User Guide"
date: 2026-06-17
tags: [JetCache]
categories: Middleware
lang: en
label: 103_JetCache-使用手册
---

# 1. Component Overview

JetCache is a general-purpose cache access framework open-sourced by Alibaba ([source](https://github.com/alibaba/jetcache)). It does one thing: with a unified `Cache<K, V>` interface, it seamlessly combines local in-memory cache with remote Redis cache, then provides standard cache protocol integration through both annotations and API — letting business code use caching in the most concise way possible.

Compared to Spring Cache, JetCache's core advantages:

|Capability|Spring Cache|JetCache|
|---|---|---|
|TTL (time-to-live)|Not natively supported, requires customization|**Natively supported** — write `expire` directly on the annotation|
|Two-level cache|Not supported|**Natively supported** `CacheType.BOTH` (local + remote)|
|Auto cache refresh|Not supported|**Supported** `@CacheRefresh` with globally unique distributed refresh|
|Penetration protection|Not supported|**Supported** `@CachePenetrationProtect`|
|Distributed lock|Not supported|**Built-in** `tryLock` / `tryLockAndRun`|
|Async API|Not supported|**Supported** (truly non-blocking with Lettuce client)|
|Stats & monitoring|Requires third-party|**Built-in** hit rate, load count, and other statistics|
|Update/delete cache annotations|Exists but limited|`@CacheUpdate` / `@CacheInvalidate` with SpEL support|

![alt text](/img/jetcache-final.png)

# 2. Core Concepts

<!-- more -->
## 2.1 Cache<K, V> Interface

Whether the underlying implementation is Caffeine (local memory), Redis (remote), or a two-level combination, business code always faces the same interface:

```Java
public interface Cache<K, V> {
    V get(K key);
    void put(K key, V value);
    boolean remove(K key);
    V computeIfAbsent(K key, Function<K, V> loader);
    // ... more methods
}
```

Using it feels like working with a `Map` — very intuitive.

## 2.2 CacheType — Cache Types

|Type|Meaning|Use Case|Notes|
|---|---|---|---|
|`CacheType.LOCAL`|Pure local in-memory cache<br>(Caffeine or LinkedHashMap)|Dictionary data, config items, rarely changing data|No current use case for local cache|
|`CacheType.REMOTE`|Pure remote cache (Redis)|General business scenarios, centralized Redis storage|Our current usage|
|`CacheType.BOTH`|Two-level cache: local + remote|High-frequency reads, local for volume + Redis as fallback|No current use case for multi-level cache|

## 2.3 Key Generation Rules

The final key stored in Redis follows this format:

```Java
Redis key = keyPrefix + keyConvertor(K);
```

- **keyPrefix**: comes from `@Cached(name = "toc:user:info:")`'s `name`, or from `QuickConfig.newBuilder("toc:user:info:")`'s parameter. Its job is to give different business domains a "namespace prefix" to avoid key collisions.

- **keyConvertor**: converts Java objects to Strings. The default uses `fastjson2` — String-type keys pass through directly, complex objects get JSON-serialized.

Example: `@Cached(name = "toc:user:info:", key = "#userId")` with userId = 12345 produces the Redis key `toc:user:info:12345`.

## 2.4 Area — Cache Areas

Area is JetCache's multi-tenancy mechanism. There's a default `"default"` area corresponding to `jetcache.local.default` and `jetcache.remote.default` in the config. If your project needs to connect to multiple Redis instances, you can configure multiple areas and specify `area = "otherArea"` in annotations. Most scenarios work fine with the default.

---

# 3. Quick Integration (Spring Boot)

## Step 1: Add Maven Dependency

Choose the starter matching your application's Redis client (**pick one**):

```XML
<!-- Option 1: Lettuce (recommended, supports async API) -->
<dependency>
    <groupId>com.alicp.jetcache</groupId>
    <artifactId>jetcache-starter-redis-lettuce</artifactId>
    <version>2.8.0</version>
</dependency>

<!-- Option 2: Jedis (classic choice) -->
<dependency>
    <groupId>com.alicp.jetcache</groupId>
    <artifactId>jetcache-starter-redis</artifactId>
    <version>2.8.0</version>
</dependency>

<!-- Option 3: Redisson (feature-rich) -->
<dependency>
    <groupId>com.alicp.jetcache</groupId>
    <artifactId>jetcache-starter-redisson</artifactId>
    <version>2.8.0</version>
</dependency>
```

**Version notes**: JetCache 2.8+ requires **JDK 17+**, **Spring Boot 3.x+**, and **Spring Framework 6.x+**. If your project is still on JDK 8, use version 2.7.x.

## Step 2: Configure application.yml

```YAML
jetcache:
  # Stats interval (minutes). 0 = no stats. Production recommendation: 15
  statIntervalMinutes: 15
  # Whether key prefix includes areaName. New projects: set to false
  areaInCacheName: false
  # Deserialization whitelist (required for 2.8+)
  decodeFilterAllowPatterns:
    - com.remotecarter.

  # Local cache config
  local:
    default:
      type: caffeine                        # Recommended: caffeine. Can also use linkedhashmap
      limit: 100                            # Max elements per cache instance
      keyConvertor: fastjson2               # Key conversion method
      expireAfterWriteInMillis: 60000       # Local cache default TTL (milliseconds)

  # Remote cache config
  remote:
    default:
      type: redis.redisson                   # redis / redis.lettuce / redis.redisson
      keyConvertor: fastjson2
      # Broadcast channel for two-level cache cross-node sync invalidation
      # When multiple services share Redis, use different channels per service to avoid broadcast storms
      broadcastChannel: crm-user
      valueEncoder: java                    # Serialization: java / kryo / kryo5
      valueDecoder: java
      poolConfig:
        minIdle: 5
        maxIdle: 20
        maxTotal: 50
      host: ${REDIS_HOST:127.0.0.1}
      port: ${REDIS_PORT:6379}
      # If using Lettuce, you can also use the URI format
      # uri: redis://127.0.0.1:6379/0
```

## Step 3: Add Annotations to the Startup Class

```Java
@SpringBootApplication
@EnableMethodCache(basePackages = "com.remotecarter")// Activate @Cached and similar annotations
@EnableCreateCacheAnnotation                      // Activate @CreateCache annotation (Deprecated in 2.7+, optional)
public class MyApplication {
    public static void main(String[] args) {
        SpringApplication.run(MyApplication.class, args);
    }
}
```

- **`@EnableMethodCache(basePackages = "...")`**: tells JetCache which packages to scan for Spring Beans with `@Cached`, `@CacheUpdate`, `@CacheInvalidate` annotations and create AOP proxies for them. **basePackages must cover all packages using cache annotations**.

- **`@EnableCreateCacheAnnotation`**: activates `@CreateCache` annotation support for injecting Cache instances directly on fields. Marked as Deprecated in the source — optional.

Integration complete. Now let's cover usage.

# 4. Usage Guide

## 4.1 Annotation-Driven Cache (Declarative)

This is the most common approach. Add annotations to methods on your Service interface (or implementation class), and JetCache automatically handles cache reads, writes, and deletes via Spring AOP proxies.

**Note**: annotations can go on interface methods or class methods, but the annotated class must be a **Spring Bean**.

### @Cached — Cache Reads

```Java
public interface UserService {

    // Specify name and key
    @Cached(name = "toc:user:info:", key = "#uuid", expire = 3600, cacheType = CacheType.REMOTE)
    User getUserById(String uuid);

    // Cache null values (prevent cache penetration)
    @Cached(name = "toc:user:info:", key = "#uuid", expire = 300, cacheNullValue = true)
    User getUserById(String uuid);
}
```

### @Cached — Attribute Reference

|Attribute|Default|Description|
|---|---|---|
|`area`|`"default"`|Cache area — rarely needs changing|
|`name`|Auto-generated (classname.methodname)|Unique cache name, **used as Redis key prefix**|
|`key`|Auto-generated (from all params)|SpEL expression for key, e.g. `"#userId"` or `"args[0]"`|
|`expire`|Follows global config|Time-to-live|
|`timeUnit`|`TimeUnit.SECONDS`|Time unit for expire|
|`cacheType`|`CacheType.REMOTE`|LOCAL / REMOTE / BOTH|
|`localLimit`|100|Max elements in local cache (effective for LOCAL/BOTH)|
|`localExpire`|Same as expire|Separate TTL for local cache (effective for BOTH only)|
|`syncLocal`|false|Broadcast invalidation of other JVMs' local cache on update (BOTH only)|
|`serialPolicy`|`java`|Serialization: `SerialPolicy.JAVA` or `SerialPolicy.KRYO`|
|`keyConvertor`|`fastjson2`|Key conversion method|
|`enabled`|true|Whether caching is active. false = bypass cache, can be temporarily activated via `CacheContext.enableCache`|
|`cacheNullValue`|false|Whether to cache when method returns null|
|`condition`|None|SpEL expression — cache is queried only if this evaluates to true (before method execution)|
|`postCondition`|None|SpEL expression — cache is updated only if this evaluates to true (after method execution, can use `#result`)|

### @CacheUpdate — Update Cache

When data is modified, use this annotation to update the cache directly instead of waiting for TTL expiry:

```Java
public interface UserService {

    @Cached(name = "toc:user:info:", key = "#uuid", expire = 3600)
    User getUserById(String uuid);

    // Update cache: key and name must match @Cached
    @CacheUpdate(name = "toc:user:info:", key = "#user.uuid", value = "#user")
    void updateUser(User user);
}
```

### @CacheInvalidate — Delete Cache

When data is deleted, remove it from cache too:

```Java
@CacheInvalidate(name = "toc:user:info:", key = "#uuid")
void deleteUser(String uuid);
```

**Important for both @CacheUpdate and @CacheInvalidate**: their `name` and `area` must match exactly with the corresponding `@Cached` annotation, so JetCache knows which cache to operate on.

### @CacheRefresh — Auto Refresh

One of JetCache's standout features. For data that's expensive to load and doesn't need strict real-time accuracy (like report summaries), configure auto-refresh to **prevent concurrent requests from hammering the database the moment cache expires (cache stampede)**:

```Java
public interface SummaryService {

    @Cached(expire = 3600, cacheType = CacheType.REMOTE)
    @CacheRefresh(refresh = 1800, stopRefreshAfterLastAccess = 3600, timeUnit = TimeUnit.SECONDS)
    BigDecimal salesVolumeSummary(int timeId, long categoryId);
}
```

|Attribute|Default|Description|
|---|---|---|
|`refresh`|None|Refresh interval|
|`timeUnit`|`TimeUnit.SECONDS`|Time unit|
|`stopRefreshAfterLastAccess`|None (refreshes forever)|Stop refreshing after this duration of no access|
|`refreshLockTimeout`|60 seconds|Distributed lock timeout in Redis during refresh|

**Key feature**: when `cacheType` is REMOTE or BOTH, **refresh is globally unique across the cluster** — no matter how many servers, only one node refreshes a given key at a time, implemented via distributed lock.

### @CachePenetrationProtect — Penetration Protection

```Java
@Cached(expire = 3600, cacheType = CacheType.REMOTE)
@CachePenetrationProtect
User getUserById(long userId);
```

When cache misses, **only one thread within the same JVM loads the data for a given key** — other threads wait for the result. This prevents a flood of concurrent requests from penetrating to the database in high-concurrency scenarios.

The current implementation provides **single-node protection**, not distributed. If multiple nodes miss the same key simultaneously, each loads independently.

**You can combine auto-refresh + penetration protection**:

```Java
@Cached(name = "toc:user:info:", key = "#uuid", expire = 3600)
@CacheRefresh(refresh = 1800, stopRefreshAfterLastAccess = 3600, timeUnit = TimeUnit.SECONDS)
@CachePenetrationProtect
User getUserById(String uuid);
```

Auto-refreshes every 30 minutes (cluster-wide unique), stops refreshing after 30 minutes of no access, and has penetration protection as a safety net.

## 4.2 Programmatic Cache (Cache API)

Annotations are concise but limited in flexibility — for example, if you need to decide keys dynamically at runtime or use caching in classes not managed by Spring. That's when you use the **Cache API**.

### CacheManager + QuickConfig for Cache Instance Creation

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
            .cacheType(CacheType.BOTH)    // Two-level cache
            .syncLocal(true)              // Broadcast invalidation to other nodes on update
            .localLimit(200)              // Max elements in local cache
            .build();
        orderCache = cacheManager.getOrCreateCache(qc);
    }
}
```

`QuickConfig` supports these settings:

|Method|Description|
|---|---|
|`expire(Duration)`|Time-to-live|
|`localExpire(Duration)`|Separate local cache TTL (BOTH)|
|`localLimit(Integer)`|Max local cache elements|
|`cacheType(CacheType)`|LOCAL / REMOTE / BOTH|
|`syncLocal(Boolean)`|Whether to sync local cache invalidation across nodes|
|`keyConvertor(Function)`|Key converter|
|`valueEncoder / valueDecoder`|Serialization/deserialization|
|`cacheNullValue(Boolean)`|Whether to cache null|
|`penetrationProtect(Boolean)`|Enable penetration protection|
|`penetrationProtectTimeout(Duration)`|Penetration protection timeout|
|`refreshPolicy(RefreshPolicy)`|Auto-refresh policy|
|`loader(CacheLoader)`|Load function on cache miss|

### Basic Operations

```Java
// Read
UserDO user = userCache.get("toc:user:info:12345");

// Write
userCache.put("toc:user:info:12345", user);

// Write with custom TTL
userCache.put("toc:user:info:12345", user, 10, TimeUnit.MINUTES);

// Delete
userCache.remove("toc:user:info:12345");

// Batch read
Map<String, UserDO> users = userCache.getAll(Set.of("toc:user:info:1", "toc:user:info:2", "toc:user:info:3"));

// Batch write
userCache.putAll(Map.of("toc:user:info:1", o1, "toc:user:info:2", o2));

// Batch delete
userCache.removeAll(Set.of("toc:user:info:1", "toc:user:info:2"));
```

### computeIfAbsent — Auto-Load on Cache Miss

This is extremely practical — it's an atomic `get` + `put` operation:

```Java
// Returns cached value on hit; on miss, calls the loader and writes to cache
OrderDO order = userCache.computeIfAbsent("toc:user:info:12345", key -> {
    return userMapper.selectById(key);  // Load from database
});
```

You can also set the loader at cache creation time, so every `get` auto-loads on miss:

```Java
// Set loader at creation
QuickConfig qc = QuickConfig.newBuilder("userCache")
    .expire(Duration.ofSeconds(300))
    .loader(key -> userMapper.selectById(key))
    .build();
userCache = cacheManager.getOrCreateCache(qc);

// Now just call get — it auto-loads on miss
UserDO user = userCache.get("toc:user:info:12345");
```

### Uppercase API — Operations with Full Status Codes

When lowercase `get()` returns null, you can't distinguish between "not in cache" and "cache error." The uppercase API returns `CacheGetResult` with full status information:

```Java
CacheGetResult<UserDO> r = userCache.GET("toc:user:info:12345");
if (r.isSuccess()) {
    UserDO user = r.getValue();
    // Handle business logic
} else if (r.getResultCode() == CacheResultCode.NOT_EXISTS) {
    // Cache entry doesn't exist
} else if (r.getResultCode() == CacheResultCode.EXPIRED) {
    // Cache entry has expired
} else {
    // Cache access error (network exception, etc.)
}
```

Other uppercase APIs: `GET_ALL`, `PUT`, `PUT_ALL`, `REMOVE`, `REMOVE_ALL`, `PUT_IF_ABSENT`.

### Async API

When using the **Lettuce** client, the uppercase API supports true async non-blocking:

```Java
CacheGetResult<UserDO> r = userCache.GET("toc:user:info:12345");
// The operation may not have completed yet
CompletionStage<ResultData> future = r.future();
future.thenRun(() -> {
    if (r.isSuccess()) {
        System.out.println(r.getValue());
    }
});
```

Note: lowercase `put()` and `removeAll()` have no return value and are automatically optimized for async calls under Lettuce, reducing RT. But `get()` needs to wait for the result, so it still blocks.

# 5. Key Types and Strategies

Understanding how JetCache generates and processes keys is essential for seeing the expected keys in Redis.

## 5.1 Redis Key Concatenation Rules

```Java
Redis key = keyPrefix + keyConvertor(Java Key object)
```

Examples:

- `@Cached(name = "toc:user:info:", key = "#userId")` + userId = `12345` (long type)
- keyConvertor converts long to `"Long12345"`
- Final Redis key = `toc:user:info:Long12345`

If the key is a String type:

- `@Cached(name = "toc:user:info:", key = "#uuid")` + uuid = `"X123456"`
- keyConvertor passes Strings through directly
- Final Redis key = `toc:user:info:X123456`

## 5.2 Supported Key Types

From the `ExternalKeyUtil.buildKeyAfterConvert` source code, JetCache supports these key types:

|Java Type|Conversion Rule|Example|
|---|---|---|
|`String`|**Used directly**, no conversion|`"abc"` → `abc`|
|`Number` (Long, Integer, etc.)|ClassName + value|`12345L` → `Long12345`|
|`Date`|ClassName + yyyyMMddHHmmss,SSS|`new Date()` → `Date20260617100000,000`|
|`Boolean`|toString|`true` → `true`|
|`byte[]`|Used directly|—|
|Other `Serializable` objects|Java serialization|Complex object → serialized bytes|

**Practical recommendation**: **use String-type keys**. If you use Long/Integer keys, the Redis key will include a `Long`/`Integer` prefix — functionally fine but not intuitive. Convert in SpEL: `key = "'' + #userId"` or `key = "#userId.toString()"`.

## 5.3 keyConvertor Mechanism

The keyConvertor converts Java objects to Strings suitable for Redis storage:

|Value|Description|
|---|---|
|`fastjson2`|**Default recommendation**. Strings pass through directly; other objects use `JSON.toJSONString()`|
|`jackson`|Converts to JSON using Jackson|
|`jackson3`|Jackson 3.x version|
|`none`|No conversion, uses `equals` comparison directly. Only for `@CreateCache` with `cacheType = LOCAL`|

## 5.4 SpEL Expressions for Keys

`@Cached`'s `key` attribute supports Spring SpEL expressions:

```Java
// Use parameter name directly (requires javac -parameters compilation)
@Cached(name = "toc:user:info:", key = "#uuid", expire = 3600)
User getUserById(String uuid);

// Access by index (no -parameters needed)
@Cached(name = "toc:user:info:", key = "args[0]", expire = 3600)
User getUserById(String uuid);

// Access object properties
@Cached(name = "toc:user:info:", key = "#user.uuid", expire = 3600)
User getUser(User user);

// String concatenation
@Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid", expire = 1800)
List<Archives> getArchives(String appId, String uuid);
```

**Note**: using parameter names (like `#userId`) requires the `-parameters` compiler flag. Without it, use `args[0]` for index-based access.

**Maven configuration:**

```XML
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-compiler-plugin</artifactId>
    <configuration>
        <compilerArgument>-parameters</compilerArgument>
    </configuration>
</plugin>
```

**IntelliJ IDEA configuration**: Settings → Build → Compiler → Java Compiler → Additional command-line parameters, enter `-parameters`.

## 5.5 Single-Value vs Multi-Value Cache Scenarios

JetCache uses a pure KV model (Redis STRING type underneath) and **does not support Redis HASH sub-field operations** (HGET/HSET). If you've been using Redisson's `RMap` for Hash caching, you'll need to adjust your approach when migrating to JetCache.

**Scenario: `toc:user:archives:{uuid}` — one user with multiple KYC records**

Redisson approach (Hash-level operations):

```Java
// Redisson: can read/write by kycType individually
RMap<String, String> map = redissonClient.getMap("user:archives:" + uuid);
map.put("archive_real", jsonString);           // HSET
String json = map.get("archive_real");         // HGET
```

JetCache approach (whole-object caching):

```Java
// Option 1: entire List as value
@Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid", expire = 30, timeUnit = TimeUnit.MINUTES)
List<ApiArchivesStatus> getAllArchives(String appId, String uuid);

// Query by kycType: fetch all, then filter in memory
public ApiArchivesStatus getByKycType(String appId, String uuid, String kycType) {
    return getAllArchives(appId, uuid).stream()
        .filter(s -> kycType.equals(s.getKycType()))
        .findFirst().orElse(null);
}

// Option 2: Map as value (kycType as Map key)
@Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid", expire = 30, timeUnit = TimeUnit.MINUTES)
Map<String, ApiArchivesStatus> getArchivesMap(String appId, String uuid);
```

JetCache can't perform Hash field-level operations — you need to cache "all data for a given uuid" as a single complete value. If your business requires sub-field read/write granularity, keep using Redisson RMap. If reads and writes are mostly whole-object, JetCache's two-level cache and auto-refresh capabilities are more valuable.

---

# 6. Two-Level Cache (BOTH)

Two-level cache is one of JetCache's highlights, though we're not using it yet. Simply put: **local memory cache (L1) + Redis (L2) combined. Reads check L1 first, then L2. Writes go to both levels.**

## 6.1 How It Works

```Plaintext
Read flow:
  1. Check local cache (Caffeine/LinkedHashMap)
  2. Local hit → return directly
  3. Local miss → check Redis
  4. Redis hit → backfill local cache → return
  5. Redis miss → return NOT_EXISTS

Write flow:
  1. Write to both local cache and Redis simultaneously

Delete flow:
  1. Delete from both local cache and Redis simultaneously
```

## 6.2 Configuration

### Annotation approach:

```Java
@Cached(name = "toc:user:info:", key = "#uuid", expire = 3600,
    cacheType = CacheType.BOTH,     // Two-level cache
    syncLocal = true,               // Broadcast invalidation to other nodes' local cache on update
    localLimit = 100,               // Max local elements
    localExpire = 60                // Local cache TTL 60 seconds (usually shorter than remote expire)
)
User getUserById(String uuid);
```

### Programmatic approach:

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

## 6.3 syncLocal — Cross-Node Sync Invalidation

This is the critical setting for two-level cache. Say you have 3 servers, each with its own local cache. If node A updates a user's data, nodes B and C still have stale values in their local cache — that's an inconsistency.

`syncLocal = true` solves this:

1. When node A updates the cache, it publishes an invalidation message to the Redis `broadcastChannel`
2. Nodes B and C subscribe to this channel and clear their corresponding local cache entries upon receiving the message
3. Next read causes B and C to pull fresh data from Redis

**Prerequisite**: `broadcastChannel` must be configured in your yml.

```YAML
jetcache:
  remote:
    default:
      broadcastChannel: crm-user  # This config is required
```

**Important**: when multiple services share the same Redis, use different `broadcastChannel` values per service. Otherwise, one service's cache updates will trigger local cache invalidation across all other services — manageable at small scale but catastrophic under heavy broadcast volume.

## 6.4 localExpire — Separating Local and Remote Expiry

In two-level cache scenarios, the local cache TTL should typically be **shorter** than the remote cache. For example: remote set to 1 hour, local set to 1 minute. That way, even if broadcast messages are lost, the local cache auto-expires after 1 minute and re-fetches from Redis.

|Scenario|Recommended CacheType|Reasoning|
|---|---|---|
|Dictionary data, config items|`LOCAL`|Rarely changes, local memory is enough|
|General business data|`REMOTE`|Centralized Redis, simple and reliable|
|High-frequency reads + seconds-level inconsistency acceptable|`BOTH` + `syncLocal = true`|Local handles read pressure, Redis as fallback|
|High-frequency reads + very large data|`BOTH` + `localLimit` to control size|Prevent local memory overflow|

---

# 7. Serialization Configuration

Data in remote cache (Redis) is stored as byte streams. Storing requires **serialization (encode)**, retrieving requires **deserialization (decode)**. JetCache provides three serialization options:

## 7.1 valueEncoder / valueDecoder Selection

|Method|Pros|Cons|
|---|---|---|
|`java` (default)|Best compatibility, Java native|Worst performance, largest byte size|
|`kryo` / `kryo5`|Good performance, small byte size|Requires class registration, watch compatibility on upgrades|

```YAML
jetcache:
  remote:
    default:
      valueEncoder: java    # or kryo / kryo5
      valueDecoder: java
```

Custom codec implementations are not recommended here — they risk causing multi-level cache inconsistency. Mismatched encoders/decoders will cause JetCache broadcast start exceptions.

## 7.2 Deserialization Security Filter (2.8+)

JetCache 2.8.x enables a deserialization security filter by default — **only whitelisted classes can be deserialized**. This prevents deserialization vulnerability attacks. The default whitelist includes: `java.lang`, `java.util.`, `java.time.`, `java.math`, `com.alicp.jetcache.`.

If your cached values include custom classes (like `UserDO`, `OrderDO`), **you must add them to the whitelist** or deserialization will fail:

```YAML
jetcache:
  decodeFilterAllowPatterns:
    - com.remotecarter.                    # Prefix match: all classes in this package and subpackages
    - com.remotecarter.UserDto             # Exact match: only this specific class
```

**Pattern matching rules:**

|Pattern|Match Type|Example|
|---|---|---|
|`com.remotecarter.`<br>|Prefix match (ends with `.`)|Matches `com.remotecarter.Foo`, `com.remotecarter.sub.Bar`|
|`com.remotecarter`|Package match (no trailing `.`)|Matches `com.remotecarter.Foo` only, not subpackages|
|`com.remotecarter.UserDto`|Exact match (full class name)|Matches only `com.remotecarter.UserDto`|

The built-in deny list includes known deserialization attack gadget chains (Commons Collections, Spring AOP, Hibernate, etc.) and dangerous classes like `Runtime` and `ProcessBuilder`. **The deny list cannot be overridden by the allow list.**

You can also configure this programmatically:

```Java
DecodeFilter.getDefault().addAllowPatterns("com.yourcompany.");
```

# 8. Real-World Usage Scenarios

## Scenario 1: Single-Value Cache (User Info)

The most common scenario — look up users by ID, cache in Redis.

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

Redis keys look like: `toc:user:info:X12345`.

## Scenario 2: Multi-Value Cache (Hash Alternative)

One user maps to multiple KYC records. Previously implemented with Redisson `RMap` (Hash), migrated to JetCache using **whole-object caching**:

```Java
// Entire List as one cache entry
public interface ArchivesCacheService {

    @Cached(name = "toc:user:archives:", key = "#appId + ':' + #uuid",
            expire = 30, timeUnit = TimeUnit.MINUTES, cacheType = CacheType.REMOTE)
    List<ApiArchivesStatus> getAllArchives(String appId, String uuid);

    @CacheUpdate(name = "toc:user:archives:", key = "#appId + ':' + #uuid", value = "#list")
    void saveAllArchives(String appId, String uuid, List<ApiArchivesStatus> list);

    @CacheInvalidate(name = "toc:user:archives:", key = "#appId + ':' + #uuid")
    void deleteArchives(String appId, String uuid);
}

// Query by kycType
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
    
    // Can also use Map
}
```

## Scenario 3: High-Frequency Reads + Auto Refresh (Report Summaries)

```Java
public interface ReportService {
    @Cached(expire = 7200, cacheType = CacheType.BOTH, syncLocal = true)
    @CacheRefresh(refresh = 1800, stopRefreshAfterLastAccess = 3600, timeUnit = TimeUnit.SECONDS)
    @CachePenetrationProtect
    ReportSummary getReportSummary(String reportId);
}
```

Cache for 2 hours, auto-refresh every 30 minutes (cluster-wide unique), stop refreshing after 30 minutes of no access. Local + Redis two-level cache, with penetration protection as a safety net.

## Scenario 4: Conditional Caching

**Situations where you need to conditionally use cache:**

```Java
// Only cache when type == 1
@Cached(name = "data-", key = "#id", expire = 3600, condition = "#type == 1")
DataObject getData(long id, int type);

// Only cache when result is non-null
@Cached(name = "data-", key = "#id", expire = 3600, postCondition = "#result != null")
DataObject getData(long id);

// Temporarily disable cache for a specific scenario (e.g., data export shouldn't use cache)
@Cached(name = "data-", key = "#id", expire = 3600, enabled = false)
DataObject getData(long id);

// Activate caching where needed
public void exportData() {
    CacheContext.enableCache(() -> {
        // getData here will use cache
        DataObject data = getData(123L);
        return data;
    });
}
```

**If you need to toggle caching via hot config deployment:**

```Java
package com.remotecarter.appuser.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.context.config.annotation.RefreshScope;
import org.springframework.stereotype.Component;

@Component
@RefreshScope
public class SwitchCache {

    private static volatile boolean CACHE_ON = true;

    @Value("${nacos.user.info.cacheOn:true}")
    public void setCacheOn(boolean cacheOn) {
        CACHE_ON = cacheOn;
    }

    public static boolean isCacheOn() {
        return CACHE_ON;
    }
}

@Cached(name = "toc:user:info:",
        key = "#uuid",
        expire = 3600,
        condition = "T(com.remotecarter.appuser.config.SwitchCache).isCacheOn()")
interface UserInfoDetailDTO queryUserDetail(String uuid);
```

## Best Practices and Caveats

### 1. Always Set TTL

`@CacheUpdate` and `@CacheInvalidate` can fail due to network issues. Without a TTL, failed delete/update operations leave the cache permanently inconsistent. **Always set a reasonable expire as a final consistency safety net**.

### 2. Serialization Choice

- **Development phase / unsure**: use `java` — best compatibility

- **Performance-focused**: use `kryo` — smaller size, faster speed, but requires class registration

- **JSON serialization**: not recommended. JSON isn't a dedicated Java serialization tool — when reflection can't determine the type, it deserializes as JSONObject, causing compatibility issues

### 3. broadcastChannel Isolation

When multiple services share the same Redis instance, different services must use different `broadcastChannel` values. Otherwise, service A's cache update broadcasts will trigger service B's local cache invalidation — seems harmless at first, but becomes a disaster under heavy broadcast volume.

### 4. AOP Proxy Pitfall

JetCache annotations work through Spring AOP proxies. **Internal method calls within the same class bypass the proxy, so caching won't take effect**:

```Java
@Service
public class UserServiceImpl implements UserService {

    public User getUser(long userId) {
        // Calling getUserById here — cache won't work!
        // Because this.getUserById() doesn't go through the proxy
        return getUserById(userId);
    }

    @Cached(expire = 3600)
    public User getUserById(long userId) {
        return userMapper.selectById(userId);
    }
}
```

**Solution**: inject yourself via `@Autowired` and use the injected proxy instance:

```Java
@Service
public class UserServiceImpl implements UserService {

    @Autowired
    private UserService self;  // Inject proxy instance

    public User getUser(long userId) {
        return self.getUserById(userId);  // Goes through proxy — cache works
    }
}
```

### 5. -parameters Compiler Flag

If you want to use parameter names in SpEL (like `#uuid`), you must add `-parameters` at compile time. Otherwise, use `args[0]` for index-based access.

### 6. name Naming Convention

`name` becomes the Redis key prefix. Recommendations:

- Use names with clear business meaning, like `"toc:user:info:"`
- End with `-` or `:` as a separator, like `"userCache-12345"`
- Don't assign the same `name + area` to different `@Cached` annotations

### 7. Local Cache Memory Control

`localLimit` is a limit **per cache instance**, not total. If you have 10 cache instances created with `@CreateCache`, each with limit 100, local memory could hold up to 1,000 elements total. Watch this carefully with large objects.

# 9. FAQ

## Q: @Cached annotation on another method in the same class isn't working?

Spring AOP is proxy-based. Internal method calls within the same class don't go through the proxy. See Best Practice #4 above for the solution.

## Q: Used a parameter name as key, but cache isn't working?

Check if the `-parameters` compiler flag is configured. Without it, switch to `args[0]` for index-based access.

## Q: Deserialization errors after upgrading to 2.8?

2.8+ enables the deserialization security filter by default. You need to configure `decodeFilterAllowPatterns` in your yml to include the packages containing your custom classes.

## Q: How to connect to multiple Redis instances?

Configure multiple areas:

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

Then specify the area in annotations: `@Cached(area = "second", ...)`.

## Q: What happens if @CacheUpdate / @CacheInvalidate fails?

These operations can fail due to network issues. JetCache won't throw an exception — it fails silently. That's why **setting a reasonable TTL is essential** — even if update/delete fails, the cache auto-expires after TTL and reloads from the database.

## Q: Local cache and Redis data are inconsistent?

Make sure you've configured `syncLocal = true` and `broadcastChannel`. Also set a `localExpire` shorter than the Redis expire as a fallback — even if broadcast messages are lost, local cache auto-expires after localExpire.

## Q: Can JetCache's distributed lock be used?

JetCache's lock is based on Redis `SETNX` + TTL — it's a **non-strict distributed lock**, suitable for "prevent duplicate execution" scenarios. It works. But from what we've seen, each domain has its own distributed lock implementation. I'd recommend using your own — JetCache's core responsibility is defining the cache framework protocol.

## Q: Complete Configuration Reference

```YAML
jetcache:
  # ============ Global Config ============
  statIntervalMinutes: 15                    # Stats interval (minutes). 0 = disabled
  areaInCacheName: false                     # Whether key prefix includes area. New projects: false
  hidePackages: com.remotecarter                # Package prefix stripped when auto-generating name
  useDefaultLocalExpireInMultiLevelCache: false  # Whether to use local builder's TTL for BOTH

  # ============ Deserialization Security (2.8+) ============
  decodeFilterEnabled: true                  # Master switch
  decodeFilterAllowPatterns:                 # Allow list
    - com.remotecarter.
  decodeFilterDenyPatterns:                  # Deny list (always takes priority over allow list)
    - com.dangerous.

  # ============ Local Cache Config ============
  local:
    default:                                 # Area name
      type: caffeine                         # caffeine or linkedhashmap
      limit: 100                             # Max elements per cache instance
      keyConvertor: fastjson2                # fastjson2 / jackson / jackson3 / none
      expireAfterWriteInMillis: 60000        # Default TTL (milliseconds)
      expireAfterAccessInMillis: 0           # TTL after access (0 = not used)

    # Can configure multiple areas
    otherArea:
      type: linkedhashmap
      limit: 50
      keyConvertor: none

  # ============ Remote Cache Config ============
  remote:
    default:                                 # Area name
      type: redis.redisson                   # redis / redis.lettuce / redis.redisson / redis.springdata
      keyConvertor: fastjson2                # Key conversion
      valueEncoder: java                     # Serialization: java / kryo / kryo5
      valueDecoder: java                     # Deserialization: java / kryo / kryo5
      broadcastChannel: crm-user             # Two-level cache broadcast channel (not configured = disabled)

      # --- Jedis / Redisson connection pool config ---
      poolConfig:
        minIdle: 5
        maxIdle: 20
        maxTotal: 50
      host: 127.0.0.1
      port: 6379
      # password: xxx                       # Set when password is required

      # --- Lettuce connection (pick one) ---
      # uri: redis://127.0.0.1:6379/0

      expireAfterWriteInMillis: 300000       # Default TTL (milliseconds)
```


