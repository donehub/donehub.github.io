---
title: DataX 兼容携程 Dal 数据访问框架
date: 2021-11-09 23:57:01
tags: 数据同步
categories: 数据库
---

-----

#### 一、 携程 `Dal` 开源框架

`Dal` 是携程开源的数据库访问框架，为大规模的 `DB` 管理和使用提供一套优质的解决方案。

首先在 `DB` 管理方面，`Dal` 统一集成了主流程的数据访问：支持 `Java` 和 `C#` 客户端；支持 `MySQL` 、`SQLServer` 数据库；支持 `ORM` 和非 `ORM` 方式的数据访问；使用了 `Emit` 映射技术，提供高性能 `ORM`；多数据源访问和主从分离（读写分离）；日志、监控集成。

其次在 `DB` 使用方面， `Dal` 支持代码生成。通过 `Dal` 平台，可一键生成 `Entity`、`Dao`、`Unit Test`。这不仅可以让开发者脱离 `DB` 编程、提升开发效率，还可以统一面向 `DB` 的代码风格和代码质量。

#### 二、 `DataX` 与 `Dal` 的兼容

`Dal` 的主要特点是统一收口和集中管理，在 `DB` 连接方面，客户端无需配置 `DB` 的用户名和密码，只需要配置 `Dal` 提供的 `TitanKey` 或 `ClusterName` 即可。简单来说，`TitanKey` 或 `ClusterName` 就是 `Dal` 生成的，供客户端的访问 `DB` 的钥匙。也正因此，`DataX` 在 `Dal` 架构的系统上就不起作用了。需要解决两个问题：`DataX` 如何配置 `TitanKey` 或 `ClusterName`；`DataX` 如何通过 `Dal` 获取数据源。

#### 三、 `Datax` 配置 `TitanKey` 或 `ClusterName`

这是 `mysqlwriter` 的配置信息模板:

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

`Dal` 不关心 `username` 和 `password`，不妨将 `TitanKey` 或 `ClusterName`放在 `jdbcurl`处。

#### 四、`DataX` 获取 `Dal` 数据源

`DataX` 通过如下方式获取数据连接：

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

`Dal` 通过如下方式获取数据连接：

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
     * 数据源工厂
     */
    @Bean
    public DalDataSourceFactory getCtripDalDataSource() {
        return new DalDataSourceFactory();
    }
    
    /**
     * 通过 titanKey 获取数据连接
     */
	public static Connection getConnectionByTitanKey(final String titanKey) {
	    try {
	        DataSource dataSource = dsFactory.createDataSource(titanKey);
            return dataSource.getConnection();
	    } catch (Exception e) {
            throw DataXException
                .asDataXException(DBUtilErrorCode.CONN_DB_ERROR,
                String.format("数据库连接失败. 因为根据您配置的连接信息:%s获取数据库连接失败. 请检查您的配置并作出修改.", titanKey), e);
	    }
	}
    
    /**
     * 通过 clusterName 获取数据连接
     */
	public static Connection getConnectionByClusterName(final String clusterName) {
	    try {
            DataSource ds = dsFactory.getOrCreateDataSource(clusterName);
            return dataSource.getConnection();
	    } catch (Exception e) {
            throw DataXException
                .asDataXException(DBUtilErrorCode.CONN_DB_ERROR,
                String.format("数据库连接失败. 因为根据您配置的连接信息:%s获取数据库连接失败. 请检查您的配置并作出修改.", clusterName), e);
	    }
	}
}
```

综上：借助 `DataSource` 工厂，就可以用 `Dal` 数据连接替换掉 `DataX` 的数据连接。

#### 五、`DataX` 兼容 `Dal` 优化

从以上实现可以看出，获取 `Dal` 数据连接主要有两步：生成数据源和建立数据连接，并且每次数据同步都要重复一遍。既然 `Dal` 已经提供了 `DataSource` 工厂，是否可以考虑将数据源缓存下来呢？

所以，有一套更好的兼容方案：在工具启动过程中，加载数据源并缓存下来， `dbName` 作为查找数据源的 `key`。

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
     * 数据源工厂
     */
    @Bean
    public DalDataSourceFactory getCtripDalDataSource() {
        return new DalDataSourceFactory();
    }
    
    private static final String CLUSTER_CONN_TYPE_FLAG = "cluster";

    /**
     * titan key 连接信息
     */
    public static final String TITAN_KEY_TEST_DB = "test_titan_db";

    /**
     * cluster name 连接信息
     */
    public static final String CLUSTER_NAME_TEST_DB = "test_cluster_db";

    /**
     * 根据 titan key 加载数据源
     */
    private void fillDataSourceFromTitanKey(String titanKey) {
        try {
            
            Assert.hasText(titanKey,
                           "connect to db failed; titan key cannot be null or empty");

            DataSource dataSource = dsFactory.createDataSource(titanKey);
            // 缓存数据源
            DBUtil.setDataSourceIfAbsent(titanKey, dataSource);
        } catch (Exception t) {
            throw Throwables.propagate(t);
        }
    }

    /**
     * 根据 cluster name 加载单库数据源
     */
    private void fillDataSourceFromClusterName(String clusterName) {
        try {
            Assert.hasText(clusterName,
                           "connect to db failed; dal cluster cannot be null or empty");

            // 判断是否为 clusterName 格式
            Assert.isTrue(clusterName.contains(CLUSTER_CONN_TYPE_FLAG),
                          String.format("%s is not in a cluster format", clusterName));

            DataSource dataSource = dsFactory.getOrCreateDataSource(clusterName);
            // 缓存数据源
            DBUtil.setDataSourceIfAbsent(clusterName, dataSource);
        } catch (Exception t) {
            throw Throwables.propagate(t);
        }
    }

    @PostConstruct
    public void initDataSource() {

        // 通过 titan key 加载数据源
        fillDataSourceFromTitanKey(TITAN_KEY_TEST_DB);

        // 通过 cluster name 加载数据源
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
     * 从外部将数据源放到Engine里
     *
     * @param dsName 数据源名称(后续根据名称取出数据源)
     * @param ds     数据源
     */
    public static void setDataSourceIfAbsent(String dsName, DataSource ds) {
        if (DS_MAP.containsKey(dsName)) {
            return;
        }
        synchronized (DS_MAP) {
            if (!dsMap.containsKey(dsName)) {
                DS_MAP.put(dsName, ds);
                LOG.info("setDataSourceIfAbsent将数据源{}放入Engine", dsName);
            }
        }
    }
    
    /**
   	 * 获取数据源
   	 *
   	 * @param dsName 数据源名称
   	 * @return 数据源
  	 */
    private static DataSource getDataSource(String dsName) {
        // 处理 jdbc 格式的数据源名称
        if (dsName.contains("?")) {
            dsName = dsName.substring(0, dsName.indexOf("?"));
        }
        
        return DS_MAP.get(dsName);
    }
    
    /**
     * 通过数据源名称获取数据库连接
     *
     * @param dsName 数据源名称
     * @return 数据库连接
     */
	public static Connection getConnection(String dsName) {
	    try {
            // 获取数据源
	        DataSource dataSource = getDataSource(dsName);
            
            Assert.notNull(dataSource, String.format("获取数据源%s失败", dsName));
            
            return dataSource.getConnection();
	    } catch (Exception e) {
            throw DataXException
                .asDataXException(DBUtilErrorCode.CONN_DB_ERROR,
                String.format("数据库连接失败. 因为根据您配置的连接信息:%s获取数据库连接失败. 请检查您的配置并作出修改.", dsName), e);
	    }
	}
}
```