---
title: Spring Batch 基础应用
date: 2022-02-02 23:12:45
tags: Spring
categories: 后端
---

-----

#### 一、项目简介

上一节介绍了 Spring Batch 的基础架构和设计原理，本节将通过一个简单的批处理任务来学习如何使用 Spring Batch。

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_22_33_0_batch_demo_process_person_2.png)

现在需要将逗号分隔值文件 `sample-data.cvs` 中的数据，按照姓氏、名称拆分，导入数据表 `person` 中。看图可知，`BatchProcessJob` 只有一个 `Step`，分为三个部分：解析 `cvs` 文件；将文件数据转化为 `Person` 对象；将 `Person` 对象信息导入数据表 `batch-demo.person`。

#### 二、项目搭建与配置

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_22_52_11_build_spring_batch_demo.png)

使用[Spring 应用构建工具](https://start.spring.io/)，即可创建项目。我的应用部署地址：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)

#### 三、创建数据表

Spring Batch 的组件`JobRepository`， 专门负责与数据库打交道，记录整个批处理中的增加、检索、更新、删除动作。也就是说，Spring Batch 是依赖数据库进行管理的。数据表[创建脚本](https://docs.spring.io/spring-batch/docs/current/reference/html/schema-appendix.html#exampleDDLScripts)可在[仓库](https://github.com/donehub/spring-batch/tree/master/spring-batch-core/src/main/resources/org/springframework/batch/core)中找到。`MySQL` 数据库的脚本文件为：`schema-mysql.sql`。框架依赖表建好后，不要忘了创建表 `batch-demo.person`。

```sql
USE batch-demo;
CREATE TABLE `person` (
  `person_id` bigint(30) unsigned NOT NULL AUTO_INCREMENT,
  `first_name` varchar(10) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(20) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`person_id`)
) ENGINE=InnoDB AUTO_INCREMENT=142 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='人员信息表';
```

#### 四、批处理任务配置

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/27_21_7_30_spring-batch-flow.png)

根据批处理框架的运作流程，我们做出如下配置：

**4.1 `cvs`文件内容读取器：**

```java
import com.example.springbatchdemo.entity.Person;
import org.springframework.batch.item.file.FlatFileItemReader;
import org.springframework.batch.item.file.builder.FlatFileItemReaderBuilder;
import org.springframework.batch.item.file.mapping.BeanWrapperFieldSetMapper;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;

@Configuration
public class CustomItemReader {

    @Bean("personItemReader")
    public FlatFileItemReader<Person> reader() {
        return new FlatFileItemReaderBuilder<Person>()
                .name("personItemReader")
                .resource(new ClassPathResource("sample-data.csv"))
                .delimited()
                .names(new String[]{"firstName", "lastName"})
                .fieldSetMapper(new BeanWrapperFieldSetMapper<Person>() {{
                    setTargetType(Person.class);
                }})
                .build();
    }
}
```

**4.2 解析数据处理器：**

```java
import com.example.springbatchdemo.entity.Person;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;
import java.util.Optional;

@Configuration
public class PersonItemProcessor implements ItemProcessor<Person, Person> {

    private static final Logger log = LoggerFactory.getLogger(PersonItemProcessor.class);

    @Override
    public Person process(final Person person) throws Exception {

        final String firstName = Optional.ofNullable(person.getFirstName()).orElse(null);
        final String lastName = Optional.ofNullable(person.getLastName()).orElse(null);

        final Person transformedPerson = new Person();
        transformedPerson.setFirstName(firstName);
        transformedPerson.setLastName(lastName);

        log.info("Converting ({}) into ({})", person, transformedPerson);

        return transformedPerson;
    }
}
```

**4.3 `Person` 对象写入器：**

```java
import com.example.springbatchdemo.entity.Person;
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

    @Bean("personItemWriter")
    public JdbcBatchItemWriter<Person> writer() {

        return new JdbcBatchItemWriterBuilder<Person>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("INSERT INTO person (first_name, last_name) VALUES (:firstName, :lastName)")
                .dataSource(batchDemoDB)
                .build();
    }
}
```

**4.4 `MySQL` 数据源配置：**

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

**4.5 Step 配置**

```java
import com.example.springbatchdemo.component.processor.PersonItemProcessor;
import com.example.springbatchdemo.entity.Person;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.configuration.annotation.StepBuilderFactory;
import org.springframework.batch.item.database.JdbcBatchItemWriter;
import org.springframework.batch.item.file.FlatFileItemReader;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;

@Configuration
public class BatchProcessPersonStep {

    @Autowired
    public StepBuilderFactory stepBuilderFactory;

    @Autowired
    @Qualifier(value = "personItemReader")
    private FlatFileItemReader<Person> personItemReader;

    @Autowired
    @Qualifier(value = "personItemWriter")
    private JdbcBatchItemWriter<Person> personItemWriter;

    @Autowired
    private PersonItemProcessor personItemProcessor;

    @Bean("batchProcessPersonStep1")
    public Step step1() {
        return stepBuilderFactory.get("step1")
                .<Person, Person>chunk(10)
                .reader(personItemReader)
                .processor(personItemProcessor)
                .writer(personItemWriter)
                .build();
    }
}
```

**4.6 `Job` 配置**

```java
import com.example.springbatchdemo.component.listener.BatchProcessPersonCompletionListener;
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
public class BatchProcessPersonJob {

    @Autowired
    public JobBuilderFactory jobBuilderFactory;

    @Autowired
    @Qualifier(value = "batchProcessPersonStep1")
    private Step batchProcessPersonStep1;

    @Autowired
    private BatchProcessPersonCompletionListener batchProcessPersonCompletionListener;

    @Bean
    public Job importUserJob() {
        return jobBuilderFactory.get("importUserJob")
                .preventRestart()
                .incrementer(new RunIdIncrementer())
                .listener(batchProcessPersonCompletionListener)
                .flow(batchProcessPersonStep1)
                .end()
                .build();
    }
}
```

**4.7 任务状态监听器**

```java
import com.example.springbatchdemo.entity.Person;
import com.example.springbatchdemo.mapper.PersonMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.core.BatchStatus;
import org.springframework.batch.core.JobExecution;
import org.springframework.batch.core.listener.JobExecutionListenerSupport;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.util.List;

@Component
public class BatchProcessPersonCompletionListener extends JobExecutionListenerSupport {

    private static final Logger log = LoggerFactory.getLogger(BatchProcessPersonCompletionListener.class);

    @Autowired
    private PersonMapper personMapper;

    @Override
    public void afterJob(JobExecution jobExecution) {
        if (jobExecution.getStatus() == BatchStatus.COMPLETED) {
            log.info("Job finished! Time to verify the results");

            // spring-mybatis 查询所有的人员信息
            List<Person> personList = personMapper.queryAll();
            personList.forEach(person -> log.info("Found <{}> in the database.", person));
        }
    }
}
```

**4.8 `cvs` 测试数据文件配置**

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_23_30_14_sample-data.png)

#### 五、执行批处理任务

运行 `SpringBoot` 项目，`JobLauncher` 自动发起任务 `importUserJob`。任务执行结果如下：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_23_40_7_batch_demo_log.png)

查看表 `batch-demo.person`，`cvs` 文件内的测试数据已成功导入数据表！

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_23_41_47_batch_task_db.png)