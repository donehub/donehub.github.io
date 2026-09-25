---
title: Spring Batch Listeners
date: 2022-02-02 23:59:25
lang: en
label: 034_spring_batch_listeners
tags: Spring
categories: Backend
---

-----

<!-- more -->
#### 1. Listener Overview

During batch execution, you often need to hook into key events like job start, job completion, and error handling. Spring Batch provides listeners for exactly this purpose, organized across two dimensions:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/12_20_43_8_objects.png)

**Job-level listeners:**

* `JobExecutionListener`: fires before the job starts (`beforeJob`) and after it finishes (`afterJob`);

**Step-level listeners:**

* `ChunkListener`: fires before a chunk executes (`beforeChunk`), after it completes (`afterChunk`), and after a chunk error (`afterChunkError`);
* `StepExecutionListener`: fires before the step starts (`beforeStep`) and after it finishes (`afterStep`);
* `ItemReadListener`: fires before reading (`beforeRead`), after reading (`afterRead`), and on read errors (`onReadError`);
* `ItemProcessListener`: fires before processing (`beforeProcess`), after processing (`afterProcess`), and on process errors (`onProcessError`);
* `ItemWriteListener`: fires before writing (`beforeWrite`), after writing (`afterWrite`), and on write errors (`onWriteError`);

#### 2. Usage Example

The example reads the contents of a `ticket.csv` file and prints each record:

```cvs
Hefei,Bengbu,60.00
Nanjing,Bengbu,70.00
Shanghai,Bengbu,220.00
Shanghai,Hangzhou,75.20
Shanghai,Kunshan,19.00
```

Entity class:

```java
import lombok.Data;
import java.math.BigDecimal;

@Data
public class Ticket {

    /**
     * Departure station
     */
    private String departureStation;

    /**
     * Arrival station
     */
    private String arrivalStation;

    /**
     * Ticket price
     */
    private BigDecimal price;

    @Override
    public String toString() {
        return String.format("Departure: %s; Arrival: %s; Price: %s", departureStation, arrivalStation, price);
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
        // job listener
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
        // step listener
        .listener(testStepListener)
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(2)
        .faultTolerant()
        // chunk listener
        .listener(testChunkListener)
        .reader(ticketFileItemReader)
        // read listener
        .listener(testReadListener)
        .processor(ticketItemProcessor)
        // process listener
        .listener(testProcessListener)
        .writer(list -> list.forEach(System.out::println))
        // write listener
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

Start the application. The log output:

```java
2022-06-12 19:31:13.774  INFO 33680 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testListenerJob]] launched with the following parameters: [{run.id=4}]
2022-06-12 19:31:13.820  INFO 33680 --- [restartedMain] c.e.s.c.listener.job.TestJobListener     : before job: testListenerJob
2022-06-12 19:31:13.858  INFO 33680 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testListenerStep]
2022-06-12 19:31:13.867  INFO 33680 --- [restartedMain] c.e.s.c.listener.step.TestStepListener   : before step: testListenerStep
2022-06-12 19:31:13.889  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : before chunk: testListenerStep
2022-06-12 19:31:13.891  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.905  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: Departure: Hefei; Arrival: Bengbu; Price: 60.00
2022-06-12 19:31:13.906  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.907  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: Departure: Nanjing; Arrival: Bengbu; Price: 70.00
2022-06-12 19:31:13.911  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: Departure: Hefei; Arrival: Bengbu; Price: 60.00
2022-06-12 19:31:13.912  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: Departure: Hefei; Arrival: Bengbu; Price: 60.00
2022-06-12 19:31:13.912  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: Departure: Nanjing; Arrival: Bengbu; Price: 70.00
2022-06-12 19:31:13.912  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: Departure: Nanjing; Arrival: Bengbu; Price: 70.00
2022-06-12 19:31:13.913  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : before write: [Departure: Hefei; Arrival: Bengbu; Price: 60.00, Departure: Nanjing; Arrival: Bengbu; Price: 70.00]
Departure: Hefei; Arrival: Bengbu; Price: 60.00
Departure: Nanjing; Arrival: Bengbu; Price: 70.00
2022-06-12 19:31:13.914  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : after write: [Departure: Hefei; Arrival: Bengbu; Price: 60.00, Departure: Nanjing; Arrival: Bengbu; Price: 70.00]
2022-06-12 19:31:13.928  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : after chunk: testListenerStep
2022-06-12 19:31:13.929  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : before chunk: testListenerStep
2022-06-12 19:31:13.929  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.930  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: Departure: Shanghai; Arrival: Bengbu; Price: 220.00
2022-06-12 19:31:13.930  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: Departure: Shanghai; Arrival: Bengbu; Price: 220.00
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: Departure: Shanghai; Arrival: Bengbu; Price: 220.00
2022-06-12 19:31:13.931  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
2022-06-12 19:31:13.932  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
2022-06-12 19:31:13.932  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : before write: [Departure: Shanghai; Arrival: Bengbu; Price: 220.00, Departure: Shanghai; Arrival: Hangzhou; Price: 75.20]
Departure: Shanghai; Arrival: Bengbu; Price: 220.00
Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
2022-06-12 19:31:13.932  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : after write: [Departure: Shanghai; Arrival: Bengbu; Price: 220.00, Departure: Shanghai; Arrival: Hangzhou; Price: 75.20]
2022-06-12 19:31:13.943  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : after chunk: testListenerStep
2022-06-12 19:31:13.944  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : before chunk: testListenerStep
2022-06-12 19:31:13.944  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : after read: Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.reader.TestReadListener        : before read
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : before process: Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-12 19:31:13.945  INFO 33680 --- [restartedMain] c.e.s.c.l.processor.TestProcessListener  : after process: Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-12 19:31:13.946  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : before write: [Departure: Shanghai; Arrival: Kunshan; Price: 19.00]
Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-12 19:31:13.946  INFO 33680 --- [restartedMain] c.e.s.c.l.writer.TestWriteListener       : after write: [Departure: Shanghai; Arrival: Kunshan; Price: 19.00]
2022-06-12 19:31:13.959  INFO 33680 --- [restartedMain] c.e.s.c.l.chunk.TestChunkListener        : after chunk: testListenerStep
2022-06-12 19:31:13.959  INFO 33680 --- [restartedMain] c.e.s.c.listener.step.TestStepListener   : after step: testListenerStep
2022-06-12 19:31:13.962  INFO 33680 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testListenerStep] executed in 104ms
2022-06-12 19:31:13.978  INFO 33680 --- [restartedMain] c.e.s.c.listener.job.TestJobListener     : after job: testListenerJob
2022-06-12 19:31:13.997  INFO 33680 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testListenerJob]] completed with the following parameters: [{run.id=4}] and the following status: [COMPLETED] in 178ms
```

The log output confirms this behavior:

* Job and Step listeners span the entire lifecycle of the task;

* Each chunk performs 2 reads, 2 processes, and 1 write (since the chunk size is 2);
* Every read triggers `beforeRead()` and `afterRead()`;
* Every process triggers `beforeProcess()` and `afterProcess()`;
* Every write triggers `beforeWrite()` and `afterWrite()`;



Sample code: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)
