---
title: DataX 的设计与简单使用
date: 2021-05-03 14:57:01
tags: 数据同步
categories: 数据库
---

-----

### 写在前面的话

最近在做数据迁移工具。经过多方调研，最后选择阿里巴巴开源工具 `DataX`。为了兼容携程 `Dal` 组件，对 `DataX` 连接源库和目标库的部分做了改造，以便通过 `TitanKey` 实现数据的同步。因此，关于数据同步的内容，计划分为三个章节：`DataX` 工具研究介绍、携程 `Dal` 组件研究介绍、`DataX` 整合 `Dal`。本篇介绍 `DataX` 的作用机制与使用。

##### 一、`DataX` 介绍

`DataX` 是阿里巴巴开源出来的数据同步工具，主要解决解决各种异构数据源之间的同步难题。目前已经拥有比较完善的插件体系，包括常用的 `RDBMS` 数据库、`NOSQL`、大数据计算系统。良好的架构设计，方便开发者引入新插件，一步步构建起数据同步的生态圈。

![](https://gitee.com/donehub/imgbed/raw/master/DataX_introduction.png)

##### 二、目前支持的插件

| 类型                 | 数据源                              | Reader(读) | Writer(写) |
| :------------------- | ----------------------------------- | ---------- | ---------- |
| `RDBMS` 关系型数据库 | `MySQL`                             | √          | √          |
|                      | `Oracle`                            | √          | √          |
|                      | `SQLServer`                         | √          | √          |
|                      | `PostgreSQL`                        | √          | √          |
|                      | `DRDS`(分布式关系型数据库)          | √          | √          |
|                      | 通用 `RDBMS` (支持所有关系型数据库) | √          | √          |
| 阿里云数仓数据存储   | `ODPS`                              | √          | √          |
|                      | `ADS`                               | ×          | √          |
|                      | `OSS`                               | √          | √          |
|                      | `OCS`                               | √          | √          |
| `NoSQL`数据存储      | `OTS`                               | √          | √          |
|                      | `Hbase0.94`                         | √          | √          |
|                      | `Hbase1.1`                          | √          | √          |
|                      | `Phoenix4.x`                        | √          | √          |
|                      | `Phoenix5.x`                        | √          | √          |
|                      | `MongoDB`                           | √          | √          |
|                      | `Hive`                              | √          | √          |
|                      | `Cassandra`                         | √          | √          |
| 无结构化数据存储     | `TxtFile`                           | √          | √          |
|                      | `FTP`                               | √          | √          |
|                      | `HDFS`                              | √          | √          |
|                      | `Elasticsearch`                     |            | √          |
| 时间序列数据库       | `OpenTSDB`                          | √          | ×          |
|                      | `TSDB`                              | √          | √          |

##### 三、`DataX` 同步机制

`DataX` 将数据同步过程中的读取和写入分别抽象为 `Reader`/`Writer`插件，并且以框架作为媒介，实现读取数据源和同步数据源的灵活组合。

![](https://gitee.com/donehub/imgbed/raw/master/datax3.0.png)

 简单来说，`DataX` 的设计愿景，是建立一个万能数据池（图中的 `FrameWork`）：有无限根管道通往池子，负责导入数据；同时又有无限根管道负责向外导出数据。向池子里导入数据，依赖 `Reader` 插件；从池子向外导出数据，依赖 `Writer` 插件。这种设计的精妙之处，在于这个数据池子是万能的，就是说可以从任何一根管道导入数据，也可以将数据导出到任何一根管道。因此，我们只需要关心导入数据和导出数据的管道建设，也就是开发新的 `Reader`/`Writer`插件，便可实现多种数据源之间的同步。

##### 四、`DataX`数据同步过程

![](https://gitee.com/donehub/imgbed/raw/master/datax_sync_flow.png)

名词解释：

`Job`：`DataX` 执行数据同步任务的最小业务单元；

`Task`：`DataX` 执行数据同步任务的最小执行单元，由 `Job` 拆分而来，为实现最大的同步效率；

`TaskGroup`：包含一组 `Task` 的集合；

`DataX` 调度过程：

提交一个数据同步 `Job` 至 `DataX` 后，`DataX` 会开启一个 `Job` 进程，然后根据拆分策略，将 `Job` 拆分为多个 `Task`。接下来，`Job` 调用 `Scheduler`，依据配置的并发数量，重新对拆分好的 `Task` 进行组合，这样组合叫做 `TaskGroup`。最后，`TaskGroup` 以一定的并发量（配置项: `channel`）来执行组内的 `Task`。任务执行过程中，`DataX` 框架会收集任务执行结果，并以报表的形式打印在日志中。

##### 五、 `DataX` 的使用

为了演示方便，我们直接做 `MySQL` 到 `MySQL` 库的数据同步。

首先需要获取 `DataX` 工具包。有两种途径：一是下载`Datax=X` [源码](https://github.com/alibaba/DataX.git)，通过 `Maven` 打包；二是直接下载[官方工具包](http://datax-opensource.oss-cn-hangzhou.aliyuncs.com/datax.tar.gz)；

然后获取数据同步配置模板。查看源码可知，为了操作方便，`DataX` 已经内嵌了 `Python` 执行脚本，可以通过脚本语言获取配置模板，以及执行后续的同步操作。这里我们执行（在 `DataX` 工具包的 `bin` 目录下）：

```pyth
python datax.py -r mysqlreader -w mysqlwriter

DataX (DATAX-OPENSOURCE-3.0), From Alibaba !
Copyright (C) 2010-2017, Alibaba Group. All Rights Reserved.


Please refer to the mysqlreader document:
     https://github.com/alibaba/DataX/blob/master/mysqlreader/doc/mysqlreader.md

Please refer to the mysqlwriter document:
     https://github.com/alibaba/DataX/blob/master/mysqlwriter/doc/mysqlwriter.md

Please save the following configuration as a json file and  use
     python {DATAX_HOME}/bin/datax.py {JSON_FILE_NAME}.json
to run the job.

{
    "job": {
        "content": [
            {
                "reader": {
                    "name": "mysqlreader",
                    "parameter": {
                        "column": [],
                        "connection": [
                            {
                                "jdbcUrl": [],
                                "table": []
                            }
                        ],
                        "password": "",
                        "username": "",
                        "where": ""
                    }
                },
                "writer": {
                    "name": "mysqlwriter",
                    "parameter": {
                        "column": [],
                        "connection": [
                            {
                                "jdbcUrl": "",
                                "table": []
                            }
                        ],
                        "password": "",
                        "preSql": [],
                        "session": [],
                        "username": "",
                        "writeMode": ""
                    }
                }
            }
        ],
        "setting": {
            "speed": {
                "channel": ""
            }
        }
    }
}
```

上面打印出来的 `Json` 串就是 `MySQL` 到 `MySQL`数据同步的配置模板。将模板中的选项补充完成，`mysql2mysql.json` 样例如下：

```json
{
    "job": {
        "content": [
            {
                "reader": {
                    "name": "mysqlreader",
                    "parameter": {
                        "column": [
							"id",
							"name"
						],
                        "connection": [
                            {
                                "jdbcUrl": ["jdbc:mysql://127.0.0.1:3306/test?useSSL=false&zeroDateTimeBehavior=EXCEPTION&serverTimezone=UTC"],
                                "table": ["from_table"]
                            }
                        ],
                        "password": "**********",
                        "username": "root",
                        "where": ""
                    }
                },
                "writer": {
                    "name": "mysqlwriter",
                    "parameter": {
                        "column": [
							"id",
							"name"
						],
                        "connection": [
                            {
                                "jdbcUrl": "jdbc:mysql://127.0.0.1:3306/test?useSSL=false&zeroDateTimeBehavior=EXCEPTION&serverTimezone=UTC",
                                "table": ["to_table"]
                            }
                        ],
                        "password": "**********",
                        "preSql": ["delete from to_table"],
                        "session": [],
                        "username": "root",
                        "writeMode": "insert"
                    }
                }
            }
        ],
        "setting": {
            "speed": {
                "channel": 5
            }
        }
    }
}
```

把这个文件放在 `dataX` 目录下，执行 `Python` 脚本（在 `DataX` 的 `bin` 目录下）：

```cmd
python datax.py ./mysql2mysql.json

...
2021-04-08 11:20:25.263 [job-0] INFO  JobContainer - 
任务启动时刻                    : 2021-04-08 11:20:15
任务结束时刻                    : 2021-04-08 11:20:25
任务总计耗时                    :                 10s
任务平均流量                    :              205B/s
记录写入速度                    :              5rec/s
读出记录总数                    :                  50
读写失败总数                    :                   0
```

这样我们便可以将 `from_table` 中数据同步至 `to_table` 中。`DataX` 框架收集到的各项指标打印在最后。关于配置项中的各项指标，可参见源码的文档介绍。