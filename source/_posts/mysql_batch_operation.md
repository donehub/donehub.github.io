---
title: MySQL 批处理
date: 2021-12-24 01:28:45
tags: MySQL
categories: 数据库
---

-----

#### 一、MySQL 批处理介绍

执行多条增、删、改语句，`mysql-connector-java`  支持两种模式：

* 串行化语句，一条一条发送；
* 打包语句，分批次发送；

批处理模式，即按照包容量算法，将语句分批打包，发送到数据库服务器，旨在提升大批量语句的执行性能。在数据库连接参数 `jdbc-url` 后追加 `rewriteBatchedStatements=true` 即可完成配置，如：

```properties
spring.datasource.batch-demo.jdbc-url=jdbc:mysql://127.0.0.1:3306/batch-demo?rewriteBatchedStatements=true
```

#### 二、MySQL 批处理基础实现

以下源码参照 `ClientPreparedStatement.java`，`mysql-connector-java` `8.0.28` 版本。

```java
@Override
protected long[] executeBatchInternal() throws SQLException {
    synchronized (checkClosed().getConnectionMutex()) {
        // 不能是只读连接
        if (this.connection.isReadOnly()) {
            throw new SQLException(Messages.getString("PreparedStatement.25") + Messages.getString("PreparedStatement.26"), MysqlErrorNumbers.SQL_STATE_ILLEGAL_ARGUMENT);
        }
        
        // 批量语句大小必须大于 0
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

            // 1. 没有包含原始 sql 并且支持批量重写
            // batchHasPlainStatements 包含原始 sql
            // rewriteBatchedStatements 支持批量重写
            if (!this.batchHasPlainStatements && this.rewriteBatchedStatements.getValue()) {
                // 1.1 批量插入语句，支持多值重写
                if (getParseInfo().canRewriteAsMultiValueInsertAtSqlLevel()) {
                    // 执行批量 insert 
                    return executeBatchedInserts(batchTimeout);
                }

                // 1.2 删、改操作, 没有包含原始 sql 并且批次语句数量大于 3
                if (!this.batchHasPlainStatements && this.query.getBatchedArgs() != null
                    && this.query.getBatchedArgs().size() > 3) {
                    // 执行批量 delete 或 update
                    return executePreparedBatchAsMultiStatement(batchTimeout);
                }
            }

            // 2. 串行执行语句
            return executeBatchSerially(batchTimeout);
        } finally {
            this.query.getStatementExecuting().set(false);

            clearBatch();
        }
    }
}
```

从源码实现可知，`MySQL` 的批处理操作，要求语句不包含原生 `sql`，且数据连接支持批量重写。因为 `insert` 语句的批量重写规则（多值拼接）与 `delete`、`update` 语句（英文分号拼接）不同 ，因此独立出 `insert` 批处理过程。

原生 `sql` 的简单示例：

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

 ##### 2.1 Insert 批处理

基础实现：

```java
protected long[] executeBatchedInserts(int batchTimeout) throws SQLException {
    synchronized (checkClosed().getConnectionMutex()) {
        // 获取语句值模板; 如 (?, ?, ?)
        String valuesClause = getParseInfo().getValuesClause();

        JdbcConnection locallyScopedConn = this.connection;

        if (valuesClause == null) {
            return executeBatchSerially(batchTimeout);
        }

        // insert 语句总数
        int numBatchedArgs = this.query.getBatchedArgs().size();

        if (this.retrieveGeneratedKeys) {
            this.batchedGeneratedKeys = new ArrayList<>(numBatchedArgs);
        }

        // 计算每个批次的语句数量
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
                // 构建批量 insert 预编译语句
                batchedStatement = prepareBatchedInsertSQL(locallyScopedConn, numValuesPerBatch);

                timeoutTask = startQueryTimer(batchedStatement, batchTimeout);
                
                // 计算需要批量 insert 的次数
                numberToExecuteAsMultiValue = numBatchedArgs < numValuesPerBatch ? numBatchedArgs : numBatchedArgs / numValuesPerBatch;

                // 计算 batchedStatement 需要 insert 的语句总量
                int numberArgsToExecute = numberToExecuteAsMultiValue * numValuesPerBatch;

                // 循环填补 insert 值
                for (int i = 0; i < numberArgsToExecute; i++) {
                    // 填补完一个批次, 发起执行, 然后再填补下一个批次
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

            // 如果按照以上批次执行, 仍有未执行的语句, 则在这里统一执行
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

从源码实现可知，`insert` 语句批处理，首先会按照一定的批次大小处理语句，剩余不够一个批次执行的，最后会交给保底任务执行。以插入10万条学生信息数据为例，具体的处理流程如下：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/4_22_34_26_mysql_batch_insert.png)

##### 2.2 Delete、Update 批处理

基础实现：

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

            // 语句总数
            int numBatchedArgs = this.query.getBatchedArgs().size();

            if (this.retrieveGeneratedKeys) {
                this.batchedGeneratedKeys = new ArrayList<>(numBatchedArgs);
            }

            // 计算每个批次的语句数量
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

                // 构建批处理语句
                batchedStatement = this.retrieveGeneratedKeys
                    ? ((Wrapper) locallyScopedConn.prepareStatement(generateMultiStatementForBatch(numValuesPerBatch), RETURN_GENERATED_KEYS)).unwrap(java.sql.PreparedStatement.class)
                    : ((Wrapper) locallyScopedConn.prepareStatement(generateMultiStatementForBatch(numValuesPerBatch))).unwrap(java.sql.PreparedStatement.class);

                timeoutTask = startQueryTimer((StatementImpl) batchedStatement, batchTimeout);
                
                // 计算批处理次数
                numberToExecuteAsMultiValue = numBatchedArgs < numValuesPerBatch ? numBatchedArgs : numBatchedArgs / numValuesPerBatch;

                // 计算 batchedStatement 需要执行的语句数量
                int numberArgsToExecute = numberToExecuteAsMultiValue * numValuesPerBatch;

                // 循环填补语句值
                for (int i = 0; i < numberArgsToExecute; i++) {
                    // 填补完一个批次, 发起执行, 然后再填补下一个批次
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

            // 如果按照以上批次执行, 仍有未执行的语句, 则在这里统一执行
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

`delete`、`update` 语句的批处理方案，与 `insert` 类似，区别在于 `delete`、`update` 语句是用英文分号拼接起来的，而 `insert` 语句是将 `values` 拼接起来的。以更新10万条学生信息数据为例，具体的处理流程如下：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/05/4_23_0_12_mysql_batch_update.png)

#### 三、MySQL 批处理性能测试

##### 3.1 批量插入 100000 条学生信息：

```java
public void batchInsert() {
    
    long start = System.currentTimeMillis();

    Connection connection = null;
    
    String sqlTemplate = "INSERT INTO student_target(student_id, name, address) VALUES (?, ?, ?)";
    
    try {
        // 查询10万条数据
        List<Student> studentList = studentMapper.queryAll();
        
        // 获取数据连接
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

    LOGGER.info("插入100000条数据, 耗时: {} ms", System.currentTimeMillis() - start);
}
```

* `rewriteBatchedStatements=false`：

  ```java
  插入100000条数据, 耗时: 18652 ms
  ```

* `rewriteBatchedStatements=true`：

  ```java
  插入100000条数据, 耗时: 2404 ms
  ```

##### 3.2 批量更新 10000 条学生信息

```java
public void batchUpdate() {

    long start = System.currentTimeMillis();

    Connection connection = null;
    
    String sqlTemplate = "UPDATE student_target set address = ? WHERE student_id = ?";
    
    try {
        // 查询10万条数据
        List<Student> studentList = studentMapper.queryAll();

        // 获取数据连接
        connection = batchDemoDB.getConnection();
        
        connection.setAutoCommit(false);

        PreparedStatement preparedStatement = connection.prepareStatement(sqlTemplate);
        for (Student student : studentList) {
            preparedStatement.setString(1, student.getName() + "_呵呵");
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
    
    LOGGER.info("更新100000条数据, 耗时: {} ms", System.currentTimeMillis() - start);
}
```

* `rewriteBatchedStatements=false`：

  ```java
  更新100000条数据, 耗时: 25579 ms
  ```

* `rewriteBatchedStatements=true`：

  ```java
  更新100000条数据, 耗时: 10122 ms
  ```

##### 3.3 批量删除 100000 条学生信息

```java
public void batchDelete() {
    
    long start = System.currentTimeMillis();

    Connection connection = null;
    
    String sqlTemplate = "DELETE FROM student_target WHERE student_id = ?";
    
    try {
        // 查询10万条数据
        List<Student> studentList = studentMapper.queryAll();

        // 获取数据连接
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

    LOGGER.info("删除100000条数据, 耗时: {} ms", System.currentTimeMillis() - start);
}
```

* `rewriteBatchedStatements=false`：

  ```java
  删除100000条数据, 耗时: 20817 ms
  ```

* `rewriteBatchedStatements=true`：

  ```java
  删除100000条数据, 耗时: 12053 ms
  ```