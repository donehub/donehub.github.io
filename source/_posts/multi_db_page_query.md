---
title: 分库分表-跨库分页查询
date: 2022-11-11 22:57:01
tags: MySQL
categories: 数据库
---

-----

#### 一、跨库分页查询

对于一定数量级的表，如订单表，通常采用分库分表的方式保存数据。根据指定字段，如果用户ID，散列数据到不同的库中。那么，如果需要按照下单时间分页查询订单信息，就涉及到跨库查询。

假设有45笔订单，存于三个库中，散列算法是 OrderID % 3，则数据分布为：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_32_38_origin.png)

如果以每页五个订单，查询第二页的所有订单，则单库查询 sql 为：

```sql
select * from order_info order by id limit 5 offset 5;
```

但跨库查询就行不通了。下面，主要有三种方案可以用于跨库分页查询：

* 全局查询法
* 禁止跳页查询法
* 二次查询法

#### 二、全局查询法

全局查询法，需要在每个分库中执行查询语句，然后再程序中排序，再定位切割到指定的数据段。

如果需要查询第二页订单，需要查询每个库的前二页数据：

```sql
select * from order_info_1 order by id limit 10;
select * from order_info_2 order by id limit 10;
select * from order_info_3 order by id limit 10;
```

结果为：![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_33_7_quanjuchaxunfa.png)

将以上三个库的查询结果排序：

1，2，3，4，5，6，7，8，9，10，11，12，13，14，15，16，17，18，19，20，21，22，23，24，25，26，27，28，29，30

那么第二页的订单列表为：

6，7，8，9，10

**小结：**对于低页码查询，全局查询法是可以应付的，但是，当页码越来越大，查出来的数据也就越来越多，需要排序的数据也越来越多，查询效率也就会越来越慢。

#### 三、禁止跳页查询法

全局查询法的一个显著缺陷，就是随着页码越来越大，查询的数据量也越来越大。那么，如果禁止跳页查询，且每次查询都以上次查询的最大ID为基点，就可以保证每次查询的数据量都是相同的。

**查询第一页数据：**![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_40_36_firstpage.png)

将以上三个库的查询结果排序：

1，2，3，4，5，6，7，8，9，10，11，12，13，14，15

那么第一页的订单列表为：

1，2，3，4，5

**查询第二页数据：**

第一页的订单ID最大值为5，因此第二页的订单ID起始值应大于5，查询得到：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_21_44_37_secondpage.png)

将以上三个库的查询结果排序：

6，7，8，9，10，11，12，13，14，15，16，17，18，19，20

那么第二页的订单列表为：

6，7，8，9，10

**小结：**禁止跳页查询法，保证每次查询的数据量是相同的，避免了分页查询带来的性能衰减问题；但禁止跳页也是功能缺陷，没法一步定位到指定数据段。

#### 四、二次查询法

二次查找法，既满足跳页查询，也能避免分页查询性能衰减。为了解释这一思想，我们以查询第三页订单数据为例。单库查询语句：

```sql
select * from order_info order by id limit 5 offset 10;
```

之所以叫二次查询法，当然需要查询两次。这两次查询有什么不同，希望通过以下四个步骤说清楚：

**第一步：语句改写**

将 `select * from order_info order by id limit 5 offset 10` 改写成 `select * from order_info order by id limit 5 offset 3`。偏移量10变成3，是基于10/3计算得出的。将语句在三个库分别执行，得到数据：![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_22_14_21_first_rewrite_1.png)

**第二步：找最小值**

* 第一个库：最小数据为8
* 第二个库：最小数据为11
* 第三个库：最小数据为12

因此，从三个库中拿到的最小数据为8。

**第三步：第二次语句改写**

这次需要把 `select * from order_info order by id limit 5 offset 3` 改写成一个between语句，起点是最小的OrderID，终点是原来每个分库各自返回数据的最大值：

* 第一个分库改写为: select * from order_info order by id where id between id_min and 22
* 第二个分库改写为: select * from order_info order by id where id between id_min and 23
* 第三个分库改写为: select * from order_info order by id where id between id_min and 24

查询结果如下：![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/04/11_22_20_40_sencond_rewrite.png)

**第四步：找到id_min的全局偏移量**

第一次查询的偏移量为3，那么每一个库的第一个目标数据的偏移量应该都是4。因此可知每个库的id_min的偏移量：

* 第一个库：8就是id_min，偏移量为4；
* 第二个库：11的偏移量为4，那么id_min的偏移量就是1；
* 第三个库：12的偏移量为4，那么id_min的偏移量就是3；

因此id_min的全局偏移量为：4 + 1 + 3 = 8。

**第五步：定位目标数据**

* 第一个库：8，13，14，19，22
* 第二个库：9，10，11，16，17，18，23
* 第三个库：12，15，20，21，24

经过排序，得到：

8，9，10，11，12，13，14，15，16，17，18，19，20，21，22，23，24

因为id_min的全局偏移量为8，最终结果需要 limit 5 offset 10，因此需要向后推移10 - 8 = 2 位，然后再取5位，得到：

11，12，13，14，15

**小结：**二次查找法，既避免了数据越处理越多，也支持跳转查询。但其也存在短板，需要查询两次，才能拿到目标数据。