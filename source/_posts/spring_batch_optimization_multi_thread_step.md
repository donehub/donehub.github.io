---
title: Spring Batch 性能调优-多线程Step
date: 2022-02-04 01:28:45
tags: Spring
categories: 后端
---

-----

#### 一、Spring Batch 性能优化指标

Spring Batch 是一款伸缩性非常好的批处理工具，既可以处理简单的任务，也可以处理复杂的、高容量的任务。在性能调优方面，Spring Batch 提供了丰富的接口支持，各项优化指标可归纳如下：

* 多线程 `Step`：由独立线程执行提交块（a chunk of items）的输入、处理和输出过程；
* [并行化 `Step`](https://takeshell.com/2022/02/08/spring_batch_optimization_parallel_step/)：对于可并行处理的 `Step`，交由不同的线程去处理；
* 分片化 `Step`：通过 `SPI(Serial Peripheral Interface)`，对 `Step` 分片执行；
* 远程组块：对于输入无性能瓶颈，但处理和输出有性能瓶颈的任务，交由远程组块执行；

详见[Spring文档](https://docs.spring.io/spring-batch/docs/current/reference/html/scalability.html#scalability)。

#### 二、多线程 `Step` 配置

Spring Batch 执行一个 `Step`，会按照 `chunk` 配置的数量分批次提交。对于多线程 `Step`，由线程池去处理任务批次。因此，每个 `chunk` 都不用串行等待，这大大地提高了批处理性能。

配置多线程 `Step` 非常简单，可以通过 `xml` 或接口来配置。以接口配置为例：

```java
@Bean
public Step sampleStep(TaskExecutor taskExecutor) {
    return this.stepBuilderFactory.get("sampleStep")
        .<String, String>chunk(10)
        .reader(itemReader())
        .writer(itemWriter())
        .taskExecutor(taskExecutor)
        // 节流配置, 不要超过线程池的最大线程数量
        .throttleLimit(20)
        .build();
}
```

此外，在配置多线程 `Step` 时，我们需要考虑得更多：

* 线程池：推荐使用 `Spring` 线程池 `ThreadPoolTaskExecutor`，兼容性好；
* 线程安全：输入器和输出器必须是线程安全的，否则可能会导致重复任务、脏数据等问题；
* 框架节流：Spring Batch 自带节流器，默认最多可处理 4 个小任务，因此需要重新配置；

#### 三、批处理配置

通过 Spring Batch 应用，迁移 100 万条数据。相关配置如下：

##### 3.1 数据读取器

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

##### 3.2 数据映射器

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

##### 3.3 数据处理器

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

##### 3.4 数据写入器

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

##### 3.5 Step 配置-单线程

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

##### 3.6 Step 配置-多线程

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

##### 3.7 Job 配置

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

##### 3.8 `MySQL` 数据源配置

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
    // 数据源配置参数识别前缀, 根据具体配置来设定
    @ConfigurationProperties(prefix = "spring.datasource.batch-demo")
    public DataSource druidDataSource() {
        // 使用 SpringBoot 默认的数据源 HikariDataSource
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }
}
```

##### 3.9 线程池配置

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

#### 四、批处理性能测试

##### 4.1 单线程 Step

启动批处理任务，同步 100 万条数据。执行结果如下：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/2_15_30_43_single_thred_step_performance.png)

总耗时：313 秒

##### 4.2 多线程 Step

启动批处理任务，同步 100 万条数据。执行结果如下：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/2_15_42_8_multi_thred_step_performance.png)

总耗时：81 秒



---

性能提升超**300%**

#### 五、总结

多线程 `Step` 将 `chunk` 任务交给线程池异步执行，可以显著地提升批处理的性能。但在多线程场景下，我们要了解 Spring Batch 的基础架构，避免并发导致的重复任务、脏数据等问题。

示例代码：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)