---
title: Spring Batch ItemReaders
date: 2022-02-03 12:48:01
lang: en
label: 035_spring_batch_item_readers
tags: Spring
categories: Backend
---

-----

<!-- more -->
#### 1. Overview

Spring Batch reads data through the `ItemReader` interface. The framework ships with readers for most common data sources ([full list](https://docs.spring.io/spring-batch/docs/current/reference/html/appendix.html#itemReadersAppendix)). This article covers the five most commonly used readers:

* `FlatFileItemReader`: reads data from flat text files;
* `JdbcPagingItemReader`: reads data from a database with pagination;
* `StaxEventItemReader`: reads data from XML files;
* `JsonItemReader`: reads data from JSON files;
* `MultiResourceItemReader`: reads data from multiple text files;

#### 2. Usage Examples

The entity class `Ticket.class`:

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

##### 2.1 FlatFileItemReader — Reading Flat Files

The `ticket.csv` file:

```csv
Hefei,Bengbu,60.00
Nanjing,Bengbu,70.00
Shanghai,Bengbu,220.00
Shanghai,Hangzhou,75.20
Shanghai,Kunshan,19.00
```

Each line in the file represents one `Ticket` object, with fields separated by commas. `FlatFileItemReader` parses the file line by line and maps each row to a `POJO`.

```java
/**
 * Job
 */
@Bean
public Job testFlatItemFileReaderJob() {
    return jobBuilderFactory.get("testFlatItemFileReaderJob")
        .incrementer(new RunIdIncrementer())
        .flow(testFlatFileItemReaderStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testFlatFileItemReaderStep")
public Step testFlatFileItemReaderStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testFlatFileItemReaderStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketFileItemReader)
        .writer(list -> list.forEach(System.out::println))
        .build();
}

/**
 * Reader
 */
@Bean("ticketFileItemReader")
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
```

Start the application. Console output:

```java
2022-06-02 13:50:23.538  INFO 77808 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testFlatItemFileReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 13:50:23.599  INFO 77808 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testFlatFileItemReaderStep]
Departure: Hefei; Arrival: Bengbu; Price: 60.00
Departure: Nanjing; Arrival: Bengbu; Price: 70.00
Departure: Shanghai; Arrival: Bengbu; Price: 220.00
Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-02 13:50:23.680  INFO 77808 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testFlatFileItemReaderStep] executed in 79ms
```

##### 2.2 JdbcPagingItemReader — Reading from a Database

Read records from the `student` table in MySQL with pagination and print them out.

```java
/**
 * Job
 */
@Bean
public Job testDatabaseItemReaderJob() {
    return jobBuilderFactory.get("testDatabaseItemReaderJob")
        .incrementer(new RunIdIncrementer())
        .flow(testDatabaseItemReaderStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testDatabaseItemReaderStep")
public Step testDatabaseItemReaderStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testDatabaseItemReaderStep")
        .transactionManager(transactionManager)
        .<Student, Student>chunk(10)
        .reader(studentItemReader)
        .writer(list -> list.forEach(System.out::println))
        .build();
}

/**
 * Reader
 */
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

public class StudentRowMapper implements RowMapper<Student> {
    
    /**
     * Map ResultSet columns to Student fields
     */
    @Override
    public Student mapRow(ResultSet rs, int rowNum) throws SQLException {

        Student student = new Student();
        student.setStudentId(rs.getLong("student_id"));
        student.setName(rs.getString("name"));
        student.setAddress(rs.getString("address"));
        return student;
    }
}

/**
 * MySQL data source configuration
 */
@Primary
@Bean(name = "batchDemoDB")
@ConfigurationProperties(prefix = "spring.datasource.batch-demo")
public DataSource druidDataSource() {
    return DataSourceBuilder.create().type(HikariDataSource.class).build();
}
```

Start the application. Console output:

```java
2022-06-02 14:00:19.010  INFO 67748 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testDatabaseItemReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 14:00:19.107  INFO 67748 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testDatabaseItemReaderStep]
name: Zhang San1, address: Shanghai1
name: Zhang San2, address: Shanghai2
name: Zhang San3, address: Shanghai3
name: Zhang San4, address: Shanghai4
name: Zhang San5, address: Shanghai5
name: Zhang San6, address: Shanghai6
name: Zhang San7, address: Shanghai7
name: Zhang San8, address: Shanghai8
name: Zhang San9, address: Shanghai9
name: Zhang San10, address: Shanghai10
2022-06-02 14:00:19.284  INFO 67748 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testDatabaseItemReaderStep] executed in 176ms
```

##### 2.3 StaxEventItemReader — Reading XML Files

The `ticket.xml` file:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tickets>
    <ticket>
        <departureStation>Hefei</departureStation>
        <arrivalStation>Bengbu</arrivalStation>
        <price>60.00</price>
    </ticket>
    <ticket>
        <departureStation>Nanjing</departureStation>
        <arrivalStation>Bengbu</arrivalStation>
        <price>70.00</price>
    </ticket>
    <ticket>
        <departureStation>Shanghai</departureStation>
        <arrivalStation>Bengbu</arrivalStation>
        <price>220.00</price>
    </ticket>
    <ticket>
        <departureStation>Shanghai</departureStation>
        <arrivalStation>Hangzhou</arrivalStation>
        <price>75.20</price>
    </ticket>
    <ticket>
        <departureStation>Shanghai</departureStation>
        <arrivalStation>Kunshan</arrivalStation>
        <price>19.00</price>
    </ticket>
</tickets>
```

The file contains multiple `<ticket>` elements, each representing one `Ticket` object. Each `<ticket>` element has three child elements corresponding to the three properties.

Mapping XML to objects requires OXM (Object/XML Mapping). The recommended approach is `spring-oxm`. Add these dependencies:

```java
<dependency>
    <groupId>org.springframework</groupId>
    <artifactId>spring-oxm</artifactId>
</dependency>
<dependency>
    <groupId>com.thoughtworks.xstream</groupId>
    <artifactId>xstream</artifactId>
    <version>1.4.11.1</version>
</dependency>
```

```java
/**
 * Job
 */
@Bean
public Job testXmlItemReaderJob() {
    return jobBuilderFactory.get("testXmlItemReaderJob")
        .incrementer(new RunIdIncrementer())
        .flow(testXmlItemReaderStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testXmlItemReaderStep")
public Step testXmlItemReaderStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testXmlItemReaderStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketXmlItemReader)
        .writer(list -> list.forEach(System.out::println))
        .build();
}

/**
 * Reader
 */
@Bean("ticketXmlItemReader")
public StaxEventItemReader<Ticket> itemReader() {
    return new StaxEventItemReaderBuilder<Ticket>()
        .name("ticketXmlItemReader")
        .resource(new ClassPathResource("ticket.xml"))
        .addFragmentRootElements("ticket")
        .unmarshaller(ticketMarshaller)
        .build();
}

/**
 * XML-to-object marshaller
 */
@Bean("ticketMarshaller")
public XStreamMarshaller ticketMarshaller() {

    Map<String, Class<Ticket>> aliases = new HashMap<>(1);
    aliases.put("ticket", Ticket.class);

    XStreamMarshaller marshaller = new XStreamMarshaller();
    marshaller.setAliases(aliases);

    return marshaller;
}
```

Start the application. Console output:

```java
2022-06-02 14:15:48.444  INFO 87024 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testXmlItemReaderJob]] launched with the following parameters: [{run.id=3}]
2022-06-02 14:15:48.503  INFO 87024 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testXmlItemReaderStep]
Departure: Hefei; Arrival: Bengbu; Price: 60.00
Departure: Nanjing; Arrival: Bengbu; Price: 70.00
Departure: Shanghai; Arrival: Bengbu; Price: 220.00
Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-02 14:15:48.710  INFO 87024 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testXmlItemReaderStep] executed in 205ms
```

##### 2.4 JsonItemReader — Reading JSON Files

The `ticket.json` file:

```json
[
  {
    "departureStation": "Hefei",
    "arrivalStation": "Bengbu",
    "price": "60.00"
  },
  {
    "departureStation": "Nanjing",
    "arrivalStation": "Bengbu",
    "price": "70.00"
  },
  {
    "departureStation": "Shanghai",
    "arrivalStation": "Bengbu",
    "price": "220.00"
  },
  {
    "departureStation": "Shanghai",
    "arrivalStation": "Hangzhou",
    "price": "75.20"
  },
  {
    "departureStation": "Shanghai",
    "arrivalStation": "Kunshan",
    "price": "19.00"
  }
]
```

```java
/**
 * Job
 */
@Bean
public Job testJsonItemReaderJob() {
    return jobBuilderFactory.get("testJsonItemReaderJob")
        .incrementer(new RunIdIncrementer())
        .flow(testJsonItemReaderStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testJsonItemReaderStep")
public Step testJsonItemReaderStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testJsonItemReaderStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketJsonItemReader)
        .writer(list -> list.forEach(System.out::println))
        .build();
}

/**
 * Reader
 */
@Bean("ticketJsonItemReader")
public JsonItemReader<Ticket> ticketJsonItemReader() {
    return new JsonItemReaderBuilder<Ticket>()
        .name("ticketJsonItemReader")
        .jsonObjectReader(new JacksonJsonObjectReader<>(Ticket.class))
        .resource(new ClassPathResource("ticket.json"))
        .build();
}
```

Start the application. Console output:

```java
2022-06-02 14:25:38.142  INFO 76544 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testJsonItemReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 14:25:38.211  INFO 76544 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testJsonItemReaderStep]
Departure: Hefei; Arrival: Bengbu; Price: 60.00
Departure: Nanjing; Arrival: Bengbu; Price: 70.00
Departure: Shanghai; Arrival: Bengbu; Price: 220.00
Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-02 14:25:38.328  INFO 76544 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testJsonItemReaderStep] executed in 116ms
```

##### 2.5 MultiResourceItemReader — Reading Multiple Files

Reading from multiple files works on the same principle as reading a single flat file. `MultiResourceItemReader` adds a delegation layer on top of `FlatFileItemReader`. The requirement is that all files share the same data structure. Here is an example reading from `ticket-1.csv` and `ticket-2.csv`:

```cvs
Hefei,Bengbu,60.00
Nanjing,Bengbu,70.00
Shanghai,Bengbu,220.00
```

```cvs
Shanghai,Hangzhou,75.20
Shanghai,Kunshan,19.00
```

```java
/**
 * Job
 */
@Bean
public Job testMultiFileItemReaderJob() {
    return jobBuilderFactory.get("testMultiFileItemReaderJob")
        .incrementer(new RunIdIncrementer())
        .flow(testMultiFileItemReaderStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testMultiFileItemReaderStep")
public Step testMultiFileItemReaderStep1(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testMultiFileItemReaderStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketMultiFileItemReader)
        .writer(list -> list.forEach(System.out::println))
        .build();
}

/**
 * Proxy Reader
 */
@Bean("ticketMultiFileItemReader")
public MultiResourceItemReader<Ticket> ticketMultiFileItemReader() {

    // Resource files
    Resource[] resources = new Resource[]{
        new ClassPathResource("ticket-1.csv"),
        new ClassPathResource("ticket-2.csv")};

    return new MultiResourceItemReaderBuilder<Ticket>()
        .name("ticketMultiFileItemReader")
        .delegate(commonTicketFileItemReader())
        .resources(resources)
        .build();
}

/**
 * Reader
 */
@Bean("commonTicketFileItemReader")
public FlatFileItemReader<Ticket> commonTicketFileItemReader() {
    return new FlatFileItemReaderBuilder<Ticket>()
        .name("commonTicketFileItemReader")
        .delimited()
        .names(new String[]{"departureStation", "arrivalStation", "price"})
        .fieldSetMapper(new BeanWrapperFieldSetMapper<Ticket>() {{
            setTargetType(Ticket.class);
        }})
        .build();
}
```

Start the application. Console output:

```java
2022-06-02 14:37:49.693  INFO 86124 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testMultiFileItemReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 14:37:49.785  INFO 86124 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testMultiFileItemReaderStep]
Departure: Hefei; Arrival: Bengbu; Price: 60.00
Departure: Nanjing; Arrival: Bengbu; Price: 70.00
Departure: Shanghai; Arrival: Bengbu; Price: 220.00
Departure: Shanghai; Arrival: Hangzhou; Price: 75.20
Departure: Shanghai; Arrival: Kunshan; Price: 19.00
2022-06-02 14:37:49.944  INFO 86124 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testMultiFileItemReaderStep] executed in 157ms
```



Sample code: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)
