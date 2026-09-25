---
title: Spring Batch in Practice
date: 2022-02-02 23:12:45
lang: en
label: 033_spring_batch_demo
tags: Spring
categories: Backend
---

-----

<!-- more -->
#### 1. Project Overview

The previous section covered the architecture and design principles of Spring Batch. This section walks through a simple batch job to see how it works in practice.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_22_33_0_batch_demo_process_person_2.png)

The task is to read a CSV file called `sample-data.csv`, split each line into first name and last name, and import the data into the `person` table. The `BatchProcessJob` has a single `Step` with three parts: parse the CSV file, transform each line into a `Person` object, and write the `Person` objects into the `batch-demo.person` table.

#### 2. Project Setup

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_22_52_11_build_spring_batch_demo.png)

You can create the project using the [Spring Initializr](https://start.spring.io/). The full project is available here: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)

#### 3. Creating the Database Table

Spring Batch's `JobRepository` handles all database operations, tracking every insert, query, update, and delete during batch execution. This means Spring Batch depends on the database for state management. The [table creation scripts](https://docs.spring.io/spring-batch/docs/current/reference/html/schema-appendix.html#exampleDDLScripts) are available in the [repository](https://github.com/donehub/spring-batch/tree/master/spring-batch-core/src/main/resources/org/springframework/batch/core). For MySQL, the script file is `schema-mysql.sql`. After setting up the framework tables, don't forget to create the `batch-demo.person` table:

```sql
USE batch-demo;
CREATE TABLE `person` (
  `person_id` bigint(30) unsigned NOT NULL AUTO_INCREMENT,
  `first_name` varchar(10) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `last_name` varchar(20) COLLATE utf8mb4_general_ci DEFAULT NULL,
  PRIMARY KEY (`person_id`)
) ENGINE=InnoDB AUTO_INCREMENT=142 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci COMMENT='Person info table';
```

#### 4. Batch Job Configuration

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/27_21_7_30_spring-batch-flow.png)

Following the batch framework's execution model, here is the configuration:

**4.1 CSV file reader:**

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
    public FlatFileItemReader<Person> personItemReader() {
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

**4.2 Data processor:**

```java
import com.example.springbatchdemo.entity.Person;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.batch.item.ItemProcessor;
import org.springframework.context.annotation.Configuration;

@Configuration
public class PersonItemProcessor implements ItemProcessor<Person, Person> {

    private static final Logger log = LoggerFactory.getLogger(PersonItemProcessor.class);

    @Override
    public Person process(final Person person) throws Exception {

        final String firstName = person.getFirstName();
        final String lastName = person.getLastName();

        final Person transformedPerson = new Person();
        transformedPerson.setFirstName(firstName);
        transformedPerson.setLastName(lastName);

        log.info("Converting ({}) into ({})", person, transformedPerson);

        return transformedPerson;
    }
}
```

**4.3 Person object writer:**

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
    public JdbcBatchItemWriter<Person> personItemWriter() {

        return new JdbcBatchItemWriterBuilder<Person>()
                .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
                .sql("INSERT INTO person (first_name, last_name) VALUES (:firstName, :lastName)")
                .dataSource(batchDemoDB)
                .build();
    }
}
```

**4.4 MySQL data source configuration:**

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
    // Configuration property prefix, adjust based on your setup
    @ConfigurationProperties(prefix = "spring.datasource.batch-demo")
    public DataSource druidDataSource() {
        // Use HikariDataSource, the default in Spring Boot
        return DataSourceBuilder.create().type(HikariDataSource.class).build();
    }
}
```

**4.5 Step configuration**

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

**4.6 Job configuration**

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

**4.7 Job status listener**

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
        if (BatchStatus.COMPLETED.equals(jobExecution.getStatus())) {
            log.info("Job finished! Time to verify the results");

            // Query all person records via spring-mybatis
            List<Person> personList = personMapper.queryAll();
            personList.forEach(person -> log.info("Found <{}> in the database.", person));
        }
    }
}
```

**4.8 CSV test data file**

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_23_30_14_sample-data.png)

#### 5. Running the Batch Job

Start the Spring Boot application. The `JobLauncher` automatically triggers the `importUserJob`. The execution results:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_23_40_7_batch_demo_log.png)

Check the `batch-demo.person` table: the test data from the CSV file has been imported successfully.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/30_23_41_47_batch_task_db.png)
