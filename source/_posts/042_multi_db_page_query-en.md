---
title: Sharding — Cross-Database Paginated Queries
date: 2022-11-11 22:57:01
tags: MySQL
categories: 数据库
lang: en
label: 042_multi_db_page_query
---

-----

<!-- more -->
#### 1. Cross-Database Paginated Queries

For tables at a certain scale — order tables being the classic example — sharding across multiple databases is the standard approach. Data gets distributed to different databases based on a specified field like user ID. When you need to paginate through orders by creation time, you're dealing with a cross-database query.

Suppose there are 45 orders spread across three databases, with the sharding algorithm being OrderID % 3. The data distribution looks like this:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_32_38_origin.png)

To fetch the second page with 5 orders per page, the single-database SQL would be:

```sql
select * from order_info order by id limit 5 offset 5;
```

But this doesn't work across databases. Below are three approaches for cross-database paginated queries:

* Global query method
* No-skip pagination method
* Two-pass query method

#### 2. Global Query Method

The global query method runs the query on every shard, then sorts and slices the combined results in the application layer.

To fetch the second page, you need the first two pages from each database:

```sql
select * from order_info_1 order by id limit 10;
select * from order_info_2 order by id limit 10;
select * from order_info_3 order by id limit 10;
```

Results: ![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_33_7_quanjuchaxunfa.png)

Sort the combined results from all three databases:

1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30

The second page is:

6, 7, 8, 9, 10

**Summary:** The global query method works fine for low page numbers. But as the page number grows, so does the amount of data fetched, sorted, and processed — performance degrades accordingly.

#### 3. No-Skip Pagination Method

The global query method's main flaw is that data volume grows with the page number. If you forbid page-skipping and always use the maximum ID from the previous query as the starting point, every query fetches the same amount of data.

**Querying the first page:** ![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_40_36_firstpage.png)

Sort the combined results from all three databases:

1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15

The first page is:

1, 2, 3, 4, 5

**Querying the second page:**

The maximum order ID on the first page is 5, so the second page starts with IDs greater than 5:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_44_37_secondpage.png)

Sort the combined results:

6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20

The second page is:

6, 7, 8, 9, 10

**Summary:** The no-skip pagination method ensures consistent data volume per query, eliminating the performance degradation that comes with deeper pages. The trade-off is that users can't jump to an arbitrary page — it's a functional limitation.

#### 4. Two-Pass Query Method

The two-pass query method supports page-skipping while avoiding performance degradation. To illustrate, we'll use fetching the third page as an example. The single-database query would be:

```sql
select * from order_info order by id limit 5 offset 10;
```

It's called "two-pass" because it requires two queries. Here's how they differ, step by step:

**Step 1: Rewrite the query**

Rewrite `select * from order_info order by id limit 5 offset 10` as `select * from order_info order by id limit 5 offset 3`. The offset changes from 10 to 3, computed as 10 / 3 (number of shards). Execute this on all three databases: ![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_22_14_21_first_rewrite_1.png)

**Step 2: Find the minimum value**

* Database 1: minimum data is 8
* Database 2: minimum data is 11
* Database 3: minimum data is 12

The global minimum across all three databases is 8.

**Step 3: Second query rewrite**

Now rewrite `select * from order_info order by id limit 5 offset 3` into a between statement. The starting point is the minimum OrderID, and the endpoint is the maximum value returned by each shard:

* Shard 1: select * from order_info order by id where id between id_min and 22
* Shard 2: select * from order_info order by id where id between id_min and 23
* Shard 3: select * from order_info order by id where id between id_min and 24

Query results: ![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_22_20_40_sencond_rewrite.png)

**Step 4: Find the global offset of id_min**

The first query had an offset of 3, so each database's first target data point has an offset of 4. From this, we can determine the offset of id_min in each database:

* Database 1: 8 is id_min, offset is 4
* Database 2: 11 has offset 4, so id_min's offset is 1
* Database 3: 12 has offset 4, so id_min's offset is 3

The global offset of id_min is: 4 + 1 + 3 = 8.

**Step 5: Locate the target data**

* Database 1: 8, 13, 14, 19, 22
* Database 2: 9, 10, 11, 16, 17, 18, 23
* Database 3: 12, 15, 20, 21, 24

After sorting:

8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24

Since the global offset of id_min is 8, and the final result needs limit 5 offset 10, we shift forward by 10 - 8 = 2 positions, then take 5 values:

11, 12, 13, 14, 15

**Summary:** The two-pass method avoids growing data volumes while still supporting page jumps. Its drawback is needing two queries to reach the target data.
