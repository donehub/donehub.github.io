---
title: unsafe.Pointer-指针转换与运算
date: 2021-08-13 14:57:01
tags: Golang
categories: 后端
---

-----

#### 一、`unsafe.Pointer` 定义及使用背景

```go
// ArbitraryType is here for the purposes of documentation only and is not actually
// part of the unsafe package. It represents the type of an arbitrary Go expression.
type ArbitraryType int

type Pointer *ArbitraryType
```

本质上，`unsafe.Pointer`  是 `int` 类型的指针，用于各种类型指针转换的桥接。`Go` 语言有着严格的类型系统，弱化了指针的操作，所允许的操作仅仅操作其指向的对象，不能进行类似 `C` 语言的指针转换和运算。但在日常开发中，可能就需要打破这种强制限制，对内存执行任意的读写。因此，作为通用的指针类型，`unsafe.Pointer` 开启了一扇指针操作的“后门”。

#### 二、`unsafe.Pointer` 特性

![](https://gitee.com/donehub/imgbed/raw/master/unsafe_convert2.png)

* 任意类型的指针都可以转换为 `unsafe.Pointer`；

* `unsafe.Pointer` 可以转换为任意类型的指针；

* `uintptr` 可以转换为 `unsafe.Pointer`；

* `unsafe.Pointer` 可以转换为 `uintptr`；

  前面说到，`unsafe.Pointer` 是通用的指针类型，只能转换不同类型的指针，无法实现类似 `C` 语言的指针运算。因此 `Go` 引入内置类型 `uintptr`，以弥补类型系统带来的短板。`uintptr` 的官方定义：

  ```go
  // uintptr is an integer type that is large enough to hold the bit pattern of
  // any pointer.
  type uintptr uintptr
  ```

  本质上，`uintptr` 是一个足够大的无符号整型，可以表示任意指针的地址。相当于一个中介，可以完成指针运算或者数值类型到指针类型的转换。

#### 三、`unsafe.Pointer` 应用

##### 3.1 指针与指针之间的转换

作为通用的指针类型，`unsafe.Pointer` 最基本的功能就是转换不同类型的指针。从  `*X` 转到 `*Y` 要求 `Y` 不大于 `X` 且两者具有相同的内存布局。

![](https://gitee.com/donehub/imgbed/raw/master/3bae7ae30938f90422720c9ac68ba9b.png)

例如 `byte` 与 `string` 互转。由于 `Go` 的类型系统限制，`byte` 指针是不可以直接转为 `string` 指针的，在编译阶段就会报错。我们需要借助 `unsafe.Pointer` 作为中间桥接类型来完成这个转换。

```go
package main

import (
    "fmt"
    "unsafe"
)

func main() {
    b := []byte{'a', 'b', 'c'}
    fmt.Println(b)
    
    // []byte -> string
    s := *(*string)(unsafe.Pointer(&b))
    fmt.Println(s)
    
    // string -> []byte
    bb := *(*[]byte)(unsafe.Pointer(&s))
    fmt.Println(bb)
}

输出：
[97 98 99]
abc
[97 98 99]
```

##### 3.2 数值与指针之间的转换

在 `C` 语言中，经常使用普通数值来表示指针，这也就意味着要完成数值与指针之间的互转。 `unsafe.Pointer` 是通用指针，已无能为力。因此中间人 `uintptr` 就派上用场了。我们借助 `uintptr` 先将数值转换为 `unsafe.Pointer`，然后再转换为任意类型的指针；或者将任意类型的指针，先转换为 `unsafe.Pointer`，再转换为 `uintptr`。实际上，数值与指针的互转也是 `CGO` 编程的要点之一。

例如 `int64` 与 `*C.char` 互转：

![](https://gitee.com/donehub/imgbed/raw/master/num_to_pointer_convert.png)

```go
package main

import "C"
import (
    "fmt"
    "unsafe"
)

func main() {
    var num = int64(12)
    
    // int64 -> C.char
    p := (*C.char)(unsafe.Pointer(uintptr(num)))
    
    // C.char -> int64
    num2 := int64(uintptr(unsafe.Pointer(p)))
    
    fmt.Println(num2)
}

输出：
12
```

##### 3.3 指针运算

`Go` 指针不仅不支持不同类型的转换，也不支持指针的运算。借助 `uintptr` 可以实现指针的移动和运算。

例如依次打印一个字节组信息：

```go
package main

import (
    "fmt"
    "unsafe"
)

func main() {
    data := []byte("1234")
    for i := 0; i < len(data); i++ {
        ptr := unsafe.Pointer(uintptr(unsafe.Pointer(&data[0])) + uintptr(i)*unsafe.Sizeof(data[0]))
        fmt.Printf("%c\n", *(*byte)(ptr))
    }
}

输出：
1
2
3
4
```

#### 四、总结

`unsafe.Pointer` 的意义在于绕过 `Go` 的类型系统，直接读写内存，高效操作。正如字面理解那样，这是一种不安全的行为，如 `uintptr` 并没有指针的语义，所指向的对象存在被 `GC` 回收的风险。`Go` 是十分不鼓励这样操作的。