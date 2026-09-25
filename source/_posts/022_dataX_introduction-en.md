---
title: DataX — Design and Basic Usage
date: 2021-05-03 14:57:01
tags: Data Sync
categories: Database
lang: en
label: 022_dataX_introduction
---

-----

<!-- more -->
### Background

I was building a data migration tool recently. After evaluating several options, I settled on Alibaba's open-source tool `DataX`. To make it compatible with Ctrip's `Dal` component, I modified the parts of `DataX` that connect to source and target databases, enabling data sync through `TitanKey`. The data sync story breaks into three parts: an introduction to `DataX`, an introduction to Ctrip's `Dal` component, and integrating `DataX` with `Dal`. This post covers how `DataX` works and how to use it.

##### 1. What Is `DataX`

`DataX` is Alibaba's open-source data sync tool, built to solve the problem of synchronizing data across heterogeneous data sources. It has a mature plugin ecosystem covering common `RDBMS` databases, `NoSQL` stores, and big data processing systems. Its clean architecture makes it straightforward for developers to add new plugins and gradually build out a data sync ecosystem.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_6_29_DataX_introduction.png)

##### 2. Supported Plugins

| Type                          | Data Source                            | Reader | Writer |
|:------------------------------|:---------------------------------------|:---------|:---------|
| `RDBMS` (Relational Databases)| `MySQL`                                | √        | √        |
|                               | `Oracle`                               | √        | √        |
|                               | `SQLServer`                            | √        | √        |
|                               | `PostgreSQL`                           | √        | √        |
|                               | `DRDS` (Distributed Relational DB)     | √        | √        |
|                               | Generic `RDBMS` (all relational DBs)   | √        | √        |
| Alibaba Cloud Data Warehouse  | `ODPS`                                 | √        | √        |
|                               | `ADS`                                  | ×        | √        |
|                               | `OSS`                                  | √        | √        |
|                               | `OCS`                                  | √        | √        |
| `NoSQL` Stores                | `OTS`                                  | √        | √        |
|                               | `Hbase0.94`                            | √        | √        |
|                               | `Hbase1.1`                             | √        | √        |
|                               | `Phoenix4.x`                           | √        | √        |
|                               | `Phoenix5.x`                           | √        | √        |
|                               | `MongoDB`                              | √        | √        |
|                               | `Hive`                                 | √        | √        |
|                               | `Cassandra`                            | √        | √        |
| Unstructured Data Stores      | `TxtFile`                              | √        | √        |
|                               | `FTP`                                  | √        | √        |
|                               | `HDFS`                                 | √        | √        |
|                               | `Elasticsearch`                        |          | √        |
| Time-Series Databases         | `OpenTSDB`                             | √        | ×        |
|                               | `TSDB`                                 | √        | √        |

##### 3. The Sync Mechanism

`DataX` abstracts the read and write sides of data sync into `Reader` and `Writer` plugins, with a framework sitting in the middle to flexibly combine any source with any target.

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_6_59_datax3.0.png)

Think of `DataX`'s design as a universal data pool (the `FrameWork` in the diagram). Unlimited pipes feed data into the pool via `Reader` plugins, and unlimited pipes drain data out via `Writer` plugins. The key insight is that the pool is universal — data from any reader can flow to any writer. So the only work left is building new pipes, which means developing new `Reader`/`Writer` plugins. That's how `DataX` achieves sync across diverse data sources.

##### 4. The Sync Process

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/2_20_7_23_datax_sync_flow.png)

Terminology:

`Job`: The minimum business unit for a `DataX` sync task;

`Task`: The minimum execution unit, split from a `Job` to maximize sync throughput;

`TaskGroup`: A collection of `Task` instances;

How `DataX` schedules a job:

When you submit a sync `Job`, `DataX` spins up a `Job` process and splits it into multiple `Task` instances based on a split strategy. The `Job` then calls the `Scheduler`, which groups the tasks into `TaskGroup` collections based on the configured concurrency. Each `TaskGroup` executes its tasks with a configurable level of parallelism (the `channel` setting). Throughout execution, the `DataX` framework collects results and prints a summary report in the logs.

##### 5. Using `DataX`

For this walkthrough, we'll do a `MySQL`-to-`MySQL` sync.

First, get the `DataX` toolkit. Two options: download the [`DataX` source code](https://github.com/alibaba/DataX.git) and build it with `Maven`, or grab the [pre-built package](http://datax-opensource.oss-cn-hangzhou.aliyuncs.com/datax.tar.gz) directly.

Next, get a sync configuration template. Looking at the source, `DataX` ships with an embedded `Python` script for convenience. We'll use it to generate the template (run from the `bin` directory of the `DataX` package):

```python
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

The JSON output above is the configuration template for `MySQL`-to-`MySQL` sync. Fill in the template values — here's a complete example in `mysql2mysql.json`:

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

Place this file under the `dataX` directory and run the Python script (from the `bin` directory):

```cmd
python datax.py ./mysql2mysql.json

...
2021-04-08 11:20:25.263 [job-0] INFO  JobContainer - 
Job start time              : 2021-04-08 11:20:15
Job end time                : 2021-04-08 11:20:25
Total time                  :                 10s
Average throughput          :              205B/s
Record write speed          :              5rec/s
Total records read          :                  50
Total read/write failures   :                   0
```

That syncs data from `from_table` to `to_table`. The `DataX` framework prints the collected metrics at the end. For details on each configuration option, check the documentation in the source code.
