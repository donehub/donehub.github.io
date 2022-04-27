---
title: Spring Batch 基础介绍
date: 2022-01-30 22:48:01
tags: Spring
categories: 后端
---

-----

#### 一、简介

Spring Batch 是一个轻量级批处理框架，主要被用在高容量、高性能的批处理应用中。作为 Spring 子项目之一，Spring Batch 基于 Spring 框架，发展出一套完备的解决方案，再凭借良好的技术生态，Spring Batch 被广泛应用于批处理领域。

Spring Batch 有着强大的组件库，包括任务重启、任务跳过、任务统计、日志追踪、事务管理、资源管理等。对于大批量数据处理任务，Spring Batch 通过分区和优化技术，实现高性能的批处理作业。总之，Spring Batch 既可以处理简单的任务，也可以处理复杂的、高容量的任务。

#### 二、基础架构

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/27_21_7_30_spring-batch-flow.png)

看图可知：

* 一个  `Job` 可以有一个或多个 `Step`；
* 每个 `Step` 都包含一个 `ItemReader`、一个 `ItemProcessor` 和一个 `ItemWriter`；
* `Job` 需要 `JobLauncher` 发起；
* 批处理过程中的元数据存在 `JobRepository` 中；

---

##### Job

 `Job` 封装了整个批处理所需要的数据，可以通过 `xml` 或 `Java Bean` 注解配置。`Job` 的继承链：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/27_21_38_32_job_detail.png)

`JobInstance` 是 `Job` 的运行实例，就像同一个 `Java` 类可以实例化出不同的对象， `Job` 也可以有不同的 `JobInstance`，这取决于入参（`JobParameters`）。因此可以说，`JobInstance` = `Job` + `JobParameters`。`JobExecution`是 `JobInstance` 的一次执行，包括要做什么、具体怎么做、执行结果等。

---

##### Step

从 Spring Batch 的基础架构图可知，一个 `Step` 包含输入、处理、输出这样一种模型，说明在批处理框架中， `Step` 是最小的执行单元。`Step` 的继承链：

![](https://gitlab.com/donelab/img-bed/-/raw/main/pictures/2022/04/27_22_7_8_step_detail.png)

`StepExecution` 是 `Step` 的一次执行，包含 `Step` 、`JobExecution` 以及事务相关数据的引用，比如提交和回滚次数、开始和结束时间等。输入器（`ItemReader`）、处理器（`ItemProcessor`）和输出器（`ItemWriter`），是 Spring Batch 的顶级接口。作为完备的批处理框架，Spring Batch 自带许多有用的组件，如文件数据存取器、数据库数据存取器等，开箱即用。

---

##### JobLauncher

对于给定的 `JobParameters` ，`JobLauncher` 负责启动 `Job`。

---

##### JobRepository

`JobRepository` 专门负责与数据库打交道，记录整个批处理中的增加、检索、更新、删除动作。因此， Spring Batch 是依赖数据库进行管理的。相关表的[功能简介](https://docs.spring.io/spring-batch/docs/current/reference/html/schema-appendix.html#metaDataSchema)如下：

* `BATCH_JOB_INSTANCE`：储存 `JobInstance` 相关的所有信息；
* `BATCH_JOB_EXECUTION_PARAMS`： 储存 `JobParameters` 相关的所有信息；
* `BATCH_JOB_EXECUTION`：储存 `JobExecution` 相关的所有信息；
* `BATCH_STEP_EXECUTION`：存储 `StepExecution` 相关的所有信息；
* `BATCH_JOB_EXECUTION_CONTEXT`：存储 `Job` - `ExecutionContext` 相关的所有信息；
* `BATCH_STEP_EXECUTION_CONTEXT`：存储 `Step` - `ExecutionContext` 相关的所有信息；

#### 三、设计原则

Spring Batch 只需要简单的配置即可用在基于 Spring 的应用上，实现了与基础架构的完美兼容，小巧却强大。其[设计原则](https://docs.spring.io/spring-batch/docs/current/reference/html/spring-batch-intro.html#springBatchUsageScenarios)总结如下：

* 继承 Spring 编程模型，开发者只专注于业务逻辑，基础实现交由框架负责；

* 解耦基础架构、执行环境和批处理应用之间的关注点；

* 抽取核心服务，设计顶层接口；

* 实现热门组件，开箱即用；
* 增强核心服务的可拓展性；
* 通过 Maven 构建简单的部署模型，独立于应用程序；

#### 四、使用原则

Spring Batch 性能强劲，但开发者在构建批处理方案时，也应考虑以下[原则](https://docs.spring.io/spring-batch/docs/current/reference/html/spring-batch-intro.html#springBatchArchitecture)：

* 搭建架构和环境，尽量使用通用的构建块，批处理架构与在线框架之间会相互影响；

* 避免在单机应用中构建复杂的逻辑结构；
* 尽可能多地在内存中处理任务，尽可能少地使用系统资源，尤其是物理 `IO`：
  * 每个事务都去读取数据，完全可以读取一次，缓存下来；
  * 同一个事务中，重复读取数据；
  * 全表扫描或索引扫描；
* 不做重复的任务（记录已处理的任务，对于相同的后续任务，直接跳过）；
* 合理分配初始内存，防止在批处理中再次分配，耗费时间；
* 设定足够的校验和记录，保证数据的完整性；
* 模拟生产环境，尽早压测；
* 注重数据备份；

#### 五、总结

Spring Batch 是一款优秀的批处理框架，其良好的可扩展性和性能天花板，大大简化了日常的批处理工作。

一方面，Spring Batch 实现了批处理任务的完全解耦。原本复杂且庞大的一条龙任务，可以拆解为若干个 `Step`，各司其职。同时，每个 `Step` 都有自己的输入、处理、输出模型，规范且简单。

另一方面，Spring Batch 使得项目设计科学且合理。开发者不仅可以总览环节要点，还可以专注于单一模块，不至于头晕眼花，bug 爆炸。