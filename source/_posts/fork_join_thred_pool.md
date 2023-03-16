---
title: JUC线程池-ForkJoinPool
date: 2021-02-20 10:57:01
tags: Java
categories: 后端
---

-----

#### 一、ForkJoinPool 介绍

ForkJoinPool 是 jdk 1.7 引入的一个线程池，其底层设计基于分治算法(Divide-and-Conquer)的并行实现，是一款可以获得良好并行性能的简单且高效的设计技术。通过任务分治，可以更好地利用多处理器，并行处理任务，提升计算效能。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/13_20_27_1_fork_join.png)

Fork/Join 框架主要包含三个模块：

* 线程池：ForkJoinPool
* 执行 Fork/Join 任务的线程：ForkJoinWorkerThread
* 任务对象：ForkJoinTask，继承者有 RecursiveTask、RecursiveAction、CountedCompleter

ForkJoinPool 通过 ForkJoinWorkerThread 来处理提交的 ForkJoinTask。通常不会直接创建 ForkJoinTask，而是借助其继承类，根据实际需要创建对应的分治任务。RecursiveTask 是一个可以递归执行的 ForkJoinTask；RecursiveAction 是一个没有返回值的 RecursiveTask；CountedCompleter 在完成任务执行后，回自动触发执行一个自定义的钩子函数。

#### 二、工作窃取（Work-Stealing）算法

工作窃取 (work-stealing) 算法，是 Fork/Join 的设计原理，指线程池内的所有工作线程都尝试找到并执行已经提交的任务，或者是被其他活动任务创建的子任务。因此，在运行多个可以产生子任务的任务，或提交的许多小任务，ForkJoinPool 的效率非常高。

在 ForkJoinPool 中，每个工作线程 (ForkJoinWorkerThread) 都对应一个任务队列 (WorkQueue)，工作线程优先处理自身队列的任务，然后以 FIFO 的顺序随机窃取其他队列中的任务。处理自身队列的任务的方式有两种：先进先出 (FIFO)、先进后出 (LIFO)。这由 ForkJoinPool 的构造参数 asyncMode 决定，默认先进先出 (FIFO)。

- 每个工作线程 (ForkJoinWorkerThread) 都有自己的一个 WorkQueue，该工作队列是一个双端队列；
- WorkQueue 支持三种操作 push、pop、poll；
- push/pop 只能被队列的所有者线程调用，而 poll 可以被其他线程调用；
- 划分的子任务调用 fork 方法时，都会被 push 到自己的 WorkQueue 中；
- 一般情况下，工作线程 (ForkJoinWorkerThread) 从自己的双端队列获出任务并执行；
- 当自己的队列为空时，工作线程 (ForkJoinWorkerThread) 便随机从其他 WorkQueue 末尾调用 poll 方法窃取任务并执行；

#### 三、ForkJoinPool 使用

我们以 RecursiveTask 学习使用 ForkJoinPool，可递归分治任务实现类图：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/13_20_49_59_recursive_task.png)

计算1+2+3+...+10000的值：

```java
public class SumTest extends RecursiveTask<Integer> {
    final int start;
    final int end;

    SumTest(int start, int end) {
        this.start = start;
        this.end = end;
    }
    
    @Override
    protected Integer compute() {
		
        if (end - start < 100) {
            System.out.println(Thread.currentThread().getName() + " 开始执行: " + start + "-" + end);
            int sum = 0;
            for (int i = start; i <= end; i++) {
                sum += i;
            }
            return sum;
        }

        SumTest sumTest1 = new SumTest(start, (end + start) / 2);
        SumTest sumTest2 = new SumTest((start + end) / 2 + 1, end);

        sumTest1.fork();
        sumTest2.fork();

        return sumTest1.join() + sumTest2.join();
    }

    public static void main(String[] args) throws ExecutionException, InterruptedException {
        ForkJoinPool pool = new ForkJoinPool();
        ForkJoinTask<Integer> task = new SumTest(1, 1000);
        pool.submit(task);
        System.out.println(task.get());
    }
}
```

运行结果：

```java
ForkJoinPool-1-worker-13 开始执行: 1-63
ForkJoinPool-1-worker-11 开始执行: 501-563
ForkJoinPool-1-worker-13 开始执行: 126-188
ForkJoinPool-1-worker-11 开始执行: 564-625
ForkJoinPool-1-worker-13 开始执行: 189-250
ForkJoinPool-1-worker-10 开始执行: 251-313
ForkJoinPool-1-worker-4 开始执行: 64-125
ForkJoinPool-1-worker-10 开始执行: 314-375
ForkJoinPool-1-worker-13 开始执行: 376-438
ForkJoinPool-1-worker-10 开始执行: 439-500
ForkJoinPool-1-worker-4 开始执行: 626-688
ForkJoinPool-1-worker-0 开始执行: 814-875
ForkJoinPool-1-worker-7 开始执行: 751-813
ForkJoinPool-1-worker-11 开始执行: 689-750
ForkJoinPool-1-worker-3 开始执行: 939-1000
ForkJoinPool-1-worker-15 开始执行: 876-938
500500
```

从执行结果来看，ForkJoinPool 通过分治算法，一级级拆分表达式，直到拆分的数据单元的差值小于100，接着分别计算各个小数据单元的和，提交汇总。

#### 四、Fork/Join 任务提交方式

ForkJoinPool 支持三种任务提交方式：

* submit: 异步执行，有返回值，通过 task.get() 获取执行结果；
* invoke: 同步执行，等待任务执行完毕后，返回计算结果；
* execute: 直接提交任务，同步执行，无返回结果。