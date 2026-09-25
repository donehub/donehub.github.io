---
title: How Java's Switch Keyword Works Under the Hood
date: 2021-09-30 21:57:18
tags: Java
categories: Backend
lang: en
label: 026_java_switch
---

-----

<!-- more -->
#### 1. The Switch Keyword

`switch` is a selection statement in `Java`. Unlike `if/else`, `switch` only works with constant expressions — byte, short, int, char, enum constants, and String constants (from JDK 1.7 onward).

The conventional wisdom is that `switch` exists for two reasons: cleaner code structure and better performance. To understand how `switch` actually achieves this, let's examine its underlying implementation from the bytecode perspective.

#### 2. Typical Use Cases

##### 2.1 Switching on int

```java
public static void switchInt(int flag) {
    switch (flag) {
        case 1:
            System.out.println("This is 1");
            break;
        case 8:
            System.out.println("This is 8");
            break;
        case 3:
            System.out.println("This is 3");
            break;
        default:
            System.out.println("Unknown value");
            break;
    }
}
```

Bytecode inspected with Jclasslib:

```java
 0 iload_0
 1 lookupswitch 3
	1:  36 (+35)
	3:  58 (+57)
	8:  47 (+46)
	default:  69 (+68)
36 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
39 ldc #4 <This is 1>
41 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
44 goto 77 (+33)
47 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
50 ldc #6 <This is 8>
52 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
55 goto 77 (+22)
58 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
61 ldc #7 <This is 3>
63 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
66 goto 77 (+11)
69 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
72 ldc #8 <Unknown value>
74 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
77 return
```

For int values, `switch` directly compares the integer — no conversion needed.

##### 2.2 Switching on byte

```java
public static void switchByte(byte flag) {
    switch (flag) {
        case 1:
            System.out.println("This is 1");
            break;
        case 8:
            System.out.println("This is 8");
            break;
        case 3:
            System.out.println("This is 3");
            break;
        default:
            System.out.println("Unknown value");
            break;
    }
}
```

Bytecode inspected with Jclasslib:

```java
 0 iload_0
 1 lookupswitch 3
	1:  36 (+35)
	3:  58 (+57)
	8:  47 (+46)
	default:  69 (+68)
36 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
39 ldc #4 <This is 1>
41 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
44 goto 77 (+33)
47 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
50 ldc #6 <This is 8>
52 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
55 goto 77 (+22)
58 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
61 ldc #7 <This is 3>
63 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
66 goto 77 (+11)
69 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
72 ldc #8 <Unknown value>
74 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
77 return
```

For byte values, the bytecode first promotes byte to int, then performs the comparison on int values.

##### 2.3 Switching on char

```java
public static void switchChar(char flag) {
    switch (flag) {
        case 'a':
            System.out.println("This is a");
            break;
        case 'c':
            System.out.println("This is c");
            break;
        case 'b':
            System.out.println("This is b");
            break;
        default:
            System.out.println("Unknown value");
            break;
    }
}
```

Bytecode inspected with Jclasslib:

```java
 0 iload_0
 1 tableswitch 97 to 99
	97:  28 (+27)
	98:  50 (+49)
	99:  39 (+38)
	default:  61 (+60)
28 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
31 ldc #4 <This is a>
33 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
36 goto 69 (+33)
39 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
42 ldc #6 <This is c>
44 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
47 goto 69 (+22)
50 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
53 ldc #7 <This is b>
55 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
58 goto 69 (+11)
61 getstatic #3 <java/lang/System.out : Ljava/io/PrintStream;>
64 ldc #8 <Unknown value>
66 invokevirtual #5 <java/io/PrintStream.println : (Ljava/lang/String;)V>
69 return
```

Same pattern as byte — char values are promoted to int before comparison. The short type follows the same promotion path, so I won't repeat the bytecode here.

##### 2.4 Switching on enums

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
            System.out.println("Invalid state");
            break;
    }
}
```

Bytecode inspected with Jclasslib:

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
72 ldc #11 <Invalid state>
74 invokevirtual #8 <java/io/PrintStream.println : (Ljava/lang/String;)V>
77 return
```

For enums, the compiler calls `ordinal()` on the enum constant, adds 1 to the result, and then switches on that int value. The compiler also generates a synthetic `$SwitchMap` array to map ordinals to switch indices.

##### 2.5 Switching on strings

```java
 public static void switchString(String flag) {
     switch (flag) {
         case "ONE":
             System.out.println("This is ONE");
             break;
         case "TWO":
             System.out.println("This is TWO");
             break;
         case "THREE":
             System.out.println("This is THREE");
             break;
         default:
             System.out.println("Unknown value");
             break;
     }
 }
```

Bytecode inspected with Jclasslib:

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
115 ldc #9 <This is ONE>
117 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
120 goto 153 (+33)
123 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
126 ldc #11 <This is TWO>
128 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
131 goto 153 (+22)
134 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
137 ldc #12 <This is THREE>
139 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
142 goto 153 (+11)
145 getstatic #8 <java/lang/System.out : Ljava/io/PrintStream;>
148 ldc #13 <Unknown value>
150 invokevirtual #10 <java/io/PrintStream.println : (Ljava/lang/String;)V>
153 return
```

String switching uses a two-phase approach. First, it computes the `hashCode` of the string and uses `lookupswitch` to find a candidate match. When hash collisions occur (multiple strings mapping to the same hash), it falls back to `String.equals` for disambiguation. After identifying the matching case, it performs a second `tableswitch` on an assigned index to jump to the correct branch.

#### 3. Key Characteristics

##### 3.1 Everything boils down to int comparison

Across all the cases above, regardless of the source type, `switch` ultimately converts the value to int and performs integer comparison. This is the fundamental mechanism.

##### 3.2 Why long is not supported

Since `switch` operates on int values internally, it doesn't support long. The language designers didn't extend the range to long for good reason.

The practical answer is that most selection logic involves small, finite sets of values — int covers those cases easily. A larger value range would also complicate the jump table implementation, increasing both memory footprint and lookup cost. The decision to cap at int represents a pragmatic trade-off between expressiveness and implementation complexity.

##### 3.3 The compiler sorts the case values

One interesting pattern in the bytecode: when the case values are 1, 8, 3, the jump table lists them in sorted order — 1, 3, 8. With more case values, this ordering becomes even more apparent. The compiler sorts the branch targets to enable binary search (O(log₂n)), which significantly reduces lookup time when there are many branches.

##### 3.4 lookupswitch vs tableswitch

The bytecode reveals two different jump instructions:

* When case values are 1, 3, 8 (sparse), the compiler emits `lookupswitch`;
* When case values are string hashes (sparse), the compiler emits `lookupswitch`;
* When case values are 'a', 'b', 'c' mapping to 97, 98, 99 (dense), the compiler emits `tableswitch`;
* When case values are enum ordinal+1 mapping to 1, 2, 3 (dense), the compiler emits `tableswitch`;

The pattern is clear: `lookupswitch` is used when case values are spread apart (high dispersion), while `tableswitch` is used when case values are contiguous or nearly contiguous (low dispersion). The compiler decides which instruction to emit at compile time based on the density of the case values. Both strategies aim to minimize lookup time — `tableswitch` uses direct indexing (O(1)), while `lookupswitch` uses binary search (O(log₂n)).



>Reference: [stackoverflow: Why can't your switch statement data type be long?](https://stackoverflow.com/questions/2676210/why-cant-your-switch-statement-data-type-be-long-java?r=SearchResults)