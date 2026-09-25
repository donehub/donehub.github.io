---
title: Spring Batch Item Writers
date: 2022-02-03 23:21:35
tags: Spring
categories: Backend
lang: en
label: 036_spring_batch_item_writers
---

-----

<!-- more -->
#### 1. Spring Batch Item Writers

Spring Batch writes data through the `ItemWriter` interface. For common output scenarios, the framework ships with several built-in options ([see the full list](https://docs.spring.io/spring-batch/docs/current/reference/html/appendix.html#itemWritersAppendix)). This article covers the five most commonly used writers:

* `FlatFileItemWriter`: writes plain text data;
* `JdbcBatchItemWriter`: writes data to a database via JDBC;
* `StaxEventItemWriter`: writes XML files;
* `JsonFileItemWriter`: writes JSON files;
* `ClassifierCompositeItemWriter`: routes items to different writers based on a classifier;

#### 2. Basic Usage

Entity class `Ticket.class`:

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

Input file `ticket.csv`:

```csv
合肥,蚌埠,60.00
南京,蚌埠,70.00
上海,蚌埠,220.00
上海,杭州,75.20
上海,昆山,19.00
```

##### 2.1 FlatFileItemWriter — Plain Text Output

The following configuration reads `ticket.csv`, converts each record into a JSON string, and writes the result to `ticket_output.txt`:

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

    // Line aggregator: serialize each Ticket to JSON
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

Writing text output means converting each POJO into a string. Spring Batch ships with several `LineAggregator` implementations: `PassThroughLineAggregator` (calls `toString()`), `RecursiveCollectionLineAggregator` (prints collections), `DelimitedLineAggregator` (joins fields with a delimiter), and `FormatterLineAggregator` (formats fields using `Formatter`). You can also write a custom aggregator, as shown above where we serialize the POJO to JSON.

After starting the application, the output file `ticket_output.txt` looks like this:

```tXT
{"departureStation":"合肥","arrivalStation":"蚌埠","price":60.00}
{"departureStation":"南京","arrivalStation":"蚌埠","price":70.00}
{"departureStation":"上海","arrivalStation":"蚌埠","price":220.00}
{"departureStation":"上海","arrivalStation":"杭州","price":75.20}
{"departureStation":"上海","arrivalStation":"昆山","price":19.00}
```

##### 2.2 JdbcBatchItemWriter — Database Output

This example imports records from `student.csv` into the MySQL table `student`:

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
 * MySQL datasource configuration
 */
@Primary
@Bean(name = "batchDemoDB")
@ConfigurationProperties(prefix = "spring.datasource.batch-demo")
public DataSource druidDataSource() {
    return DataSourceBuilder.create().type(HikariDataSource.class).build();
}
```

After startup, the CSV data is imported into the `student` table:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/06/3_18_46_44_database_writer_result.png)

##### 2.3 StaxEventItemWriter — XML Output

This example reads `ticket.csv` and writes the records to `ticket_output.xml`:

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
 * Marshaller — maps Ticket fields to XML elements
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

After startup, the generated `ticket_output.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?><tickets><ticket><departureStation>合肥</departureStation><arrivalStation>蚌埠</arrivalStation><price>60.00</price></ticket><ticket><departureStation>南京</departureStation><arrivalStation>蚌埠</arrivalStation><price>70.00</price></ticket><ticket><departureStation>上海</departureStation><arrivalStation>蚌埠</arrivalStation><price>220.00</price></ticket><ticket><departureStation>上海</departureStation><arrivalStation>杭州</arrivalStation><price>75.20</price></ticket><ticket><departureStation>上海</departureStation><arrivalStation>昆山</arrivalStation><price>19.00</price></ticket></tickets>
```

##### 2.4 JsonFileItemWriter — JSON Output

This example reads `ticket.csv` and writes the records to `ticket_output.json`:

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

After startup, the generated `ticket_output.json`:

```json
[
 {"departureStation":"合肥","arrivalStation":"蚌埠","price":60.00},
 {"departureStation":"南京","arrivalStation":"蚌埠","price":70.00},
 {"departureStation":"上海","arrivalStation":"蚌埠","price":220.00},
 {"departureStation":"上海","arrivalStation":"杭州","price":75.20},
 {"departureStation":"上海","arrivalStation":"昆山","price":19.00}
]
```

##### 2.5 ClassifierCompositeItemWriter — Multi-Target Output

This example routes tickets with a departure station of **Shanghai** to a text file, and sends the rest to an XML file:

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
 * Classifier Writer — routes items by departure station
 */
@Bean("ticketClassifierMultiFileItemWriter")
public ClassifierCompositeItemWriter<Ticket> ticketClassifierMultiFileItemWriter() {
    ClassifierCompositeItemWriter<Ticket> writer = new ClassifierCompositeItemWriter<>();
    writer.setClassifier((Classifier<Ticket, ItemWriter<? super Ticket>>) ticket -> {
        // Tickets departing from Shanghai go to text; the rest go to XML
        return "上海".equals(ticket.getDepartureStation()) ? ticketFileItemWriter() : ticketXmlItemWriter();
    });
    return writer;
}

/**
 * Text Writer
 */
@Bean("ticketFileItemWriter")
public FlatFileItemWriter<Ticket> ticketFileItemWriter() {

    // Line aggregator: serialize each Ticket to JSON
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
 * XML Writer
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
 * Marshaller — maps Ticket fields to XML elements
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

After startup, two output files are generated:

`ticket_output.txt`:

```txt
{"departureStation":"上海","arrivalStation":"蚌埠","price":220.00}
{"departureStation":"上海","arrivalStation":"杭州","price":75.20}
{"departureStation":"上海","arrivalStation":"昆山","price":19.00}
```

`ticket_output.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?><tickets><ticket><departureStation>合肥</departureStation><arrivalStation>蚌埠</arrivalStation><price>60.00</price></ticket><ticket><departureStation>南京</departureStation><arrivalStation>蚌埠</arrivalStation><price>70.00</price></ticket></tickets>
```



Sample code: [spring-batch-demo](https://github.com/donehub/spring-batch-demo)