---
title: Spring Batch 监听器
date: 2022-02-02 23:59:25
tags: Spring
categories: 后端
---

-----

#### 一、Spring Batch 监听器

在批处理过程中，需要对一些关键节点，如启动、结束、抛异常等，添加额外的处理。关注节点，需要借助 Spring Batch 监听器。Spring Batch 提供了两个维度的监听器：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/12_20_43_8_objects.png)

**Job 层面：**

* `JobExecutionListener`: 在 Job 执行之前（beforeJob）、之后（afterJob）触发；

**Step 层面:**

* `ChunkListener`: 在 Chunk 执行之前（beforeChunk）、之后（afterChunk）和异常后（afterChunkError）触发；
* `StepExecutionListener`: 在 Step 执行之前（beforeStep）、之后（afterStep）触发；
* `ItemReadListener`: 在 Read 执行之前（beforeRead）、之后（afterRead）和异常时（onReadError）触发；
* `ItemProcessListener`: 在 Process 执行之前（beforeProcess）、之后（afterProcess）和异常时（onProcessError）触发；
* `ItemWriteListener`: 在 Write 执行之前（beforeWrite）、之后（afterWrite）和异常时（onWriteError）触发；

#### 二、简单使用

将文件 `ticket.cvs` 中的内容，打印出来：

```cvs
合肥,蚌埠,60.00
南京,蚌埠,70.00
上海,蚌埠,220.00
上海,杭州,75.20
上海,昆山,19.00
```

实体类：

```java
import lombok.Data;
import java.math.BigDecimal;

@Data
public class Ticket {

    /**
     * 始发站
     */
    private String departureStation;

    /**
     * 到达站
     */
    private String arrivalStation;

    /**
     * 票价
     */
    private BigDecimal price;

    @Override
    public String toString() {
        return String.format("始发站: %s; 到达站: %s; 票价: %s", departureStation, arrivalStation, price);
    }
}
```

```java
/**
 * Job
 */
@Bean
public Job testListenerJob() {
    return jobBuilderFactory.get("testListenerJob")
        .incrementer(new RunIdIncrementer())
        // job 监听器
        .listener(testJobListener)
        .flow(testListenerStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testListenerStep")
public Step testListenerStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testListenerStep")
        // step 监听器
        .listener(testStepListener)
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(2)
        .faultTolerant()
        // chunk 监听器
        .listener(testChunkListener)
        .reader(ticketFileItemReader)
        // read 监听器
        .listener(testReadListener)
        .processor(ticketItemProcessor)
        // process 监听器
        .listener(testProcessListener)
        .writer(list -> list.forEach(System.out::println))
        // write 监听器
        .listener(testWriteListener)
        .build();
}

/**
 * Reader
 */
public FlatFileItemReader<Ticket> ticketFileItemReader() {
    return new FlatFileItemReaderBuilder<Ticket>()
        .name("ticketFileItemReader")
        .resource(new ClassPathResource("ticket.csv"))
        .delimited()
        .names(new String[]{"departureStation", "arrivalStation", "price"})
        .fieldSetMapper(new BeanWrapperFieldSetMapper<Ticket>() {{
            setTargetType(Ticket.class);
        }})
        .build();
}

/**
 * Processor
 */
@Component
public class TicketItemProcessor implements ItemProcessor<Ticket, Ticket> {

    private static final Logger log = LoggerFactory.getLogger(TicketItemProcessor.class);

    @Override
    public Ticket process(final Ticket ticketSource) throws Exception {

        final String departureStation = ticketSource.getDepartureStation();
        final String arrivalStation = ticketSource.getArrivalStation();
        final BigDecimal price = ticketSource.getPrice();

        final Ticket ticketTarget = new Ticket();
        ticketTarget.setDepartureStation(departureStation);
        ticketTarget.setArrivalStation(arrivalStation);
        ticketTarget.setPrice(price);

        return ticketTarget;
    }
}
```

```java
/**
 * Job Listener
 */
@Component
public class TestJobListener extends JobExecutionListenerSupport {

    private static final Logger log = LoggerFactory.getLogger(TestJobListener.class);

    @Override
    public void beforeJob(JobExecution jobExecution) {
        log.info("before job: {}", jobExecution.getJobInstance().getJobName());
    }

    @Override
    public void afterJob(JobExecution jobExecution) {
        log.info("after job: {}", jobExecution.getJobInstance().getJobName());
    }
}

/**
 * Chunk Listener
 */
@Component
public class TestChunkListener extends ChunkListenerSupport {

    private static final Logger log = LoggerFactory.getLogger(TestChunkListener.class);

    @Override
    public void beforeChunk(ChunkContext context) {
        log.info("before chunk: {}", context.getStepContext().getStepName());
    }

    @Override
    public void afterChunk(ChunkContext context) {
        log.info("after chunk: {}", context.getStepContext().getStepName());
    }

    @Override
    public void afterChunkError(ChunkContext context) {
        log.info("after chunk error: {}", context.getStepContext().getStepName());
    }
}

/**
 * Read Listener
 */
@Component
public class TestReadListener implements ItemReadListener<Ticket> {

    private static final Logger log = LoggerFactory.getLogger(TestReadListener.class);

    @Override
    public void beforeRead() {
        log.info("before read");
    }

    @Override
    public void afterRead(Ticket item) {
        log.info("after read: {}", item);
    }

    @Override
    public void onReadError(Exception ex) {
        log.info("read item error: {}", ex.getMessage(), ex);
    }
}

/**
 * Process Listener
 */
@Component
public class TestProcessListener implements ItemProcessListener<Ticket, Ticket> {

    private static final Logger log = LoggerFactory.getLogger(TestProcessListener.class);

    @Override
    public void beforeProcess(Ticket item) {
        log.info("before process: {}", item);

    }

    @Override
    public void afterProcess(Ticket item, Ticket result) {
        log.info("after process: {}", item);
    }

    @Override
    public void onProcessError(Ticket item, Exception e) {
        log.info("process: {} error: {}", item, e.getMessage(), e);
    }
}

/**
 * Write Listener
 */
@Component
public class TestWriteListener implements ItemWriteListener<Ticket> {

    private static final Logger log = LoggerFactory.getLogger(TestWriteListener.class);

    @Override
    public void beforeWrite(List<? extends Ticket> items) {
        log.info("before write: {}", items);
    }

    @Override
    public void afterWrite(List<? extends Ticket> items) {
        log.info("after write: {}", items);
    }

    @Override
    public void onWriteError(Exception exception, List<? extends Ticket> items) {
        log.info("write item error: {}", exception.getMessage(), exception);
    }
}
```

启动应用，打印日志：

```java
2022-06-12 19:31:13.774  INFO 33680 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testListenerJob]] launched with the following parameters: [{run.id=4}]
2022-06-12 19:31:13.820  INFO 33680 --- [restartedMain] c.e.s.c.listener.job.TestJobListener     : before job: testListenerJob
2022-06-12 19:31:13.858  INFO 33680 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testListenerStep]
2022-06-12 19:31:13.867  INFO 33680 --- [restartedMain] c.e.s.c.listener.step.TestStepListener   : before step: testListenerStep
2022-06-12 19:31:13.889  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : before chunk: testListenerStep
2022-06-12 19:31:13.891  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.905  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: 始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
2022-06-12 19:31:13.906  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.907  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: 始发站: 南京; 到达站: 蚌埠; 票价: 70.00
2022-06-12 19:31:13.911  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: 始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
2022-06-12 19:31:13.912  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: 始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
2022-06-12 19:31:13.912  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: 始发站: 南京; 到达站: 蚌埠; 票价: 70.00
2022-06-12 19:31:13.912  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: 始发站: 南京; 到达站: 蚌埠; 票价: 70.00
2022-06-12 19:31:13.913  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : before write: [始发站: 合肥; 到达站: 蚌埠; 票价: 60.00, 始发站: 南京; 到达站: 蚌埠; 票价: 70.00]
始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
始发站: 南京; 到达站: 蚌埠; 票价: 70.00
2022-06-12 19:31:13.914  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : after write: [始发站: 合肥; 到达站: 蚌埠; 票价: 60.00, 始发站: 南京; 到达站: 蚌埠; 票价: 70.00]
2022-06-12 19:31:13.928  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : after chunk: testListenerStep
2022-06-12 19:31:13.929  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : before chunk: testListenerStep
2022-06-12 19:31:13.929  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.930  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: 始发站: 上海; 到达站: 蚌埠; 票价: 220.00
2022-06-12 19:31:13.930  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: 始发站: 上海; 到达站: 杭州; 票价: 75.20
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: 始发站: 上海; 到达站: 蚌埠; 票价: 220.00
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: 始发站: 上海; 到达站: 蚌埠; 票价: 220.00
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: 始发站: 上海; 到达站: 杭州; 票价: 75.20
2022-06-12 19:31:13.932  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: 始发站: 上海; 到达站: 杭州; 票价: 75.20
2022-06-12 19:31:13.932  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : before write: [始发站: 上海; 到达站: 蚌埠; 票价: 220.00, 始发站: 上海; 到达站: 杭州; 票价: 75.20]
始发站: 上海; 到达站: 蚌埠; 票价: 220.00
始发站: 上海; 到达站: 杭州; 票价: 75.20
2022-06-12 19:31:13.932  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : after write: [始发站: 上海; 到达站: 蚌埠; 票价: 220.00, 始发站: 上海; 到达站: 杭州; 票价: 75.20]
2022-06-12 19:31:13.943  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : after chunk: testListenerStep
2022-06-12 19:31:13.944  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : before chunk: testListenerStep
2022-06-12 19:31:13.944  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: 始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: 始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: 始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-12 19:31:13.946  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : before write: [始发站: 上海; 到达站: 昆山; 票价: 19.00]
始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-12 19:31:13.946  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : after write: [始发站: 上海; 到达站: 昆山; 票价: 19.00]
2022-06-12 19:31:13.959  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : after chunk: testListenerStep
2022-06-12 19:31:13.959  INFO 33680 --- [restartedMain] c.e.s.c.listener.step.TestStepListener   : after step: testListenerStep
2022-06-12 19:31:13.962  INFO 33680 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testListenerStep] executed in 104ms
2022-06-12 19:31:13.978  INFO 33680 --- [restartedMain] c.e.s.c.listener.job.TestJobListener     : after job: testListenerJob
2022-06-12 19:31:13.997  INFO 33680 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testListenerJob]] completed with the following parameters: [{run.id=4}] and the following status: [COMPLETED] in 178ms
```

从日志可以看出：

* Job 、Step 监听器贯穿任务的始终；

* 每一个 chunk 中，执行 2 次读、2 次处理、1 次写；
* 每一次 read 过程，触发 beforeRead()、afterRead()；
* 每一次 process 过程，触发  beforeProcess()、afterProcess()；
* 每一次 write 过程，触发 beforeWrite()、afterWrite()；



示例代码：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)

