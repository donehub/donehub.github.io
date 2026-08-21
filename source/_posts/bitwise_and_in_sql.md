---
title: 位与运算在SQL中的使用
date: 2020-07-19 01:50:12
tags: 位运算
categories: 数据库
---

#### 一、需求背景

本周负责做调账线上化，其中一个业务需求比较棘手：提交调账申请后，需在数据表记录对应的调账类型；而在调账复核页面，列表筛选项-调账类型，需支持多选。简单枚举如下:

```java
public enum AdjustTypeEnum {
    /**
     * 调账类型枚举; 一次调账申请可能对应多种调账类型，在数据表中枚举值之间以英文 , 分隔
     */
    FINE(0, "应还罚息"),
    TOTAL_REPAYMENT(1, "应还总额"),
    FACT_REPAYMENT(2, "实还总额"),
    FACT_PAYMENT_DATE(3, "实还日期"),
    OVERDUE_DAYS(4, "逾期天数"),
    PAYMENT_STATUS(5, "还款状态");
}
```

假如调账申请A的调账类型包括应还罚息和应还总额，则数据表相应字段值为`0,1`。在复核页面，若调账类型复选项中包含应还罚息或应还总额，则需查询到该申请。此时，我们发现`SQL`内置函数`FIND_IN_SET`只支持单选项查询，而无法灵活拆分筛选条件和存储数据。因此，有必要调整一下数据的存储规则和查询规则。

<!-- more -->
#### 二、位与运算的妙用

首先，我们需要进一步抽象：一方面，为了不浪费存储空间，科学地设计数据表，我们需要将目标数据列表整合存储在一个字段中；另一方面，数据库引擎需要灵活使用整合后的字段，以执行相应的查询语句。说白了，就是看起来像做了整合，实际上还是原始的目标数据列表。

事实证明，上面提出的方案根本满足不了业务需求，是一个非常差的设计。除了以逗号分隔枚举值的存储方式，还有一种更为科学的存储方式——二进制。简单做几个位与运算：

```c
// 存储值: 3; 查询条件: 1
// 3 == 2 + 1
// 1 & 3 == 1
0001
&
0011
=
0001    
```

```c
// 存储值: 7; 查询条件: 1
// 7 == 1 + 2 + 4
// 1 & 7 == 1
0111
&
0001
=
0001
```

```c
// 存储值: 7; 查询条件: 3
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
// 存储值: 7; 查询条件: 15
// 7 == 1 + 2 + 4
// 15 == 1 + 2 + 4 + 8
// 15 & 7 == 7
0111
&
1111
=
0111
```

从以上位与运算实例，可以发现一个有趣的现象：若将枚举值设置为`2`的`n`次幂，则只需将目标数据列表加合，即可保证每一个目标数据对应到二进制中的一位。

![](http://www.plantuml.com/plantuml/png/TP9TIyCm58Rl-oj2hsTf-j7fjfGL5q6OcwoPC8QCQjArMBkHLhrG_xinSP14xSKBvpbFtuj3fbrVyFxbkN4SMkzvSQn0n_Whu-3T0UBZHVj4QmuGcA_6ZaJjWR9jLnL79YXdZmTE1-2jfdqbPWyEGCNgVTNBuLxxnzysnGDh17SdfPzwdlSnAM4AHGOoGvcHp5Xcaa9Nwxxujnl-wdR5-hGDpEtLzG8Zg0kXAP0boUQx5RxDDZTuGL2Wkv5LbbqIJOrqDVv3_H5tiunWTAxRYMalx_1gjiP2tEG89hevDCrJPKuoiivH6BZ6sKTbSfRACunAVwppMF7Gvf7YaSr3nMER1uedDeUA3stkAmub_tIchANVB_0B)

此时，对于任何一个查询条件，只需要将其与整合值进行位与运算，即可得到匹配的值。

由此，我们调整枚举为：

```java
public enum AdjustTypeEnum {
    /**
     * 调账类型枚举; 一次调账申请可能对应多种调账类型，在数据表中存储各值之和
     */
    FINE(1, "应还罚息"),
    TOTAL_REPAYMENT(2, "应还总额"),
    FACT_REPAYMENT(4, "实还总额"),
    FACT_PAYMENT_DATE(8, "实还日期"),
    OVERDUE_DAYS(16, "逾期天数"),
    PAYMENT_STATUS(32, "还款状态");
}
```

调整`SQL`为：

```sql
SELECT
*
FROM `boss-account`.acct_adjust_account_record
WHERE
adjust_type_sum & #{调账类型筛选条件值之和} > 0
```







