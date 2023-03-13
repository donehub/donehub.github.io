---
title: JUC线程池-ForkJoinPool
date: 2021-08-13 14:57:01
tags: Java
categories: 后端
---

-----

#### 一、ForkJoinPool 介绍

ForkJoinPool 是 jdk 1.7 引入的一个线程池，其底层设计基于分治算法(Divide-and-Conquer)的并行实现，是一款可以获得良好并行性能的简单且高效的设计技术。通过任务分治，可以更好地利用多处理器，提升预算效能。

// 图片

Fork/Join 框架主要包含三个模块：

* 线程池：ForkJoinPool
* 执行 Fork/Join 任务的线程：ForkJoinWorkerThread
* 任务对象：ForkJoinTask，继承者有 RecursiveTask、RecursiveAction、CountedCompleter

ForkJoinPool 通过 ForkJoinWorkerThread 来处理提交的 ForkJoinTask。通常不会直接创建 ForkJoinTask，而是借助其继承类，根据实际需要创建对应的分治任务。RecursiveTask 是一个可以递归执行的 ForkJoinTask；RecursiveAction 是一个没有返回值的 RecursiveTask；CountedCompleter 在完成任务执行后，回自动触发执行一个自定义的钩子函数。

#### 二、ForkJoinPool 使用

我们以 RecursiveTask 学习使用 ForkJoinPool，可递归分治任务实现：

// 类继承关系图

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

从执行结果来看，ForkJoinPool 通过分治算法，拆分数列和表达式，直到拆分的数据单元只差小于100，然后分别计算各个小数据单元的和，提交汇总。

#### 三、Fork/Join 任务提交方式

ForkJoinPool 支持三种任务提交方式：

* submit: 异步执行，有返回值，通过 task.get() 获取执行结果；
* invoke: 同步执行，等待任务执行完毕后，返回计算结果；
* execute: 直接提交任务，同步执行，无返回结果。