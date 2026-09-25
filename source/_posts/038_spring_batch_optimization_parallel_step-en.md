---
title: Spring Batch Performance Tuning — Parallel Steps
date: 2022-02-08 11:28:35
tags: Spring
categories: Backend
lang: en
label: 038_spring_batch_optimization_parallel_step
---

-----

<!-- more -->
#### 1. Spring Batch Performance Optimization Overview

Spring Batch is a highly scalable batch processing framework that handles everything from simple scheduled tasks to complex, high-volume data pipelines. For performance, the framework offers several optimization strategies:

* [Multi-threaded `Step`](https://takeshell.com/2022/02/04/spring_batch_optimization_multi_thread_step/): each chunk is read, processed, and written by a thread from a pool;
* Parallel `Step`: independent steps run concurrently on separate threads;
* [Partitioned `Step`](https://takeshell.com/2022/02/15/spring_batch_optimization_partition_step/): a step is split into partitions, each processed independently;
* Remote chunking: offloads processing and writing to remote workers when the read side is not the bottleneck;

See the [Spring documentation](https://docs.spring.io/spring-batch/docs/current/reference/html/scalability.html#scalability) for the full picture.

#### 2. Parallel Steps

A single job can contain multiple steps. Some of those steps may have dependencies — step B can't start until step A finishes. Others are completely independent and could run in any order. Running independent steps in parallel is a straightforward way to reduce overall job duration.

Consider a job with four steps:

* `step1`: append "1" to every student's name;
* `step2`: append "2" to every student's name;
* `step3`: append "8" to every student's address;
* `step4`: migrate all student records to the target table;

Steps 1–3 modify different fields and don't depend on each other. Step 4 depends on all three completing first. We can run steps 1, 2, and 3 in parallel, then execute step 4 after they all finish. The serial and parallel execution flows look like this:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/5_21_33_37_parallel_step_2.png)

#### 3. Batch Job Configuration

##### 3.1 Job Configuration

```java
import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.EnableBatchProcessing;
import org.springframework.batch.core.configuration.annotation.JobBuilderFactory;
import org.springframework.batch.core.job.flow.Flow;
import org.springframework.batch.core.launch.support.RunIdIncrementer;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableBatchProcessing
public class BatchManageStudentJob {

    @Autowired
    public JobBuilderFactory jobBuilderFactory;

    @Autowired
    @Qualifier(value = "batchProcessStudentSplitFlow1")
    private Flow batchProcessStudentSplitFlow;

    @Autowired
    @Qualifier(value = "batchTransferStudentStep1")
    private Step batchTransferStudentStep;

    @Bean
    public Job manageStudentJob() {
        return jobBuilderFactory.get("manageStudentJob1")
                .incrementer(new RunIdIncrementer())
            	// Run the parallel flow first: name append 1, name append 2, address append 8
                .start(batchProcessStudentSplitFlow)
            	// Then migrate student data: student_source -> student_target
                .next(batchTransferStudentStep)
                .end()
                .build();
    }
}
```

##### 3.2 Flow Configuration

`batchProcessStudentSplitFlow` — the split flow that runs three steps in parallel:

```java
import org.springframework.batch.core.job.builder.FlowBuilder;
import org.springframework.batch.core.job.flow.Flow;
import org.springframework.batch.core.job.flow.support.SimpleFlow;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import static com.example.springbatchdemo.config.ExecutorConfig.TASK_EXECUTOR;

@Configuration
public class BatchProcessStudentSplitFlow {

    @Autowired
    @Qualifier(value = TASK_EXECUTOR)
    private ThreadPoolTaskExecutor taskExecutor;

    @Autowired
    @Qualifier(value = "batchUpdateStudentNameOneAndTwoFlow")
    private Flow batchUpdateStudentNameOneAndTwoFlow;

    @Autowired
    @Qualifier(value = "batchUpdateStudentAddressFlow1")
    private Flow batchUpdateStudentAddressFlow;

    @Bean("batchProcessStudentSplitFlow1")
    public Flow batchProcessStudentSplitFlow1() {
        return new FlowBuilder<SimpleFlow>("batchProcessStudentSplitFlow1")
                .split(taskExecutor)
                .add(batchUpdateStudentNameOneAndTwoFlow, batchUpdateStudentAddressFlow)
                .build();
    }
}
```

`batchUpdateStudentNameOneAndTwoFlow` — runs name-append-1 then name-append-2 sequentially:

```java
import org.springframework.batch.core.Step;
import org.springframework.batch.core.job.builder.FlowBuilder;
import org.springframework.batch.core.job.flow.Flow;
import org.springframework.batch.core.job.flow.support.SimpleFlow;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class BatchUpdateStudentNameFlow {

    @Autowired
    @Qualifier(value = "batchUpdateStudentNameStep1")
    private Step batchUpdateStudentNameStep1;

    @Autowired
    @Qualifier(value = "batchUpdateStudentNameStep2")
    private Step batchUpdateStudentNameStep2;

    @Bean("batchUpdateStudentNameOneAndTwoFlow")
    public Flow updateStudentNameOneAndTwoFlow() {
        return new FlowBuilder<SimpleFlow>("batchUpdateStudentNameOneAndTwoFlow")
                .start(batchUpdateStudentNameStep1)
                .next(batchUpdateStudentNameStep2)
                .build();
    }
}
```

`batchUpdateStudentAddressFlow` — runs address-append as a single-step flow:

```java
import org.springframework.batch.core.Step;
import org.springframework.batch.core.job.builder.FlowBuilder;
import org.springframework.batch.core.job.flow.Flow;
import org.springframework.batch.core.job.flow.support.SimpleFlow;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class BatchUpdateStudentAddressFlow {

    @Autowired
    @Qualifier(value = "batchUpdateStudentAddressStep1")
    private Step batchUpdateStudentAddressStep;

    @Bean("batchUpdateStudentAddressFlow1")
    public Flow batchUpdateStudentAddressFlow1() {
        return new FlowBuilder<SimpleFlow>("batchUpdateStudentAddressFlow1")
                .start(batchUpdateStudentAddressStep)
                .build();
    }
}
```

##### 3.3 Step Configuration

`BatchUpdateStudentNameStep`:

```java
import com.example.springbatchdemo.component.processor.AppendStudentNameOneProcessor;
import com.example.springbatchdemo.component.processor.AppendStudentNameTwoProcessor;
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
public class BatchUpdateStudentNameStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "studentItemReader")
    private JdbcPagingItemReader<Student> studentItemReader;

    @Autowired
    @Qualifier(value = "studentItemUpdateName")
    private JdbcBatchItemWriter<Student> studentItemUpdateName;

    @Autowired
    private AppendStudentNameOneProcessor appendStudentNameOneProcessor;

    @Autowired
    private AppendStudentNameTwoProcessor appendStudentNameTwoProcessor;

    @Bean("batchUpdateStudentNameStep1")
    public Step batchUpdateStudentNameStep1() {
        return stepBuilderFactory.get("batchUpdateStudentNameStep1")
                .<Student, Student>chunk(1000)
                .reader(studentItemReader)
            	// Append "_1" to student name
                .processor(appendStudentNameOneProcessor)
                .writer(studentItemUpdateName)
                .build();
    }

    @Bean("batchUpdateStudentNameStep2")
    public Step batchUpdateStudentNameStep2() {
        return stepBuilderFactory.get("batchUpdateStudentNameStep2")
                .<Student, Student>chunk(1000)
                .reader(studentItemReader)
            	// Append "_2" to student name
                .processor(appendStudentNameTwoProcessor)
                .writer(studentItemUpdateName)
                .build();
    }
}
```

`BatchUpdateStudentAddressStep`:

```java
import com.example.springbatchdemo.component.processor.AppendStudentAddressProcessor;
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
public class BatchUpdateStudentAddressStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "studentItemReader")
    private JdbcPagingItemReader<Student> studentItemReader;

    @Autowired
    @Qualifier(value = "studentItemUpdateAddress")
    private JdbcBatchItemWriter<Student> studentItemUpdateAddress;

    @Autowired
    private AppendStudentAddressProcessor appendStudentAddressProcessor;

    @Bean("batchUpdateStudentAddressStep1")
    public Step batchUpdateStudentAddressStep1() {
        return stepBuilderFactory.get("batchUpdateStudentAddressStep1")
                .<Student, Student>chunk(1000)
                .reader(studentItemReader)
            	// Append "_8" to student address
                .processor(appendStudentAddressProcessor)
                .writer(studentItemUpdateAddress)
                .build();
    }
}
```

`BatchProcessStudentStep` — the final migration step:

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

    @Bean("batchTransferStudentStep1")
    public Step batchTransferStudentStep1() {
        return stepBuilderFactory.get("batchTransferStudentStep1")
                .<Student, Student>chunk(1000)
                .reader(studentItemReader)
            	// Migrate data: student_source -> student_target
                .processor(studentItemProcessor)
                .writer(studentItemWriter)
                .build();
    }
}
```

##### 3.4 Item Reader

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

    @Bean("studentItemReader")
    @StepScope
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

##### 3.5 Item Processors

`AppendStudentNameOneProcessor`:

```java
import com.example.springbatchdemo.entity.Student;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AppendStudentNameOneProcessor implements ItemProcessor<Student, Student> {

    private static final Logger log = LoggerFactory.getLogger(AppendStudentNameOneProcessor.class);

    @Override
    public Student process(final Student studentSource) throws Exception {

        final Long studentId = studentSource.getStudentId();
        final String name = studentSource.getName();
        final String address = studentSource.getAddress();

        final Student studentTarget = new Student();
        studentTarget.setStudentId(studentId);
        studentTarget.setName(name.concat("_1"));
        studentTarget.setAddress(address);

        log.info("Converting ({}) into ({})", studentSource, studentTarget);

        return studentTarget;
    }
}
```

`AppendStudentNameTwoProcessor`:

```java
import com.example.springbatchdemo.entity.Student;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AppendStudentNameTwoProcessor implements ItemProcessor<Student, Student> {

    private static final Logger log = LoggerFactory.getLogger(AppendStudentNameTwoProcessor.class);

    @Override
    public Student process(final Student studentSource) throws Exception {

        final Long studentId = studentSource.getStudentId();
        final String name = studentSource.getName();
        final String address = studentSource.getAddress();

        final Student studentTarget = new Student();
        studentTarget.setStudentId(studentId);
        studentTarget.setName(name.concat("_2"));
        studentTarget.setAddress(address);

        log.info("Converting ({}) into ({})", studentSource, studentTarget);

        return studentTarget;
    }
}
```

`AppendStudentAddressProcessor`:

```java
import com.example.springbatchdemo.entity.Student;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;

@Configuration
public class AppendStudentAddressProcessor implements ItemProcessor<Student, Student> {

    private static final Logger log = LoggerFactory.getLogger(AppendStudentAddressProcessor.class);

    @Override
    public Student process(final Student studentSource) throws Exception {

        final Long studentId = studentSource.getStudentId();
        final String name = studentSource.getName();
        final String address = studentSource.getAddress();

        final Student studentTarget = new Student();
        studentTarget.setStudentId(studentId);
        studentTarget.setName(name);
        studentTarget.setAddress(address.concat("_8"));

        log.info("Converting ({}) into ({})", studentSource, studentTarget);

        return studentTarget;
    }
}
```

`StudentItemProcessor` — used by the final migration step:

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

##### 3.6 Item Writers

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

    @Bean("studentItemWriter")
    public JdbcBatchItemWriter<Student> studentItemWriter() {

        return new JdbcBatchItemWriterBuilder<Student>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("INSERT INTO student_target (student_id, name, address) VALUES (:studentId, :name, :address)")
                .dataSource(batchDemoDB)
                .build();
    }

    @Bean("studentItemUpdateName")
    @StepScope
    public JdbcBatchItemWriter<Student> studentItemUpdateName() {

        return new JdbcBatchItemWriterBuilder<Student>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("UPDATE student_source SET name = :name WHERE student_id = :studentId")
                .dataSource(batchDemoDB)
                .build();
    }

    @Bean("studentItemUpdateAddress")
    public JdbcBatchItemWriter<Student> studentItemUpdateAddress() {

        return new JdbcBatchItemWriterBuilder<Student>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("UPDATE student_source SET address = :address WHERE student_id = :studentId")
                .dataSource(batchDemoDB)
                .build();
    }
}
```

>@StepScope:
>
>In the step configurations above, `studentItemReader` is referenced by multiple steps. By default, a reader's lifecycle is tied to the job — it gets opened once. When multiple steps share the same reader instance, the second step that tries to open it will throw:
>
>```java
>Caused by: java.lang.IllegalStateException: Cannot open an already opened ItemReader, call close first
>```
>
>Annotating the reader bean with `@StepScope` makes its lifecycle scoped to each step, so every step gets a fresh instance. The same applies to writers and processors that are shared across multiple steps.

#### 4. Performance Test

Dataset: 100,000 rows

Environment: Windows 10, i7 8-core, MySQL 8.0.28

##### 4.1 Serial Steps

Running all steps in sequence (code omitted for brevity). Results:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/8_12_36_15_serial_step_performance.png)

Elapsed time: **91s**

##### 4.2 Parallel Steps

Running the independent steps in parallel. Results:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/8_12_41_53_parallel_step_performance.png)

Elapsed time: **68s**



Sample code: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)