---
title: Spring Batch Performance Tuning — Partitioned Steps
date: 2022-02-15 09:28:35
tags: Spring
categories: Backend
lang: en
label: 039_spring_batch_optimization_partition_step
---

-----

<!-- more -->
#### 1. Spring Batch Performance Optimization Overview

Spring Batch is a highly scalable batch processing framework that handles everything from simple scheduled tasks to complex, high-volume data pipelines. For performance, the framework offers several optimization strategies:

* [Multi-threaded `Step`](https://takeshell.com/2022/02/04/spring_batch_optimization_multi_thread_step/): each chunk is read, processed, and written by a thread from a pool;
* [Parallel `Step`](https://takeshell.com/2022/02/08/spring_batch_optimization_parallel_step/): independent steps run concurrently on separate threads;
* Partitioned `Step`: a step is split into partitions, each processed independently;
* Remote chunking: offloads processing and writing to remote workers when the read side is not the bottleneck;

See the [Spring documentation](https://docs.spring.io/spring-batch/docs/current/reference/html/scalability.html#scalability) for the full picture.

#### 2. Partitioned Steps

When a single step has a large volume of work, splitting it into partitions can dramatically reduce execution time. Each partition processes a slice of the data independently, and the partitions can run in parallel without interfering with each other. As a rough illustration: if a monolithic step takes 100 seconds to migrate 100,000 rows, splitting it into 100 partitions of 1,000 rows each could bring that down to around 1 second.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_20_41_39_partition_step_2.png)

The partitioning model uses a master-slave pattern. A master step coordinates the work and delegates to multiple slave handlers. The slaves can be local threads or remote services. Communication between master and slave does not need to be persisted or strictly guaranteed, because the `JobRepository` tracks each slave's execution independently in the `batch_step_execution` table. This metadata management ensures that each slave partition runs exactly once.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_53_13_partition_step_structure.png)

Two components are central to step partitioning: the `Partitioner` and the `PartitionHandler`.

* Partitioner: assigns an `ExecutionContext` (a set of key-value parameters) to each slave partition;
* PartitionHandler: defines how many slaves to create and what step each slave executes;

In a data migration scenario, the partition handler splits one master task into 100 slave tasks and specifies which step each slave runs. The partitioner then determines the data range for each slave — for example, `SELECT * FROM table WHERE id BETWEEN ? AND ?`.

#### 3. Batch Job Configuration

##### 3.1 Job Configuration

```java
import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.EnableBatchProcessing;
import org.springframework.batch.core.configuration.annotation.JobBuilderFactory;
import org.springframework.batch.core.launch.support.RunIdIncrementer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableBatchProcessing
public class PartitionTransferStudentJob {

    @Autowired
    public JobBuilderFactory jobBuilderFactory;

    @Autowired
    @Qualifier(value = "masterTransferStudentStep1")
    private Step masterTransferStudentStep;

    @Bean
    public Job transferStudentJob() {
        return jobBuilderFactory.get("partitionTransferStudentJob")
                .incrementer(new RunIdIncrementer())
                .flow(masterTransferStudentStep)
                .end()
                .build();
    }
}
```

##### 3.2 Step Configuration

`MasterTransferStudentStep` — the coordinator step:

```java
import com.example.springbatchdemo.component.partitioner.TransferStudentPartitioner;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.StepBuilderFactory;
import org.springframework.batch.core.partition.PartitionHandler;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration
public class MasterTransferStudentStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "transferStudentPartitionHandler1")
    private PartitionHandler transferStudentPartitionHandler;

    @Autowired
    private TransferStudentPartitioner transferStudentPartitioner;

    @Bean("masterTransferStudentStep1")
    public Step masterTransferStudentStep1(PlatformTransactionManager transactionManager) {
        return stepBuilderFactory.get("masterTransferStudentStep1.manager")
                .partitioner("masterTransferStudentStep1", transferStudentPartitioner)
                .partitionHandler(transferStudentPartitionHandler)
                .build();
    }
}
```

`SlaveTransferStudentStep` — the worker step that each partition executes:

```java
import com.example.springbatchdemo.component.processor.SlaveStudentItemProcessor;
import com.example.springbatchdemo.entity.Student;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.StepBuilderFactory;
import org.springframework.batch.item.database.JdbcBatchItemWriter;
import org.springframework.batch.item.database.JdbcPagingItemReader;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.transaction.PlatformTransactionManager;

@Configuration
public class SlaveTransferStudentStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "slaveTransferStudentItemReader")
    private JdbcPagingItemReader<Student> slaveTransferStudentItemReader;

    @Autowired
    @Qualifier(value = "slaveTransferStudentItemWriter")
    private JdbcBatchItemWriter<Student> slaveTransferStudentItemWriter;

    @Autowired
    private SlaveStudentItemProcessor slaveStudentItemProcessor;


    @Bean("slaveTransferStudentStep1")
    public Step slaveTransferStudentStep1(PlatformTransactionManager transactionManager) {
        return stepBuilderFactory.get("slaveTransferStudentStep1")
                .transactionManager(transactionManager)
                .<Student, Student>chunk(1000)
                .reader(slaveTransferStudentItemReader)
                .processor(slaveStudentItemProcessor)
                .writer(slaveTransferStudentItemWriter)
                .build();
    }
}
```

##### 3.3 Partitioner Configuration

```java
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.core.partition.support.Partitioner;
import org.springframework.batch.item.ExecutionContext;
import org.springframework.context.annotation.Configuration;
import java.util.HashMap;
import java.util.Map;

@Configuration
public class TransferStudentPartitioner implements Partitioner {

    private static final Logger LOGGER = LoggerFactory.getLogger(TransferStudentPartitioner.class);

    @Override
    public Map<String, ExecutionContext> partition(int gridSize) {

        Map<String, ExecutionContext> result = new HashMap<>(gridSize);

        int range = 1000;
        int fromId = 0;
        int toId = range;

        for (int i = 1; i <= gridSize; i++) {

            ExecutionContext value = new ExecutionContext();

            value.putInt("fromId", fromId);
            value.putInt("toId", toId);

            result.put("partition" + i, value);

            fromId = toId;
            toId += range;

            LOGGER.info("partition{}; fromId: {}; toId: {}", i, fromId, toId);
        }

        return result;
    }
}
```

##### 3.4 PartitionHandler Configuration

```java
import org.springframework.batch.core.Step;
import org.springframework.batch.core.partition.PartitionHandler;
import org.springframework.batch.core.partition.support.TaskExecutorPartitionHandler;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import static com.example.springbatchdemo.config.ExecutorConfig.TASK_EXECUTOR;

@Configuration
public class TransferStudentPartitionHandler {

    @Autowired
    @Qualifier(value = TASK_EXECUTOR)
    private ThreadPoolTaskExecutor taskExecutor;

    @Autowired
    @Qualifier(value = "slaveTransferStudentStep1")
    private Step slaveTransferStudentStep;

    @Bean("transferStudentPartitionHandler1")
    public PartitionHandler transferStudentPartitionHandler1() {
        TaskExecutorPartitionHandler retVal = new TaskExecutorPartitionHandler();
        retVal.setTaskExecutor(taskExecutor);
        retVal.setStep(slaveTransferStudentStep);
        retVal.setGridSize(100);
        return retVal;
    }
}
```

##### 3.5 Item Reader

```java
import com.example.springbatchdemo.component.reader.rowmapper.StudentRowMapper;
import com.example.springbatchdemo.entity.Person;
import com.example.springbatchdemo.entity.Student;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.item.database.JdbcPagingItemReader;
import org.springframework.batch.item.database.Order;
import org.springframework.batch.item.database.builder.JdbcPagingItemReaderBuilder;
import org.springframework.batch.item.database.support.MySqlPagingQueryProvider;
import org.springframework.batch.item.file.FlatFileItemReader;
import org.springframework.batch.item.file.builder.FlatFileItemReaderBuilder;
import org.springframework.batch.item.file.mapping.BeanWrapperFieldSetMapper;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import javax.sql.DataSource;
import java.util.HashMap;
import java.util.Map;

@Configuration
public class CustomItemReader {

    @Autowired
    @Qualifier(value = "batchDemoDB")
    private DataSource batchDemoDB;

    @Bean("slaveTransferStudentItemReader")
    @StepScope
    public JdbcPagingItemReader<Student> slaveTransferStudentItemReader(
            @Value("#{stepExecutionContext[fromId]}") final Long fromId,
            @Value("#{stepExecutionContext[toId]}") final Long toId) {

        MySqlPagingQueryProvider queryProvider = new MySqlPagingQueryProvider();
        queryProvider.setSelectClause("student_id, name, address");
        queryProvider.setFromClause("from student_source");
        queryProvider.setWhereClause(String.format("where student_id > %s and student_id <= %s", fromId, toId));

        Map<String, Order> sortKeys = new HashMap<>(1);
        sortKeys.put("student_id", Order.ASCENDING);
        queryProvider.setSortKeys(sortKeys);

        return new JdbcPagingItemReaderBuilder<Student>()
                .name("studentItemReader")
                .dataSource(batchDemoDB)
                .fetchSize(1000)
                .rowMapper(new StudentRowMapper())
                .queryProvider(queryProvider)
                .build();
    }
}
```

##### 3.6 Item Processor

```java
import com.example.springbatchdemo.entity.Student;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;

@Configuration
@StepScope
public class SlaveStudentItemProcessor implements ItemProcessor<Student, Student> {

    private static final Logger log = LoggerFactory.getLogger(StudentItemProcessor.class);

    @Override
    public Student process(final Student studentSource) throws Exception {

        final Long studentId = studentSource.getStudentId();
        final String name = studentSource.getName();
        final String address = studentSource.getAddress();

        final Student studentTarget = new Student();
        studentTarget.setStudentId(studentId);
        studentTarget.setName(name);
        studentTarget.setAddress(address);

        log.info("Converting ({}) into ({})", studentSource, studentTarget);

        return studentTarget;
    }
}
```

##### 3.7 Item Writer

```java
import com.example.springbatchdemo.entity.Person;
import com.example.springbatchdemo.entity.Student;
import org.springframework.batch.core.configuration.annotation.StepScope;
import org.springframework.batch.item.database.BeanPropertyItemSqlParameterSourceProvider;
import org.springframework.batch.item.database.JdbcBatchItemWriter;
import org.springframework.batch.item.database.builder.JdbcBatchItemWriterBuilder;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import javax.sql.DataSource;

@Configuration
public class CustomItemWriter {

    @Autowired
    @Qualifier(value = "batchDemoDB")
    private DataSource batchDemoDB;

    @Bean("slaveTransferStudentItemWriter")
    @StepScope
    public JdbcBatchItemWriter<Student> slaveTransferStudentItemWriter() {

        return new JdbcBatchItemWriterBuilder<Student>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("INSERT INTO student_target (student_id, name, address) VALUES (:studentId, :name, :address)")
                .dataSource(batchDemoDB)
                .build();
    }
}
```

#### 4. Performance Test

Dataset: 100,000 rows

Environment: Windows 10, i7 8-core, MySQL 8.0.28

##### 4.1 Standard Step

Test code omitted — see the demo repository. Results:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_20_57_normal_step_transfer.png)

Elapsed time: **13s**

##### 4.2 Partitioned Step

Results:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_28_21_partition_step_performance.png)

The `batch_step_execution` table confirms 100 slave partitions ran in parallel, each migrating 1,000 rows.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_31_26_partition_step_performance_detail.png)

Elapsed time: **7s**



Sample code: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)