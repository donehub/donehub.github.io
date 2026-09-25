---
title: Monitoring Thread Pools with Prometheus
date: 2020-08-17 01:45:12
lang: en
label: 012_metrics_in_thread_pool
tags: Prometheus
categories: Operations
---

#### 1. Background

In our payment system, thread pools play a critical role in batch payment processing. As transaction volume grew, the payment endpoint's throughput degraded to the point where a single batch could take over 5 minutes — unacceptable for the calling services. The obvious fix is to increase the thread count and queue capacity, but figuring out the right numbers without over-provisioning is hard to do by feel alone. Prometheus + Grafana is a well-established monitoring stack, and it works well for thread pool observability too.

<!-- more -->
#### 2. Thread Pool Configuration

The configuration uses Spring's `ThreadPoolTaskExecutor`. Based on the business requirements, two pools are defined: a synchronous pool and an asynchronous pool.

```java
@Configuration
public class ExecutorPoolConfig {
    
    /**
    * Thread pool parameter configuration
    */
    @Resource
    private ExecutorProperties executorProperties;
    
    private static final String ASYNC_EXECUTOR = "asyncExecutor";
    private static final String SYNC_EXECUTOR = "syncExecutor";
    
    /**
    * @return synchronous thread pool
    */
    @RefreshScope
    @Bean(SYNC_EXECUTOR)
    public ThreadPoolTaskExecutor serviceExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(executorProperties.getSync().getCorePoolSize());
        executor.setMaxPoolSize(executorProperties.getSync().getMaxPoolSize());
        executor.setQueueCapacity(executorProperties.getSync().getQueueCapacity());
        executor.setKeepAliveSeconds((int)executorProperties.getSync()
                                     .getKeepAlive().getSeconds());
        executor.setThreadNamePrefix("executor-sync-service-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(executorProperties.getSync()
                                            .getAwaitTerminationSeconds());
        return executor;
    }
    
    /**
     * Default executor for @Async annotation
     * @return asynchronous processing thread pool
     */
    @RefreshScope
    @Bean(ASYNC_EXECUTOR)
	public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(executorProperties.getAsync().getCorePoolSize());
        executor.setMaxPoolSize(executorProperties.getAsync().getMaxPoolSize());
        executor.setQueueCapacity(executorProperties.getAsync().getQueueCapacity());
        executor.setKeepAliveSeconds((int)executorProperties.getAsync()
                                     .getKeepAlive().getSeconds());
        executor.setThreadNamePrefix("common-async-executor-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(executorProperties.getAsync()
                                            .getAwaitTerminationSeconds());
        return executor;
    }
}
```

#### 3. Monitoring Metrics

Combining the core thread pool parameters with the operational metrics that matter for production, here are the gauges to expose:

* Core pool size
* Max pool size
* Active thread count
* Current pool size
* Queued task count
* Completed task count

 ```java
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Metrics;

@Component
public class ExecutorMetricsSupport implements InitializingBean {
    
    /**
    * Prometheus metric collection registry
    */
    @Resource
    private MeterRegistry meterRegistry;
    
    @Autowired
    @Qualifier(SYNC_EXECUTOR)
    private ThreadPoolTaskExecutor syncExecutor;
    
    @Autowired
    @Qualifier(ASYNC_EXECUTOR)
    private ThreadPoolTaskExecutor asyncExecutor;
    
    @Override
    public void afterPropertiesSet() throws Exception {
        initServiceExecutorMetrics(syncExecutor, "executor.sync");
        initServiceExecutorMetrics(asyncExecutor, "executor.async");
    }

    /**
     * Register thread pool metrics
     * @param serviceExecutor the thread pool
     * @param namePrefix metric name prefix
     */
    private void initServiceExecutorMetrics(ThreadPoolTaskExecutor serviceExecutor, String namePrefix) {
        Gauge
            .builder(namePrefix.concat(".active"),
                     serviceExecutor, ThreadPoolTaskExecutor::getActiveCount)
            .register(meterRegistry);
        
        Gauge
            .builder(namePrefix.concat(".core"),
                     serviceExecutor, ThreadPoolTaskExecutor::getCorePoolSize)
            .register(meterRegistry);
        
        Gauge
            .builder(namePrefix.concat(".max"),
                      serviceExecutor, ThreadPoolTaskExecutor::getMaxPoolSize)
            .register(meterRegistry);
        
        Gauge
            .builder(namePrefix.concat(".pool"),
                     serviceExecutor, ThreadPoolTaskExecutor::getPoolSize)
            .register(meterRegistry);
        
        Gauge
            .builder(namePrefix.concat(".queue"), serviceExecutor,
                     executor -> executor.getThreadPoolExecutor().getQueue().size())
            .register(meterRegistry);
        
        Gauge
            .builder(namePrefix.concat(".completetask"), serviceExecutor,
                     executor -> executor.getThreadPoolExecutor().getCompletedTaskCount())
            .register(meterRegistry);
    }
}
 ```

#### 4. Metric Analysis

These metrics are visualized in Grafana via Prometheus. Prometheus defaults to a 15-second scrape interval, but for something as volatile as a thread pool, 10 seconds gives a more responsive and accurate picture.

* Async thread pool

![dDNE9g.png](https://s1.ax1x.com/2020/08/24/dDNE9g.png)

* Sync thread pool

[![dDN6vd.png](https://s1.ax1x.com/2020/08/24/dDN6vd.png)](https://imgchr.com/i/dDN6vd)

The monitoring data tells a clear story:

* The async pool is lightly loaded — no queue backlog has ever appeared, and both the core and max thread counts could be reduced.
* The sync pool configuration is well-tuned: non-core threads were never activated during peak load, the queued task count stayed within a reasonable range, and request processing throughput remained high.
