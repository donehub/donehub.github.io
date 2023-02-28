---
title: Java 关键字 Switch 的实现原理
date: 2021-09-31 21:57:18
tags: Java
categories: 后端
---

-----

#### 一、Swicth 关键字

`switch` 是 `Java` 中的选择语句，与 `if/else` 不同的是，`switch` 只支持常量表达式，包括 byte、short、int、char、枚举常量和字符串常量(From jdk1.7)。

通常说，引入 `switch` ，一是为了优化代码结构，让代码更简洁；二是为了优化性能，提升效率。为了进一步学习 `switch` 作用机制，本文将从字节码的角度来探索其底层实现。

#### 二、Switch 的典型应用

##### 2.1 对整型-int的支持

```java
public static void switchInt(int flag) {
    switch (flag) {
        case 1:
            System.out.println("这是1");
            break;
        case 8:
            System.out.println("这是8");
            break;
        case 3:
            System.out.println("这是3");
            break;
        default:
            System.out.println("这是未知数");
            break;
    }
}
```

使用 Jclasslib 查看字节码：

```java
 0 iload_0
 1 lookupswitch 3
	1:  36 (+35)
	3:  58 (+57)
	8:  47 (+46)
	default:  69 (+68)
36 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
39 ldc #4 <这是1>
41 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
44 goto 77 (+33)
47 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
50 ldc #6 <这是8>
52 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
55 goto 77 (+22)
58 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
61 ldc #7 <这是3>
63 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
66 goto 77 (+11)
69 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
72 ldc #8 <这是未知数>
74 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
77 return
```

可以看出，`switch` 对整形-int类型的选择，是直接比较 int 值的。

##### 2.2 对整型-byte的支持

```java
public static void switchByte(byte flag) {
    switch (flag) {
        case 1:
            System.out.println("这是1");
            break;
        case 8:
            System.out.println("这是8");
            break;
        case 3:
            System.out.println("这是3");
            break;
        default:
            System.out.println("这是未知数");
            break;
    }
}
```

使用 Jclasslib 查看字节码：

```java
 0 iload_0
 1 lookupswitch 3
	1:  36 (+35)
	3:  58 (+57)
	8:  47 (+46)
	default:  69 (+68)
36 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
39 ldc #4 <这是1>
41 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
44 goto 77 (+33)
47 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
50 ldc #6 <这是8>
52 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
55 goto 77 (+22)
58 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
61 ldc #7 <这是3>
63 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
66 goto 77 (+11)
69 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
72 ldc #8 <这是未知数>
74 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
77 return
```

可以看出，`switch` 对整形-byte类型的选择，是先将其转化为 int 类型，再比较 int 值的。

##### 2.3 对整型-char的支持

```java
public static void switchChar(char flag) {
    switch (flag) {
        case 'a':
            System.out.println("这是a");
            break;
        case 'c':
            System.out.println("这是c");
            break;
        case 'b':
            System.out.println("这是b");
            break;
        default:
            System.out.println("这是未知数");
            break;
    }
}
```

使用 Jclasslib 查看字节码：

```java
 0 iload_0
 1 tableswitch 97 to 99
	97:  28 (+27)
	98:  50 (+49)
	99:  39 (+38)
	default:  61 (+60)
28 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
31 ldc #4 <这是a>
33 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
36 goto 69 (+33)
39 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
42 ldc #6 <这是c>
44 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
47 goto 69 (+22)
50 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
53 ldc #7 <这是b>
55 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
58 goto 69 (+11)
61 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
64 ldc #8 <这是未知数>
66 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
69 return
```

可以看出，`switch` 对整形-char类型的选择，是先将其转化为 int 类型，再比较 int 值的。此外，short 类型的选择也是先转化为 int 类型再做比较的，就不一一展开了。

##### 2.4 对枚举类型的支持

```java
public static void switchEnum(PayStatusEnum flag) {
    switch (flag) {
        case INIT:
            System.out.println("INIT");
            break;
        case PAYING:
            System.out.println("PAYING");
            break;
        case PAID:
            System.out.println("PAID");
            break;
        default:
            System.out.println("非法状态");
            break;
    }
}
```

使用 Jclasslib 查看字节码：

```java
0 getstatic #4 <com/example/springbatchdemo/job/Test$1.$SwitchMap$com$example$springbatchdemo$job$PayStatusEnum : [I>
 3 aload_0
 4 invokevirtual #5 <com/example/springbatchdemo/job/PayStatusEnum.ordinal : ()I>
 7 iaload
 8 tableswitch 1 to 3
	1:  36 (+28)
	2:  47 (+39)
	3:  58 (+50)
	default:  69 (+61)
36 getstatic #6 <java/lang/System.out : Ljava/io/PrintStream;>
39 ldc #7 <INIT>
41 invokevirtual #8 <java/io/PrintStream.println : (Ljava/lang/String;)V>
44 goto 77 (+33)
47 getstatic #6 <java/lang/System.out : Ljava/io/PrintStream;>
50 ldc #9 <PAYING>
52 invokevirtual #8 <java/io/PrintStream.println : (Ljava/lang/String;)V>
55 goto 77 (+22)
58 getstatic #6 <java/lang/System.out : Ljava/io/PrintStream;>
61 ldc #10 <PAID>
63 invokevirtual #8 <java/io/PrintStream.println : (Ljava/lang/String;)V>
66 goto 77 (+11)
69 getstatic #6 <java/lang/System.out : Ljava/io/PrintStream;>
72 ldc #11 <非法状态>
74 invokevirtual #8 <java/io/PrintStream.println : (Ljava/lang/String;)V>
77 return
```

可以看出，`switch` 对枚举类型的选择，是先将枚举项的`ordinal()`的返回值+1，再做比较的。

##### 2.5 对字符串的支持

```java
 public static void switchString(String flag) {
     switch (flag) {
         case "ONE":
             System.out.println("这是ONE");
             break;
         case "TWO":
             System.out.println("这是TWO");
             break;
         case "THREE":
             System.out.println("这是THREE");
             break;
         default:
             System.out.println("未知数");
             break;
     }
 }
```

使用 Jclasslib 查看字节码：

```java
  0 aload_0
  1 astore_1
  2 iconst_m1
  3 istore_2
  4 aload_1
  5 invokevirtual #4 <java/lang/String.hashCode : ()I>
  8 lookupswitch 3
	78406:  44 (+36)
	83500:  58 (+50)
	79801726:  72 (+64)
	default:  83 (+75)
 44 aload_1
 45 ldc #2 <ONE>
 47 invokevirtual #5 <java/lang/String.equals : (Ljava/lang/Object;)Z>
 50 ifeq 83 (+33)
 53 iconst_0
 54 istore_2
 55 goto 83 (+28)
 58 aload_1
 59 ldc #6 <TWO>
 61 invokevirtual #5 <java/lang/String.equals : (Ljava/lang/Object;)Z>
 64 ifeq 83 (+19)
 67 iconst_1
 68 istore_2
 69 goto 83 (+14)
 72 aload_1
 73 ldc #7 <THREE>
 75 invokevirtual #5 <java/lang/String.equals : (Ljava/lang/Object;)Z>
 78 ifeq 83 (+5)
 81 iconst_2
 82 istore_2
 83 iload_2
 84 tableswitch 0 to 2
	0:  112 (+28)
	1:  123 (+39)
	2:  134 (+50)
	default:  145 (+61)
112 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
115 ldc #9 <这是ONE>
117 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
120 goto 153 (+33)
123 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
126 ldc #11 <这是TWO>
128 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
131 goto 153 (+22)
134 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
137 ldc #12 <这是THREE>
139 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
142 goto 153 (+11)
145 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
148 ldc #13 <未知数>
150 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
153 return
```

可以看出，`switch` 对字符串类型的选择，是先比较其 `hashCode`，若出现哈希碰撞，再通过 `String.equals`做校验的。

#### 三、Switch 的特点

##### 3.1 本质上是int值的比较

从以上使用场景和对应的字节码可知，不管 `switch` 筛选何种类型的数据，最终都都是将其转化为int类型，再做值的比较的。

##### 3.2 对筛选值排序

以上案例出现一个很有意思的现象，如 `switch` 筛选1，8，3这个三个值，但字节码中的筛选顺序却是1，3，8，如果筛选值更多更乱，就更能验证这个机制——对筛选值排序。

说到排序查找，很容易想到二分查找。实际上，`switch` 确实引入了二分查找算法（时间复杂度：O(log2n)）。在分支较多的情况下，使用二分查找，可以大大降低查找时间，提升筛选效率。

##### 3.3 lookupswitch 和 tableswitch

从字节码可以看出，`switch` 的作用机制，是先比较int值，再映射到执行地址的。这种类似 `map` 的映射结构，专业名叫跳转表。那么 `switch` 的跳转表为什么会有两种呢？

从以上案例可以发现：

* 筛选值是1，3，8时，使用的是 `lookupswitch`；
* 筛选值是字符串的哈希值时，使用的是 `lookupswitch`；
* 筛选值是a，b，c时，对应的 int 值分别是97，98，99，使用的是 `tableswitch`；
* 筛选值是枚举项的下标+1时，对应的 int 值分别是1，2，3，使用的是 `tableswitch`；

阅相关文档可知：`lookpswitch` 应用于筛选值离散度比较高的场景，`tableswitch` 应用于筛选值离散度比较低的场景。这是由编译器在编辑阶段，根据分支的离散度决定的，本质上都是为了提升查找速度。