---
title: Spring Batch 性能调优-分片化Step
date: 2022-02-15 09:28:35
tags: Spring
categories: 后端
---

-----

#### 一、Spring Batch 性能优化指标

Spring Batch 是一款伸缩性非常好的批处理工具，既可以处理简单的任务，也可以处理复杂的、高容量的任务。在性能调优方面，Spring Batch 提供了丰富的接口支持，各项优化指标可归纳如下：

* [多线程 `Step`](https://takeshell.com/2022/02/04/spring_batch_optimization_multi_thread_step/)：由独立线程执行提交块（a chunk of items）的输入、处理和输出过程；
* [并行化 `Step`](https://takeshell.com/2022/02/08/spring_batch_optimization_parallel_step/)：对于可并行处理的 `Step`，交由不同的线程去处理；
* 分片化 `Step`：通过 `SPI(Serial Peripheral Interface)`，对 `Step` 分片执行；
* 远程组块：对于输入无性能瓶颈，但处理和输出有性能瓶颈的任务，交由远程组块执行；

详见[Spring文档](https://docs.spring.io/spring-batch/docs/current/reference/html/scalability.html#scalability)。

#### 二、分片化 `Step` 

如果一个 `Step` 的任务量比较大，可以尝试将其拆分成多个子任务。子任务之间可并行处理且互不干扰，这将大大提升批处理效率。例如：Master 这个 `Step` 迁移 100000 条数据需要 100 s，如果将其拆分为 100 个 Slave 任务，那么时间可缩短至 1 s。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_20_41_39_partition_step_2.png)

`Step` 分片原理，是一个 Master 处理器对应多个 Salve 处理器。Slave 处理器可以是远程服务，也可以是本地执行线程。主从服务间的消息不需要持久化，也不需要严格保证传递，因为 `JobRepository` 的元数据管理，是将每个 Salve 独立保存在 `batch_step_execution` 中的，这样便可以保证每个 Slave 任务只执行一次。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_53_13_partition_step_structure.png)

`Step` 分片化，需要了解两个组件：分片器（Partitioner）和分片处理（PartitionHandler）。

* 分片器（Partitioner）：为每个 Slave 服务配置上下文（StepExecutionContext）；

* 分片处理（PartitionHandler）：定义 Slave 服务的数量以及 Slave 任务内容；

比如在一个数据迁移 `Step` 中，分片处理就是将 1 个主任务拆分成 100 个从任务，并定义从任务的执行内容；分片器就是依次为这 100 个从任务划定数据迁移的范围（`select * from table where id between ? and ? `）。

#### 三、批处理配置

##### 3.1 Job 配置

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

##### 3.2 Step 配置

`MasterTransferStudentStep`：

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

`SlaveTransferStudentStep`：

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

##### 3.3 Partitioner 配置

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

##### 3.4 Partition-Handler 配置

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

##### 3.5 数据输入器

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
    public JdbcPagingItemReader<Student> slaveTransferStudentItemReader(@Value("#{stepExecutionContext[fromId]}") final Long fromId,
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

##### 3.6 数据处理器

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

##### 3.7 数据输出器

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

#### 四、性能测试

测试数据量：100000

测试环境：Windows 10，i7-8核，MySQL-8.0.28

##### 4.1 常规 Step

省略测试代码，具体请查看 `demo`。测试结果：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_20_57_normal_step_transfer.png)

耗时：**13s**

##### 4.2 分片化 Step

测试结果：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_28_21_partition_step_performance.png)

从 `batch_step_execution` 可以看出，共有 100 个子任务并行处理，每个子任务迁移 1000 条数据。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/19_21_31_26_partition_step_performance_detail.png)

耗时：**7s**



示例代码：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)