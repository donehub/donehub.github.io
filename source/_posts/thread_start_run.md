---
qtitle: Thread 之 start()、run() 详解
date: 2020-06-07 19:57:01
tags: Java
categories: 后端
---

-----

#### 一、线程的使用

```java
public static void main(String[] args) {
    Thread thread1 = new Thread(new Runnable() {
        @Override
        public void run() {
            System.out.println("执行线程1");
        }
    });
    thread1.start();

    Thread thread2 = new Thread(new Runnable() {
        @Override
        public void run() {
            System.out.println("执行线程2");
        }
    });
    thread2.run();
}
```

创建以上两个线程，执行结果：

```java
执行线程1
执行线程2
```

线程1与线程2都执行了 run()，但线程1是通过 start() 执行的，线程2是直接调用 run() 执行的。

#### 二、start() 与 run() 的区别

为了更精准地找到两种调用之间的区别，需要打印线程相关的信息：

```java
public static void main(String[] args) {
    Thread thread1 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("执行线程1; 线程名称：" + currentThread.getName());
        }
    });
    thread1.start();

    Thread thread2 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("执行线程2; 线程名称：" + currentThread.getName());
        }
    });
    thread2.run();
}
```

执行结果：

```java
执行线程1; 线程名称：Thread-0
执行线程2; 线程名称：main
```

从执行结果来看，start() 调用，是通过开启一个新线程来执行 run() 的；而直接调用 run()，是主线程直接执行方法内容的。

此外，我们还可以做另一种尝试：多次执行 run() 方法：

```java
public static void main(String[] args) {
    Thread thread1 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("执行线程1; 线程名称：" + currentThread.getName());
        }
    });
    thread1.run();
    thread1.run();

    Thread thread2 = new Thread(new Runnable() {
        @Override
        public void run() {
            Thread currentThread = Thread.currentThread();
            System.out.println("执行线程2; 线程名称：" + currentThread.getName());
        }
    });

    thread2.start();
    thread2.start();
}
```

执行结果：

```java
执行线程1; 线程名称：main
执行线程1; 线程名称：main
执行线程2; 线程名称：Thread-1
Exception in thread "main" java.lang.IllegalThreadStateException
	at java.lang.Thread.start(Thread.java:708)
	at com.example.springbatchdemo.job.Test.main(Test.java:29)
```

从执行结果可知，可以多次调用 run()，而 start() 只能被执行一次，这是为什么呢？我们看下 start 方法说明：

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

调用 start()，首先需要判断当前线程的状态是否为 0 （NEW），如果不是，则抛异常。当第一次调用 start() 时，线程状态从 NEW （新建）变为 RUNNABLE（就绪），当第二次调用 start() 时，线程状态肯定不是 NEW。

#### 三、总结

Thread 的 start() 与 run() 都可以完成任务执行，主要区别在：

* 作用机制不同：直接调用 run()，相当于在当前线程中执行普通方法；调用 start()，是开启一个新的线程来执行 run()；
* 执行速度不同：调用 run() 会立即执行任务，调用 start() 是将线程的状态改为就绪状态，等待空闲 CPU，不会立即执行；
* 调用次数不同：run() 可以被重复调用，而 start() 只能被调用一次。
