---
title: Zero Copy
date: 2022-08-15 19:57:01
tags: Java
categories: 后端
lang: en
label: 041_zero_copy
---

-----

<!-- more -->
#### 1. Zero Copy Technology

Zero copy is a design philosophy that improves on traditional I/O. In traditional I/O, data gets copied back and forth between user space and kernel space, and the kernel space data itself requires multiple copies when reading from or writing to disk through OS-level I/O interfaces. Zero copy aims to minimize context switches and data copies, boosting I/O performance.

#### 2. How Traditional I/O Works

When an application server handles a client request, traditional I/O typically requires two system calls:

```java
// Read
read(file, tmp_buf, len);
// Write
write(socket, tmp_buf, len);
```

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/16_19_22_10_%E4%BC%A0%E7%BB%9F%20IO.png)

The diagram reveals that even a simple read-write pair involves a fairly complex internal process.

**A single read-write cycle triggers 4 context switches:**

* Read data: switch from user mode to kernel mode
* Read complete: kernel finishes data preparation, switch from kernel mode to user mode
* Write data: switch from user mode to kernel mode
* Write complete: kernel finishes data writing, switch from kernel mode to user mode

**A single read-write cycle involves 4 data copies (2 DMA copies + 2 CPU copies):**

* First copy (DMA): disk file data → kernel buffer
* Second copy (CPU): kernel buffer → user buffer, for the application to use
* Third copy (CPU): user buffer → kernel socket buffer
* Fourth copy (DMA): kernel socket buffer → NIC buffer

A single context switch takes only a few microseconds, but under high concurrency these delays accumulate and compound, degrading overall performance. Disk and NIC operations are orders of magnitude slower than memory, and memory operations are orders of magnitude slower than CPU — four copies drag system performance down significantly. Improving I/O performance therefore requires reducing both context switches and data copies.

#### 3. Zero Copy Implementations

Given the analysis above, the design principle is clear: minimize context switches and data copies as much as possible.

The concrete implementations are:

* mmap: maps the virtual addresses of kernel space and user space to the same physical address
* sendfile: copies data directly from kernel buffer to NIC buffer
* direct I/O: establishes a direct channel between the application layer and disk/NIC

##### 3.1 mmap for Zero Copy

Before explaining how mmap() works, a quick introduction to virtual memory. Virtual memory is a memory management mechanism used in modern operating systems that substitutes virtual addresses for physical addresses. Two benefits follow: multiple virtual addresses can point to the same physical address, and the virtual address space can be far larger than physical memory.

In traditional I/O, the read() call copies data from the kernel buffer to the user buffer — expensive in both time and effort. If the virtual addresses of kernel space and user space both map to the same physical address, the CPU no longer needs to shuttle data between them.

mmap() leverages this property of virtual memory. It replaces the traditional read() call by mapping the kernel buffer and user buffer to the same physical memory address, eliminating one CPU copy and improving I/O performance. The process works like this:

* The application calls mmap(); DMA copies disk file data into the kernel buffer
* The application and the kernel share this buffer
* The application then calls write(), which copies data directly from the kernel buffer to the kernel socket buffer
* DMA copies the kernel socket buffer data to the NIC buffer

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/16_19_24_29_mmap%20%20%20writer.png)

Compared to traditional I/O, mmap() + write only eliminates 1 CPU copy. There are still 4 context switches and 3 data copies.

##### 3.2 sendfile() for Zero Copy

sendfile() is a Linux system call designed specifically for sending files. It replaces the traditional read() and write() pair, saving 2 context switches. The data copy path also gets optimized — the specific optimization depends on the Linux kernel version, because after version 2.4, Linux introduced SG-DMA technology, which provides further optimization beyond standard DMA.

Before version 2.4, the CPU could copy data directly from the kernel buffer to the kernel socket buffer, skipping the user buffer entirely. This still involves 2 context switches and 3 data copies.

Execution steps:

* DMA copies disk file data to the kernel buffer
* CPU copies kernel buffer data to the kernel socket buffer
* DMA copies kernel socket buffer data to the NIC buffer

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/16_19_25_16_sendfile_dma.png)

After version 2.4, SG-DMA was introduced. If the NIC supports this technology, data can be copied directly from the kernel buffer to the NIC buffer, reducing the process to 2 context switches and 2 data copies.

Execution steps:

* DMA copies disk file data to the kernel buffer
* The kernel buffer descriptor and data length are passed to the kernel socket buffer
* SG-DMA copies data directly from the kernel buffer to the NIC buffer

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/16_19_25_39_sendfile_sg_dma.png)

##### 3.3 Direct I/O

Direct I/O establishes a direct channel between the user buffer and disk/NIC. When reading or writing data, it bypasses the kernel entirely, reducing context switches and data copies for better efficiency.

Execution steps:

* DMA copies disk file data directly to the user buffer
* DMA copies user buffer data directly to the NIC buffer

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/16_19_26_8_direct_io.png)

Direct I/O uses a direct channel to operate on data, with the application layer managing data entirely. This design has clear trade-offs.

Advantages:

* The direct channel between the application layer and disk/NIC reduces context switches and data copies, resulting in faster throughput
* Data is cached directly at the application layer, giving applications more flexibility in how they manipulate it

Disadvantages:

* Introducing direct I/O at the application layer requires the application to manage it, adding extra complexity to the system
* If data isn't already in the application buffer, it goes straight to disk, which can severely degrade performance
