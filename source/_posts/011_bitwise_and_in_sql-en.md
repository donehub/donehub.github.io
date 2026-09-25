---
title: Using Bitwise AND in SQL for Multi-Select Filtering
date: 2020-07-19 01:50:12
lang: en
label: 011_bitwise_and_in_sql
tags: Bitwise Operations
categories: Database
---

#### 1. Background

I was working on an online account adjustment system this week, and one requirement was tricky: after submitting an adjustment request, the system records the corresponding adjustment types in a database table. On the review page, the filter for adjustment types needed to support multi-select. Here's the enum:

```java
public enum AdjustTypeEnum {
    /**
     * Adjustment type enum; a single request may involve multiple types,
     * stored as comma-separated values in the database.
     */
    FINE(0, "Expected Penalty Interest"),
    TOTAL_REPAYMENT(1, "Expected Total Repayment"),
    FACT_REPAYMENT(2, "Actual Total Repayment"),
    FACT_PAYMENT_DATE(3, "Actual Payment Date"),
    OVERDUE_DAYS(4, "Overdue Days"),
    PAYMENT_STATUS(5, "Repayment Status");
}
```

If request A involves both "Expected Penalty Interest" and "Expected Total Repayment," the stored value would be `0,1`. On the review page, if the filter includes either of those two types, the query should return this request. The problem is that MySQL's `FIND_IN_SET` only supports single-value matching — it can't flexibly decompose the stored comma-separated values against a multi-select filter. This meant rethinking both the storage format and the query logic.

<!-- more -->
#### 2. The Power of Bitwise AND

The abstraction we needed had to do two things at once: store multiple values in a single column (saving space, keeping the schema clean), while still letting the database engine query individual items within that combined value. The data should look combined on the surface, but each piece remains individually addressable underneath.

The comma-separated approach couldn't satisfy this. Binary representation works better. A few bitwise AND examples show why:

```c
// Stored value: 3; Filter condition: 1
// 3 == 2 + 1
// 1 & 3 == 1
0001
&
0011
=
0001    
```

```c
// Stored value: 7; Filter condition: 1
// 7 == 1 + 2 + 4
// 1 & 7 == 1
0111
&
0001
=
0001
```

```c
// Stored value: 7; Filter condition: 3
// 7 == 1 + 2 + 4
// 3 == 1 + 2
// 3 & 7 == 3
0111
&
0011
=
0011
```

```c
// Stored value: 7; Filter condition: 15
// 7 == 1 + 2 + 4
// 15 == 1 + 2 + 4 + 8
// 15 & 7 == 7
0111
&
1111
=
0111
```

The pattern is clear: if each enum value is a power of 2, summing the selected values maps each one to a distinct bit position.

![](http://www.plantuml.com/plantuml/png/TP9TIyCm58Rl-oj2hsTf-j7fjfGL5q6OcwoPC8QCQjArMBkHLhrG_xinSP14xSKBvpbFtuj3fbrVyFxbkN4SMkzvSQn0n_Whu-3T0UBZHVj4QmuGcA_6ZaJjWR9jLnL79YXdZmTE1-2jfdqbPWyEGCNgVTNBuLxxnzysnGDh17SdfPzwdlSnAM4AHGOoGvcHp5Xcaa9Nwxxujnl-wdR5-hGDpEtLzG8Zg0kXAP0boUQx5RxDDZTuGL2Wkv5LbbqIJOrqDVv3_H5tiunWTAxRYMalx_1gjiP2tEG89hevDCrJPKuoiivH6BZ6sKTbSfRACunAVwppMF7Gvf7YaSr3nMER1uedDeUA3stkAmub_tIchANVB_0B)

For any filter condition, a single bitwise AND against the stored sum tells you whether there's a match — the result equals the filter value if matched, or differs if not.

With this approach, the enum becomes:

```java
public enum AdjustTypeEnum {
    /**
     * Adjustment type enum; a single request may involve multiple types,
     * stored as the sum of their values in the database.
     */
    FINE(1, "Expected Penalty Interest"),
    TOTAL_REPAYMENT(2, "Expected Total Repayment"),
    FACT_REPAYMENT(4, "Actual Total Repayment"),
    FACT_PAYMENT_DATE(8, "Actual Payment Date"),
    OVERDUE_DAYS(16, "Overdue Days"),
    PAYMENT_STATUS(32, "Repayment Status");
}
```

And the query becomes:

```sql
SELECT
*
FROM `boss-account`.acct_adjust_account_record
WHERE
adjust_type_sum & #{sum of selected filter values} > 0
```
