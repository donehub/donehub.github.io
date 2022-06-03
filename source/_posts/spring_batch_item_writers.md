---
title: Spring Batch 数据输出器
date: 2022-02-03 23:21:35
tags: Spring
categories: 后端
---

-----

#### 一、Spring Batch 数据输出器

Spring Batch 的数据输出器，是通过接口 `ItemWriter` 来实现的。针对常用的数据输出场景，Spring Batch 提供了丰富的组件支持（[查看所有组件](https://docs.spring.io/spring-batch/docs/current/reference/html/appendix.html#itemWritersAppendix)），本文介绍最常用的五个组件：

* `FlatFileItemWriter`：输出文本数据；
* `JdbcBatchItemWriter`：输出数据到数据库；
* `StaxEventItemWriter`：输出 `XML` 文件数据；
* `JsonFileItemWriter`：输出 `JSON` 文件数据；
* `ClassifierCompositeItemWriter`：输出多文本数据；

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

文件 `ticket.csv`：

```csv
合肥,蚌埠,60.00
南京,蚌埠,70.00
上海,蚌埠,220.00
上海,杭州,75.20
上海,昆山,19.00
```

##### 2.1 FlatFileItemWriter-文本数据输出

将 `ticket.csv` 中的信息，转换为 JSON 字符串，输出到文件 `ticket_output.txt` 中：

```java
/**
 * Job
 */
@Bean
public Job testFlatFileItemWriterJob() {
    return jobBuilderFactory.get("testFlatFileItemWriterJob")
        .incrementer(new RunIdIncrementer())
        .flow(testFlatFileItemWriterStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testFlatFileItemWriterStep")
public Step testFlatFileItemWriterStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testFlatFileItemWriterStep")
        .transactionManager(transactionManager)
        .reader(ticketFileItemReader)
        .writer(ticketFileItemWriter)
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

/**
 * Writer
 */
@Bean("ticketFileItemWriter")
public FlatFileItemWriter<Ticket> ticketFileItemWriter() {

    // 聚合器; JSON 序列化
    LineAggregator<Ticket> aggregator = item -> {
        try {
            ObjectMapper mapper = new ObjectMapper();
            return mapper.writeValueAsString(item);
        } catch (JsonProcessingException e) {
            LOGGER.error("parse object to json error: {}", e.getMessage(), e);
        }
        return "";
    };

    return new FlatFileItemWriterBuilder<Ticket>()
        .name("ticketFileItemWriter")
        .resource(new FileSystemResource("ticket_output.txt"))
        .lineAggregator(aggregator)
        .build();
}
```

输出文本数据，要求目标数据的格式为字符串，因此需要将 `POJO` 按照一定规则聚合成字符串。Spring Batch 已实现聚合器 `LineAggregator` ：`PassThroughLineAggregator`（打印 `POJO`）、`RecursiveCollectionLineAggregator`（打印 `POJO` 列表）、`DelimitedLineAggregator`（分隔符拼接 `POJO` 字段值）、`FormatterLineAggregator`（格式化 `POJO` 字段值）。当然，我们也可以手动实现聚合器，例如示例代码中，将 `POJO` 转换为 JSON 格式。

启动应用，生成文件 `ticket_output.txt`：

```tXT
{"departureStation":"合肥","arrivalStation":"蚌埠","price":60.00}
{"departureStation":"南京","arrivalStation":"蚌埠","price":70.00}
{"departureStation":"上海","arrivalStation":"蚌埠","price":220.00}
{"departureStation":"上海","arrivalStation":"杭州","price":75.20}
{"departureStation":"上海","arrivalStation":"昆山","price":19.00}
```

##### 2.2 JdbcBatchItemWriter-数据库数据输出

将文件 `student.cvs` 中的信息（内容如下），导入到 MySQL 数据表 `student` 中：

```cvs
1,张三,合肥
2,李四,蚌埠
3,王二,南京
```

```java
/**
 * Job
 */
@Bean
public Job testDatabaseItemWriterJob() {
    return jobBuilderFactory.get("testDatabaseItemWriterJob")
        .incrementer(new RunIdIncrementer())
        .flow(testDatabaseItemWriterStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testDatabaseItemWriterStep")
public Step testDatabaseItemWriterStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testDatabaseItemWriterStep")
        .transactionManager(transactionManager)
        .<Student, Student>chunk(10)
        .reader(studentFileItemReader)
        .writer(studentItemWriter)
        .build();
}

/**
 * Reader
 */
@Bean("studentFileItemReader")
public FlatFileItemReader<Student> studentFileItemReader() {
    return new FlatFileItemReaderBuilder<Student>()
        .name("ticketFileItemReader")
        .resource(new ClassPathResource("student.csv"))
        .delimited()
        .names(new String[]{"studentId", "name", "address"})
        .fieldSetMapper(new BeanWrapperFieldSetMapper<Student>() {{
            setTargetType(Student.class);
        }})
        .build();
}

/**
 * Writer
 */
@Bean("studentItemWriter")
public JdbcBatchItemWriter<Student> studentItemWriter() {
    return new JdbcBatchItemWriterBuilder<Student>()
        .itemSqlParameterSourceProvider(new BeanPropertyItemSqlParameterSourceProvider<>())
        .sql("INSERT INTO student_target (student_id, name, address) VALUES (:studentId, :name, :address)")
        .dataSource(batchDemoDB)
        .build();
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

启动应用，文件中的数据已导入表 `student`：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/3_18_46_44_database_writer_result.png)

##### 2.3 StaxEventItemWriter-XML 文件数据输出

将 `ticket.csv` 中的信息，输出到文件 `ticket_output.xml` 中：

```java
/**
 * Job
 */
@Bean
public Job testXmlItemWriterJob() {
    return jobBuilderFactory.get("testXmlItemWriterJob")
        .incrementer(new RunIdIncrementer())
        .flow(testXmlItemWriterStep)
        .build();
}

/**
 * Step
 */
@Bean("testXmlItemWriterStep")
public Step testXmlItemWriterStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testXmlItemWriterStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketFileItemReader)
        .writer(ticketXmlItemWriter)
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

/**
 * Writer
 */
@Bean("ticketXmlItemWriter")
public StaxEventItemWriter<Ticket> ticketXmlItemWriter() {
    return new StaxEventItemWriterBuilder<Ticket>()
        .name("ticketXmlItemWriter")
        .marshaller(ticketMarshaller)
        .resource(new FileSystemResource("ticket_output.xml"))
        .rootTagName("tickets")
        .overwriteOutput(true)
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

启动应用，生成文件 `ticket_output.xml`：

```xml
<?xml version="1.0" encoding="UTF-8"?><tickets><ticket><departureStation>合肥</departureStation><arrivalStation>蚌埠</arrivalStation><price>60.00</price></ticket><ticket><departureStation>南京</departureStation><arrivalStation>蚌埠</arrivalStation><price>70.00</price></ticket><ticket><departureStation>上海</departureStation><arrivalStation>蚌埠</arrivalStation><price>220.00</price></ticket><ticket><departureStation>上海</departureStation><arrivalStation>杭州</arrivalStation><price>75.20</price></ticket><ticket><departureStation>上海</departureStation><arrivalStation>昆山</arrivalStation><price>19.00</price></ticket></tickets>
```

##### 2.4 JsonFileItemWriter-JSON文件数据输出

将 `ticket.csv` 中的信息，输出到文件 `ticket_output.json` 中：

```java
/**
 * Job
 */
@Bean
public Job testJsonItemWriterJob() {
    return jobBuilderFactory.get("testJsonItemWriterJob")
        .incrementer(new RunIdIncrementer())
        .flow(testJsonItemWriterStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testJsonItemWriterStep")
public Step testJsonItemWriterStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testJsonItemWriterStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketFileItemReader)
        .writer(ticketJsonItemWriter)
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

/**
 * Writer
 */
@Bean("ticketJsonItemWriter")
public JsonFileItemWriter<Ticket> ticketJsonItemWriter() {
    return new JsonFileItemWriterBuilder<Ticket>()
        .jsonObjectMarshaller(new JacksonJsonObjectMarshaller<>())
        .resource(new FileSystemResource("ticket_output.json"))
        .name("ticketJsonItemWriter")
        .build();
}
```

启动应用，生成文件 `ticket_output.json`：

```json
[
 {"departureStation":"合肥","arrivalStation":"蚌埠","price":60.00},
 {"departureStation":"南京","arrivalStation":"蚌埠","price":70.00},
 {"departureStation":"上海","arrivalStation":"蚌埠","price":220.00},
 {"departureStation":"上海","arrivalStation":"杭州","price":75.20},
 {"departureStation":"上海","arrivalStation":"昆山","price":19.00}
]
```

##### 2.5 ClassifierCompositeItemWriter-输出多文本数据

将文件 `ticket.csv` 中始发站为**上海**的车票信息输出到文本中，其余的输出到 XML 文件中：

```java
/**
 * Job
 */
@Bean
public Job testMultiFileItemWriterJob() {
    return jobBuilderFactory.get("testMultiFileItemWriterJob")
        .incrementer(new RunIdIncrementer())
        .flow(testMultiFileItemWriterStep)
        .end()
        .build();
}

/**
 * Step
 */
@Bean("testMultiFileItemWriterStep")
public Step testMultiFileItemWriterStep(PlatformTransactionManager transactionManager) {
    return stepBuilderFactory.get("testMultiFileItemWriterStep")
        .transactionManager(transactionManager)
        .<Ticket, Ticket>chunk(10)
        .reader(ticketFileItemReader)
        .writer(ticketClassifierMultiFileItemWriter)
        .stream(ticketFileItemWriter)
        .stream(ticketXmlItemWriter)
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

/**
 * Classifier Writer
 */
@Bean("ticketClassifierMultiFileItemWriter")
public ClassifierCompositeItemWriter<Ticket> ticketClassifierMultiFileItemWriter() {
    ClassifierCompositeItemWriter<Ticket> writer = new ClassifierCompositeItemWriter<>();
    writer.setClassifier((Classifier<Ticket, ItemWriter<? super Ticket>>) ticket -> {
        // 始发站是上海的, 输出到文本中, 否则输出到 XML 文件中
        return "上海".equals(ticket.getDepartureStation()) ? ticketFileItemWriter() : ticketXmlItemWriter();
    });
    return writer;
}

/**
 * 文本-Writer
 */
@Bean("ticketFileItemWriter")
public FlatFileItemWriter<Ticket> ticketFileItemWriter() {

    // 聚合器; JSON 序列化
    LineAggregator<Ticket> aggregator = item -> {
        try {
            ObjectMapper mapper = new ObjectMapper();
            return mapper.writeValueAsString(item);
        } catch (JsonProcessingException e) {
            LOGGER.error("parse object to json error: {}", e.getMessage(), e);
        }
        return "";
    };

    return new FlatFileItemWriterBuilder<Ticket>()
        .name("ticketFileItemWriter")
        .resource(new FileSystemResource("ticket_output.txt"))
        .lineAggregator(aggregator)
        .build();
}

/**
 * XML-Writer
 */
@Bean("ticketXmlItemWriter")
public StaxEventItemWriter<Ticket> ticketXmlItemWriter() {
    return new StaxEventItemWriterBuilder<Ticket>()
        .name("ticketXmlItemWriter")
        .marshaller(ticketMarshaller)
        .resource(new FileSystemResource("ticket_output.xml"))
        .rootTagName("tickets")
        .overwriteOutput(true)
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

启动应用，生成文件如下：

`ticket_output.txt`：

```txt
{"departureStation":"上海","arrivalStation":"蚌埠","price":220.00}
{"departureStation":"上海","arrivalStation":"杭州","price":75.20}
{"departureStation":"上海","arrivalStation":"昆山","price":19.00}
```

`ticket_output.xml`：

```xml
<?xml version="1.0" encoding="UTF-8"?><tickets><ticket><departureStation>合肥</departureStation><arrivalStation>蚌埠</arrivalStation><price>60.00</price></ticket><ticket><departureStation>南京</departureStation><arrivalStation>蚌埠</arrivalStation><price>70.00</price></ticket></tickets>
```



示例代码：[spring-batch-demo](https://github.com/donehub/spring-batch-demo)