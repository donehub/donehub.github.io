---
title: Spring Batch 数据读取器
date: 2022-02-03 12:48:01
tags: Spring
categories: 后端
---

-----

#### 一、Spring Batch 数据读取器

Spring Batch 的数据读取器，是通过接口 `ItemReader` 来实现的。针对常用的数据读取场景，Spring Batch 提供了丰富的组件支持（[查看所有组件](https://docs.spring.io/spring-batch/docs/current/reference/html/appendix.html#itemReadersAppendix)），本文介绍最常用的五个组件：

* `FlatFileItemReader`：读取文本数据；
* `JdbcPagingItemReader`：分页读取数据库的数据；
* `StaxEventItemReader`：读取 `XML` 文件数据；
* `JsonItemReader`：读取 `JSON` 文件数据；
* `MultiResourceItemReader`：读取多文本数据；

#### 二、简单使用

实体类 `Ticket.class`：

```java
import lombok.Data;
import java.math.BigDecimal;

@Data
public class Ticket {

    /**
     * 始发站
     */
    private String departureStation;

    /**
     * 到达站
     */
    private String arrivalStation;

    /**
     * 票价
     */
    private BigDecimal price;

    @Override
    public String toString() {
        return String.format("始发站: %s; 到达站: %s; 票价: %s", departureStation, arrivalStation, price);
    }
}
```

##### 2.1 FlatFileItemReader-文本数据读取

文件 `ticket.csv`：

```csv
合肥,蚌埠,60.00
南京,蚌埠,70.00
上海,蚌埠,220.00
上海,杭州,75.20
上海,昆山,19.00
```

可以看到，文本数据的每一行代表一个 `Ticket` 实体，对象属性之间以英文逗号分隔。通过 `FlatFileItemReader`，可以按照行将文本数据转换为 `POJO` 存储。

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

启动应用，控制台打印日志：

```java
2022-06-02 13:50:23.538  INFO 77808 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testFlatItemFileReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 13:50:23.599  INFO 77808 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testFlatFileItemReaderStep]
始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
始发站: 南京; 到达站: 蚌埠; 票价: 70.00
始发站: 上海; 到达站: 蚌埠; 票价: 220.00
始发站: 上海; 到达站: 杭州; 票价: 75.20
始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-02 13:50:23.680  INFO 77808 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testFlatFileItemReaderStep] executed in 79ms
```

##### 2.2 JdbcPagingItemReader-数据库数据读取

从 `MySQL` 数据库，分页读取表 `student` 的数据，并打印数据内容。

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
     * Student 字段映射
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
 * MySQL 数据源配置
 */
@Primary
@Bean(name = "batchDemoDB")
@ConfigurationProperties(prefix = "spring.datasource.batch-demo")
public DataSource druidDataSource() {
    return DataSourceBuilder.create().type(HikariDataSource.class).build();
}
```

启动应用，控制台打印日志：

```java
2022-06-02 14:00:19.010  INFO 67748 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testDatabaseItemReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 14:00:19.107  INFO 67748 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testDatabaseItemReaderStep]
name: 张三1, address: 上海市1
name: 张三2, address: 上海市2
name: 张三3, address: 上海市3
name: 张三4, address: 上海市4
name: 张三5, address: 上海市5
name: 张三6, address: 上海市6
name: 张三7, address: 上海市7
name: 张三8, address: 上海市8
name: 张三9, address: 上海市9
name: 张三10, address: 上海市10
2022-06-02 14:00:19.284  INFO 67748 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testDatabaseItemReaderStep] executed in 176ms
```

##### 2.3 StaxEventItemReader-XML 数据读取

文件 `ticket.xml`：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tickets>
    <ticket>
        <departureStation>合肥</departureStation>
        <arrivalStation>蚌埠</arrivalStation>
        <price>60.00</price>
    </ticket>
    <ticket>
        <departureStation>南京</departureStation>
        <arrivalStation>蚌埠</arrivalStation>
        <price>70.00</price>
    </ticket>
    <ticket>
        <departureStation>上海</departureStation>
        <arrivalStation>蚌埠</arrivalStation>
        <price>220.00</price>
    </ticket>
    <ticket>
        <departureStation>上海</departureStation>
        <arrivalStation>杭州</arrivalStation>
        <price>75.20</price>
    </ticket>
    <ticket>
        <departureStation>上海</departureStation>
        <arrivalStation>昆山</arrivalStation>
        <price>19.00</price>
    </ticket>
</tickets>
```

可以看到，文件内容是多组 `ticket` 标签组成的，每一个标签代表一个 `Ticket` 实体；每个 `ticket` 标签，内含 3 个子标签，代表 `Ticket` 实体的 3 个属性值。

涉及到 `XML` 与 `Object` 的映射，因此需要引入 `OXM` 技术。推荐使用 `spring oxm`，pom 依赖：

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
 * 映射器
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

启动应用，控制台打印日志：

```java
2022-06-02 14:15:48.444  INFO 87024 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testXmlItemReaderJob]] launched with the following parameters: [{run.id=3}]
2022-06-02 14:15:48.503  INFO 87024 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testXmlItemReaderStep]
始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
始发站: 南京; 到达站: 蚌埠; 票价: 70.00
始发站: 上海; 到达站: 蚌埠; 票价: 220.00
始发站: 上海; 到达站: 杭州; 票价: 75.20
始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-02 14:15:48.710  INFO 87024 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testXmlItemReaderStep] executed in 205ms
```

##### 2.4 JsonItemReader-JSON 数据读取

文件 `ticket.json`：

```json
[
  {
    "departureStation": "合肥",
    "arrivalStation": "蚌埠",
    "price": "60.00"
  },
  {
    "departureStation": "南京",
    "arrivalStation": "蚌埠",
    "price": "70.00"
  },
  {
    "departureStation": "上海",
    "arrivalStation": "蚌埠",
    "price": "220.00"
  },
  {
    "departureStation": "上海",
    "arrivalStation": "杭州",
    "price": "75.20"
  },
  {
    "departureStation": "上海",
    "arrivalStation": "昆山",
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

启动应用，控制台打印日志：

```java
2022-06-02 14:25:38.142  INFO 76544 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testJsonItemReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 14:25:38.211  INFO 76544 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testJsonItemReaderStep]
始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
始发站: 南京; 到达站: 蚌埠; 票价: 70.00
始发站: 上海; 到达站: 蚌埠; 票价: 220.00
始发站: 上海; 到达站: 杭州; 票价: 75.20
始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-02 14:25:38.328  INFO 76544 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testJsonItemReaderStep] executed in 116ms
```

##### 2.5 MultiResourceItemReader-多文本数据读取

多文本数据读取，与文本数据读取的原理一致，只是在其基础上，做了一层代理。多文本数据读取，要求每个文本的数据结构相同，如从 `ticket-1.cvs` 和 `ticket-2.cvs` 两个文件中读取数据：

```cvs
合肥,蚌埠,60.00
南京,蚌埠,70.00
上海,蚌埠,220.00
```

```cvs
上海,杭州,75.20
上海,昆山,19.00
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

    // 资源文件
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

启动程序，控制台打印日志：

```java
2022-06-02 14:37:49.693  INFO 86124 --- [restartedMain] o.s.b.c.l.support.SimpleJobLauncher      : Job: [FlowJob: [name=testMultiFileItemReaderJob]] launched with the following parameters: [{run.id=2}]
2022-06-02 14:37:49.785  INFO 86124 --- [restartedMain] o.s.batch.core.job.SimpleStepHandler     : Executing step: [testMultiFileItemReaderStep]
始发站: 合肥; 到达站: 蚌埠; 票价: 60.00
始发站: 南京; 到达站: 蚌埠; 票价: 70.00
始发站: 上海; 到达站: 蚌埠; 票价: 220.00
始发站: 上海; 到达站: 杭州; 票价: 75.20
始发站: 上海; 到达站: 昆山; 票价: 19.00
2022-06-02 14:37:49.944  INFO 86124 --- [restartedMain] o.s.batch.core.step.AbstractStep         : Step: [testMultiFileItemReaderStep] executed in 157ms
```



示例代码：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)
