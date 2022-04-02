---

title: Spring 线程池饥饿死锁
date: 2021-12-23 23:58:20
tags: Spring
categories: 后端
---

-----

#### 一、 `Spring` 线程池

`Spring` 自带的线程池 `ThreadPoolTaskExecutor` ，本质上是对 `ThreadPoolExecutor` 的包装。一方面，基于 `SpringBoot` 的项目可以通过 `yaml` 或 `properties` 文件快速配置线程池，并借助 `@RefreshScope` 实现线程池的热部署；另一方面，通过`@EnableAsync`、`@Async`配置，可以方便地执行异步并发任务，无需编写异步调用代码。 凭借 `Spring` 生态圈，`ThreadPoolTaskExecutor` 因其良好的设计感和兼容性而被广泛使用。

#### 二、 `Spring` 线程池死锁

像 `jdk` 线程池一样，`Spring` 线程池同样潜藏着一些坑，比如死锁。不得不说这是一个大坑。

首先，在业务上难以理解。线程池是面向 `Task` 的工具，无非就做三件事：创建并管理线程、执行任务调度、存放待办任务。对于 `Task` 来说，抢占到资源的就执行，抢占不到的，就按照拒绝策略处理。不同的 `Task` 怎么会互相等待呢？

其次，在技术上难以定位故障。线程池处于死锁状态，导致主线程走着走着就“失踪了”。重启系统后可以正常工作，一旦压测大概率又会死掉。没有错误日志，没有 `cpu` 飙升，没有 `FullGC`。从表象上看，跟并发有关系，而且属于偶发故障。我们把 `dump` 拉下来分析一下：

```txt
http-nio-8080-exec-32" daemon prio=5 tid=1676 WAITING
    at sun.misc.Unsafe.park(Native Method)
    at java.util.concurrent.locks.LockSupport.park(LockSupport.java:175)
    at java.util.concurrent.FutureTask.awaitDone(FutureTask.java:429)
       Local Variable: java.util.concurrent.FutureTask$WaitNode#4
    at java.util.concurrent.FutureTask.get(FutureTask.java:191)
       Local Variable: java.util.concurrent.FutureTask#4
```

线程(1676) 目前处于 `WAITING` 状态，原因是 `FutureTask` 在等待 `cpu` 的宠幸。但在压测场景下，任务抢占线程资源实属正常，所以此时还没有朝着死锁上面想。

最后，冒出一个念头：如果 `Task` 嵌套 `Task`，并且共用同一个线程池，那么在并发争夺资源的场景下，就有可能出现外部  `Task` 等待内部 `Task`、内部 `Task` 等待外部 `Task` 的情况，从而导致整个线程池死锁。

#### 三、场景模拟

为了更好地理解，我们用打工人进站乘地铁这件事来模拟 `Spring` 线程池的工作机制。

假设有 `5` 个常开闸机（核心线程数），`5` 个应急闸机（5+5=最大线程数），进站围栏可以排 `100` 人（阻塞队列大小）。

约定进站规则：

* 必须有票；
* 必须按照先来后到的顺序进站；
* 一旦走到闸机口或者进入围栏，就不可再撤退；
* 先使用 `5` 个常开闸机进站；
* `5` 个常开闸机若都有乘客进入，则安排后来者在进站围栏里排队等待；
* 若进站围栏已经站满了乘客，则开启另外 `5` 个应急闸机（一个个开启）；

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_28_38_thread_pool_change.png)

为了模拟 `Task` 任务嵌套的场景，假设所有打工人都有一个同伴，而且都是走到闸机口才发现忘记买票，只能安排同伴去买票。这里：

* 外层 `Task`：打工人进闸机；
* 内层 `Task`：打工人的同伴出去买票；

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_19_30_8_thread_pool_dead_lock_2.jpg)

假设张三、李四等人走到闸机口时才发现忘了买票，于是便可能发生如下对话：

* 张三：“怎么出去买个票要这么久？”

* 张三的同伴：“我在排队呢！闸机门口的人别挡着路！赶紧进去！”

* 李四：“这边的人都忘了买票啦！伙伴们不把票带过来，我们也进不去啊！”

* 熊二的同伴：“你们不进去，我们就没法向前走啊！”

* 郑十：“你们都别吵了，我的同伴还在买票的路上呢！”

大家吵成一团，场面十分焦灼，但违反规定就会被拉去枪毙，于是这波打工人都堵在闸机口，一个能进站的都没有。

#### 四、代码模拟

定义线程池：

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
     * @return 任务线程池
     */
    @Bean(TASK_EXECUTOR)
    public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        // 核心线程数
        executor.setCorePoolSize(5);
        // 最大线程数
        executor.setMaxPoolSize(10);
        // 阻塞队列大小
        executor.setQueueCapacity(100);
        // 线程最大空闲时间
        executor.setKeepAliveSeconds(60);
        // 线程名称前缀
        executor.setThreadNamePrefix("common-sync-executor-");
        // 拒绝策略
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(30);
        return executor;
    }
}
```

测试方法：

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
        // 初始化打工人的姓名
        int workerCount = 500;
        List<String> workerNameList = new ArrayList<>(workerCount);
        for (int i = 1; i <= workerCount; i++) {
            workerNameList.add(String.format("%s号打工人", i));
        }
        
        Random random = new Random();
        
        // 打工人进站
        final List<CompletableFuture<Void>> completableFutures = workerNameList
            .stream()
            .map(workerName -> CompletableFuture.runAsync(() -> {
                // 打印线程池的运行信息
                this.printThreadPoolTaskExecutorInfo(workerName);
                
                // 外层Task: 打工人进站
                int passGateMillSecond = random.nextInt(500);
                try {
                    TimeUnit.MILLISECONDS.sleep(passGateMillSecond);
                } catch (InterruptedException e) {
                    e.printStackTrace();
                }

                int buyTicketMillSecond = random.nextInt(500);
                LOGGER.info("{}走到闸机口, 发现未买票, 安排同伴去买票, 需要{}毫秒", workerName, buyTicketMillSecond);

                // 内层Task: 打工人的同伴出来买票
                try {
                    taskExecutor.submit(() -> {
                        LOGGER.info("{}的同伴出来买票了", workerName);
                        try {
                            TimeUnit.MILLISECONDS.sleep(buyTicketMillSecond);
                        } catch (InterruptedException e) {
                            e.printStackTrace();
                        }
                        return true;
                    }).get();
                } catch (InterruptedException | ExecutionException e) {
                    LOGGER.error("{}的同伴出来买票失败：{}", workerName, e.getMessage(), e);
                }
                LOGGER.info("{}与同伴成功进站", workerName);
            }, taskExecutor).exceptionally(e -> {
                LOGGER.error("{}进站失败: {}", workerName, e.getMessage(), e);
                return null;
            }))
            .collect(Collectors.toList());
        // 等待所有打工人进站
        completableFutures.stream().map(CompletableFuture::join).collect(Collectors.toList());
        
        LOGGER.info("打工人都进站了");
    }
    
    /**
     * 【打印线程池运行信息】
     */
    private void printThreadPoolTaskExecutorInfo(String workName) {
        LOGGER.info("进站人：{}", workName);
        LOGGER.info("核心线程数：{}", taskExecutor.getCorePoolSize());
        LOGGER.info("线程池大小：{}", taskExecutor.getPoolSize());
        LOGGER.info("活跃线程数：{}", taskExecutor.getActiveCount());
        LOGGER.info("线程保持时间（秒）：{}", taskExecutor.getKeepAliveSeconds());
        LOGGER.info("线程池最大数量：{}", taskExecutor.getMaxPoolSize());
        LOGGER.info("线程池等待的任务数量: {}", taskExecutor.getThreadPoolExecutor().getQueue().size());
        LOGGER.info("线程池已完成任务数量: {}", taskExecutor.getThreadPoolExecutor().getCompletedTaskCount());
    }
}
```

运行起来，日志打印：

```java
13:02:46.354 [common-sync-executor-1] INFO TaskTest - 进站人：1号打工人
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 核心线程数：5
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 线程池大小：3
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 活跃线程数：3
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 进站人：2号打工人
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 核心线程数：5
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 线程池最大数量：10
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 线程池大小：3
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 线程池等待的任务数量: 0
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 活跃线程数：3
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 线程池最大数量：10
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 线程池等待的任务数量: 0
13:02:46.355 [common-sync-executor-2] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.355 [common-sync-executor-1] INFO TaskTest - 1号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要275毫秒
13:02:46.355 [common-sync-executor-3] INFO TaskTest - 进站人：3号打工人
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 核心线程数：5
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 线程池大小：4
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 活跃线程数：4
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 线程池最大数量：10
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 线程池等待的任务数量: 0
13:02:46.356 [common-sync-executor-3] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 进站人：4号打工人
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 核心线程数：5
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 线程池大小：5
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 活跃线程数：5
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 线程池最大数量：10
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 线程池等待的任务数量: 0
13:02:46.356 [common-sync-executor-4] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.356 [common-sync-executor-5] INFO TaskTest - 进站人：5号打工人
13:02:46.356 [common-sync-executor-5] INFO TaskTest - 核心线程数：5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - 线程池大小：5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - 活跃线程数：5
13:02:46.357 [common-sync-executor-5] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.357 [common-sync-executor-5] INFO TaskTest - 线程池最大数量：10
13:02:46.357 [common-sync-executor-5] INFO TaskTest - 线程池等待的任务数量: 100
13:02:46.357 [common-sync-executor-5] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 进站人：106号打工人
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 核心线程数：5
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 线程池大小：8
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 活跃线程数：8
13:02:46.358 [common-sync-executor-7] INFO TaskTest - 1号打工人的同伴出来买票了
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 线程池最大数量：10
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 线程池等待的任务数量: 100
13:02:46.358 [common-sync-executor-6] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.358 [common-sync-executor-8] INFO TaskTest - 进站人：107号打工人
13:02:46.358 [common-sync-executor-8] INFO TaskTest - 核心线程数：5
13:02:46.358 [common-sync-executor-8] INFO TaskTest - 线程池大小：9
13:02:46.358 [common-sync-executor-8] INFO TaskTest - 活跃线程数：9
13:02:46.359 [common-sync-executor-8] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.359 [common-sync-executor-8] INFO TaskTest - 线程池最大数量：10
13:02:46.359 [common-sync-executor-8] INFO TaskTest - 线程池等待的任务数量: 100
13:02:46.359 [common-sync-executor-8] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 进站人：108号打工人
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 核心线程数：5
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 线程池大小：10
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 活跃线程数：10
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 线程池最大数量：10
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 线程池等待的任务数量: 100
13:02:46.359 [common-sync-executor-9] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.359 [main] INFO TaskTest - 进站人：110号打工人
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 进站人：109号打工人
13:02:46.359 [main] INFO TaskTest - 核心线程数：5
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 核心线程数：5
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 线程池大小：10
13:02:46.359 [main] INFO TaskTest - 线程池大小：10
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 活跃线程数：10
13:02:46.359 [main] INFO TaskTest - 活跃线程数：10
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.359 [main] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 线程池最大数量：10
13:02:46.359 [main] INFO TaskTest - 线程池最大数量：10
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 线程池等待的任务数量: 100
13:02:46.359 [main] INFO TaskTest - 线程池等待的任务数量: 100
13:02:46.359 [common-sync-executor-10] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.360 [main] INFO TaskTest - 线程池已完成任务数量: 0
13:02:46.368 [common-sync-executor-8] INFO TaskTest - 107号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要81毫秒
13:02:46.368 [common-sync-executor-8] INFO TaskTest - 107号打工人的同伴出来买票了
13:02:46.417 [common-sync-executor-2] INFO TaskTest - 2号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要391毫秒
13:02:46.417 [common-sync-executor-2] INFO TaskTest - 2号打工人的同伴出来买票了
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 107号打工人与同伴成功进站
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 进站人：6号打工人
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 核心线程数：5
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 线程池大小：10
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 活跃线程数：10
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 线程池最大数量：10
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 线程池等待的任务数量: 99
13:02:46.449 [common-sync-executor-8] INFO TaskTest - 线程池已完成任务数量: 1
13:02:46.515 [common-sync-executor-4] INFO TaskTest - 4号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要34毫秒
13:02:46.559 [common-sync-executor-6] INFO TaskTest - 106号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要116毫秒
13:02:46.559 [common-sync-executor-6] INFO TaskTest - 106号打工人的同伴出来买票了
13:02:46.570 [common-sync-executor-9] INFO TaskTest - 108号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要149毫秒
13:02:46.570 [common-sync-executor-9] INFO TaskTest - 108号打工人的同伴出来买票了
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 进站人：7号打工人
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 1号打工人与同伴成功进站
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 核心线程数：5
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 线程池大小：10
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 进站人：8号打工人
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 活跃线程数：10
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 核心线程数：5
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 线程池大小：10
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 线程池最大数量：10
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 活跃线程数：10
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 线程池等待的任务数量: 98
13:02:46.633 [common-sync-executor-7] INFO TaskTest - 线程池已完成任务数量: 3
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 线程池最大数量：10
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 线程池等待的任务数量: 98
13:02:46.633 [common-sync-executor-1] INFO TaskTest - 线程池已完成任务数量: 3
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 106号打工人与同伴成功进站
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 进站人：9号打工人
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 核心线程数：5
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 线程池大小：10
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 活跃线程数：10
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 线程池最大数量：10
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 线程池等待的任务数量: 97
13:02:46.675 [common-sync-executor-6] INFO TaskTest - 线程池已完成任务数量: 4
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 108号打工人与同伴成功进站
13:02:46.719 [common-sync-executor-5] INFO TaskTest - 5号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要380毫秒
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 进站人：10号打工人
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 核心线程数：5
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 线程池大小：10
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 活跃线程数：10
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 线程池最大数量：10
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 线程池等待的任务数量: 97
13:02:46.719 [common-sync-executor-9] INFO TaskTest - 线程池已完成任务数量: 5
13:02:46.784 [main] INFO TaskTest - 110号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要291毫秒
13:02:46.796 [common-sync-executor-3] INFO TaskTest - 3号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要205毫秒
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 2号打工人与同伴成功进站
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 进站人：11号打工人
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 核心线程数：5
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 线程池大小：10
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 活跃线程数：10
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 线程池最大数量：10
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 线程池等待的任务数量: 98
13:02:46.808 [common-sync-executor-2] INFO TaskTest - 线程池已完成任务数量: 6
13:02:46.815 [common-sync-executor-2] INFO TaskTest - 11号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要192毫秒
13:02:46.821 [common-sync-executor-10] INFO TaskTest - 109号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要115毫秒
13:02:46.837 [common-sync-executor-1] INFO TaskTest - 8号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要67毫秒
13:02:46.837 [common-sync-executor-1] INFO TaskTest - 8号打工人的同伴出来买票了
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 8号打工人与同伴成功进站
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 进站人：12号打工人
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 核心线程数：5
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 线程池大小：10
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 活跃线程数：10
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 线程保持时间（秒）：60
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 线程池最大数量：10
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 线程池等待的任务数量: 99
13:02:46.904 [common-sync-executor-1] INFO TaskTest - 线程池已完成任务数量: 7
13:02:46.934 [common-sync-executor-8] INFO TaskTest - 6号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要198毫秒
13:02:46.949 [common-sync-executor-7] INFO TaskTest - 7号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要470毫秒
13:02:46.949 [common-sync-executor-7] INFO TaskTest - 7号打工人的同伴出来买票了
13:02:46.969 [common-sync-executor-6] INFO TaskTest - 9号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要142毫秒
13:02:46.969 [common-sync-executor-6] INFO TaskTest - 9号打工人的同伴出来买票了
13:02:47.102 [common-sync-executor-1] INFO TaskTest - 12号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要470毫秒
13:02:47.102 [common-sync-executor-1] INFO TaskTest - 12号打工人的同伴出来买票了
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 9号打工人与同伴成功进站
13:02:47.111 [common-sync-executor-9] INFO TaskTest - 10号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要109毫秒
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 进站人：13号打工人
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 核心线程数：5
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 线程池大小：10
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 活跃线程数：10
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 线程保持时间（秒）：60
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 线程池最大数量：10
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 线程池等待的任务数量: 100
13:02:47.111 [common-sync-executor-6] INFO TaskTest - 线程池已完成任务数量: 8
13:02:47.220 [common-sync-executor-6] INFO TaskTest - 13号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要245毫秒
13:02:47.220 [common-sync-executor-6] INFO TaskTest - 13号打工人的同伴出来买票了
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 7号打工人与同伴成功进站
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 进站人：14号打工人
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 核心线程数：5
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 线程池大小：10
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 活跃线程数：10
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 线程保持时间（秒）：60
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 线程池最大数量：10
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 线程池等待的任务数量: 99
13:02:47.419 [common-sync-executor-7] INFO TaskTest - 线程池已完成任务数量: 9
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 13号打工人与同伴成功进站
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 进站人：15号打工人
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 核心线程数：5
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 线程池大小：10
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 活跃线程数：10
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 线程保持时间（秒）：60
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 线程池最大数量：10
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 线程池等待的任务数量: 98
13:02:47.465 [common-sync-executor-6] INFO TaskTest - 线程池已完成任务数量: 10
13:02:47.468 [common-sync-executor-6] INFO TaskTest - 15号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要392毫秒
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 12号打工人与同伴成功进站
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 进站人：16号打工人
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 核心线程数：5
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 线程池大小：10
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 活跃线程数：10
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 线程保持时间（秒）：60
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 线程池最大数量：10
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 线程池等待的任务数量: 98
13:02:47.572 [common-sync-executor-1] INFO TaskTest - 线程池已完成任务数量: 11
13:02:47.898 [common-sync-executor-7] INFO TaskTest - 14号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要249毫秒
13:02:48.064 [common-sync-executor-1] INFO TaskTest - 16号打工人走到闸机口, 发现未买票, 安排同伴去买票, 需要407毫秒
    ...线程池饥饿死锁
```

从日志可以看出，`TASK_EXECUTOR` 线程池一共经历了三个阶段：开启核心线程处理任务；将多余任务放入阻塞队列；开启非核心线程处理任务。一共有 `500` 个打工人需要进站，最终只有大概 `11` 人（`ThreadPoolExecutor().getCompletedTaskCount()`返回模糊数量）成功进站。线程池死锁，主线程全部处于 `WAITING` 状态。

#### 五、 `Spring` 线程池饥饿死锁解决方案

线程池死锁，影响比较严重。在编码过程中容易忽略（需要追溯整条业务代码链）；在测试过程中不易发现（需要压测，且是偶发现象）。我们可以采用以下方案：

* 禁止嵌套任务共用线程池（推荐）；
* 硬编码 `jdk` 线程池，执行完任务后手动`shutdown`（不推荐）；
* 回归业务，整合嵌套任务（不推荐）。