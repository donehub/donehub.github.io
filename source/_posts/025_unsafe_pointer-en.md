---
title: unsafe.Pointer — Pointer Conversion and Arithmetic in Go
date: 2021-08-13 14:57:01
tags: Golang
categories: Backend
lang: en
label: 025_unsafe_pointer
---

-----

<!-- more -->
#### 1. Definition and Background of `unsafe.Pointer`

```go
// ArbitraryType is here for the purposes of documentation only and is not actually
// part of the unsafe package. It represents the type of an arbitrary Go expression.
type ArbitraryType int

type Pointer *ArbitraryType
```

At its core, `unsafe.Pointer` is an `int`-typed pointer that serves as a bridge for converting between different pointer types. Go has a strict type system that intentionally limits pointer operations — you can only operate on the object a pointer refers to, not perform `C`-style pointer casting or arithmetic. But real-world development sometimes requires breaking out of these constraints to read and write memory directly. As a universal pointer type, `unsafe.Pointer` opens a back door for low-level pointer operations.

#### 2. Properties of `unsafe.Pointer`

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_44_21_unsafe_convert2.png)

* Any pointer type can be converted to `unsafe.Pointer`;

* `unsafe.Pointer` can be converted to any pointer type;

* `uintptr` can be converted to `unsafe.Pointer`;

* `unsafe.Pointer` can be converted to `uintptr`;

  `unsafe.Pointer` is a universal pointer type, but it only handles type conversion between pointers — it can't do `C`-style pointer arithmetic. That's where `uintptr` comes in. Here's the official definition:

  ```go
  // uintptr is an integer type that is large enough to hold the bit pattern of
  // any pointer.
  type uintptr uintptr
  ```

  `uintptr` is an unsigned integer large enough to hold any pointer's address. It acts as an intermediary, enabling pointer arithmetic and conversions between numeric types and pointer types.

#### 3. Using `unsafe.Pointer`

##### 3.1 Converting Between Pointer Types

As a universal pointer type, `unsafe.Pointer`'s most basic job is bridging conversions between different pointer types. Converting from `*X` to `*Y` requires that `Y` is no larger than `X` and that both share the same memory layout.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_47_43_x-y_pointer.png)

Take `byte` and `string` conversion as an example. Go's type system won't let you cast a `byte` pointer directly to a `string` pointer — the compiler rejects it. We need `unsafe.Pointer` as an intermediary.

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

Output:
[97 98 99]
abc
[97 98 99]
```

##### 3.2 Converting Between Numeric Values and Pointers

In `C`, it's common to use plain integers to represent pointers. To convert between integers and pointers, `unsafe.Pointer` alone isn't enough — we need the middleman `uintptr`. The pattern is: convert the integer to `uintptr` first, then to `unsafe.Pointer`, and finally to the target pointer type. Or in reverse: convert any pointer to `unsafe.Pointer`, then to `uintptr`, then to the target integer type. Integer-to-pointer conversion is also one of the key techniques in `CGO` programming.

Here's an example converting between `int64` and `*C.char`:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_48_14_num_to_pointer_convert.png)

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

Output:
12
```

##### 3.3 Pointer Arithmetic

Go pointers don't support arithmetic operations either. But with `uintptr`, you can move pointers around and perform arithmetic.

Here's an example that prints each byte of a byte slice one at a time:

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

Output:
1
2
3
4
```

#### 4. Summary

`unsafe.Pointer` exists to bypass Go's type system and read/write memory directly for performance. As the name suggests, this is unsafe territory. `uintptr` lacks pointer semantics, so the object it points to risks being collected by the `GC`. Go strongly discourages these operations — use them only when you have no other choice.
