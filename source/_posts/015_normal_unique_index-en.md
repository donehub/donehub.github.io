---
title: InnoDB - Regular Index vs Unique Index
date: 2020-11-13 14:57:01
lang: en
label: 015_normal_unique_index
tags: MySQL
categories: Database
---

-----

<!-- more -->
#### 1. InnoDB Indexing

Indexes are a core part of database performance — they speed up data retrieval and take load off the storage engine. InnoDB supports both hash indexes and B+Tree indexes, with B+Tree as the default. Regular indexes and unique indexes are the two most common types, and this post covers how they actually differ.

#### 2. What Regular and Unique Indexes Do

A regular index exists on leaf nodes in a sorted structure. Its sole purpose is to accelerate random lookups and range scans.

A unique index does everything a regular index does, but additionally enforces a uniqueness constraint on the indexed column.

#### 3. Where They Differ

##### The change buffer

To understand the difference, you first need to understand the change buffer — it's the mechanism that separates regular indexes from unique indexes most significantly. Start with how MySQL manages data.

To minimize disk reads, MySQL splits data between disk and memory. The disk holds the original data; memory (the buffer pool) holds cached data pages and index pages. The buffer pool is essentially a read optimization. But MySQL didn't stop there — disk writes are also expensive, so the change buffer was introduced as a write optimization.

When a data page needs to be updated and it's already in the buffer pool, the update happens in place. If the page isn't cached, InnoDB doesn't fetch it from disk — instead, it buffers the update in the change buffer. The actual page update (called a merge) happens later, triggered by events like:

* The page is accessed again
* A background thread runs a periodic merge
* The change buffer runs out of capacity
* The database shuts down cleanly
* The redo log fills up (fixed-size, circular write)

Although the change buffer looks like a temporary cache, it's actually persisted to disk as well as held in memory. This is the right design — if something goes wrong, the on-disk change buffer can replay the buffered operations and preserve data correctness.

----

##### 3.1 Query Performance Difference

Assume `id` is the clustered index and `k` is a secondary index. This is a textbook covering index scenario.

```sql
select id from T where k = 10;
```

With a regular index on `k`, the lookup uses binary search to find the first matching entry, then follows the leaf node chain to check the next entry — if it doesn't match, the scan stops and returns results.

With a unique index on `k`, the lookup uses binary search to find the matching entry and returns immediately — uniqueness guarantees there's exactly one match.

The difference is that a regular index requires one extra step — checking the next leaf node. If that node is on the same data page, it's a cheap pointer traversal. If it's on a different page, it triggers a disk I/O read. Regular index queries are slightly slower as a result.

##### 3.2 Update Performance Difference

From the change buffer discussion, when a data page isn't in memory, a regular index update gets buffered in the change buffer and merged later — reducing I/O operations. A unique index, by contrast, must read the data page into memory to verify uniqueness before applying the update, then write it back to disk. In other words, regular index updates are faster than unique index updates.
