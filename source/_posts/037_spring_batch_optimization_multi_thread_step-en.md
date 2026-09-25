---
title: Spring Batch Performance Tuning — Multi-Threaded Steps
date: 2022-02-04 01:28:45
tags: Spring
categories: Backend
lang: en
label: 037_spring_batch_optimization_multi_thread_step
---

-----

<!-- more -->
#### 1. Spring Batch Performance Optimization Overview

Spring Batch is a highly scalable batch processing framework that handles everything from simple scheduled tasks to complex, high-volume data pipelines. For performance, the framework offers several optimization strategies:

* Multi-threaded `Step`: each chunk is read, processed, and written by a thread from a pool;
* [Parallel `Step`](https://takeshell.com/2022/02/08/spring_batch_optimization_parallel_step/): independent steps run concurrently on separate threads;
* [Partitioned `Step`](https://takeshell.com/2022/02/15/spring_batch_optimization_partition_step/): a step is split into partitions, each processed independently;
* Remote chunking: offloads processing and writing to remote workers when the read side is not the bottleneck;

See the [Spring documentation](https://docs.spring.io/spring-batch/docs/current/reference/html/scalability.html#scalability) for the full picture.

#### 2. Configuring a Multi-Threaded Step

Spring Batch processes a step in chunks. In a multi-threaded step, each chunk gets dispatched to a thread pool instead of being processed sequentially. This eliminates the serial wait between chunks and can significantly improve throughput.

Setting up a multi-threaded step is straightforward. Here is the Java config approach:

```java
@Bean
public Step sampleStep(TaskExecutor taskExecutor) {
    return this.stepBuilderFactory.get("sampleStep")
        .<String, String>chunk(10)
        .reader(itemReader())
        .writer(itemWriter())
        .taskExecutor(taskExecutor)
        // Throttle limit — should not exceed the thread pool's max pool size
        .throttleLimit(20)
        .build();
}
```

There are a few things to keep in mind when configuring a multi-threaded step:

* Thread pool: Spring's `ThreadPoolTaskExecutor` is the recommended choice for its compatibility with the framework;
* Thread safety: both the `ItemReader` and `ItemWriter` must be thread-safe. A non-thread-safe reader can cause duplicate reads or dirty data;
* Throttle limit: Spring Batch defaults to a throttle limit of 4, which caps concurrent chunk processing. You'll almost certainly want to raise this to match your thread pool size;

#### 3. Batch Job Configuration

The example below migrates 1 million rows through a Spring Batch job.

##### 3.1 Item Reader

```java
import com.example.springbatchdemo.component.reader.rowmapper.StudentRowMapper;
import com.example.springbatchdemo.entity.Student;
import org.springframework.batch.item.database.JdbcPagingItemReader;
import org.springframework.batch.item.database.Order;
import org.springframework.batch.item.database.builder.JdbcPagingItemReaderBuilder;
import org.springframework.batch.item.database.support.MySqlPagingQueryProvider;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import javax.sql.DataSource;
import java.util.HashMap;
import java.util.Map;

@Configuration
public class CustomItemReader {

    @Autowired
    @Qualifier(value = "batchDemoDB")
    private DataSource batchDemoDB;

    @Bean("studentItemReader")
    public JdbcPagingItemReader<Student> studentItemReader() {

        MySqlPagingQueryProvider queryProvider = new MySqlPagingQueryProvider();
        queryProvider.setSelectClause("student_id, name, address");
        queryProvider.setFromClause("from student_source");

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

##### 3.2 Row Mapper

```java
import com.example.springbatchdemo.entity.Student;
import org.springframework.jdbc.core.RowMapper;
import java.sql.ResultSet;
import java.sql.SQLException;

public class StudentRowMapper implements RowMapper<Student> {

    @Override
    public Student mapRow(ResultSet rs, int rowNum) throws SQLException {
        Student student = new Student();
        student.setStudentId(rs.getLong("student_id"));
        student.setName(rs.getString("name"));
        student.setAddress(rs.getString("address"));
        return student;
    }
}
```

##### 3.3 Item Processor

```java
import com.example.springbatchdemo.entity.Student;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;

@Configuration
public class StudentItemProcessor implements ItemProcessor<Student, Student> {

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

##### 3.4 Item Writer

```java
import com.example.springbatchdemo.entity.Student;
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

    @Bean("studentItemWriter")
    public JdbcBatchItemWriter<Student> studentItemWriter() {

        return new JdbcBatchItemWriterBuilder<Student>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("INSERT INTO student_target (student_id, name, address) VALUES (:studentId, :name, :address)")
                .dataSource(batchDemoDB)
                .build();
    }
}
```

##### 3.5 Step Configuration — Single Thread

```java
import com.example.springbatchdemo.component.processor.StudentItemProcessor;
import com.example.springbatchdemo.entity.Student;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.StepBuilderFactory;
import org.springframework.batch.item.database.JdbcBatchItemWriter;
import org.springframework.batch.item.database.JdbcPagingItemReader;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class BatchProcessStudentStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "studentItemReader")
    private JdbcPagingItemReader<Student> studentItemReader;

    @Autowired
    @Qualifier(value = "studentItemWriter")
    private JdbcBatchItemWriter<Student> studentItemWriter;

    @Autowired
    private StudentItemProcessor studentItemProcessor;

    @Bean("batchProcessStudentStep1")
    public Step step1() {
        return stepBuilderFactory.get("step1")
                .<Student, Student>chunk(2000)
                .reader(studentItemReader)
                .processor(studentItemProcessor)
                .writer(studentItemWriter)
                .build();
    }
}
```

##### 3.6 Step Configuration — Multi-Thread

```java
import com.example.springbatchdemo.component.processor.StudentItemProcessor;
import com.example.springbatchdemo.entity.Student;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.StepBuilderFactory;
import org.springframework.batch.item.database.JdbcBatchItemWriter;
import org.springframework.batch.item.database.JdbcPagingItemReader;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import static com.example.springbatchdemo.config.ExecutorConfig.TASK_EXECUTOR;

@Configuration
public class BatchProcessStudentStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "studentItemReader")
    private JdbcPagingItemReader<Student> studentItemReader;

    @Autowired
    @Qualifier(value = "studentItemWriter")
    private JdbcBatchItemWriter<Student> studentItemWriter;

    @Autowired
    private StudentItemProcessor studentItemProcessor;

    @Autowired
    @Qualifier(value = TASK_EXECUTOR)
    private ThreadPoolTaskExecutor taskExecutor;

    @Bean("batchProcessStudentStep1")
    public Step step1() {
        return stepBuilderFactory.get("step1")
                .<Student, Student>chunk(2000)
                .reader(studentItemReader)
                .processor(studentItemProcessor)
                .writer(studentItemWriter)
                .taskExecutor(taskExecutor)
                .throttleLimit(30)
                .build();
    }
}
```

##### 3.7 Job Configuration

```java
import com.example.springbatchdemo.component.listener.BatchProcessStudentCompletionListener;
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
public class BatchProcessStudentJob {

    @Autowired
    public JobBuilderFactory jobBuilderFactory;

    @Autowired
    @Qualifier(value = "batchProcessStudentStep1")
    private Step batchProcessStudentStep1;

    @Autowired
    private BatchProcessStudentCompletionListener batchProcessStudentCompletionListener;

    @Bean
    public Job transferStudentJob() {
        return jobBuilderFactory.get("transferStudentJob")
                .incrementer(new RunIdIncrementer())
                .listener(batchProcessStudentCompletionListener)
                .flow(batchProcessStudentStep1)
                .end()
                .build();
    }
}
```

##### 3.8 MySQL Datasource Configuration

```java
import com.zaxxer.hikari.HikariDataSource;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.jdbc.DataSourceBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Primary;
import javax.sql.DataSource;

@Configuration
public class DataSourceConfig {

    @Primary
    @Bean(name = "batchDemoDB")
    // Datasource property prefix — adjust to match your application properties
    @ConfigurationProperties(prefix = "spring.datasource.batch-demo")
    public DataSource druidDataSource() {
        // Use HikariDataSource, the default in Spring Boot
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }
}
```

##### 3.9 Thread Pool Configuration

```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import java.util.concurrent.ThreadPoolExecutor;

@Configuration
public class ExecutorConfig {

    public static final String TASK_EXECUTOR = "taskExecutor";

    @Bean(TASK_EXECUTOR)
    public ThreadPoolTaskExecutor taskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(20);
        executor.setMaxPoolSize(30);
        executor.setQueueCapacity(10);
        executor.setKeepAliveSeconds(60);
        executor.setThreadNamePrefix("common-async-executor-");
        executor.setRejectedExecutionHandler(new ThreadPoolExecutor.CallerRunsPolicy());
        executor.setWaitForTasksToCompleteOnShutdown(true);
        executor.setAwaitTerminationSeconds(60);
        return executor;
    }
}
```

#### 4. Performance Test Results

##### 4.1 Single-Threaded Step

Migrating 1 million rows with a single-threaded step:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/2_15_30_43_single_thred_step_performance.png)

Total elapsed time: 313 seconds

##### 4.2 Multi-Threaded Step

Migrating the same 1 million rows with the multi-threaded step:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/2_15_42_8_multi_thred_step_performance.png)

Total elapsed time: 81 seconds



---

Performance improvement: over **300%**

#### 5. Summary

Dispatching chunks to a thread pool is one of the simplest ways to speed up a Spring Batch job. The configuration is minimal — add a `TaskExecutor` and raise the throttle limit. Multi-threading does introduce concurrency concerns though. The reader and writer must be thread-safe, and you need to understand how Spring Batch manages chunk-level transactions to avoid duplicate processing or dirty data.

Sample code: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)