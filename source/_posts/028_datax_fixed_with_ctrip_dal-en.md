---
title: Making DataX Work with Ctrip's Dal Database Framework
date: 2021-11-09 23:57:01
tags: Data Sync
categories: Database
lang: en
label: 028_datax_fixed_with_ctrip_dal
---

-----

<!-- more -->
#### 1. Ctrip's Dal Framework

`Dal` is Ctrip's open-source database access framework, designed to manage large-scale database infrastructure.

On the DB management side, Dal provides a unified data access layer: it supports both Java and C# clients, works with MySQL and SQL Server, handles both ORM and raw SQL access patterns, uses Emit mapping for high-performance ORM, supports multi-datasource configurations with master-slave separation (read-write splitting), and includes built-in logging and monitoring.

On the developer experience side, Dal supports code generation. Through the Dal platform, developers can generate Entity classes, Dao layers, and unit tests with a single click. This frees developers from writing boilerplate DB code and enforces consistent coding standards across teams.

#### 2. The Compatibility Problem

Dal's core design principle is centralized control. Clients don't configure database usernames and passwords directly — they use a `TitanKey` or `ClusterName` issued by Dal, which acts as the credential for database access. This means DataX, which expects traditional JDBC connection parameters, can't work out of the box on a Dal-managed system.

Two problems need to be solved: how to configure DataX with Dal's connection credentials, and how to obtain a DataSource through Dal's API.

#### 3. Configuring DataX with TitanKey or ClusterName

Here's the standard `mysqlwriter` configuration template:

```json
{
    "name": "mysqlwriter",
    "parameter": {
        "username": "",
        "password": "",
        "writeMode": "",
        "column": [],
        "session": [],
        "preSql": [],
        "connection": [
            {
                "jdbcUrl": "",
                "table": []
            }
        ]
    }
}
```

Since Dal doesn't use `username` and `password`, the simplest approach is to place the `TitanKey` or `ClusterName` in the `jdbcUrl` field.

#### 4. Obtaining a Dal DataSource

DataX obtains database connections through the standard JDBC DriverManager:

```java
private static synchronized Connection connect(DataBaseType dataBaseType, String url, Properties prop) {
    try {
        Class.forName(dataBaseType.getDriverClassName());
        DriverManager.setLoginTimeout(Constant.TIMEOUT_SECONDS);
        return DriverManager.getConnection(url, prop);
    } catch (Exception e) {
        throw RdbmsException.asConnException(dataBaseType, e, prop.getProperty("user"), null);
    }
}
```

Dal, on the other hand, obtains connections through its DataSource factory:

```java
import javax.annotation.Resource;
import javax.sql.DataSource;
import java.sql.Connection;
import com.ctrip.datasource.configure.DalDataSourceFactory;

public final class DBUtil {
    
    private DBUtil() {
    }
    
    @Resource
    private DalDataSourceFactory dsFactory;
    
    /**
     * DataSource factory bean
     */
    @Bean
    public DalDataSourceFactory getCtripDalDataSource() {
        return new DalDataSourceFactory();
    }
    
    /**
     * Get connection by titanKey
     */
    public static Connection getConnectionByTitanKey(final String titanKey) {
        try {
            DataSource dataSource = dsFactory.createDataSource(titanKey);
            return dataSource.getConnection();
        } catch (Exception e) {
            throw DataXException
                .asDataXException(DBUtilErrorCode.CONN_DB_ERROR,
                                  String.format("Database connection failed. Unable to get connection with config: %s. Please check your configuration.", titanKey), e);
        }
    }
    
    /**
     * Get connection by clusterName
     */
    public static Connection getConnectionByClusterName(final String clusterName) {
        try {
            DataSource ds = dsFactory.getOrCreateDataSource(clusterName);
            return dataSource.getConnection();
        } catch (Exception e) {
            throw DataXException
                .asDataXException(DBUtilErrorCode.CONN_DB_ERROR,
                                  String.format("Database connection failed. Unable to get connection with config: %s. Please check your configuration.", clusterName), e);
        }
    }
}
```

The solution is straightforward: use Dal's `DataSource` factory to create connections, replacing DataX's default JDBC-based approach.

#### 5. An Optimized Approach

The implementation above has a performance issue — it creates a new DataSource on every sync job. Since Dal already provides a DataSource factory with built-in pooling, we can cache the DataSource instances and reuse them across jobs, using `dbName` as the cache key.

Here's the improved approach: load and cache DataSources during application startup.

`DataSourceConfiguration.class`

```java
import com.alibaba.datax.plugin.rdbms.util.DBUtil;
import com.ctrip.datasource.configure.DalDataSourceFactory;
import com.google.common.base.Throwables;
import com.google.common.collect.Maps;
import org.apache.commons.lang.StringUtils;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.Assert;

import javax.annotation.PostConstruct;
import javax.annotation.Resource;
import javax.sql.DataSource;
import java.util.Map;

/**
 * @author zourongsheng
 */
@Configuration
public class DataSourceConfiguration {
    
    @Resource
    private DalDataSourceFactory dsFactory;

    /**
     * DataSource factory bean
     */
    @Bean
    public DalDataSourceFactory getCtripDalDataSource() {
        return new DalDataSourceFactory();
    }
    
    private static final String CLUSTER_CONN_TYPE_FLAG = "cluster";

    /**
     * Titan key connection info
     */
    public static final String TITAN_KEY_TEST_DB = "test_titan_db";

    /**
     * Cluster name connection info
     */
    public static final String CLUSTER_NAME_TEST_DB = "test_cluster_db";

    /**
     * Load DataSource by titan key
     */
    private void fillDataSourceFromTitanKey(String titanKey) {
        try {
            
            Assert.hasText(titanKey,
                           "connect to db failed; titan key cannot be null or empty");

            DataSource dataSource = dsFactory.createDataSource(titanKey);
            // Cache the DataSource
            DBUtil.setDataSourceIfAbsent(titanKey, dataSource);
        } catch (Exception t) {
            throw Throwables.propagate(t);
        }
    }

    /**
     * Load DataSource by cluster name
     */
    private void fillDataSourceFromClusterName(String clusterName) {
        try {
            Assert.hasText(clusterName,
                           "connect to db failed; dal cluster cannot be null or empty");

            // Validate cluster name format
            Assert.isTrue(clusterName.contains(CLUSTER_CONN_TYPE_FLAG),
                          String.format("%s is not in a cluster format", clusterName));

            DataSource dataSource = dsFactory.getOrCreateDataSource(clusterName);
            // Cache the DataSource
            DBUtil.setDataSourceIfAbsent(clusterName, dataSource);
        } catch (Exception t) {
            throw Throwables.propagate(t);
        }
    }

    @PostConstruct
    public void initDataSource() {

        // Load DataSources by titan key
        fillDataSourceFromTitanKey(TITAN_KEY_TEST_DB);

        // Load DataSources by cluster name
        fillDataSourceFromClusterName(CLUSTER_NAME_TEST_DB);
    }
}
```

`DBUtil.class`

```java
import com.alibaba.datax.common.exception.DataXException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import javax.sql.DataSource;
import java.io.File;
import java.sql.*;
import java.util.*;
import java.util.concurrent.*;

public final class DBUtil {
    
    private DBUtil() {
    }
    
    private static final Logger LOG = LoggerFactory.getLogger(DBUtil.class);
    private static final Map<String, DataSource> DS_MAP = new ConcurrentHashMap<>();
    
    /**
     * Register a DataSource into the engine cache
     *
     * @param dsName DataSource name (used to retrieve the DataSource later)
     * @param ds     DataSource instance
     */
    public static void setDataSourceIfAbsent(String dsName, DataSource ds) {
        if (DS_MAP.containsKey(dsName)) {
            return;
        }
        synchronized (DS_MAP) {
            if (!dsMap.containsKey(dsName)) {
                DS_MAP.put(dsName, ds);
                LOG.info("setDataSourceIfAbsent registered DataSource: {}", dsName);
            }
        }
    }
    
    /**
     * Get a cached DataSource by name
     * @param dsName DataSource name
     * @return DataSource instance
     */
    private static DataSource getDataSource(String dsName) {
        // Strip query parameters from JDBC URLs
        if (dsName.contains("?")) {
            dsName = dsName.substring(0, dsName.indexOf("?"));
        }
        
        return DS_MAP.get(dsName);
    }
    
    /**
     * Get a database connection from the cached DataSource
     * @param dsName DataSource name
     * @return database connection
     */
    public static Connection getConnection(String dsName) {
        try {
            // Get the cached DataSource
            DataSource dataSource = getDataSource(dsName);
            
            Assert.notNull(dataSource, String.format("Failed to get DataSource: %s", dsName));
            
            return dataSource.getConnection();
        } catch (Exception e) {
            throw DataXException
                .asDataXException(DBUtilErrorCode.CONN_DB_ERROR,
                                  String.format("Database connection failed. Unable to get connection with config: %s. Please check your configuration.", dsName), e);
        }
    }
}
```

This design loads all DataSources once at startup and caches them in a `ConcurrentHashMap`. Subsequent sync jobs retrieve connections from the cached DataSources by name, avoiding the overhead of recreating DataSource instances on every run.