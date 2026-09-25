---
title: Starvation Deadlock in Spring's ThreadPoolTaskExecutor
date: 2021-12-23 23:58:20
tags: Spring
categories: Backend
lang: en
label: 030_thread_pool_task_executor_dead_lock
---

-----

<!-- more -->
#### 1. Spring's Thread Pool

Spring's `ThreadPoolTaskExecutor` is essentially a wrapper around JDK's `ThreadPoolExecutor`. It offers two practical advantages for Spring Boot projects. First, thread pools can be configured through `yaml` or `properties` files and hot-reloaded via `@RefreshScope`. Second, the `@EnableAsync` and `@Async` annotations make it trivial to execute tasks asynchronously without writing explicit threading code. Given the ubiquity of the Spring ecosystem, `ThreadPoolTaskExecutor` sees widespread use.

#### 2. The Deadlock Problem

Like the JDK thread pool it wraps, Spring's thread pool has a nasty surprise hidden in it: starvation deadlock. This is a serious issue for two reasons.

First, it defies intuition. A thread pool is a task execution tool — it creates threads, schedules tasks, and queues pending work. Tasks that get resources execute; tasks that don't are handled by the rejection policy. The idea that tasks could end up waiting on each other seems paradoxical.

Second, the failure is extremely hard to diagnose. The thread pool enters a deadlocked state, and the main thread simply vanishes — no response, no error. Restarting the system temporarily fixes it, but under load testing the deadlock recurs. There are no error logs, no CPU spikes, no Full GC events. The symptoms suggest a concurrency issue, but the intermittent nature makes it hard to reproduce. Pulling a thread dump reveals this:

```txt
http-nio-8080-exec-32" daemon prio=5 tid=1676 WAITING
    at sun.misc.Unsafe.park(Native Method)
    at java.util.concurrent.locks.LockSupport.park(LockSupport.java:175)
    at java.util.concurrent.FutureTask.awaitDone(FutureTask.java:429)
       Local Variable: java.util.concurrent.FutureTask$WaitNode#4
    at java.util.concurrent.FutureTask.get(FutureTask.java:191)
       Local Variable: java.util.concurrent.FutureTask#4
```

Thread 1676 is in `WAITING` state, blocked on `FutureTask.get()`. Under load testing, threads waiting for CPU time is normal — at this point, deadlock wasn't yet on the radar.

Then a critical realization: if tasks are nested (a task submits another task to the same pool) and the pool is under resource contention, the outer task blocks waiting for the inner task to complete, while the inner task can't execute because all threads are occupied by outer tasks. This creates a circular wait — the entire pool deadlocks.

#### 3. An Analogy

To make this concrete, imagine workers entering a subway station through turnstiles.

Suppose there are 5 always-open turnstiles (core pool size), 5 emergency turnstiles (total max pool size = 10), and a queuing area that holds 100 people (blocking queue capacity).

The entry rules:

* Everyone must have a ticket;
* People enter in order of arrival;
* Once you reach a turnstile or enter the queue, you can't turn back;
* The 5 always-open turnstiles are used first;
* When all 5 turnstiles are occupied, newcomers queue in the waiting area;
* When the waiting area is full (100 people), the 5 emergency turnstiles open one by one;

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_28_38_thread_pool_change.png)

Now, to simulate nested tasks, suppose every worker reaches the turnstile only to realize they forgot to buy a ticket, and must send their companion back to buy one:

* Outer task: the worker entering through the turnstile;
* Inner task: the companion going out to buy a ticket;

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_30_8_thread_pool_dead_lock_2.jpg)

When Zhang San, Li Si, and others reach the turnstiles and discover they have no tickets, the scene unfolds like this:

* Zhang San: "Why is your companion taking so long to buy a ticket?"

* Zhang San's companion: "I'm in line! Stop blocking the turnstile and get through!"

* Li Si: "Everyone here forgot their ticket! Until our companions bring the tickets, we can't move!"

* Xiong Er's companion: "If you don't go through, we can't move forward either!"

* Zheng Shi: "Stop arguing! My companion is still on the way to buy tickets!"

Everyone is shouting, the situation is gridlocked. But breaking the rules means getting shot, so all the workers are stuck at the turnstiles — not a single person gets through.

#### 4. Reproducing with Code

Thread pool configuration:

```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

/**
 * @author zourongsheng
 */
@Configuration
public class ExecutorConfig {
    
    public static final String TASK_EXECUTOR = "taskExecutor";

    /**
     * @return task thread pool
     */
    @Bean(TASK_EXECUTOR)
    public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        // Core pool size
        executor.setCorePoolSize(5);
        // Max pool size
        executor.setMaxPoolSize(10);
        // Blocking queue capacity
        executor.setQueueCapacity(100);
        // Thread idle timeout
        executor.setKeepAliveSeconds(60);
        // Thread name prefix
        executor.setThreadNamePrefix("common-sync-executor-");
        // Rejection policy
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);
        return executor;
    }
}
```

Test method:

```java
/**
 * @author zourongsheng
 * @date 2021/12/23 14:33
 */
import org.junit.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import javax.annotation.Resource;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.stream.Collectors;

import org.junit.runner.RunWith;
import org.springframework.boot.test.context.SpringBootTest;

import static ExecutorConfig.TASK_EXECUTOR;

@RunWith(SpringJUnit4ClassRunner.class)
@SpringBootTest(classes = ServiceInitializer.class)
public class TaskTest {
    
    private static Logger LOGGER = LoggerFactory.getLogger(TaskTest.class);
    
    @Resource(name = TASK_EXECUTOR)
    private ThreadPoolTaskExecutor taskExecutor;
    
    @Test
    public void test() {
        // Initialize worker names
        int workerCount = 500;
        List<String> workerNameList = new ArrayList<>(workerCount);
        for (int i = 1; i <= workerCount; i++) {
            workerNameList.add(String.format("Worker-%d", i));
        }
        
        Random random = new Random();
        
        // Workers entering the station
        final List<CompletableFuture<Void>> completableFutures = workerNameList
            .stream()
            .map(workerName -> CompletableFuture.runAsync(() -> {
                // Print thread pool status
                this.printThreadPoolTaskExecutorInfo(workerName);
                
                // Outer task: worker entering the station
                int passGateMillSecond = random.nextInt(500);
                try {
                    TimeUnit.MILLISECONDS.sleep(passGateMillSecond);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }

                int buyTicketMillSecond = random.nextInt(500);
                LOGGER.info("{} reached the turnstile, no ticket found, sending companion to buy one ({}ms needed)", workerName, buyTicketMillSecond);

                // Inner task: companion goes out to buy a ticket
                try {
                    taskExecutor.submit(() -> {
                        LOGGER.info("{}'s companion is buying a ticket", workerName);
                        try {
                            TimeUnit.MILLISECONDS.sleep(buyTicketMillSecond);
                        } catch (InterruptedException e) {
                            e.printStackTrace();
                        }
                        return true;
                    }).get();
                } catch (InterruptedException | ExecutionException e) {
                    LOGGER.error("{}'s companion failed to buy ticket: {}", workerName, e.getMessage(), e);
                }
                LOGGER.info("{} and companion entered successfully", workerName);
            }, taskExecutor).exceptionally(e -> {
                LOGGER.error("{} failed to enter: {}", workerName, e.getMessage(), e);
                return null;
            }))
            .collect(Collectors.toList());
        // Wait for all workers to enter
        completableFutures.stream().map(CompletableFuture::join).collect(Collectors.toList());
        
        LOGGER.info("All workers have entered the station");
    }
    
    /**
     * Print thread pool runtime info
     */
    private void printThreadPoolTaskExecutorInfo(String workName) {
        LOGGER.info("Worker: {}", workName);
        LOGGER.info("Core pool size: {}", taskExecutor.getCorePoolSize());
        LOGGER.info("Pool size: {}", taskExecutor.getPoolSize());
        LOGGER.info("Active threads: {}", taskExecutor.getActiveCount());
        LOGGER.info("Thread keep-alive (seconds): {}", taskExecutor.getKeepAliveSeconds());
        LOGGER.info("Max pool size: {}", taskExecutor.getMaxPoolSize());
        LOGGER.info("Queued tasks: {}", taskExecutor.getThreadPoolExecutor().getQueue().size());
        LOGGER.info("Completed tasks: {}", taskExecutor.getThreadPoolExecutor().getCompletedTaskCount());
    }
}
```

Running the test produces this log:

```java
13:02:46.354 [common-sync-executor-1] INFO TaskTest - Worker: Worker-1
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Core pool size: 5
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Pool size: 3
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Active threads: 3
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Worker: Worker-2
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Core pool size: 5
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Max pool size: 10
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Pool size: 3
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Queued tasks: 0
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Active threads: 3
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Completed tasks: 0
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Max pool size: 10
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Queued tasks: 0
13:02:46.355 [common-sync-executor-2] INFO TaskTest - Completed tasks: 0
13:02:46.355 [common-sync-executor-1] INFO TaskTest - Worker-1 reached the turnstile, no ticket found, sending companion to buy one (275ms needed)
13:02:46.355 [common-sync-executor-3] INFO TaskTest - Worker: Worker-3
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Core pool size: 5
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Pool size: 4
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Active threads: 4
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Max pool size: 10
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Queued tasks: 0
13:02:46.356 [common-sync-executor-3] INFO TaskTest - Completed tasks: 0
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Worker: Worker-4
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Core pool size: 5
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Pool size: 5
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Active threads: 5
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Max pool size: 10
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Queued tasks: 0
13:02:46.356 [common-sync-executor-4] INFO TaskTest - Completed tasks: 0
13:02:46.356 [common-sync-executor-5] INFO TaskTest - Worker: Worker-5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Core pool size: 5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Pool size: 5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Active threads: 5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Max pool size: 10
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Queued tasks: 100
13:02:46.357 [common-sync-executor-5] INFO TaskTest - Completed tasks: 0
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Worker: Worker-106
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Core pool size: 5
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Pool size: 8
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Active threads: 8
13:02:46.358 [common-sync-executor-7] INFO TaskTest - Worker-1's companion is buying a ticket
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Max pool size: 10
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Queued tasks: 100
13:02:46.358 [common-sync-executor-6] INFO TaskTest - Completed tasks: 0
13:02:46.358 [common-sync-executor-8] INFO TaskTest - Worker: Worker-107
13:02:46.358 [common-sync-executor-8] INFO TaskTest - Core pool size: 5
13:02:46.358 [common-sync-executor-8] INFO TaskTest - Pool size: 9
13:02:46.358 [common-sync-executor-8] INFO TaskTest - Active threads: 9
13:02:46.359 [common-sync-executor-8] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.359 [common-sync-executor-8] INFO TaskTest - Max pool size: 10
13:02:46.359 [common-sync-executor-8] INFO TaskTest - Queued tasks: 100
13:02:46.359 [common-sync-executor-8] INFO TaskTest - Completed tasks: 0
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Worker: Worker-108
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Core pool size: 5
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Pool size: 10
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Active threads: 10
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Max pool size: 10
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Queued tasks: 100
13:02:46.359 [common-sync-executor-9] INFO TaskTest - Completed tasks: 0
13:02:46.359 [main] INFO TaskTest - Worker: Worker-110
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Worker: Worker-109
13:02:46.359 [main] INFO TaskTest - Core pool size: 5
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Core pool size: 5
13:02:46.359 [main] INFO TaskTest - Pool size: 10
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Pool size: 10
13:02:46.359 [main] INFO TaskTest - Active threads: 10
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Active threads: 10
13:02:46.359 [main] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.359 [main] INFO TaskTest - Max pool size: 10
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Max pool size: 10
13:02:46.359 [main] INFO TaskTest - Queued tasks: 100
13:02:46.359 [common-sync-executor-10] INFO TaskTest - Queued tasks: 100
13:02:46.359 [main] INFO TaskTest - Completed tasks: 0
13:02:46.360 [common-sync-executor-10] INFO TaskTest - Completed tasks: 0
13:02:46.368 [common-sync-executor-8] INFO TaskTest - Worker-107 reached the turnstile, no ticket found, sending companion to buy one (81ms needed)
13:02:46.368 [common-sync-executor-8] INFO TaskTest - Worker-107's companion is buying a ticket
13:02:46.417 [common-sync-executor-2] INFO TaskTest - Worker-2 reached the turnstile, no ticket found, sending companion to buy one (391ms needed)
13:02:46.417 [common-sync-executor-2] INFO TaskTest - Worker-2's companion is buying a ticket
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Worker-107 and companion entered successfully
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Worker: Worker-6
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Core pool size: 5
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Pool size: 10
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Active threads: 10
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Thread keep-alive (seconds): 60
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Max pool size: 10
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Queued tasks: 99
13:02:46.449 [common-sync-executor-8] INFO TaskTest - Completed tasks: 1
    ...thread pool starvation deadlock
```

The log shows the thread pool going through three phases: core threads handling tasks, overflow tasks filling the blocking queue, and max threads being spawned. Out of 500 workers, only about 11 (based on `getCompletedTaskCount()`) successfully entered. The thread pool is deadlocked — all threads are in `WAITING` state.

The root cause is clear: outer tasks occupy all available threads and then block on `FutureTask.get()`, waiting for inner tasks to complete. But inner tasks can't execute because all threads are occupied by blocked outer tasks. Neither side can make progress.

#### 5. Solutions

Thread pool starvation deadlock is a serious issue. It's easy to introduce during development (you need to trace the entire task submission chain to spot it) and hard to catch in testing (it requires load testing and only manifests intermittently). Here are three approaches:

* **Don't share thread pools between nested tasks** (recommended) — use separate pools for outer and inner tasks so they can't starve each other;
* **Use a raw JDK thread pool with manual shutdown** (not recommended) — create a new thread pool for each inner task and shut it down after completion; this works but adds boilerplate and overhead;
* **Restructure the business logic to flatten nested tasks** (not recommended) — merge the inner task into the outer task to eliminate the dependency; this is the cleanest in theory but often impractical because the nesting reflects real business structure;

The first option is the most practical. Give inner tasks their own dedicated thread pool with independent resources, and the deadlock becomes impossible by construction.