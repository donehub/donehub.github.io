---
title: Understanding Thread start() vs run()
date: 2020-06-07 19:57:01
tags: Java
categories: Backend
lang: en
label: 008_thread_start_run
---

-----

<!-- more -->
#### 1. Using Threads

```java
public static void main(String[] args) {
    Thread thread1 = new Thread(new Runnable() {
        @Override
        public void run() {
            System.out.println("Running thread 1");
        }
    });
    thread1.start();

    Thread thread2 = new Thread(new Runnable() {
        @Override
        public void run() {
            System.out.println("Running thread 2");
        }
    });
    thread2.run();
}
```

Both threads ran their `run()` method. Here's the output:

```java
Running thread 1
Running thread 2
```

Both threads ran, but thread 1 was started via `start()` while thread 2 was invoked by calling `run()` directly.

#### 2. The Difference Between start() and run()

To see the exact difference, we need to print thread information:

```java
public static void main(String[] args) {
    Thread thread1 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("Running thread 1; thread name: " + currentThread.getName());
        }
    });
    thread1.start();

    Thread thread2 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("Running thread 2; thread name: " + currentThread.getName());
        }
    });
    thread2.run();
}
```

Output:

```java
Running thread 1; thread name: Thread-0
Running thread 2; thread name: main
```

The output tells the story clearly: `start()` spawns a new thread to execute `run()`, while calling `run()` directly executes it on the main thread, just like any ordinary method call.

We can take this further by calling `run()` multiple times on the same thread:

```java
public static void main(String[] args) {
    Thread thread1 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("Running thread 1; thread name: " + currentThread.getName());
        }
    });
    thread1.run();
    thread1.run();

    Thread thread2 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("Running thread 2; thread name: " + currentThread.getName());
        }
    });

    thread2.start();
    thread2.start();
}
```

Output:

```java
Running thread 1; thread name: main
Running thread 1; thread name: main
Running thread 2; thread name: Thread-1
Exception in thread "main" java.lang.IllegalThreadStateException
	at java.lang.Thread.start(Thread.java:708)
	at com.example.springbatchdemo.job.Test.main(Test.java:29)
```

The results speak for themselves: `run()` can be called repeatedly, but `start()` can only be called once. Here's why, from the `start()` method source:

```java
public synchronized void start() {
    /**
    * This method is not invoked for the main method thread or "system"
    * group threads created/set up by the VM. Any new functionality added
    * to this method in the future may have to also be added to the VM.
    *
    * A zero status value corresponds to state "NEW".
    */
    if (threadStatus != 0)
        throw new IllegalThreadStateException();
```

When `start()` is called, it first checks whether the thread's status is 0 (NEW). If not, it throws an exception. On the first `start()` call, the thread transitions from NEW to RUNNABLE. By the time you call `start()` a second time, the status is no longer NEW, so the exception fires.

#### 3. Summary

Both `start()` and `run()` get the job done, but they differ in three key ways:

* Execution model: calling `run()` directly is just a regular method call on the current thread; calling `start()` creates a new thread and runs `run()` on it.
* Timing: `run()` executes immediately on the calling thread; `start()` sets the thread to RUNNABLE state and waits for CPU scheduling, so it doesn't run right away.
* Invocation limit: `run()` can be called repeatedly, but `start()` is strictly one-shot.
