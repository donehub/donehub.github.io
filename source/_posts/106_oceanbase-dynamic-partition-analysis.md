---
title: OceanBase 动态分区设计
date: 2026-08-25
categories: 数据库
tags: [OceanBase, 分区表]
---

## 一、问题的起点

在使用 OceanBase 的过程中，大家有几乎都遇到过一个场景：按时间范围分区的表，分区需要提前手动创建。忘记创建新分区，数据写入时直接报"找不到分区"的错误；手动建了太多分区，空分区的元数据又成了维护负担。对于日志表、订单流水表这类数据有明确生命周期的场景，DBA 还要定期清理过期分区，稍有不慎就可能导致数据丢失或线上故障。

OceanBase 从 V4.3.5 BP2 开始引入动态分区功能，试图将"分区的创建与删除"从 DBA 的日常运维中彻底剥离。需要首先澄清的是，动态分区不是一种全新的分区类型，而是在 RANGE / RANGE COLUMNS 分区之上叠加了一层自动化管理策略。理解它的设计逻辑和适用边界，比单纯掌握语法更有价值。

<!-- more -->

## 二、DYNAMIC_PARTITION_POLICY 的设计逻辑

![alt text](/img/oceanbase-dynamic-partition.png)

建表时通过 `DYNAMIC_PARTITION_POLICY` 块声明分区管理策略。以一个真实的通行证日志表为例：

```sql
CREATE TABLE api_passport_logs (
    id BIGINT(20) NOT NULL AUTO_INCREMENT,
    ltime DATETIME NOT NULL COMMENT '日志时间',
    -- ... 其他业务字段省略
    create_time DATETIME NOT NULL,
    update_time DATETIME NOT NULL,
    PRIMARY KEY (id, ltime)
) DEFAULT CHARSET = utf8mb4
DYNAMIC_PARTITION_POLICY (
    ENABLE = true,
    TIME_UNIT = 'month',
    PRECREATE_TIME = '1 month',
    EXPIRE_TIME = '6 month',
    TIME_ZONE = '+8:00',
    BIGINT_PRECISION = 'none'
)
PARTITION BY RANGE COLUMNS (ltime) (
    PARTITION P202602 VALUES LESS THAN ('2026-03-01 00:00:00'),
    PARTITION P202603 VALUES LESS THAN ('2026-04-01 00:00:00')
);
```

这个建表语句包含了动态分区的六个参数。建表时只需手动定义起始的几个分区，后续分区由后台调度任务自动创建，过期分区也会被自动清理。需要注意的是，建表完成后动态分区管理不会立即执行，需要等待下一次调度任务触发，或者手动调用 `DBMS_PARTITION.MANAGE_DYNAMIC_PARTITION()`。

### TIME_UNIT：分区粒度的选择

TIME_UNIT 决定分区的时间粒度，支持 `hour`、`day`、`week`、`month`、`year`。分区粒度的选择需要根据数据增长速度、单分区数据规模、查询时间范围和数据保留周期综合确定。

以 day 粒度为例，如果每天写入 1 亿行数据、保留 7 天，用 day 分区非常合理，单分区数据量可控，查询也精确。但如果每天只有 1000 万行数据、需要保留 10 年，按 day 计算会产生 3650 个分区，此时 month 粒度更加合适。在 OceanBase 的分布式架构中，分区是数据分布、副本复制和负载均衡的基本单元，分区数量增加会带来元数据管理、调度和负载均衡等方面的开销，因此应避免在没有实际需求的情况下使用过细的粒度。

需要注意的是，分区键类型还会限制 TIME_UNIT 的取值。例如 DATE 类型的分区键不支持 `hour` 粒度，YEAR 类型只能使用 `year` 粒度。TIME_UNIT 并非可以与任意分区键类型自由组合。

### PRECREATE_TIME：未来分区的覆盖窗口

PRECREATE_TIME 控制预创建分区的时间覆盖范围，取值为带时间单位的字符串（如 `'1 month'`、`'7 day'`、`'2 hour'`）。它的准确含义是：调度任务每次执行时，会确保最大分区的上界大于 `now() + PRECREATE_TIME`。

以 `TIME_UNIT = month`、`PRECREATE_TIME = '1 month'` 为例，调度任务会确保当前时间往后至少一个月内的分区都已经创建好。这不是"提前一个月执行 ADD PARTITION"，而是保证未来分区覆盖窗口始终满足业务写入需求。PRECREATE_TIME 本质上是为动态分区调度提供未来分区覆盖窗口，较大的预创建窗口可以提高对调度延迟或连续调度失败的容错能力。如果未来分区没有及时创建，而业务写入时间超过现有最大分区上界，则仍可能出现写入失败。

PRECREATE_TIME 应根据调度周期、业务写入特征和可接受的预创建分区数量来确定。单次动态分区管理任务最多创建 2048 个分区，如果由于长时间未调度导致需要补充大量分区，可能需要多次执行动态分区管理任务。

### EXPIRE_TIME：分区级生命周期管理

EXPIRE_TIME 定义数据的保留时长，取值同样是带时间单位的字符串（如 `'6 month'`、`'90 day'`、`'1 year'`）。调度任务每次执行时，会删除满足以下条件的分区：

```
分区上界 < now() - EXPIRE_TIME
```

这里需要特别强调一点：EXPIRE_TIME 判断的是整个分区是否过期，过期后 DROP 的是整个分区，而不是按行的时间逐条删除。

以日志表设置的 `'6 month'` 为例，假设当前时间为 2026-08-25，则删除条件为分区上界 < 2026-02-25。这意味着上界在 2 月 25 日之前的分区会被整体删除。由于这里按月分区，实际保留的数据范围并不是精确的 180 天，而是以分区边界为粒度。相比逐行 DELETE，按分区 DROP 可以避免扫描和删除大量历史行，通常更适合大规模时序数据的生命周期管理。但分区删除仍然可能产生资源消耗（涉及对应 Tablet/副本的数据生命周期处理），不应简单理解为零成本操作。

对于有审计要求或数据回溯需求的业务表，建议在 EXPIRE_TIME 的基础上提前做好数据归档。如果业务方对数据删除有审批流程，可以将 EXPIRE_TIME 设为 `-1` 来禁用自动过期删除，只保留自动创建分区的能力。但禁用自动删除不等于数据自动归档，过期数据的管理仍需 DBA 自行规划。

### TIME_ZONE 和 BIGINT_PRECISION

TIME_ZONE 用于指定动态分区计算当前时间以及时间类型分区键边界时使用的时区。设置为 `'default'` 时使用租户时区；显式设置 `'+8:00'` 等值时，则使用指定的时区偏移。对于 DATETIME/DATE/TIMESTAMP 等时间类型的分区键，建议显式指定业务统一使用的时区，避免业务时间语义与分区边界计算不一致。也支持地域格式的时区，如 `'Asia/Shanghai'`。

BIGINT_PRECISION 仅用于 BIGINT 类型的时间戳分区键，用于指定时间戳精度（支持 `'none'`、`'us'`、`'ms'`、`'s'`）。对于 DATETIME、DATE、TIMESTAMP、YEAR 等非 BIGINT 类型分区键，应使用 `'none'`，也可以省略该参数。

## 三、分区键类型的支持范围

动态分区支持 Range 和 Range Columns 两种分区方式，但对分区键类型有明确限制：

| 分区方式 | 支持的分区键类型 |
|---------|--------------|
| Range Columns | DATE、DATETIME、TIMESTAMP、YEAR、BIGINT（需配置 BIGINT_PRECISION） |
| Range | YEAR、BIGINT（需配置 BIGINT_PRECISION） |

最常见的用法是 Range Columns 配合 DATETIME 类型的分区键，上面的日志表就是这个模式。如果业务使用时间戳整型（比如 Unix 毫秒时间戳），则可以通过 Range 配合 BIGINT_PRECISION 来实现动态分区。

动态分区作用于一级分区。对于二级分区表，也只能对一级分区开启动态分区管理，不能直接对二级分区进行动态分区生命周期管理。

## 四、动态分区与 Interval 分区的区别

OceanBase V4.4.2 在 Oracle 兼容模式中引入了 INTERVAL 分区。两者的核心机制差异如下：

|  | 动态分区 | Interval 分区 |
|--|--------|-------------|
| 创建方式 | 定时任务预创建 | 数据写入触发 |
| 删除过期分区 | 支持 | 不支持 |
| 主要目的 | 生命周期自动管理 | 自动扩展 |
| 版本 | V4.3.5 BP2 | V4.4.2+，Oracle 兼容模式 |

这是与动态分区最大的机制区别：Interval 是 DML 触发创建，而动态分区是后台定时任务主动预创建。两者是不同的自动分区管理机制，支持版本、兼容模式和分区层级也存在差异，实际使用时应根据具体的 OceanBase 版本和业务需求选择其一。

## 五、动态分区到底是怎么运行的

动态分区是调度驱动的自动化机制，不是时间到点立即触发的实时机制。它的运行流程如下：
![alt text](/img/oceanbase-scheduler.png)

V4.3.5 的调度频率由 TIME_UNIT 决定：

| TIME_UNIT | 调度频率 | 是否可调整执行时间 |
|-----------|---------|----------------|
| hour | 每小时整点 | 不可修改 |
| day / week / month / year | 每天一次，默认 0 点 | 可通过 DBMS_SCHEDULER 调整 |

hourly 任务的调度时间是固定的，无法修改。daily 任务默认在 0 点执行，对于 DDL/元数据操作敏感的业务，可以通过 `DBMS_SCHEDULER` 将 daily 任务调整到业务低峰期。

OceanBase 提供了系统包 `DBMS_PARTITION`，其中 `MANAGE_DYNAMIC_PARTITION()` 可以手动触发一次分区管理任务。这在几种场景下很有用：修改了动态分区参数后需要立即生效；需要紧急预创建分区应对突发流量；或者想验证配置是否正确。修改动态分区管理参数后，预创建和删除操作不会立即生效，必须等待下一次调度或手动触发。这个行为与很多 DBA 的预期不同——在 MySQL 中 `ALTER TABLE ADD PARTITION` 是即时执行的，而 OceanBase 的动态分区是异步调度模型。

## 六、参数修改的能力边界

V4.3.5 BP2 已经支持通过 `ALTER TABLE ... SET DYNAMIC_PARTITION_POLICY` 在线修改动态分区策略参数，但并非所有参数都允许修改：

| 参数 | 是否可修改 |
|------|----------|
| ENABLE | 可修改 |
| PRECREATE_TIME | 可修改 |
| EXPIRE_TIME | 可修改 |
| TIME_UNIT | 不可修改 |
| TIME_ZONE | 不可修改 |
| BIGINT_PRECISION | 不可修改 |

TIME_UNIT、TIME_ZONE 和 BIGINT_PRECISION 在建表时确定后就无法更改。如果这些参数配置不当，只能通过重建表来修正。这意味着在最初建表时就需要慎重确定分区粒度、时区和精度设置。

## 七、动态分区与分区分裂的关系

OceanBase V4.3.4 引入了自动分区分裂功能（V4.3.4 时为实验特性，V4.3.5 已达到 GA），它解决的是单个分区数据量过大的问题。自动分区分裂通过 `SIZE` 指定分裂阈值；如果未指定 `SIZE`，则使用租户级 `auto_split_tablet_size`。当前自动分区分裂主要针对满足条件的 Range/Range Columns 一级分区主键表，并存在主键、分区键前缀等限制。

| 功能 | 解决的问题 | 触发方式 |
|------|-----------|---------|
| 动态分区 | 分区数量随时间自动增减 | 定时任务调度 |
| 分区分裂 | 单个分区数据量过大 | 数据量达到 SIZE 阈值 |

两者可以互补使用：动态分区管理分区的生命周期（创建和过期删除），分区分裂控制单分区的数据规模。但需要注意它们不是同一个层级的能力，组合使用前应确认各自的限制条件。

## 八、生产环境如何验证动态分区是否正常

配置完动态分区后，DBA 最关心的问题是：调度任务有没有正常运行？OceanBase V4.3.5 BP2 提供了系统视图用于监控：

```sql
SELECT
    TABLE_NAME,
    MAX_HIGH_BOUND_VAL,
    ENABLE,
    TIME_UNIT,
    PRECREATE_TIME,
    EXPIRE_TIME,
    TIME_ZONE
FROM oceanbase.DBA_OB_DYNAMIC_PARTITION_TABLES
WHERE TABLE_NAME = 'api_passport_logs';
```

其中 `MAX_HIGH_BOUND_VAL` 是当前最大分区的上界。判断动态分区是否正常运行的核心逻辑是：

```
MAX_HIGH_BOUND_VAL 应大于 now() + PRECREATE_TIME
```

如果不满足，说明调度任务可能没有正常执行，或者分区创建出现了异常。此时可以先手动调用 `DBMS_PARTITION.MANAGE_DYNAMIC_PARTITION()` 触发一次调度，再观察分区是否被补充创建。如果手动触发后仍然没有变化，需要检查集群的调度任务状态和日志。

## 九、实践中的选型建议

动态分区最适合数据有明确生命周期的时序场景。以下是几种典型场景的配置思路，具体参数需要根据实际业务调整：

应用日志表。写入量大，数据保留 7 到 30 天，查询以时间范围为主。TIME_UNIT 通常设为 day，PRECREATE_TIME 根据调度容错需求设置（如 `'7 day'`），EXPIRE_TIME 根据数据保留需求设置（如 `'30 day'`）。

交易流水表。数据量大，保留周期长，可能有审计要求。TIME_UNIT 通常设为 month 以控制分区数量。PRECREATE_TIME 和 EXPIRE_TIME 应根据业务数据保留策略和合规要求确定，不建议简单套用固定经验值。如果审计部门要求数据删除必须经过审批，可以将 EXPIRE_TIME 设为 `-1` 禁用自动删除。

多租户 SaaS 平台。动态分区表数量增加，会增加后台动态分区管理任务需要处理的表数量和 DDL 管理压力。在表数量较多的情况下，需要评估调度任务的承载能力，必要时通过调整调度频率或分批管理来控制并发。

## 十、需要注意的局限

分区自动删除没有"回收站"机制，过期即 DROP。在数据合规要求严格的环境中，这个行为需要在上线前与业务方和合规团队确认清楚。建议至少提前建立数据归档流程，在分区被删除之前将需要保留的数据同步到离线存储。

从版本演进来看，V4.3.5 BP2 是首个支持动态分区的版本，同时已支持通过 ALTER TABLE 修改 ENABLE、PRECREATE_TIME 和 EXPIRE_TIME 参数。生产环境部署前务必确认目标版本的具体能力。

动态分区本质上是将分区的运维自动化了，但它没有取代分区设计本身。选择合理的粒度、设定正确的保留周期、规划好归档流程，这些判断仍然需要 DBA 基于业务特征来完成。工具解决的是执行力问题，决策力仍然是人的事。
