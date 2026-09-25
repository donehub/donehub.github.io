---
title: Deep Dive into 12306's Backup Ticket Queue System Design
date: 2024-05-03
tags: [高并发系统设计]
categories: 系统架构
lang: en
label: 044_12306-backup-queue-system-design
---

> "I'm 50th in line, but someone 200th got their ticket first — how?" This question has puzzled countless ticket buyers. The answer lies in the underlying design of the 12306 backup system: seat reuse, per-interval independent queuing, and event-driven matching. This article breaks down this world-class high-concurrency system across five dimensions — not just what it does, but why it works this way.

---

<!-- more -->
## 1. Why is 12306 So Hard to Build?

Before diving into the design, let's understand the scale of the problem.

### 1.1 Business Complexity

Railway ticketing differs fundamentally from typical e-commerce flash sales:

| Dimension | E-Commerce Flash Sale | 12306 Ticketing |
|-----------|----------------------|-----------------|
| Product granularity | SKU level (one phone) | Interval level (Beijing→Jinan, same seat, different intervals) |
| Inventory management | Just deduct stock | Overlapping intervals, seat reuse |
| Concurrency contention | Multiple buyers for one SKU | Multiple overlapping intervals for the same seat |
| Order association | Independent orders | Linked orders (connecting trips, round trips) |

**The core difference**: A single high-speed train from Beijing to Shanghai passes through 10 stations. The same seat can be split into 9 interval segments sold separately. This creates exponential complexity.

### 1.2 Scale Numbers

Take the 2024 Spring Festival travel rush as an example:
- Daily page views: **10 billion+**
- Peak QPS: **1 million+ per second**
- Backup orders: daily peak of **20 million+**
- Train data: **5,000+ trains**, each with **500–2,000 seats**

At this scale, any design flaw gets amplified instantly into a system-wide failure.

---

## 2. Core Foundation: Seat Reuse

### 2.1 What is Seat Reuse?

**Seat reuse** means the same seat can be sold to different passengers in segments, as long as their travel intervals don't overlap.

Example:

```
Train: G1 Beijing → Qingdao
Stations: Beijing → Tianjin → Jinan → Zibo → Qingdao

Seat 12A sales:
- Zhang: Beijing → Jinan (occupies Beijing→Tianjin, Tianjin→Jinan)
- Li: Jinan → Qingdao (occupies Jinan→Zibo, Zibo→Qingdao)
- Wang: Tianjin → Zibo (occupies Tianjin→Jinan, Jinan→Zibo)

Result: Seat 12A is sold to 3 people simultaneously, no conflicts
```

This design dramatically improves seat utilization, but the technical implementation gets significantly harder.

### 2.2 Implementation: Redis Bitmap

12306 uses **Redis Bitmap** to store the interval occupancy status of each seat.

**Data structure design:**

```
Key:   train:{train_id}:{date}:{seat_no}
Value: Bitmap, each bit represents the occupancy of one station interval

Example:
Train G1, date 2024-01-20, seat 12A
Stations: Beijing(0) → Tianjin(1) → Jinan(2) → Zibo(3) → Qingdao(4)

Bitmap: 1 1 0 0
         ↑ ↑ ↑ ↑
         │ │ │ └─ Zibo→Qingdao (0=available)
         │ │ └─── Jinan→Zibo (0=available)  
         │ └───── Tianjin→Jinan (1=occupied)
         └─────── Beijing→Tianjin (1=occupied)

Meaning: Beijing→Jinan sold, Jinan→Qingdao available
```

**Why Bitmap?**

| Metric | Bitmap | Traditional (e.g., Hash) |
|--------|--------|--------------------------|
| Space | N stations need only N bits (a few bytes) | One field per interval (hundreds of bytes) |
| Query complexity | O(1) | O(N) |
| Interval check | Bitwise `OR`, one operation | Must iterate all intervals |
| Use case | Fixed-length, high-frequency queries | Flexible but inefficient |

**Interval availability check (pseudocode):**

```python
def check_interval_available(redis, train_id, date, seat_no, from_station, to_station):
    """
    Check if a specific interval is available
    from_station: starting station index (e.g., Beijing=0)
    to_station: ending station index (e.g., Jinan=2)
    """
    key = f"train:{train_id}:{date}:{seat_no}"
    
    # Check all bits from from_station to to_station-1
    # i.e., interval [from_station, to_station)
    for i in range(from_station, to_station):
        bit = redis.getbit(key, i)
        if bit == 1:  # This interval is already occupied
            return False
    
    return True


def allocate_interval(redis, train_id, date, seat_no, from_station, to_station):
    """
    Allocate interval: set corresponding bits to 1
    """
    key = f"train:{train_id}:{date}:{seat_no}"
    
    for i in range(from_station, to_station):
        redis.setbit(key, i, 1)
    
    return True
```

**A more efficient approach using bitwise operations:**

```python
def check_and_allocate(redis, train_id, date, seat_no, from_station, to_station):
    """
    Check and allocate interval in one bitwise operation
    """
    key = f"train:{train_id}:{date}:{seat_no}"
    
    # 1. Get current bitmap value (represented as integer)
    current = redis.get(key)
    if current is None:
        current = 0
    
    # 2. Build interval mask
    # e.g., from=0, to=2, mask is 0b0011 (lower bits = earlier intervals)
    mask = (1 << to_station) - (1 << from_station)  # 0b0011
    
    # 3. Check if interval is already occupied
    if current & mask != 0:
        return False  # Interval is occupied
    
    # 4. Allocate interval (atomic operation, requires Lua script)
    # Lua script ensures atomicity of check + set
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

## 3. Distributed Queuing Mechanism

### 3.1 Core Design: Per-Interval Independent Queuing

Many people assume the backup queue is one big line for the entire train. It's not.

**12306's design: each travel interval has its own independent queue.**

```
Backup queues for Train G1 (Beijing → Qingdao):

Queue 1: Beijing → Tianjin (85 people in line)
Queue 2: Beijing → Jinan (320 people in line)
Queue 3: Tianjin → Jinan (56 people in line)
Queue 4: Jinan → Qingdao (198 people in line)
Queue 5: Beijing → Qingdao (1,275 people in line)
...

Each interval has its own Sorted Set
```

**Why queue by interval?**

1. **Fairness**: Beijing→Tianjin and Beijing→Qingdao aren't the same tickets at all — mixing them in one queue makes no sense
2. **Parallel processing**: Different interval queues can be processed concurrently, increasing throughput
3. **Precise matching**: When a seat is released, the system locates the exact queue directly — no iteration needed

**This answers a common question**:

> Why am I 50th in line but someone 200th got their ticket first?

Because you're not in the same queue. They queued for Tianjin→Jinan; you queued for Beijing→Jinan.

### 3.2 Implementation: Redis Sorted Set

**Data structure design:**

```
Key:   backup:{train_id}:{date}:{from_station}:{to_station}
Value: Sorted set storing backup order IDs
Score: Timestamp when user submitted the backup request (lower = earlier)

Example:
backup:G1:20240120:beijing:jinan
  ├─ order_001 (score: 1705678901) ← 1st
  ├─ order_002 (score: 1705678905) ← 2nd
  ├─ order_003 (score: 1705678912) ← 3rd
  └─ ...
```

**Core operations:**

```python
import time

def add_to_backup_queue(redis, train_id, date, from_station, to_station, order_id):
    """
    Join backup queue (ZADD)
    Timestamp as Score naturally implements first-come-first-served
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    score = int(time.time() * 1000)  # Millisecond timestamp for precise ordering
    
    redis.zadd(key, {order_id: score})
    return True


def get_queue_position(redis, train_id, date, from_station, to_station, order_id):
    """
    Query queue position (ZRANK)
    Returns current position (0-based, +1 for actual rank)
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    rank = redis.zrank(key, order_id)
    
    if rank is None:
        return -1  # Not in queue
    return rank + 1  # Actual rank (1-based)


def get_top_n_from_queue(redis, train_id, date, from_station, to_station, n=10):
    """
    Get top N from queue (ZRANGE)
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    return redis.zrange(key, 0, n - 1)


def remove_from_queue(redis, train_id, date, from_station, to_station, order_id):
    """
    Remove from queue on success or cancellation (ZREM)
    """
    key = f"backup:{train_id}:{date}:{from_station}:{to_station}"
    redis.zrem(key, order_id)
    return True
```

**Performance analysis:**

| Operation | Complexity | Time for million-level queue |
|-----------|-----------|------------------------------|
| ZADD (join queue) | O(log N) | ~21 comparisons, microsecond-level |
| ZRANK (query rank) | O(log N) | Microsecond-level |
| ZRANGE (get top N) | O(log N + M) | M = number retrieved, millisecond-level |
| ZREM (leave queue) | O(log N) | Microsecond-level |

Sorted Set is a natural fit for queuing — it stays efficient even with millions of entries.

### 3.3 Data Persistence: MySQL Sharding

Redis is an in-memory database; a crash could lose data. Backup orders must be persisted to MySQL.

**Sharding strategy:**

```
Database shard key: user_id % 16 (16 databases by user)
Table shard key: order_id % 128 (128 tables per database)

Table structure:
CREATE TABLE backup_order_00 (
    order_id BIGINT PRIMARY KEY,
    user_id BIGINT NOT NULL,
    train_id VARCHAR(20) NOT NULL,
    travel_date DATE NOT NULL,
    from_station VARCHAR(20) NOT NULL,
    to_station VARCHAR(20) NOT NULL,
    seat_type TINYINT NOT NULL,      -- Seat type: business/first/second
    status TINYINT DEFAULT 0,         -- Status: queuing/fulfilled/cancelled
    queue_position INT,              -- Redundant storage of queue position
    create_time DATETIME,
    update_time DATETIME,
    
    INDEX idx_train_date (train_id, travel_date, from_station, to_station)
);
```

**How do Redis and MySQL stay consistent?**

This is a classic distributed consistency problem, covered in detail later.

---

## 4. Event-Driven: Where Do Backup Tickets Come From?

Backup tickets don't appear from nowhere — they all come from system events.

### 4.1 Four Ticket Sources

| Source | Trigger event | Latency | Share (estimated) |
|--------|--------------|---------|-------------------|
| User refunds | User voluntarily cancels | Seconds | 40% |
| Order timeout | 30 minutes without payment after purchase | Seconds | 35% |
| Reschedule release | User switches to another train | Seconds | 15% |
| Dynamic addition | 12306 officially adds carriages | Minutes | 10% |

### 4.2 Event-Driven Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                         Event Sources                            │
├──────────┬──────────┬──────────┬─────────────────────────────────┤
│ Refund   │ Timeout  │ Resched. │ Extra seats (scheduled task)    │
└────┬─────┴────┬─────┴────┬─────┴─────────────┬───────────────────┘
     │          │          │                   │
     ▼          ▼          ▼                   ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Message Queue (Kafka/RocketMQ)                │
│                                                                  │
│  Topic: ticket-released                                         │
│  Partition: by train_id, ensuring sequential processing per train│
└───────────────────────────┬──────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────────┐
│                    Backup Matching Service                       │
│                                                                  │
│  1. Consume released seat event                                 │
│  2. Query backup queue for the interval (Redis Sorted Set)      │
│  3. Take the first person in queue                              │
│  4. Execute fulfillment process                                 │
└──────────────────────────────────────────────────────────────────┘
```

**Event message structure:**

```json
{
  "event_id": "evt_20240120_123456",
  "event_type": "REFUND",  // REFUND / TIMEOUT / RESCHEDULE / EXTRA_SEAT
  "train_id": "G1",
  "travel_date": "2024-01-20",
  "seat_no": "12A",
  "from_station": "beijing",
  "to_station": "jinan",
  "seat_type": 2,  // Second class
  "release_time": 1705678901234,
  "trace_id": "trace_abc123"  // Distributed tracing
}
```

### 4.3 Backup Matching Flow

```
Seat release event triggered:

Step 1: Parse event, determine released interval
        train_id=G1, date=20240120, seat=12A, from=beijing, to=jinan

Step 2: Compute all atomic intervals covered
        Beijing→Jinan = [Beijing→Tianjin, Tianjin→Jinan]

Step 3: Query backup queues for these intervals
        - Queue A: Beijing→Tianjin (85 people)
        - Queue B: Tianjin→Jinan (56 people)
        - Queue C: Beijing→Jinan (320 people) ← Exact match, process first

Step 4: Try to match Queue C's first person
        - Check if seat 12A meets the user's needs (seat type, availability)
        - Meets → execute fulfillment
        - Doesn't meet → try Queue C's second person

Step 5: If Queue C has no match, try other queues
        - Does Queue A + Queue B have the same seat?
        - This involves cross-interval matching, detailed later
```

### 4.4 Complete Fulfillment Flow

After a seat is released, the system must execute an atomic process to complete fulfillment:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Complete Fulfillment Flow                         │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────┐                                                        │
│  │ Seat release │                                                        │
│  │   event      │                                                        │
│  └──────┬──────┘                                                        │
│         │                                                                │
│         ▼                                                                │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 1: Query backup queue                                          ││
│  │                                                                     ││
│  │  redis.zrange("backup:G1:20240120:beijing:jinan", 0, 0)           ││
│  │  → Get first user_id in queue                                       ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 2: Acquire distributed lock                                    ││
│  │                                                                     ││
│  │  lock_keys = ["lock:G1:20240120:12A:beijing:tianjin",              ││
│  │               "lock:G1:20240120:12A:tianjin:jinan"]                 ││
│  │  redis.set(lock_key, user_id, nx=True, px=5000)                    ││
│  │  → Lock all atomic intervals to prevent overselling                 ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 3: Check seat availability (double-check)                      ││
│  │                                                                     ││
│  │  bitmap_key = "train:G1:20240120:12A"                              ││
│  │  check_interval_available(bitmap_key, beijing, jinan)              ││
│  │  → Confirm seat is truly available                                  ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 4: MySQL local transaction (atomic)                            ││
│  │                                                                     ││
│  │  BEGIN TRANSACTION;                                                ││
│  │    -- 4.1 Mark seat as occupied                                    ││
│  │    UPDATE seat SET status='OCCUPIED' WHERE ...;                    ││
│  │    -- 4.2 Create order                                             ││
│  │    INSERT INTO ticket_order (...) VALUES (...);                    ││
│  │    -- 4.3 Update backup status                                     ││
│  │    UPDATE backup_order SET status='FULFILLED' WHERE ...;           ││
│  │    -- 4.4 Write operation log (for async Redis sync)               ││
│  │    INSERT INTO backup_operation_log (...) VALUES (...);            ││
│  │  COMMIT;                                                            ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 5: Async update Redis                                          ││
│  │                                                                     ││
│  │  -- 5.1 Update seat Bitmap                                          ││
│  │  redis.setbit("train:G1:20240120:12A", beijing_idx, 1)            ││
│  │  redis.setbit("train:G1:20240120:12A", tianjin_idx, 1)            ││
│  │  -- 5.2 Remove from backup queue                                    ││
│  │  redis.zrem("backup:G1:20240120:beijing:jinan", user_id)          ││
│  │  -- 5.3 Release distributed lock                                    ││
│  │  redis.del(lock_keys)                                              ││
│  └──────────────────────────────┬──────────────────────────────────────┘│
│                                 │                                        │
│                                 ▼                                        │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │ Step 6: Post-processing                                             ││
│  │                                                                     ││
│  │  -- 6.1 Freeze prepayment (call payment service)                    ││
│  │  -- 6.2 Send SMS notification (call notification service)           ││
│  │  -- 6.3 Update operation log status                                 ││
│  └─────────────────────────────────────────────────────────────────────┘│
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

**Key points at each step:**

| Step | Key point | Failure handling |
|------|-----------|-----------------|
| Acquire lock | Acquire in lexicographic order to prevent deadlock | Failed → seat taken, skip |
| Double-check | Re-check after locking to prevent concurrent bypass | Unavailable → release lock, try next user |
| MySQL transaction | Local transaction ensures atomicity | Failed → release lock, rollback, try next |
| Async Redis update | Operation log ensures eventual consistency | Failed → scheduled task compensates |
| Post-processing | Async, doesn't block main flow | Failed → retry or alert for manual handling |

---

## 5. High-Concurrency Architecture Design

### 5.1 Four-Layer Defense Architecture

From user request to data persistence, 12306 builds a four-layer defense system, reducing pressure at each level:

```
┌─────────────────────────────────────────────────────────────────┐
│                        User Request                             │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Layer 1: Gateway Rate Limiting                  │
│                                                                 │
│  Token bucket: limits per-IP, per-user request frequency       │
│  Anti-abuse: detects abnormal request patterns                 │
│  Purpose: block malicious traffic, protect backend services    │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Layer 2: Application Local Cache                │
│                                                                 │
│  Tech: Caffeine / Guava Cache                                  │
│  Cached content:                                                │
│    - Queue length for popular routes ("what's my position?")   │
│    - Seat overview for popular trains                          │
│    - TTL: 5-10 seconds (tolerate brief inconsistency)          │
│  Effect: intercepts 60%+ of queries, reduces Redis pressure   │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Layer 3: Redis Cluster Cache                    │
│                                                                 │
│  Deployment: master-replica + sentinel for HA                   │
│  Stores:                                                        │
│    - Seat Bitmap (real-time status)                             │
│    - Backup Sorted Set (queue data)                             │
│    - Distributed locks (concurrency control)                    │
│  Performance: 100K+ QPS per node, all in-memory               │
└─────────────────────────────┬───────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Layer 4: MySQL Sharding                         │
│                                                                 │
│  Stores: order persistence, user data, backup records          │
│  Sharding: by user_id for databases, by order_id for tables    │
│  Purpose: data safety net, fallback when Redis is down         │
└─────────────────────────────────────────────────────────────────┘
```

**Why four layers?**

| Layer | Core role | If missing |
|-------|-----------|-----------|
| Gateway rate limiting | Block malicious traffic | Backend gets overwhelmed, legitimate users can't access |
| Local cache | Intercept high-frequency queries | Redis gets crushed by read requests |
| Redis cache | Handle core reads/writes | MySQL gets hammered by high-frequency queries |
| MySQL persistence | Data safety net | Data loss when Redis fails |

### 5.2 Rate Limiting and Degradation

| Scenario | Rate limiting | Degradation | User experience |
|----------|--------------|-------------|-----------------|
| Normal peak | Token bucket at 100K QPS | None | Normal service |
| Extreme peak | Sliding window | Queue wait | "System busy, please retry" |
| Redis failure | Circuit break | Reads go to MySQL, writes go to MQ | Backup delayed, position unqueryable |
| MySQL failure | Circuit break | Pause orders, read-only | "System under maintenance" |

---

## 6. Technical Deep Dives

The core design was covered above. What keeps the system rock-solid, though, is the meticulous handling of details.

### 6.1 Challenge 1: Distributed Consistency

**Problem**: How do you keep the Redis queue and MySQL orders in sync?

```
Scenario: User cancels backup

Approach 1: Update MySQL first, then delete Redis
  1. MySQL DELETE succeeds
  2. Redis ZREM fails (network blip)
  → Result: No order in MySQL, still queuing in Redis — "ghost queue"

Approach 2: Delete Redis first, then update MySQL
  1. Redis ZREM succeeds
  2. MySQL DELETE fails
  → Result: Redis deleted, MySQL still has it — user can't recover their spot
```

**Solution**: Local message table + eventual consistency

```sql
-- Backup operation log table (same database as business tables, uses local transaction)
CREATE TABLE backup_operation_log (
    log_id BIGINT PRIMARY KEY AUTO_INCREMENT,
    order_id BIGINT NOT NULL,
    operation_type VARCHAR(20) NOT NULL,  -- ADD / CANCEL / FULFILL
    redis_status TINYINT DEFAULT 0,        -- 0=pending 1=success 2=failed
    mysql_status TINYINT DEFAULT 0,       -- 0=pending 1=success 2=failed
    retry_count INT DEFAULT 0,
    create_time DATETIME,
    update_time DATETIME,
    
    INDEX idx_status (redis_status, mysql_status)
);
```

**Operation flow:**

```python
def cancel_backup_order(order_id):
    """Cancel backup order (ensures eventual consistency)"""
    
    # Step 1: Local transaction — write operation log + update order status
    with db.transaction():
        # Mark order as "cancelling"
        db.execute("UPDATE backup_order SET status = 'CANCELING' WHERE order_id = ?", order_id)
        
        # Write operation log
        log_id = db.execute("""
            INSERT INTO backup_operation_log 
            (order_id, operation_type, redis_status, mysql_status) 
            VALUES (?, 'CANCEL', 0, 0)
        """, order_id)
    
    # Step 2: Async process Redis operation
    mq.send('backup_operation', {'log_id': log_id, 'order_id': order_id, 'type': 'CANCEL'})
    
    return True


def process_cancel_message(message):
    """Process cancellation message"""
    log_id = message['log_id']
    order_id = message['order_id']
    
    try:
        # Step 3: Remove from Redis queue
        redis.zrem(f"backup:{train}:{date}:{from}:{to}", order_id)
        
        # Step 4: Update MySQL order status
        db.execute("UPDATE backup_order SET status = 'CANCELED' WHERE order_id = ?", order_id)
        
        # Step 5: Update operation log
        db.execute("UPDATE backup_operation_log SET redis_status=1, mysql_status=1 WHERE log_id=?", log_id)
        
    except Exception as e:
        # Retry on failure, alert after 3 attempts
        retry_count = db.query("SELECT retry_count FROM backup_operation_log WHERE log_id=?", log_id)
        if retry_count < 3:
            db.execute("UPDATE backup_operation_log SET retry_count = retry_count + 1 WHERE log_id=?", log_id)
            mq.send('backup_operation', message, delay=60)  # Retry after 60 seconds
        else:
            alert(f"Backup cancellation failed, log_id={log_id}, error={e}")
```

**Scheduled reconciliation task:**

```python
def reconcile_backup_data():
    """Reconcile every hour to ensure Redis and MySQL are consistent"""
    
    # Step 1: Scan all backup queues
    all_queues = redis.keys("backup:*")
    
    for queue_key in all_queues:
        order_ids = redis.zrange(queue_key, 0, -1)
        
        for order_id in order_ids:
            # Step 2: Check if order exists in MySQL
            order = db.query("SELECT * FROM backup_order WHERE order_id = ?", order_id)
            
            if not order or order.status == 'CANCELED':
                # Step 3: Exists in Redis but not in MySQL (or cancelled) — clean up Redis
                redis.zrem(queue_key, order_id)
                log.info(f"Cleaned ghost queue entry: {order_id}")
```

---

### 6.2 Challenge 2: Concurrent Contention and Overselling

**Problem**: When the same seat is released, how do multiple interval queues compete for it?

```
Scenario:
Train G1, seat 12A
Zhang cancels: Beijing → Jinan

Released intervals: Beijing→Tianjin, Tianjin→Jinan

Existing backup queues:
- Queue A: Beijing→Tianjin (100 people)
- Queue B: Tianjin→Jinan (80 people)
- Queue C: Beijing→Jinan (200 people)

Without concurrency control:
1. Queue A assigns 12A to user X (Beijing→Tianjin)
2. Queue C assigns 12A to user Y (Beijing→Jinan)
→ X and Y's intervals overlap — oversold!
```

**Solution**: Distributed locks + interval locking

```python
def allocate_seat_to_backup(train_id, date, seat_no, from_station, to_station, user_id):
    """
    Allocate seat to backup user
    Core idea: lock all involved atomic intervals to prevent concurrent overselling
    """
    
    # Step 1: Get all atomic intervals for this range (adjacent station pairs)
    atomic_intervals = get_atomic_intervals(train_id, from_station, to_station)
    # e.g., Beijing→Jinan = [(Beijing, Tianjin), (Tianjin, Jinan)]
    
    # Step 2: Generate lock keys (sorted lexicographically to prevent deadlock)
    lock_keys = sorted([
        f"lock:{train_id}:{date}:{seat_no}:{f}:{t}"
        for f, t in atomic_intervals
    ])
    
    # Step 3: Try to acquire all locks (SET NX PX with timeout)
    lock_acquired = []
    for key in lock_keys:
        success = redis.set(key, user_id, nx=True, px=5000)  # 5 second timeout
        if not success:
            # Failed to acquire — release already acquired locks
            for acquired_key in lock_acquired:
                redis.delete(acquired_key)
            return False, "Seat is occupied"
        lock_acquired.append(key)
    
    try:
        # Step 4: Double-check seat availability
        if not check_seat_available(train_id, date, seat_no, from_station, to_station):
            return False, "Seat unavailable"
        
        # Step 5: Execute fulfillment
        # 5.1 Mark seat as occupied
        mark_seat_occupied(train_id, date, seat_no, from_station, to_station, user_id)
        
        # 5.2 Create order (MySQL local transaction)
        order_id = create_ticket_order(user_id, train_id, date, seat_no, from_station, to_station)
        
        # 5.3 Freeze prepayment
        freeze_payment(user_id, order_id)
        
        # 5.4 Remove from backup queue
        redis.zrem(f"backup:{train_id}:{date}:{from_station}:{to_station}", user_id)
        
        # 5.5 Send notification
        send_notification(user_id, f"Backup successful! Order: {order_id}")
        
        return True, order_id
        
    finally:
        # Step 6: Release locks
        for key in lock_acquired:
            # Use Lua script to ensure only releasing locks you own
            redis.eval("""
                if redis.call("GET", KEYS[1]) == ARGV[1] then
                    return redis.call("DEL", KEYS[1])
                else
                    return 0
                end
            """, 1, key, user_id)
```

**Key points:**

1. **Lock granularity**: Lock at the "atomic interval" level (between adjacent stations), not the entire seat
2. **Lock ordering**: Acquire locks in lexicographic order to prevent deadlock (A waits for B, B waits for A)
3. **Double-check**: Re-check availability after acquiring the lock to prevent concurrent bypass
4. **Atomic release**: Use Lua scripts to ensure you only release locks you own

---

### 6.3 Challenge 3: Cross-Interval Matching

**Problem**: User backs up a "long interval," but only "short intervals" are released — how to match?

```
Scenario:
User backup: Beijing → Qingdao (full route)

Current releases:
- Zhang cancels: Beijing → Tianjin (first segment only)
- Li cancels: Tianjin → Jinan (second segment only)
- Wang cancels: Jinan → Qingdao (last two segments)

Can these match?
- If all three release simultaneously, they could be combined for the user
- In reality, cancellations are discrete events — hard to assemble all intervals
```

**Approach 1**: No cross-interval matching (simple, 12306's current approach)

```
Rules:
- User backing up Beijing→Qingdao needs a complete Beijing→Qingdao interval to be free
- Cannot be assembled from Beijing→Tianjin + Tianjin→Qingdao

Pros:
- Simple implementation, clear logic
- Avoids complex cross-interval lock contention

Cons:
- Slightly worse user experience — users need to back up in segments
- Lower ticket utilization
```

**Approach 2**: Smart cross-interval matching (complex, better experience)

```python
def smart_match_backup(train_id, date, from_station, to_station, user_id):
    """
    Smart matching: try to combine multiple short intervals to satisfy a long interval
    Core logic: iterate all seats, find one that's free across all intervals
    """
    
    # Step 1: Get all atomic intervals
    atomic_intervals = get_atomic_intervals(train_id, from_station, to_station)
    # e.g., Beijing→Qingdao = [Beijing→Tianjin, Tianjin→Jinan, Jinan→Zibo, Zibo→Qingdao]
    
    # Step 2: Get all seats for this train
    all_seats = get_all_seats(train_id, date, seat_type)
    # e.g., ['12A', '12B', '12C', '13A', '13B', ...]
    
    # Step 3: Check each seat for availability across all intervals
    for seat_no in all_seats:
        bitmap_key = f"train:{train_id}:{date}:{seat_no}"
        
        # Check if this seat is free in all atomic intervals
        all_available = True
        for i, (f, t) in enumerate(atomic_intervals):
            station_idx = get_station_index(f)
            bit = redis.getbit(bitmap_key, station_idx)
            if bit == 1:  # This interval is occupied
                all_available = False
                break
        
        if all_available:
            # Found a seat free across all intervals
            return seat_no
    
    # Step 4: No complete match found
    # Optional: record missing intervals, wait for future releases
    return None


def on_seat_released(train_id, date, seat_no, from_station, to_station):
    """
    Triggered by seat release event
    """
    
    # Query all potentially matching backup queues
    # Includes: exact match + users waiting for cross-interval match
    related_queues = find_related_backup_queues(train_id, date, from_station, to_station)
    
    for queue_key in related_queues:
        # Get top 10 from queue, try to match
        candidates = redis.zrange(queue_key, 0, 9)
        
        for user_id in candidates:
            # Get this user's backup request
            request = get_backup_request(user_id)
            
            # Try to match a seat for this user
            seat = smart_match_backup(
                train_id, date, 
                request.from_station, request.to_station, 
                user_id
            )
            
            if seat:
                allocate_seat(seat, request.from_station, request.to_station, user_id)
                break  # Seat assigned, exit this queue
```

**Challenges of cross-interval matching:**

| Challenge | Details |
|-----------|---------|
| Complexity spike | Need to maintain a "missing interval index," query efficiency drops |
| More complex concurrency | Multiple partially-matching users compete for the same interval |
| Unpredictable UX | With partial matching, users don't know which queue they're in |

**Practical trade-off**: 12306 currently uses the "no cross-interval matching" strategy, sacrificing some user experience for system simplicity.

---

### 6.4 Challenge 4: Hotspot Skew

**Problem**: During Spring Festival rush, a single interval queue can hit millions.

```
Scenario:
Week before Spring Festival, Beijing→Harbin, backup queue has 2 million people

Sorted Set performance:
- ZADD: O(log N) = log(2,000,000) ≈ 21 operations
- ZRANK: O(log N) ≈ 21 operations
- Single operations are microsecond-level — not the problem

The issue:
1. Frequent ZRANK queries for queue position — hot key
2. Frequent ZRANGE to get queue head — hot key
3. Redis is single-threaded — single key becomes the bottleneck
```

**Solution**: Sharded queues + virtual queuing

```python
# Approach 1: Queue sharding
def get_shard_key(train_id, date, from_station, to_station, user_id):
    """
    Split one large queue into multiple smaller queues
    Shard by user_id, ensuring same user always lands in same shard
    """
    shard_count = 32
    shard_id = hash(user_id) % shard_count
    return f"backup:{train_id}:{date}:{from_station}:{to_station}:shard:{shard_id}"


def add_to_sharded_queue(train_id, date, from_station, to_station, user_id):
    """Join sharded queue"""
    shard_key = get_shard_key(train_id, date, from_station, to_station, user_id)
    score = int(time.time() * 1000)
    redis.zadd(shard_key, {user_id: score})


def get_queue_position_sharded(train_id, date, from_station, to_station, user_id):
    """Query position in sharded queue"""
    shard_key = get_shard_key(train_id, date, from_station, to_station, user_id)
    
    # Rank within this shard
    local_rank = redis.zrank(shard_key, user_id)
    if local_rank is None:
        return -1
    
    # Add completed counts from other shards
    total_finished = sum([
        redis.get(f"backup:{train_id}:{date}:{from_station}:{to_station}:shard:{i}:finished")
        for i in range(32)
    ])
    
    # Virtual rank (more accurate estimate)
    return local_rank + total_finished + 1


# Approach 2: Virtual queue position
def get_virtual_position(redis, train_id, date, from_station, to_station, user_id):
    """
    Don't return exact rank — return a "virtual position"
    Prevents users from seeing "1.5 million in line" and giving up
    """
    real_rank = get_real_position(redis, train_id, date, from_station, to_station, user_id)
    
    if real_rank <= 100:
        # Top 100: return exact rank
        return real_rank
    elif real_rank <= 1000:
        # 100-1000: show "top 1000"
        return f"Top 1000"
    else:
        # 1000+: show estimated wait time
        avg_fulfill_rate = get_historical_fulfill_rate(train_id, from_station, to_station)
        wait_hours = real_rank / avg_fulfill_rate
        return f"Estimated wait: {wait_hours:.1f} hours"
```

**Local cache optimization:**

```python
# Approach 3: Local cache for hot data
from cachetools import TTLCache

# Local cache: queue lengths for popular trains
queue_length_cache = TTLCache(maxsize=10000, ttl=10)  # 10 second expiry

def get_queue_length(train_id, date, from_station, to_station):
    """Get queue length (prefer local cache)"""
    cache_key = f"{train_id}:{date}:{from_station}:{to_station}"
    
    if cache_key in queue_length_cache:
        return queue_length_cache[cache_key]
    
    # Cache miss — query Redis
    length = redis.zcard(f"backup:{train_id}:{date}:{from_station}:{to_station}")
    queue_length_cache[cache_key] = length
    
    return length
```

---

### 6.5 Challenge 5: Disaster Recovery and Degradation

**Problem**: How do you keep backup available when Redis fails?

```
Failure scenarios:
1. Redis master goes down, sentinel is switching (30 seconds unavailable)
2. Redis cluster network partition — some data unreachable
3. Redis OOM — killed by system OOM Killer
```

**Multi-level disaster recovery design:**

```
┌─────────────────────────────────────────────────────────────────┐
│                        Normal Flow                              │
│                                                                 │
│  User request → Redis Sorted Set queue → Match → Create order  │
│                                                                 │
└───────────────────────────┬─────────────────────────────────────┘
                            │ Redis failure detected
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                       Degraded Flow                             │
│                                                                 │
│  User request → MQ buffer → MySQL records queue → Background   │
│                               task restores when Redis returns  │
│                                                                 │
│  Specific measures:                                             │
│  1. New backup requests write to MQ (Kafka), not Redis         │
│  2. MySQL records backup order (status=PENDING)                │
│  3. Background task monitors Redis recovery, syncs MQ → Redis  │
│  4. Queue position query returns "System busy, retry later"    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Degradation code example:**

```python
def add_backup_order_with_fallback(train_id, date, from_station, to_station, user_id):
    """Join backup queue (with fallback)"""
    try:
        # Try writing to Redis
        redis.zadd(f"backup:{train_id}:{date}:{from_station}:{to_station}", 
                   {user_id: time.time()})
        return True, "Queued successfully"
    
    except RedisError as e:
        # Redis failure — fall back to MQ
        log.error(f"Redis failure, falling back to MQ: {e}")
        
        # Write to MQ
        mq.send('backup_queue_pending', {
            'train_id': train_id,
            'date': date,
            'from': from_station,
            'to': to_station,
            'user_id': user_id,
            'timestamp': time.time()
        })
        
        # Write to MySQL (status=PENDING, awaiting recovery)
        db.execute("""
            INSERT INTO backup_order 
            (user_id, train_id, travel_date, from_station, to_station, status)
            VALUES (?, ?, ?, ?, ?, 'PENDING')
        """, user_id, train_id, date, from_station, to_station)
        
        return True, "Queued successfully. System busy — position available later"


def recover_redis_from_mq():
    """
    Background task: restore queue data from MQ after Redis recovers
    Key: use idempotent operations to prevent duplicate additions
    """
    messages = mq.consume('backup_queue_pending', batch_size=100)
    
    for msg in messages:
        try:
            queue_key = f"backup:{msg['train_id']}:{msg['date']}:{msg['from']}:{msg['to']}"
            
            # Idempotency check: verify user isn't already in queue
            existing_score = redis.zscore(queue_key, msg['user_id'])
            if existing_score is not None:
                # User already in queue — skip (preserve original Score, don't update)
                log.info(f"User {msg['user_id']} already in queue, skipping recovery")
            else:
                # User not in queue — add them
                redis.zadd(queue_key, {msg['user_id']: msg['timestamp']})
            
            # Update MySQL status to QUEUED
            db.execute("""
                UPDATE backup_order SET status = 'QUEUED' 
                WHERE user_id = ? AND train_id = ? AND travel_date = ?
            """, msg['user_id'], msg['train_id'], msg['date'])
            
        except RedisError as e:
            log.error(f"Redis still not recovered, will retry: {e}")
            break  # Redis still unavailable — stop and wait for next recovery
```

**Key points in the degradation flow:**

| Key point | Details |
|-----------|---------|
| Idempotent recovery | Check if user is already in queue before adding — avoids duplicates or Score overwrites |
| State tracking | MySQL tracks PENDING→QUEUED status transitions for monitoring |
| Batch consumption | Consume 100 at a time — one failure doesn't block the entire batch |
| Graceful exit | Break when Redis is still down — unprocessed messages stay in MQ for next recovery |

---

## 7. Summary and Reflections

### 7.1 Design Essentials of the 12306 Backup System

| Design point | Core idea | Implementation |
|-------------|-----------|---------------|
| Seat reuse | Sell same seat in segments to maximize utilization | Redis Bitmap |
| Distributed queuing | Per-interval independent queues — fair and precise | Redis Sorted Set |
| Event-driven | Four ticket sources trigger automatic fulfillment | Kafka + consumer pattern |
| High-concurrency architecture | Four-layer defense + rate limiting + degradation | Gateway + Caffeine + Redis + MySQL |
| Consistency guarantee | Local message table + eventual consistency | MySQL transaction + MQ |
| Concurrency control | Distributed lock + double-check | Redis SET NX + Lua |
| Disaster recovery | MQ buffering + idempotent recovery | Kafka + scheduled reconciliation |

### 7.2 Why Official Backup Beats Third-Party Tools

| Dimension | Official backup | Third-party ticket scalpers |
|-----------|----------------|----------------------------|
| Data source | Direct access to seat data, no delay | Polls 12306 API, has latency |
| Queue fairness | Timestamp-sorted, first-come-first-served | Cannot access real queue data |
| Ticket coverage | All four sources including dynamic additions | Can only monitor some sources |
| System stability | HA architecture + degradation | Gets rate-limited and blocked by 12306 |

### 7.3 Architecture Principles Worth Borrowing

1. **Data structure choice sets the system ceiling**: Bitmap and Sorted Set keep million-level data efficient

2. **Divide and conquer solves scale problems**: Independent per-interval queuing breaks the global problem into local ones

3. **Event-driven decouples complex logic**: Refunds, timeouts, reschedules, additions — all unified as events

4. **Four-layer defense absorbs high concurrency**: Gateway rate limiting → local cache → Redis → MySQL, pressure drops at each level

5. **Eventual consistency beats strong consistency**: In distributed systems, eventual consistency is easier to implement and provides better user experience

6. **Idempotent design prevents duplicate operations**: Check before adding during degraded recovery to avoid data corruption
