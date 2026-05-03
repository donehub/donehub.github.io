---
title: 12306 候补排队系统技术设计深度解析
date: 2024-05-03
tags: [高并发系统设计]
categories: 系统架构
---

> "我排队第 50 名，别人排队第 200 名，为什么他先候补成功？"——这个问题困扰了无数抢票人。答案藏在 12306 候补系统的底层设计里：席位复用、区间独立排队、事件驱动匹配。本文从五个维度拆解这套世界级高并发系统的技术架构，让你不仅"知其然"，更"知其所以然"。

---

## 一、为什么 12306 如此难做？

在深入设计之前，先理解问题的规模。

### 1.1 业务复杂度

铁路售票与普通电商秒杀有本质区别：

| 对比维度 | 普通电商秒杀 | 12306 售票 |
|---------|-------------|-----------|
| 商品粒度 | SKU 级别（一部手机） | 区间级别（北京→济南，同一座位不同区间） |
| 库存管理 | 扣减库存即可 | 区间叠加、席位复用 |
| 并发竞争 | 单 SKU 多人竞争 | 同一座位多个区间交叉竞争 |
| 订单关联 | 独立订单 | 关联订单（联程票、往返票） |

**核心差异**：一趟北京到上海的高铁，途经 10 个站点，同一个座位可以拆分成 9 段区间分别售卖。这带来的是指数级的复杂度。

### 1.2 规模数据

以 2024 年春运为例：
- 日均访问量：**100 亿次+**
- 倰值 QPS：**每秒 100 万+**
- 候补订单：单日峰值 **2000 万+**
- 车次数据：**5000+ 趟车次**，每趟车 **500-2000 个座位**

在这种规模下，任何不当的设计都会被瞬间放大成系统崩溃。

---

## 二、核心设计基石：席位复用

### 2.1 什么是席位复用？

**席位复用**是指同一个座位可以分段卖给不同乘客，只要乘车区间不重叠。

举例说明：

```
车次：G1 北京→青岛
途经站点：北京 → 天津 → 济南 → 淄博 → 青岛

座位 12A 的售卖情况：
- 张三：北京 → 济南（占用 北京→天津、天津→济南 两段）
- 李四：济南 → 青岛（占用 济南→淄博、淄博→青岛 两段）
- 王五：天津 → 淄博（占用 天津→济南、济南→淄博 两段）

结果：同一座位 12A，同时卖给 3 个人，互不冲突
```

这个设计极大提升了座位利用率，但技术实现难度陡增。

### 2.2 技术实现：Redis Bitmap

12306 使用 **Redis Bitmap（位图）** 存储每个座位的区间占用状态。

**数据结构设计：**

```
Key:   train:{train_id}:{date}:{seat_no}
Value: Bitmap，每一位代表一个站点区间的占用状态

示例：
车次 G1，日期 2024-01-20，座位 12A
途经站点：北京(0) → 天津(1) → 济南(2) → 淄博(3) → 青岛(4)

Bitmap: 1 1 0 0
         ↑ ↑ ↑ ↑
         │ │ │ └─ 淄博→青岛 (0=空闲)
         │ │ └─── 济南→淄博 (0=空闲)  
         │ └───── 天津→济南 (1=占用)
         └─────── 北京→天津 (1=占用)

表示：北京→济南 已售，济南→青岛 空闲
```

**为什么用 Bitmap？**

| 指标 | Bitmap | 传统方案（如 Hash） |
|------|--------|-------------------|
| 空间占用 | N 个站点仅需 N bit（几字节） | 每区间存一个字段（几百字节） |
| 查询复杂度 | O(1) | O(N) |
| 区间判断 | 位运算 `OR`，一次搞定 | 需遍历所有区间 |
| 适用场景 | 固定长度、高频查询 | 灵活但低效 |

**区间可用性检查（伪代码）：**

```python
def check_interval_available(redis, train_id, date, seat_no, from_station, to_station):
    """
    检查指定区间是否可用
    from_station: 起始站点索引（如北京=0）
    to_station: 终点站点索引（如济南=2）
    """
    key = f"train:{train_id}:{date}:{seat_no}"
    
    # 获取 from_station 到 to_station-1 的所有 bit 位
    # 即区间 [from_station, to_station)
    for i in range(from_station, to_station):
        bit = redis.getbit(key, i)
        if bit == 1:  # 该区间已被占用
            return False
    
    return True


def allocate_interval(redis, train_id, date, seat_no, from_station, to_station):
    """
    分配区间：将对应 bit 位设为 1
    """
    key = f"train:{train_id}:{date}:{seat_no}"
    
    for i in range(from_station, to_station):
        redis.setbit(key, i, 1)
    
    return True
```

**更高效的方式：使用位运算**

```python
def check_and_allocate(redis, train_id, date, seat_no, from_station, to_station):
    """
    使用位运算一次性检查并分配区间
    """
    key = f"train:{train_id}:{date}:{seat_no}"
    
    # 1. 获取当前 bitmap 值（假设用整数表示）
    current = redis.get(key)
    if current is None:
        current = 0
    
    # 2. 构造区间掩码
    # 例如 from=0, to=2，掩码为 0b0011 (低位表示前面的区间)
    mask = (1 << to_station) - (1 << from_station)  # 0b0011
    
    # 3. 检查区间是否已被占用
    if current & mask != 0:
        return False  # 区间已被占用
    
    # 4. 分配区间（原子操作，需用 Lua 脚本）
    # Lua 脚本保证检查+设置原子性
    lua_script = """
        local current = tonumber(redis.call('GET', KEYS[1])) or 0
        local mask = tonumber(ARGV[1])
        if (current & mask) == 0 then
            redis.call('SET', KEYS[1], current | mask)
            return 1
        else
            return 0
        end
    """
    result = redis.eval(lua_script, 1, key, mask)
    return result == 1
```

---

## 三、分布式排队机制

### 3.1 核心设计：按区间独立排队

很多人以为候补是整趟车排一个大队列，其实不然。

**12306 的设计：每个乘车区间独立排队。**

```
车次 G1（北京→青岛）的候补队列：

队列1：北京 → 天津（85 人排队）
队列2：北京 → 济南（320 人排队）
队列3：天津 → 济南（56 人排队）
队列4：济南 → 青岛（198 人排队）
队列5：北京 → 青岛（1275 人排队）
...

每个区间一个独立的 Sorted Set
```

**为什么要按区间独立排队？**

1. **公平性**：北京→天津 和 北京→青岛 根本不是同一批票，放一起排队没有意义
2. **并行处理**：不同区间队列可以并发处理，提升吞吐
3. **精准匹配**：释放席位时，直接定位对应队列，无需遍历

**这解释了一个常见疑问**：

> 为什么我排队 50 名，别人排队 200 名，他却先候补成功？

因为你们根本不在同一个队列。他排的是天津→济南，你排的是北京→济南。

### 3.2 技术实现：Redis Sorted Set

**数据结构设计：**

```
Key:   backup:{train_id}:{date}:{from_station}:{to_station}
Value: 有序集合，存储候补订单 ID
Score: 用户提交候补的时间戳（越小越靠前）

示例：
backup:G1:20240120:beijing:jinan
  ├─ order_001 (score: 1705678901) ← 第1名
  ├─ order_002 (score: 1705678905) ← 第2名
  ├─ order_003 (score: 1705678912) ← 第3名
  └─ ...
```

**核心操作：**

```python
import time

def add_to_backup_queue(redis, train_id, date, from_station, to_station, order_id):
    """
    加入候补队列（ZADD）
    时间戳作为 Score，天然实现先到先得
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    score = int(time.time() * 1000)  # 毫秒时间戳，精确排队
    
    redis.zadd(key, {order_id: score})
    return True


def get_queue_position(redis, train_id, date, from_station, to_station, order_id):
    """
    查询排队名次（ZRANK）
    返回当前排队位置（从 0 开始，+1 后为实际名次）
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    rank = redis.zrank(key, order_id)
    
    if rank is None:
        return -1  # 未在队列中
    return rank + 1  # 返回实际名次（从 1 开始）


def get_top_n_from_queue(redis, train_id, date, from_station, to_station, n=10):
    """
    取出队列前 N 名（ZRANGE）
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    return redis.zrange(key, 0, n - 1)


def remove_from_queue(redis, train_id, date, from_station, to_station, order_id):
    """
    候补成功或取消，移出队列（ZREM）
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    redis.zrem(key, order_id)
    return True
```

**性能分析：**

| 操作 | 复杂度 | 百万级队列耗时 |
|------|--------|---------------|
| ZADD（加入队列） | O(log N) | ~21 次比较，微秒级 |
| ZRANK（查询名次） | O(log N) | 微秒级 |
| ZRANGE（取前 N 名） | O(log N + M) | M 为取出数量，毫秒级 |
| ZREM（移出队列） | O(log N) | 微秒级 |

**结论**：Sorted Set 天然适合排队场景，百万级数据依然高效。

### 3.3 数据持久化：MySQL 分库分表

Redis 是内存数据库，一旦宕机可能丢失数据。候补订单必须持久化到 MySQL。

**分库分表策略：**

```
分库键：user_id % 16（按用户分 16 个库）
分表键：order_id % 128（每个库 128 张表）

表结构：
CREATE TABLE backup_order_00 (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    train_id VARCHAR(20) NOT NULL,
    travel_date DATE NOT NULL,
    from_station VARCHAR(20) NOT NULL,
    to_station VARCHAR(20) NOT NULL,
    seat_type TINYINT NOT NULL,      -- 座位类型：商务/一等/二等
    status TINYINT DEFAULT 0,         -- 状态：排队中/已兑现/已取消
    queue_position INT,              -- 冗余存储排队名次
    create_time DATETIME,
    update_time DATETIME,
    
    INDEX idx_train_date (train_id, travel_date, from_station, to_station)
);
```

**Redis 与 MySQL 如何保持一致？**

这是一个典型的分布式一致性问题，后文技术难点部分详解。

---

## 四、事件驱动：候补车票从哪里来？

候补的车票不是凭空产生的，全部来自系统事件触发。

### 4.1 四大票源

| 票源 | 触发事件 | 延迟 | 占比（估算） |
|------|----------|------|-------------|
| 用户退票 | 用户主动退票 | 秒级 | 40% |
| 订单超时 | 抢到票后 30 分钟未支付 | 秒级 | 35% |
| 改签释放 | 用户改签其他车次 | 秒级 | 15% |
| 动态加挂 | 12306 官方追加车厢 | 分钟级 | 10% |

### 4.2 事件驱动架构

```
┌──────────────────────────────────────────────────────────────────┐
│                         事件来源                                 │
├──────────┬──────────┬──────────┬─────────────────────────────────┤
│ 退票事件  │ 超时事件  │ 改签事件  │ 加挂事件（定时任务触发）        │
└────┬─────┴────┬─────┴────┬─────┴─────────────┬───────────────────┘
     │          │          │                   │
     ▼          ▼          ▼                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                    消息队列（Kafka/RocketMQ）                     │
│                                                                  │
│  Topic: ticket-released                                         │
│  Partition: 按 train_id 分区，保证同一车次顺序处理               │
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                    候补匹配服务                                   │
│                                                                  │
│  1. 消费释放席位事件                                             │
│  2. 查询对应区间的候补队列（Redis Sorted Set）                   │
│  3. 取出队列第一名                                               │
│  4. 执行兑现流程                                                 │
└──────────────────────────────────────────────────────────────────┘
```

**事件消息结构：**

```json
{
  "event_id": "evt_20240120_123456",
  "event_type": "REFUND",  // REFUND / TIMEOUT / RESCHEDULE / EXTRA_SEAT
  "train_id": "G1",
  "travel_date": "2024-01-20",
  "seat_no": "12A",
  "from_station": "beijing",
  "to_station": "jinan",
  "seat_type": 2,  // 二等座
  "release_time": 1705678901234,
  "trace_id": "trace_abc123"  // 链路追踪
}
```

### 4.3 候补匹配流程

```
席位释放事件触发：

Step 1: 解析事件，确定释放的区间
        train_id=G1, date=20240120, seat=12A, from=beijing, to=jinan

Step 2: 计算该区间覆盖的所有原子区间
        北京→济南 = [北京→天津, 天津→济南]

Step 3: 查询这些区间的候补队列
        - 队列 A：北京→天津（85 人）
        - 队列 B：天津→济南（56 人）
        - 队列 C：北京→济南（320 人）← 完全匹配，优先处理

Step 4: 尝试匹配队列 C 的第一名
        - 检查席位 12A 是否满足用户需求（座位类型、是否有票）
        - 满足 → 执行兑现流程
        - 不满足 → 尝试队列 C 的第二名

Step 5: 若队列 C 无匹配，尝试其他队列
        - 队列 A + 队列 B 是否有同一座位？
        - 这涉及跨区间匹配，后文详解
```

### 4.4 候补兑现完整流程

席位释放后，系统需要执行一整套原子流程才能完成兑现：

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        候补兑现完整流程                                   │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐                                                        │
│  │ 席位释放事件 │                                                        │
│  └──────┬──────┘                                                        │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 1: 查询候补队列                                                 ││
│  │                                                                     ││
│  │  redis.zrange("backup:G1:20240120:beijing:jinan", 0, 0)            ││
│  │  → 取出排队第一名 user_id                                            ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 2: 获取分布式锁                                                 ││
│  │                                                                     ││
│  │  lock_keys = ["lock:G1:20240120:12A:beijing:tianjin",              ││
│  │               "lock:G1:20240120:12A:tianjin:jinan"]                 ││
│  │  redis.set(lock_key, user_id, nx=True, px=5000)                    ││
│  │  → 锁定所有原子区间，防止并发超卖                                    ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 3: 检查席位可用性（双重检查）                                   ││
│  │                                                                     ││
│  │  bitmap_key = "train:G1:20240120:12A"                               ││
│  │  check_interval_available(bitmap_key, beijing, jinan)              ││
│  │  → 确认席位真正可用                                                  ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 4: MySQL 本地事务（原子操作）                                   ││
│  │                                                                     ││
│  │  BEGIN TRANSACTION;                                                 ││
│  │    -- 4.1 标记席位占用                                               ││
│  │    UPDATE seat SET status='OCCUPIED' WHERE ...;                     ││
│  │    -- 4.2 创建订单                                                   ││
│  │    INSERT INTO ticket_order (...) VALUES (...);                     ││
│  │    -- 4.3 更新候补状态                                               ││
│  │    UPDATE backup_order SET status='FULFILLED' WHERE ...;            ││
│  │    -- 4.4 写入操作日志（用于 Redis 异步同步）                        ││
│  │    INSERT INTO backup_operation_log (...) VALUES (...);             ││
│  │  COMMIT;                                                            ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 5: 异步更新 Redis                                               ││
│  │                                                                     ││
│  │  -- 5.1 更新席位 Bitmap                                              ││
│  │  redis.setbit("train:G1:20240120:12A", beijing_idx, 1)             ││
│  │  redis.setbit("train:G1:20240120:12A", tianjin_idx, 1)             ││
│  │  -- 5.2 从候补队列移除                                               ││
│  │  redis.zrem("backup:G1:20240120:beijing:jinan", user_id)           ││
│  │  -- 5.3 释放分布式锁                                                 ││
│  │  redis.del(lock_keys)                                               ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 6: 后续处理                                                     ││
│  │                                                                     ││
│  │  -- 6.1 冻结预付款（调用支付服务）                                   ││
│  │  -- 6.2 发送短信通知（调用通知服务）                                 ││
│  │  -- 6.3 更新操作日志状态                                             ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**流程关键点**：

| 步骤 | 关键点 | 失败处理 |
|------|--------|----------|
| 获取锁 | 按字典序获取，避免死锁 | 获取失败 → 席位已被抢占，跳过 |
| 双重检查 | 锁后再检查，防止并发穿透 | 不可用 → 释放锁，尝试下一名用户 |
| MySQL 事务 | 本地事务保证原子性 | 失败 → 释放锁，回滚，尝试下一名 |
| 异步更新 Redis | 通过操作日志保证最终一致 | 失败 → 定时任务补偿恢复 |
| 后续处理 | 异步执行，不阻塞主流程 | 失败 → 重试或告警人工处理 |

---

## 五、高并发架构设计

### 5.1 四级防护架构

从用户请求到数据落地，12306 构建了四级防护体系，逐级降压：

```
┌─────────────────────────────────────────────────────────────────┐
│                        用户请求                                 │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 第一级：网关层限流                               │
│                                                                 │
│  令牌桶算法：限制单 IP、单用户请求频率                           │
│  防刷策略：识别异常请求模式                                      │
│  作用：挡住恶意流量，保护后端服务                                │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 第二级：应用层本地缓存                           │
│                                                                 │
│  技术：Caffeine / Guava Cache                                  │
│  缓存内容：                                                     │
│    - 热门车次的区间队列长度（用户查询"排队第几名"）              │
│    - 热门车次的席位概览                                         │
│    - TTL：5-10 秒（容忍短时不一致）                             │
│  效果：拦截 60%+ 的查询请求，减轻 Redis 压力                    │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 第三级：Redis 集群缓存                           │
│                                                                 │
│  部署：主从 + 哨兵，保证高可用                                   │
│  存储：                                                         │
│    - 席位 Bitmap（实时状态）                                    │
│    - 候补 Sorted Set（排队数据）                                │
│    - 分布式锁（并发控制）                                        │
│  性能：单节点 10 万+ QPS，全内存操作                            │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 第四级：MySQL 分库分表                           │
│                                                                 │
│  存储：订单持久化、用户数据、候补记录                            │
│  分片：按 user_id 分库，按 order_id 分表                        │
│  作用：数据兜底、Redis 故障时的降级数据源                        │
└─────────────────────────────────────────────────────────────────┘
```

**为什么需要四级？**

| 级别 | 核心作用 | 如果缺失会怎样 |
|------|----------|---------------|
| 网关限流 | 拦截恶意流量 | 后端被刷爆，正常用户无法访问 |
| 本地缓存 | 拦截高频查询 | Redis 被查询请求压垮 |
| Redis 缓存 | 扛住核心读写 | MySQL 被高频请求打穿 |
| MySQL 持久化 | 数据兜底 | Redis 故障时数据丢失 |

### 5.2 限流降级策略

| 场景 | 限流策略 | 降级措施 | 用户感知 |
|------|----------|----------|----------|
| 正常高峰 | 令牌桶 10 万 QPS | 无 | 正常服务 |
| 超高峰 | 滑动窗口限流 | 排队等待 | "系统繁忙，请稍后" |
| Redis 故障 | 熔断 | 查询走 MySQL，写入走 MQ | 候补延迟，排队名次不可查 |
| MySQL 故障 | 熔断 | 暂停下单，只读 | "系统维护中" |

---

## 六、技术难点深入

前文介绍了 12306 候补系统的核心设计，但真正让系统"稳如磐石"的，是对细节的极致处理。

### 6.1 难点一：分布式一致性

**问题**：Redis 队列与 MySQL 订单如何保持一致？

```
场景：用户取消候补

方案一：先更新 MySQL，再删除 Redis
  1. MySQL DELETE 成功
  2. Redis ZREM 失败（网络抖动）
  → 结果：MySQL 无订单，Redis 仍在排队，用户"幽灵排队"

方案二：先删除 Redis，再更新 MySQL  
  1. Redis ZREM 成功
  2. MySQL DELETE 失败
  → 结果：Redis 已删除，MySQL 仍存在，用户想恢复排队无法恢复
```

**解决方案**：本地消息表 + 最终一致性

```sql
-- 候补操作日志表（与业务表同库，利用本地事务）
CREATE TABLE backup_operation_log (
    log_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id BIGINT NOT NULL,
    operation_type VARCHAR(20) NOT NULL,  -- ADD / CANCEL / FULFILL
    redis_status TINYINT DEFAULT 0,        -- 0=待处理 1=成功 2=失败
    mysql_status TINYINT DEFAULT 0,       -- 0=待处理 1=成功 2=失败
    retry_count INT DEFAULT 0,
    create_time DATETIME,
    update_time DATETIME,
    
    INDEX idx_status (redis_status, mysql_status)
);
```

**操作流程**：

```python
def cancel_backup_order(order_id):
    """取消候补订单（保证最终一致性）"""
    
    # Step 1: 本地事务，写入操作日志 + 更新订单状态
    with db.transaction():
        # 标记订单为"取消中"
        db.execute("UPDATE backup_order SET status = 'CANCELING' WHERE order_id = ?", order_id)
        
        # 写入操作日志
        log_id = db.execute("""
            INSERT INTO backup_operation_log 
            (order_id, operation_type, redis_status, mysql_status) 
            VALUES (?, 'CANCEL', 0, 0)
        """, order_id)
    
    # Step 2: 异步处理 Redis 操作
    mq.send('backup_operation', {'log_id': log_id, 'order_id': order_id, 'type': 'CANCEL'})
    
    return True


def process_cancel_message(message):
    """消费取消消息"""
    log_id = message['log_id']
    order_id = message['order_id']
    
    try:
        # Step 3: 从 Redis 队列移除
        redis.zrem(f"backup:{train}:{date}:{from}:{to}", order_id)
        
        # Step 4: 更新 MySQL 订单状态
        db.execute("UPDATE backup_order SET status = 'CANCELED' WHERE order_id = ?", order_id)
        
        # Step 5: 更新操作日志
        db.execute("UPDATE backup_operation_log SET redis_status=1, mysql_status=1 WHERE log_id=?", log_id)
        
    except Exception as e:
        # 失败后重试，超过 3 次告警
        retry_count = db.query("SELECT retry_count FROM backup_operation_log WHERE log_id=?", log_id)
        if retry_count < 3:
            db.execute("UPDATE backup_operation_log SET retry_count = retry_count + 1 WHERE log_id=?", log_id)
            mq.send('backup_operation', message, delay=60)  # 60 秒后重试
        else:
            alert(f"候补取消失败，log_id={log_id}, error={e}")
```

**定时对账任务**：

```python
def reconcile_backup_data():
    """每小时对账，确保 Redis 与 MySQL 一致"""
    
    # Step 1: 扫描所有候补队列
    all_queues = redis.keys("backup:*")
    
    for queue_key in all_queues:
        order_ids = redis.zrange(queue_key, 0, -1)
        
        for order_id in order_ids:
            # Step 2: 检查 MySQL 是否存在
            order = db.query("SELECT * FROM backup_order WHERE order_id = ?", order_id)
            
            if not order or order.status == 'CANCELED':
                # Step 3: Redis 存在，MySQL 不存在或已取消，清理 Redis
                redis.zrem(queue_key, order_id)
                log.info(f"清理幽灵排队：{order_id}")
```

---

### 6.2 难点二：并发竞争与超卖

**问题**：同一席位释放，多个区间队列如何竞争？

```
场景：
车次 G1，座位 12A
张三退票：北京 → 济南

释放区间：北京→天津、天津→济南

现有候补队列：
- 队列 A：北京→天津（100 人）
- 队列 B：天津→济南（80 人）
- 队列 C：北京→济南（200 人）

如果不加控制：
1. 队列 A 把 12A 分给用户 X（北京→天津）
2. 队列 C 把 12A 分给用户 Y（北京→济南）
→ X 和 Y 的区间重叠，超卖！
```

**解决方案**：分布式锁 + 区间锁定

```python
def allocate_seat_to_backup(train_id, date, seat_no, from_station, to_station, user_id):
    """
    分配席位给候补用户
    核心思想：锁定所有涉及的原子区间，防止并发超卖
    """
    
    # Step 1: 获取该区间的所有原子区间（相邻站点间）
    atomic_intervals = get_atomic_intervals(train_id, from_station, to_station)
    # 例如：北京→济南 = [(北京,天津), (天津,济南)]
    
    # Step 2: 生成锁 Key（按字典序排序，避免死锁）
    lock_keys = sorted([
        f"lock:{train_id}:{date}:{seat_no}:{f}:{t}"
        for f, t in atomic_intervals
    ])
    
    # Step 3: 尝试获取所有锁（SET NX PX，带超时）
    lock_acquired = []
    for key in lock_keys:
        success = redis.set(key, user_id, nx=True, px=5000)  # 5 秒超时
        if not success:
            # 获取失败，释放已获取的锁
            for acquired_key in lock_acquired:
                redis.delete(acquired_key)
            return False, "席位已被占用"
        lock_acquired.append(key)
    
    try:
        # Step 4: 再次检查席位可用性（双重检查）
        if not check_seat_available(train_id, date, seat_no, from_station, to_station):
            return False, "席位不可用"
        
        # Step 5: 执行兑现流程
        # 5.1 标记席位占用
        mark_seat_occupied(train_id, date, seat_no, from_station, to_station, user_id)
        
        # 5.2 创建订单（MySQL 本地事务）
        order_id = create_ticket_order(user_id, train_id, date, seat_no, from_station, to_station)
        
        # 5.3 冻结预付款
        freeze_payment(user_id, order_id)
        
        # 5.4 从候补队列移除
        redis.zrem(f"backup:{train_id}:{date}:{from_station}:{to_station}", user_id)
        
        # 5.5 发送通知
        send_notification(user_id, f"候补成功！订单号：{order_id}")
        
        return True, order_id
        
    finally:
        # Step 6: 释放锁
        for key in lock_acquired:
            # 使用 Lua 脚本，确保只释放自己持有的锁
            redis.eval("""
                if redis.call("GET", KEYS[1]) == ARGV[1] then
                    return redis.call("DEL", KEYS[1])
                else
                    return 0
                end
            """, 1, key, user_id)
```

**关键点**：

1. **锁粒度**：锁到"原子区间"级别（相邻站点间），而非整个座位
2. **锁顺序**：按字典序获取锁，避免死锁（A 等待 B，B 等待 A）
3. **双重检查**：获取锁后再次检查可用性，防止并发穿透
4. **原子释放**：使用 Lua 脚本，确保只释放自己持有的锁

---

### 6.3 难点三：跨区间匹配

**问题**：候补"长区间"，释放"短区间"如何匹配？

```
场景：
用户候补：北京 → 青岛（全程）

当前释放：
- 张三退票：北京 → 天津（仅第一段）
- 李四退票：天津 → 济南（仅第二段）
- 王五退票：济南 → 青岛（仅后两段）

能否匹配？
- 如果三段都同时释放，可以合并给用户
- 但现实中，退票是离散事件，难以凑齐所有区间
```

**方案一**：不跨区间匹配（简单，12306 当前方案）

```
规则：
- 用户候补 北京→青岛，必须有 北京→青岛 的完整区间空位
- 不能由 北京→天津 + 天津→青岛 拼凑

优点：
- 实现简单，逻辑清晰
- 避免复杂的跨区间锁竞争

缺点：
- 用户体验稍差，需要分段候补
- 票源利用率降低
```

**方案二**：智能跨区间匹配（复杂，提升体验）

```python
def smart_match_backup(train_id, date, from_station, to_station, user_id):
    """
    智能匹配：尝试拼接多个短区间满足长区间需求
    核心逻辑：遍历所有座位，找到在所有区间都空闲的座位
    """
    
    # Step 1: 获取所有原子区间
    atomic_intervals = get_atomic_intervals(train_id, from_station, to_station)
    # 例如：北京→青岛 = [北京→天津, 天津→济南, 济南→淄博, 淄博→青岛]
    
    # Step 2: 获取该车次所有座位列表
    all_seats = get_all_seats(train_id, date, seat_type)
    # 例如：['12A', '12B', '12C', '13A', '13B', ...]
    
    # Step 3: 遍历每个座位，检查是否在所有区间都空闲
    for seat_no in all_seats:
        bitmap_key = f"train:{train_id}:{date}:{seat_no}"
        
        # 检查该座位在所有原子区间是否空闲
        all_available = True
        for i, (f, t) in enumerate(atomic_intervals):
            station_idx = get_station_index(f)  # 获取站点索引
            bit = redis.getbit(bitmap_key, station_idx)
            if bit == 1:  # 该区间已被占用
                all_available = False
                break
        
        if all_available:
            # 找到一个在所有区间都空闲的座位
            return seat_no
    
    # Step 4: 无完整匹配，返回 None
    # 可选：记录缺票区间，等待后续释放
    return None


def on_seat_released(train_id, date, seat_no, from_station, to_station):
    """
    席位释放事件触发匹配
    """
    
    # 查询所有可能匹配的候补队列
    # 包括：精确匹配 + 跨区间匹配等待中的用户
    related_queues = find_related_backup_queues(train_id, date, from_station, to_station)
    
    for queue_key in related_queues:
        # 取出队列前 10 名，尝试匹配
        candidates = redis.zrange(queue_key, 0, 9)
        
        for user_id in candidates:
            # 获取该用户的候补需求
            request = get_backup_request(user_id)
            
            # 尝试为该用户匹配座位
            seat = smart_match_backup(
                train_id, date, 
                request.from_station, request.to_station, 
                user_id
            )
            
            if seat:
                allocate_seat(seat, request.from_station, request.to_station, user_id)
                break  # 席位已分配，退出当前队列
```

**跨区间匹配的挑战**：

| 挑战点 | 说明 |
|--------|------|
| 复杂度激增 | 需维护"缺票区间索引"，查询效率下降 |
| 并发竞争更复杂 | 多个部分匹配用户竞争同一区间 |
| 用户体验不确定 | 部分匹配时，用户不知道自己排的是哪个队列 |

**实际权衡**：12306 当前采用"不跨区间匹配"策略，牺牲部分体验换取系统简洁。

---

### 6.4 难点四：热点倾斜

**问题**：春运热门线路，单个区间队列百万级

```
场景：
春节前一周，北京→哈尔滨，候补队列 200 万人

Sorted Set 性能：
- ZADD: O(log N) = log(2,000,000) ≈ 21 次操作
- ZRANK: O(log N) ≈ 21 次操作
- 单次操作微秒级，没问题

问题：
1. 频繁 ZRANK 查询排队名次，热点 Key
2. 频繁 ZRANGE 取队首用户，热点 Key
3. Redis 单线程，单 Key 成为瓶颈
```

**解决方案**：分片队列 + 虚拟排队

```python
# 方案一：队列分片
def get_shard_key(train_id, date, from_station, to_station, user_id):
    """
    将单个大队列拆分成多个小队列
    按 user_id 分片，保证同一用户始终在同一个分片
    """
    shard_count = 32  # 分片数量
    shard_id = hash(user_id) % shard_count
    return f"backup:{train_id}:{date}:{from_station}:{to_station}:shard:{shard_id}"


def add_to_sharded_queue(train_id, date, from_station, to_station, user_id):
    """
    加入分片队列
    """
    shard_key = get_shard_key(train_id, date, from_station, to_station, user_id)
    score = int(time.time() * 1000)
    redis.zadd(shard_key, {user_id: score})


def get_queue_position_sharded(train_id, date, from_station, to_station, user_id):
    """
    查询分片队列中的名次
    """
    shard_key = get_shard_key(train_id, date, from_station, to_station, user_id)
    
    # 本分片内的名次
    local_rank = redis.zrank(shard_key, user_id)
    if local_rank is None:
        return -1
    
    # 加上其他分片的历史完成数
    total_finished = sum([
        redis.get(f"backup:{train_id}:{date}:{from_station}:{to_station}:shard:{i}:finished")
        for i in range(32)
    ])
    
    # 虚拟名次（更准确的估算）
    return local_rank + total_finished + 1


# 方案二：虚拟排队名次
def get_virtual_position(redis, train_id, date, from_station, to_station, user_id):
    """
    不返回真实名次，而是"虚拟名次"
    避免用户看到"排队 150 万名"直接放弃
    """
    real_rank = get_real_position(redis, train_id, date, from_station, to_station, user_id)
    
    if real_rank <= 100:
        # 前 100 名，返回真实名次
        return real_rank
    elif real_rank <= 1000:
        # 100-1000 名，显示"排名前 1000"
        return f"前 1000 名"
    else:
        # 1000 名以后，显示预估等待时间
        avg_fulfill_rate = get_historical_fulfill_rate(train_id, from_station, to_station)
        wait_hours = real_rank / avg_fulfill_rate
        return f"预计等待 {wait_hours:.1f} 小时"
```

**本地缓存优化**：

```python
# 方案三：热点数据本地缓存
from cachetools import TTLCache

# 本地缓存：热门车次的队列长度
queue_length_cache = TTLCache(maxsize=10000, ttl=10)  # 10 秒过期

def get_queue_length(train_id, date, from_station, to_station):
    """
    获取队列长度（优先本地缓存）
    """
    cache_key = f"{train_id}:{date}:{from_station}:{to_station}"
    
    if cache_key in queue_length_cache:
        return queue_length_cache[cache_key]
    
    # 本地缓存未命中，查询 Redis
    length = redis.zcard(f"backup:{train_id}:{date}:{from_station}:{to_station}")
    queue_length_cache[cache_key] = length
    
    return length
```

---

### 6.5 难点五：容灾与降级

**问题**：Redis 故障时如何保证候补可用？

```
故障场景：
1. Redis 主节点宕机，哨兵切换中（30 秒不可用）
2. Redis 集群网络分区，部分数据不可达
3. Redis 内存溢出，被系统 OOM Killer 杀掉
```

**多级容灾设计**：

```
┌─────────────────────────────────────────────────────────────────┐
│                        正常流程                                 │
│                                                                 │
│  用户请求 → Redis Sorted Set 排队 → 候补匹配 → 订单创建        │
│                                                                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Redis 故障检测
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                        降级流程                                 │
│                                                                 │
│  用户请求 → MQ 消息队列暂存 → MySQL 记录排队 → 后台任务恢复    │
│                                                                 │
│  具体措施：                                                     │
│  1. 新增候补请求写入 MQ（Kafka），不直接写 Redis               │
│  2. MySQL 记录候补订单（status=PENDING）                       │
│  3. 后台任务监控 Redis 恢复后，将 MQ 消息同步到 Redis          │
│  4. 查询排队名次返回"系统繁忙，请稍后查询"                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**降级代码示例**：

```python
def add_backup_order_with_fallback(train_id, date, from_station, to_station, user_id):
    """
    加入候补队列（带降级）
    """
    try:
        # 尝试写入 Redis
        redis.zadd(f"backup:{train_id}:{date}:{from_station}:{to_station}", 
                   {user_id: time.time()})
        return True, "排队成功"
    
    except RedisError as e:
        # Redis 故障，降级到 MQ
        log.error(f"Redis 故障，降级到 MQ: {e}")
        
        # 写入 MQ
        mq.send('backup_queue_pending', {
            'train_id': train_id,
            'date': date,
            'from': from_station,
            'to': to_station,
            'user_id': user_id,
            'timestamp': time.time()
        })
        
        # 写入 MySQL（状态为 PENDING，待恢复）
        db.execute("""
            INSERT INTO backup_order 
            (user_id, train_id, travel_date, from_station, to_station, status)
            VALUES (?, ?, ?, ?, ?, 'PENDING')
        """, user_id, train_id, date, from_station, to_station)
        
        return True, "排队成功，系统繁忙，名次稍后可查"


def recover_redis_from_mq():
    """
    后台任务：Redis 恢复后，从 MQ 恢复排队数据
    关键：使用幂等操作，防止重复添加
    """
    messages = mq.consume('backup_queue_pending', batch_size=100)
    
    for msg in messages:
        try:
            queue_key = f"backup:{msg['train_id']}:{msg['date']}:{msg['from']}:{msg['to']}"
            
            # 幂等检查：先查询用户是否已在队列中
            existing_score = redis.zscore(queue_key, msg['user_id'])
            if existing_score is not None:
                # 用户已在队列中，跳过（保留原有的 Score，不更新）
                log.info(f"用户 {msg['user_id']} 已在队列中，跳过恢复")
            else:
                # 用户不在队列中，添加到队列
                redis.zadd(queue_key, {msg['user_id']: msg['timestamp']})
            
            # 更新 MySQL 状态为 QUEUED
            db.execute("""
                UPDATE backup_order SET status = 'QUEUED' 
                WHERE user_id = ? AND train_id = ? AND travel_date = ?
            """, msg['user_id'], msg['train_id'], msg['date'])
            
        except RedisError as e:
            log.error(f"Redis 仍未恢复，稍后重试: {e}")
            break  # Redis 仍不可用，等待下次恢复
```

**降级流程关键点**：

| 关键点 | 说明 |
|--------|------|
| 幂等恢复 | 检查用户是否已在队列，避免重复添加或 Score 被更新 |
| 状态追踪 | MySQL 记录 PENDING→QUEUED 状态变化，便于监控 |
| 批量消费 | 每次消费 100 条，避免单条失败阻塞整批 |
| 优雅退出 | Redis 仍不可用时 break，保留未处理消息供下次恢复 |

---

## 七、总结与思考

### 7.1 12306 候补系统的设计精髓

| 设计点 | 核心思想 | 技术实现 |
|--------|----------|----------|
| 席位复用 | 同一座位分段售卖，提升利用率 | Redis Bitmap |
| 分布式排队 | 按区间独立排队，公平精准 | Redis Sorted Set |
| 事件驱动 | 四类票源触发自动兑现 | Kafka + 消费者模式 |
| 高并发架构 | 四级防护 + 限流降级 | 网关 + Caffeine + Redis + MySQL |
| 一致性保证 | 本地消息表 + 最终一致 | MySQL 事务 + MQ |
| 并发控制 | 分布式锁 + 双重检查 | Redis SET NX + Lua |
| 容灾降级 | MQ 暂存 + 幂等恢复 | Kafka + 定时对账 |

### 7.2 为什么官方候补比第三方靠谱？

| 对比维度 | 官方候补 | 第三方抢票软件 |
|---------|---------|---------------|
| 数据源 | 直接操作席位数据，无延迟 | 轮询 12306 接口，有延迟 |
| 排队公平性 | 时间戳排序，先到先得 | 无法获取真实排队数据 |
| 票源覆盖 | 四类票源全覆盖，包括动态加挂 | 只能监控部分票源 |
| 系统稳定性 | 高并发架构 + 容灾降级 | 容易被 12306 限流封禁 |

### 7.3 可借鉴的架构思想

1. **数据结构选型决定系统上限**：Bitmap 和 Sorted Set 的选择，让百万级数据依然高效

2. **分而治之解决规模问题**：按区间独立排队，将全局问题拆解为局部问题

3. **事件驱动解耦复杂逻辑**：退票、超时、改签、加挂，统一为事件，简化处理

4. **四级防护扛住高并发**：网关限流 → 本地缓存 → Redis → MySQL，逐级降压

5. **最终一致胜过强一致**：分布式系统中，最终一致更易实现，用户体验更好

6. **幂等设计防止重复操作**：降级恢复时先检查再添加，避免数据错乱