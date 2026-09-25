---
title: MySQL Batch Processing
date: 2021-12-24 01:28:45
lang: en
label: 031_mysql_batch_operation
tags: MySQL
categories: Database
---

-----

<!-- more -->
#### 1. Introduction

When executing multiple INSERT, DELETE, or UPDATE statements, `mysql-connector-java` supports two modes:

* Serial execution: statements are sent one by one;
* Batch execution: statements are grouped and sent in batches;

Batch processing mode groups statements into packets according to a batch size algorithm and sends them to the database server together, improving performance for large-scale operations. To enable it, append `rewriteBatchedStatements=true` to your JDBC URL:

```properties
spring.datasource.batch-demo.jdbc-url=jdbc:mysql://127.0.0.1:3306/batch-demo?rewriteBatchedStatements=true
```

#### 2. How MySQL Batch Processing Works

The following source code references `ClientPreparedStatement.java` from `mysql-connector-java` version `8.0.28`.

```java
@Override
protected long[] executeBatchInternal() throws SQLException {
    synchronized (checkClosed().getConnectionMutex()) {
        // Connection must not be read-only
        if (this.connection.isReadOnly()) {
            throw new SQLException(Messages.getString("PreparedStatement.25") + Messages.getString("PreparedStatement.26"), MysqlErrorNumbers.SQL_STATE_ILLEGAL_ARGUMENT);
        }
        
        // Batch must contain at least one statement
        if (this.query.getBatchedArgs() == null || this.query.getBatchedArgs().size() == 0) {
            return new long[0];
        }

        // we timeout the entire batch, not individual statements
        int batchTimeout = getTimeoutInMillis();
        setTimeoutInMillis(0);

        resetCancelledState();

        try {
            statementBegins();

            clearWarnings();

            // 1. No plain SQL statements and batch rewrite is enabled
            // batchHasPlainStatements means plain SQL is present
            // rewriteBatchedStatements enables batch rewriting
            if (!this.batchHasPlainStatements && this.rewriteBatchedStatements.getValue()) {
                // 1.1 INSERT statements can be rewritten as multi-value inserts
                if (getParseInfo().canRewriteAsMultiValueInsertAtSqlLevel()) {
                    // Execute batch insert
                    return executeBatchedInserts(batchTimeout);
                }

                // 1.2 DELETE/UPDATE statements, no plain SQL, and batch size > 3
                if (!this.batchHasPlainStatements && this.query.getBatchedArgs() != null
                    && this.query.getBatchedArgs().size() > 3) {
                    // Execute batch delete or update
                    return executePreparedBatchAsMultiStatement(batchTimeout);
                }
            }

            // 2. Fall back to serial execution
            return executeBatchSerially(batchTimeout);
        } finally {
            this.query.getStatementExecuting().set(false);

            clearBatch();
        }
    }
}
```

The source code makes the core requirement clear: MySQL batch processing needs statements that don't contain raw SQL strings, and the connection must support batch rewriting. INSERT and DELETE/UPDATE use different rewriting rules — INSERT merges values clauses while DELETE/UPDATE concatenates with semicolons — so the INSERT batch process gets its own implementation.

A simple example of raw SQL that would prevent batch optimization:

```java
PreparedStatement preparedStatement = connection.prepareStatement("");
for (int i = 0; i < 10; i++) {
    StringBuilder sql = new StringBuilder();
    sql.append("INSERT INTO extenal_studentcj(grade,clazz,zkzh,NAME,scoretext,times) VALUES(");
    sql.append("'").append(i).append("',");
    sql.append("'").append(i).append("',");
    sql.append("'").append(i).append("',");
    sql.append("'").append(i).append("',");
    sql.append("'").append(i).append("',");
    sql.append("'").append(i).append("'");
    sql.append(");");
    pst.addBatch(sql.toString());
}

preparedStatement.executeBatch();
```

 ##### 2.1 Insert Batch Processing

Core implementation:

```java
protected long[] executeBatchedInserts(int batchTimeout) throws SQLException {
    synchronized (checkClosed().getConnectionMutex()) {
        // Get the value template, e.g., (?, ?, ?)
        String valuesClause = getParseInfo().getValuesClause();

        JdbcConnection locallyScopedConn = this.connection;

        if (valuesClause == null) {
            return executeBatchSerially(batchTimeout);
        }

        // Total number of INSERT statements
        int numBatchedArgs = this.query.getBatchedArgs().size();

        if (this.retrieveGeneratedKeys) {
            this.batchedGeneratedKeys = new ArrayList<>(numBatchedArgs);
        }

        // Calculate the number of statements per batch
        int numValuesPerBatch = ((PreparedQuery<?>) this.query).computeBatchSize(numBatchedArgs);

        if (numBatchedArgs < numValuesPerBatch) {
            numValuesPerBatch = numBatchedArgs;
        }

        JdbcPreparedStatement batchedStatement = null;

        int batchedParamIndex = 1;
        long updateCountRunningTotal = 0;
        int numberToExecuteAsMultiValue = 0;
        int batchCounter = 0;
        CancelQueryTask timeoutTask = null;
        SQLException sqlEx = null;

        long[] updateCounts = new long[numBatchedArgs];

        try {
            try {
                // Build the batch INSERT prepared statement
                batchedStatement = prepareBatchedInsertSQL(locallyScopedConn, numValuesPerBatch);

                timeoutTask = startQueryTimer(batchedStatement, batchTimeout);
                
                // Calculate how many batch rounds are needed
                numberToExecuteAsMultiValue = numBatchedArgs < numValuesPerBatch ? numBatchedArgs : numBatchedArgs / numValuesPerBatch;

                // Calculate total statements to execute in full batches
                int numberArgsToExecute = numberToExecuteAsMultiValue * numValuesPerBatch;

                // Fill in values and execute batch by batch
                for (int i = 0; i < numberArgsToExecute; i++) {
                    // When a full batch is filled, execute it before starting the next batch
                    if (i != 0 && i % numValuesPerBatch == 0) {
                        try {
                            updateCountRunningTotal += batchedStatement.executeLargeUpdate();
                        } catch (SQLException ex) {
                            sqlEx = handleExceptionForBatch(batchCounter - 1, numValuesPerBatch, updateCounts, ex);
                        }

                        getBatchedGeneratedKeys(batchedStatement);
                        batchedStatement.clearParameters();
                        batchedParamIndex = 1;
                    }

                    batchedParamIndex = setOneBatchedParameterSet(batchedStatement, batchedParamIndex, this.query.getBatchedArgs().get(batchCounter++));
                }

                try {
                    updateCountRunningTotal += batchedStatement.executeLargeUpdate();
                } catch (SQLException ex) {
                    sqlEx = handleExceptionForBatch(batchCounter - 1, numValuesPerBatch, updateCounts, ex);
                }

                getBatchedGeneratedKeys(batchedStatement);

                numValuesPerBatch = numBatchedArgs - batchCounter;
            } finally {
                if (batchedStatement != null) {
                    batchedStatement.close();
                    batchedStatement = null;
                }
            }

            // Handle any remaining statements that didn't fill a complete batch
            try {
                if (numValuesPerBatch > 0) {
                    batchedStatement = prepareBatchedInsertSQL(locallyScopedConn, numValuesPerBatch);

                    if (timeoutTask != null) {
                        timeoutTask.setQueryToCancel(batchedStatement);
                    }

                    batchedParamIndex = 1;

                    while (batchCounter < numBatchedArgs) {
                        batchedParamIndex = setOneBatchedParameterSet(batchedStatement, batchedParamIndex, this.query.getBatchedArgs().get(batchCounter++));
                    }

                    try {
                        updateCountRunningTotal += batchedStatement.executeLargeUpdate();
                    } catch (SQLException ex) {
                        sqlEx = handleExceptionForBatch(batchCounter - 1, numValuesPerBatch, updateCounts, ex);
                    }

                    getBatchedGeneratedKeys(batchedStatement);
                }

                if (sqlEx != null) {
                    throw SQLError.createBatchUpdateException(sqlEx, updateCounts, this.exceptionInterceptor);
                }

                if (numBatchedArgs > 1) {
                    long updCount = updateCountRunningTotal > 0 ? java.sql.Statement.SUCCESS_NO_INFO : 0;
                    for (int j = 0; j < numBatchedArgs; j++) {
                        updateCounts[j] = updCount;
                    }
                } else {
                    updateCounts[0] = updateCountRunningTotal;
                }
                return updateCounts;
            } finally {
                if (batchedStatement != null) {
                    batchedStatement.close();
                }
            }
        } finally {
            stopQueryTimer(timeoutTask, false, false);
            resetCancelledState();
        }
    }
}
```

The INSERT batch process divides all statements into groups of a fixed batch size, executes each group, then handles any leftover statements that didn't fill a complete batch in a final pass. For 100,000 student records, the flow looks like this:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/4_22_34_26_mysql_batch_insert.png)

##### 2.2 Delete and Update Batch Processing

Core implementation:

```java
protected long[] executePreparedBatchAsMultiStatement(int batchTimeout) throws SQLException {
    synchronized (checkClosed().getConnectionMutex()) {
        // This is kind of an abuse, but it gets the job done
        if (this.batchedValuesClause == null) {
            this.batchedValuesClause = ((PreparedQuery<?>) this.query).getOriginalSql() + ";";
        }

        JdbcConnection locallyScopedConn = this.connection;

        boolean multiQueriesEnabled = locallyScopedConn.getPropertySet().getBooleanProperty(PropertyKey.allowMultiQueries).getValue();
        CancelQueryTask timeoutTask = null;

        try {
            clearWarnings();

            // Total number of statements
            int numBatchedArgs = this.query.getBatchedArgs().size();

            if (this.retrieveGeneratedKeys) {
                this.batchedGeneratedKeys = new ArrayList<>(numBatchedArgs);
            }

            // Calculate the number of statements per batch
            int numValuesPerBatch = ((PreparedQuery<?>) this.query).computeBatchSize(numBatchedArgs);

            if (numBatchedArgs < numValuesPerBatch) {
                numValuesPerBatch = numBatchedArgs;
            }

            java.sql.PreparedStatement batchedStatement = null;

            int batchedParamIndex = 1;
            int numberToExecuteAsMultiValue = 0;
            int batchCounter = 0;
            int updateCountCounter = 0;
            long[] updateCounts = new long[numBatchedArgs * getParseInfo().getNumberOfQueries()];
            SQLException sqlEx = null;

            try {
                if (!multiQueriesEnabled) {
                    ((NativeSession) locallyScopedConn.getSession()).enableMultiQueries();
                }

                // Build the batch statement
                batchedStatement = this.retrieveGeneratedKeys
                    ? ((Wrapper) locallyScopedConn.prepareStatement(generateMultiStatementForBatch(numValuesPerBatch), RETURN_GENERATED_KEYS)).unwrap(java.sql.PreparedStatement.class)
                    : ((Wrapper) locallyScopedConn.prepareStatement(generateMultiStatementForBatch(numValuesPerBatch))).unwrap(java.sql.PreparedStatement.class);

                timeoutTask = startQueryTimer((StatementImpl) batchedStatement, batchTimeout);
                
                // Calculate the number of batch rounds
                numberToExecuteAsMultiValue = numBatchedArgs < numValuesPerBatch ? numBatchedArgs : numBatchedArgs / numValuesPerBatch;

                // Calculate total statements to execute in full batches
                int numberArgsToExecute = numberToExecuteAsMultiValue * numValuesPerBatch;

                // Fill in values and execute batch by batch
                for (int i = 0; i < numberArgsToExecute; i++) {
                    // When a full batch is filled, execute it before starting the next batch
                    if (i != 0 && i % numValuesPerBatch == 0) {
                        try {
                            batchedStatement.execute();
                        } catch (SQLException ex) {
                            sqlEx = handleExceptionForBatch(batchCounter, numValuesPerBatch, updateCounts, ex);
                        }

                        updateCountCounter = processMultiCountsAndKeys((StatementImpl) batchedStatement, updateCountCounter, updateCounts);

                        batchedStatement.clearParameters();
                        batchedParamIndex = 1;
                    }

                    batchedParamIndex = setOneBatchedParameterSet(batchedStatement, batchedParamIndex, this.query.getBatchedArgs().get(batchCounter++));
                }

                try {
                    batchedStatement.execute();
                } catch (SQLException ex) {
                    sqlEx = handleExceptionForBatch(batchCounter - 1, numValuesPerBatch, updateCounts, ex);
                }

                updateCountCounter = processMultiCountsAndKeys((StatementImpl) batchedStatement, updateCountCounter, updateCounts);

                batchedStatement.clearParameters();

                numValuesPerBatch = numBatchedArgs - batchCounter;

                if (timeoutTask != null) {
                    // we need to check the cancel state now because we loose if after the following batchedStatement.close()
                    ((JdbcPreparedStatement) batchedStatement).checkCancelTimeout();
                }
            } finally {
                if (batchedStatement != null) {
                    batchedStatement.close();
                    batchedStatement = null;
                }
            }

            // Handle any remaining statements that didn't fill a complete batch
            try {
                if (numValuesPerBatch > 0) {

                    batchedStatement = this.retrieveGeneratedKeys
                        ? locallyScopedConn.prepareStatement(generateMultiStatementForBatch(numValuesPerBatch), RETURN_GENERATED_KEYS)
                        : locallyScopedConn.prepareStatement(generateMultiStatementForBatch(numValuesPerBatch));

                    if (timeoutTask != null) {
                        timeoutTask.setQueryToCancel((Query) batchedStatement);
                    }
                    
                    batchedParamIndex = 1;

                    while (batchCounter < numBatchedArgs) {
                        batchedParamIndex = setOneBatchedParameterSet(batchedStatement, batchedParamIndex, this.query.getBatchedArgs().get(batchCounter++));
                    }

                    try {
                        batchedStatement.execute();
                    } catch (SQLException ex) {
                        sqlEx = handleExceptionForBatch(batchCounter - 1, numValuesPerBatch, updateCounts, ex);
                    }

                    updateCountCounter = processMultiCountsAndKeys((StatementImpl) batchedStatement, updateCountCounter, updateCounts);

                    batchedStatement.clearParameters();
                }

                if (timeoutTask != null) {
                    stopQueryTimer(timeoutTask, true, true);
                    timeoutTask = null;
                }

                if (sqlEx != null) {
                    throw SQLError.createBatchUpdateException(sqlEx, updateCounts, this.exceptionInterceptor);
                }

                return updateCounts;
            } finally {
                if (batchedStatement != null) {
                    batchedStatement.close();
                }
            }
        } finally {
            stopQueryTimer(timeoutTask, false, false);
            resetCancelledState();

            if (!multiQueriesEnabled) {
                ((NativeSession) locallyScopedConn.getSession()).disableMultiQueries();
            }

            clearBatch();
        }
    }
}
```

DELETE and UPDATE batching follows the same pattern as INSERT. The difference is in how statements get combined: DELETE and UPDATE statements are joined with semicolons, while INSERT statements merge their VALUES clauses. For 100,000 student records, the flow looks like this:

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/4_23_0_12_mysql_batch_update.png)

#### 3. Performance Testing

##### 3.1 Batch inserting 100,000 student records:

```java
public void batchInsert() {
    
    long start = System.currentTimeMillis();

    Connection connection = null;
    
    String sqlTemplate = "INSERT INTO student_target(student_id, name, address) VALUES (?, ?, ?)";
    
    try {
        // Query all 100,000 records
        List<Student> studentList = studentMapper.queryAll();
        
        // Get database connection
        connection = batchDemoDB.getConnection();
        
        connection.setAutoCommit(false);

        PreparedStatement preparedStatement = connection.prepareStatement(sqlTemplate);
        for (Student student : studentList) {
            preparedStatement.setLong(1, student.getStudentId());
            preparedStatement.setString(2, student.getName());
            preparedStatement.setString(3, student.getAddress());
            preparedStatement.addBatch();
        }
        
        preparedStatement.executeBatch();

        connection.commit();
    } catch (Exception e) {
        try {
            connection.rollback();
        } catch (Exception e2) {
            LOGGER.error("transaction rollback failed: {}", e2.getMessage(), e2);
        }
        LOGGER.error("batch insert student info error: {}", e.getMessage(), e);
    } finally {
        try {
            connection.close();
        } catch (Exception e) {
            LOGGER.error("connection close error: {}", e.getMessage(), e);
        }
    }

    LOGGER.info("Inserted 100,000 records in: {} ms", System.currentTimeMillis() - start);
}
```

* `rewriteBatchedStatements=false`:

  ```java
  Inserted 100,000 records in: 18652 ms
  ```

* `rewriteBatchedStatements=true`:

  ```java
  Inserted 100,000 records in: 2404 ms
  ```

##### 3.2 Batch updating 100,000 student records

```java
public void batchUpdate() {

    long start = System.currentTimeMillis();

    Connection connection = null;
    
    String sqlTemplate = "UPDATE student_target set address = ? WHERE student_id = ?";
    
    try {
        // Query all 100,000 records
        List<Student> studentList = studentMapper.queryAll();

        // Get database connection
        connection = batchDemoDB.getConnection();
        
        connection.setAutoCommit(false);

        PreparedStatement preparedStatement = connection.prepareStatement(sqlTemplate);
        for (Student student : studentList) {
            preparedStatement.setString(1, student.getName() + "_test");
            preparedStatement.setLong(2, student.getStudentId());
            preparedStatement.addBatch();
        }
        
        preparedStatement.executeBatch();

        connection.commit();
    } catch (Exception e) {
        try {
            connection.rollback();
        } catch (Exception e2) {
            LOGGER.error("transaction rollback failed: {}", e2.getMessage(), e2);
        }
        LOGGER.error("batch update student info error: {}", e.getMessage(), e);
    } finally {
        try {
            connection.close();
        } catch (Exception e) {
            LOGGER.error("connection close error: {}", e.getMessage(), e);
        }
    }
    
    LOGGER.info("Updated 100,000 records in: {} ms", System.currentTimeMillis() - start);
}
```

* `rewriteBatchedStatements=false`:

  ```java
  Updated 100,000 records in: 25579 ms
  ```

* `rewriteBatchedStatements=true`:

  ```java
  Updated 100,000 records in: 10122 ms
  ```

##### 3.3 Batch deleting 100,000 student records

```java
public void batchDelete() {
    
    long start = System.currentTimeMillis();

    Connection connection = null;
    
    String sqlTemplate = "DELETE FROM student_target WHERE student_id = ?";
    
    try {
        // Query all 100,000 records
        List<Student> studentList = studentMapper.queryAll();

        // Get database connection
        connection = batchDemoDB.getConnection();
        
        connection.setAutoCommit(false);

        PreparedStatement preparedStatement = connection.prepareStatement(sqlTemplate);
        for (Student student : studentList) {
            preparedStatement.setLong(1, student.getStudentId());
            preparedStatement.addBatch();
        }
        
        preparedStatement.executeBatch();

        connection.commit();
    } catch (Exception e) {
        try {
            connection.rollback();
        } catch (Exception e2) {
            LOGGER.error("transaction rollback failed: {}", e2.getMessage(), e2);
        }
        LOGGER.error("batch delete student info error: {}", e.getMessage(), e);
    } finally {
        try {
            connection.close();
        } catch (Exception e) {
            LOGGER.error("connection close error: {}", e.getMessage(), e);
        }
    }

    LOGGER.info("Deleted 100,000 records in: {} ms", System.currentTimeMillis() - start);
}
```

* `rewriteBatchedStatements=false`:

  ```java
  Deleted 100,000 records in: 20817 ms
  ```

* `rewriteBatchedStatements=true`:

  ```java
  Deleted 100,000 records in: 12053 ms
  ```
