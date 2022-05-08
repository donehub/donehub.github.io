---
title: Spring Batch 性能调优-并行化Step
date: 2022-02-08 11:28:35
tags: Spring
categories: 后端
---

-----

#### 一、Spring Batch 性能优化指标

Spring Batch 是一款伸缩性非常好的批处理工具，既可以处理简单的任务，也可以处理复杂的、高容量的任务。在性能调优方面，Spring Batch 提供了丰富的接口支持，各项优化指标可归纳如下：

* [多线程 `Step`](https://takeshell.com/2022/02/04/spring_batch_optimization_multi_thread_step/)：由独立线程执行提交块（a chunk of items）的输入、处理和输出过程；
* 并行化 `Step`：对于可并行处理的 `Step`，交由不同的线程去处理；
* 分片化 `Step`：通过 `SPI(Serial Peripheral Interface)`，对 `Step` 分片执行；
* 远程组块：对于输入无性能瓶颈，但处理和输出有性能瓶颈的任务，交由远程组块执行；

详见[Spring文档](https://docs.spring.io/spring-batch/docs/current/reference/html/scalability.html#scalability)。

#### 二、并行化 `Step` 

一个 `Job` 可配置多个 `Step`，`Step` 之间可能存在关联，需要有先有后；也可能没有关联，先执行哪一个都可以。那么，若将这些互不关联的 `Step` 进行并行化处理，将会有效提升批处理性能。

比如，现有一个批处理任务，包含 4 个 `Step`：

* `step1`：在学生姓名后面追加字符串 "1"；
* `step2`：在学生姓名后面追加字符串 "2"；
* `step3`：在学生住址后面追加字符串 "8"；
* `step4`：迁移所有学生信息；

我们发现，修改学生姓名的任务与修改学生住址的任务，互不干扰，并不需要有先后之分。因此，我们可以将 `step1`、`step2` 与 `step3` 并行执行。串行 `Step` 与并行 `Step` 流程如下：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/5_21_33_37_parallel_step_2.png)

#### 三、批处理配置

##### 3.1 Job 配置

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
            	// 姓名追加1、姓名追加2、地址追加8
                .start(batchProcessStudentSplitFlow)
            	// 迁移学生信息; student_source -> student_target
                .next(batchTransferStudentStep)
                .end()
                .build();
    }
}
```

##### 3.2 Fow 配置

`batchProcessStudentSplitFlow`：

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

`batchUpdateStudentNameOneAndTwoFlow`：

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

`batchUpdateStudentNameOneAndTwoFlow`：

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

##### 3.3 Step 配置

`BatchUpdateStudentNameStep`：

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
            	// 姓名追加 1
                .processor(appendStudentNameOneProcessor)
                .writer(studentItemUpdateName)
                .build();
    }

    @Bean("batchUpdateStudentNameStep2")
    public Step batchUpdateStudentNameStep2() {
        return stepBuilderFactory.get("batchUpdateStudentNameStep2")
                .<Student, Student>chunk(1000)
                .reader(studentItemReader)
            	// 姓名追加 2
                .processor(appendStudentNameTwoProcessor)
                .writer(studentItemUpdateName)
                .build();
    }
}
```

`BatchUpdateStudentAddressStep`：

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
            	// 住址追加 8
                .processor(appendStudentAddressProcessor)
                .writer(studentItemUpdateAddress)
                .build();
    }
}
```

`BatchProcessStudentStep`：

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
            	// 迁移数据; student_source -> student_target
                .processor(studentItemProcessor)
                .writer(studentItemWriter)
                .build();
    }
}
```

##### 3.4 数据输入器

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

##### 3.5 数据处理器

`AppendStudentNameOneProcessor`：

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

`AppendStudentNameTwoProcessor`：

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

`AppendStudentAddressProcessor`：

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

`StudentItemProcessor`：

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

##### 3.6 数据输出器

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

>@StepScope：
>
>从上面的 `Step` 配置可知，`studentItemReader` 被多个 `Step` 引用。默认情况下 `studentItemReader` 的生命周期是与 `Job` 保持一致，那么在多 `Step` 引用的情况下，就会抛出类似下面这种异常：
>
>```java
>Caused by: java.lang.IllegalStateException: Cannot open an already opened ItemReader, call close first
>```
>
>使用注解 `StepScope`，让 `studentItemReader` 的生命周期与 `Step` 保持同步，保证每个 `Step` 拿到的 `ItemReader` 都是新的实例。同样，`ItemWriter`、`ItemProcessor` 存在多 `Step` 引用的，都要使用该注解。

#### 四、性能测试

测试数据量：100000

测试环境：Windows 10，i7-8核，MySQL-8.0.28

##### 4.1 串行 Step

串行 `Step` 批处理，只需要按照顺序配置 `Step`（省略代码示例）。测试结果：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/8_12_36_15_serial_step_performance.png)

耗时：**91s**

##### 4.2 并行 Step

测试结果：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/8_12_41_53_parallel_step_performance.png)

耗时：**68s**



示例代码：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)