---
title: JUC Thread Pool: ForkJoinPool
date: 2021-02-20 10:57:01
tags: Java
categories: Backend
lang: en
label: 020_fork_join_thred_pool
---

-----

<!-- more -->
#### 1. Introduction to ForkJoinPool

ForkJoinPool was introduced in JDK 1.7. Its underlying design is based on the divide-and-conquer parallel algorithm — a simple yet efficient technique for achieving good parallel performance. By recursively splitting tasks, it makes better use of multiple processors, handles work in parallel, and improves computational throughput.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/13_20_27_1_fork_join.png)

The Fork/Join framework consists of three main modules:

* Thread pool: ForkJoinPool
* Worker threads that execute Fork/Join tasks: ForkJoinWorkerThread
* Task objects: ForkJoinTask, with subclasses including RecursiveTask, RecursiveAction, and CountedCompleter

ForkJoinPool uses ForkJoinWorkerThread to process submitted ForkJoinTasks. You typically don't create ForkJoinTask directly; instead, you use its subclasses to create the appropriate divide-and-conquer tasks based on your needs. RecursiveTask is a recursively executable ForkJoinTask that returns a result. RecursiveAction is a RecursiveTask with no return value. CountedCompleter automatically triggers a custom hook function after task completion.

#### 2. Work-Stealing Algorithm

The work-stealing algorithm is the core design principle behind Fork/Join. All worker threads in the pool try to find and execute tasks that have been submitted, including subtasks created by other active tasks. ForkJoinPool is particularly efficient when running tasks that spawn subtasks, or when submitting many small tasks.

In ForkJoinPool, each worker thread (ForkJoinWorkerThread) has its own task queue (WorkQueue). The worker prioritizes tasks in its own queue, then steals tasks from other queues in FIFO order. There are two ways to process tasks in a thread's own queue: FIFO (first-in, first-out) and LIFO (last-in, first-out). This is controlled by the `asyncMode` parameter in the ForkJoinPool constructor, which defaults to FIFO.

- Each worker thread (ForkJoinWorkerThread) has its own WorkQueue, which is a double-ended queue (deque).
- WorkQueue supports three operations: push, pop, and poll.
- push/pop can only be called by the queue's owner thread; poll can be called by other threads.
- Subtasks created by calling `fork()` are pushed onto the thread's own WorkQueue.
- Under normal circumstances, the worker thread pulls tasks from its own deque and executes them.
- When its own queue is empty, the worker thread randomly picks another WorkQueue and calls `poll()` from the tail to steal a task.

#### 3. Using ForkJoinPool

Let's use RecursiveTask to learn how ForkJoinPool works. Here's the class hierarchy for recursive divide-and-conquer tasks:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2023/03/13_20_49_59_recursive_task.png)

Computing the sum of 1+2+3+...+10000:

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
		
        // Base case: range is small enough to compute directly
        if (end - start < 100) {
            System.out.println(Thread.currentThread().getName() + " computing: " + start + "-" + end);
            int sum = 0;
            for (int i = start; i <= end; i++) {
                sum += i;
            }
            return sum;
        }

        // Split the range in half and recurse
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

Output:

```java
ForkJoinPool-1-worker-13 computing: 1-63
ForkJoinPool-1-worker-11 computing: 501-563
ForkJoinPool-1-worker-13 computing: 126-188
ForkJoinPool-1-worker-11 computing: 564-625
ForkJoinPool-1-worker-13 computing: 189-250
ForkJoinPool-1-worker-10 computing: 251-313
ForkJoinPool-1-worker-4 computing: 64-125
ForkJoinPool-1-worker-10 computing: 314-375
ForkJoinPool-1-worker-13 computing: 376-438
ForkJoinPool-1-worker-10 computing: 439-500
ForkJoinPool-1-worker-4 computing: 626-688
ForkJoinPool-1-worker-0 computing: 814-875
ForkJoinPool-1-worker-7 computing: 751-813
ForkJoinPool-1-worker-11 computing: 689-750
ForkJoinPool-1-worker-3 computing: 939-1000
ForkJoinPool-1-worker-15 computing: 876-938
500500
```

From the output, you can see how ForkJoinPool recursively splits the range until each data unit is smaller than 100, then computes the sum of each small unit in parallel across multiple workers, and finally aggregates the results.

#### 4. Task Submission Methods

ForkJoinPool supports three ways to submit tasks:

* submit: Asynchronous execution; returns a ForkJoinTask. Use `task.get()` to retrieve the result.
* invoke: Synchronous execution; waits for the task to complete and returns the result.
* execute: Direct submission; synchronous execution with no return value.
