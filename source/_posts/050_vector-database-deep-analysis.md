---
title: 向量数据库深度解析
date: 2025-05-19
tags: 向量数据库
categories: AI
---

做 RAG（检索增强生成）应用，向量数据库是绕不开的核心组件。市面上产品不少（Milvus、Qdrant、Weaviate、Chroma、Pinecone），每个都说自己最强。这篇文章从底层原理到实际选型，重点分析 Chroma 和 Milvus 两款代表产品，帮你在具体场景下做出选择。

<!-- more -->
---

## 向量数据库解决什么问题

传统数据库擅长精确匹配：`WHERE name = '张三'`。语义搜索的需求则完全不同，用户问"如何提高团队协作效率"，系统需要找出意思相近的文档，即使文档里完全没有这几个关键词。向量数据库的价值正在于此：把文本、图像、音频等非结构化数据转换成高维空间中的向量（一串浮点数字），通过计算向量间的距离来度量语义相似度，把语义最接近的内容检索出来。

整个流程分三步：原始文本经过 Embedding 模型编码成向量后存入向量数据库，查询时对用户输入做同样的编码，然后在数据库中计算相似度并返回 Top-K 个最接近的结果。

```
文本 → Embedding模型 → 向量 [0.12, -0.34, 0.56, ...] → 向量数据库
查询 → Embedding模型 → 向量 [0.15, -0.30, 0.52, ...] → 相似度计算 → Top-K结果
```

---

## 核心技术指标

### 索引算法决定性能上限

向量数据库的索引算法直接决定查询速度和召回率。主流索引类型的特点和适用场景如下：

| 索引类型 | 原理 | 查询速度 | 内存占用 | 适用场景 |
|----------|------|----------|----------|----------|
| FLAT | 暴力遍历，精确计算 | 最慢 | 最高 | 小数据量，要求100%召回 |
| IVF-FLAT | clustering + 倒排 | 中等 | 中等 | 百万级，平衡方案 |
| IVF-PQ | 聚类 + 乘积量化压缩 | 快 | 低 | 内存受限，牺牲精度 |
| HNSW | 分层可导航小世界图 | 最快 | 较高 | 高性能实时查询 |
| DISKANN | 磁盘索引 + SSD优化 | 较慢 | 极低 | 超大规模，成本敏感 |

HNSW 是当前主流选择。它构建一个多层图结构，搜索时从顶层稀疏图快速跳转到目标区域，逐层下沉到底层稠密图做精确搜索，效果类似跳表的分层定位机制。构建 HNSW 有三个关键参数：M 控制每个节点的最大连接数（默认 16），值越大召回率越高但内存占用也越大；efConstruction 决定构建索引时的搜索范围（默认 200）；efSearch 在查询阶段动态调整搜索宽度，是运行时平衡召回率和延迟的主要手段。

### 分布式架构决定扩展能力

| 架构类型 | 代表产品 | 特点 |
|----------|----------|------|
| 单机嵌入式 | Chroma、Faiss | 无部署成本，数据量受限 |
| 单机服务化 | Qdrant 单机版 | 独立进程，支持持久化 |
| 分布式集群 | Milvus、Qdrant 集群 | 水平扩展，高可用 |

### 元数据过滤能力

实际业务中，向量搜索往往要结合条件过滤，比如找出"价格在100-500元之间且类别是电子产品"的相似商品。不同数据库在这方面的能力差异明显：

| 数据库 | 过滤能力 | 实现方式 |
|----------|----------|----------|
| Qdrant | 最强 | 原生支持复杂过滤，性能最优 |
| Milvus | 强 | 支持标量字段过滤 |
| Chroma | 基础 | 简单 where 条件 |
| Pinecone | 强 | 元数据命名空间 |

---

## 主流向量数据库横向对比

### 开源产品对比

| 数据库 | 语言 | 架构 | 索引支持 | 过滤能力 | 社区活跃度 |
|----------|------|------|----------|----------|------------|
| Milvus | Go | 分布式 | HNSW/IVF/DISKANN | 强 | 活跃（CNCF项目） |
| Qdrant | Rust | 单机/分布式 | HNSW | 最强 | 活跃 |
| Weaviate | Go | 单机/分布式 | HNSW | 强 | 活跃 |
| Chroma | Python | 嵌入式 | HNSW | 基础 | 活跃 |

### 云服务对比

| 产品 | 定位 | 优势 | 劣势 |
|------|------|------|------|
| Pinecone | 全托管 Serverless | 零运维，自动扩展 | 供应商锁定，成本不可控 |
| Zilliz Cloud | Milvus 托管版 | 企业级支持，兼容 Milvus API | 价格较高 |
| MongoDB Atlas Vector | MongoDB 生态 | 复用现有基础设施 | 向量能力有限 |

### 性能基准（百万级向量，HNSW 索引）

| 数据库 | QPS | P99延迟 | 内存占用 |
|--------|-----|---------|----------|
| Milvus | ~15000 | ~10ms | 高 |
| Qdrant | ~12000 | ~8ms | 中 |
| Weaviate | ~8000 | ~15ms | 中 |
| Chroma | ~3000 | ~30ms | 低 |

---

## Chroma：轻量级入门首选

### 适用场景

Chroma 的设计哲学是极简：Python 原生、嵌入式运行、API 设计友好。它在四类场景中特别有用：快速搭建 RAG Demo 的原型验证（几行代码就能跑起来）、文档量在 10 万以下的小规模应用、数据不想出本机的本地开发，以及学习向量数据库基本概念的研究场景。

### 核心 API

```python
# Chroma 的极简 API 设计
import chromadb

# 初始化：嵌入式，无需启动服务
client = chromadb.PersistentClient(path="./chroma_db")

# 创建集合
collection = client.create_collection(
    name="documents",
    metadata={"hnsw:space": "cosine"}  # 支持 l2、ip、cosine
)

# 添加文档：自动调用 Embedding（内置默认模型）
collection.add(
    documents=["文档内容1", "文档内容2"],
    ids=["doc1", "doc2"]
)

# 查询：一步到位
results = collection.query(
    query_texts=["查询内容"],
    n_results=5
)
```

Chroma 内置了 `all-MiniLM-L6-v2` 作为默认 Embedding 模型，也可以替换为 OpenAI、Cohere 等第三方模型：

```python
from chromadb.utils import embedding_functions

# 使用 OpenAI Embedding
openai_ef = embedding_functions.OpenAIEmbeddingFunction(
    api_key="your-key",
    model_name="text-embedding-3-small"
)

collection = client.create_collection(
    name="docs",
    embedding_function=openai_ef
)
```

### 元数据过滤

```python
# 添加带元数据的文档
collection.add(
    documents=["技术文档", "产品文档"],
    ids=["d1", "d2"],
    metadatas=[
        {"category": "tech", "author": "张三"},
        {"category": "product", "author": "李四"}
    ]
)

# 查询时过滤
results = collection.query(
    query_texts=["如何部署"],
    n_results=5,
    where={"category": "tech"}  # 只在技术文档中搜索
)
```

### 局限性

| 限制 | 影响 |
|------|------|
| 单机架构 | 无法水平扩展，数据量上限约百万级 |
| 索引单一 | 仅支持 HNSW，无法根据场景切换 |
| 过滤简单 | 不支持复杂布尔组合，性能一般 |
| 无分布式 | 没有副本、分片机制，单点故障风险 |

Chroma 是向量数据库界的 SQLite，简单好用，适合快速验证想法和中小规模应用，但别指望它扛生产级大流量。

---

## Milvus：生产级大规模首选

### 适用场景

Milvus 的定位是云原生分布式向量数据库，目前是 CNCF 沙箱项目。它适合大规模生产应用（向量数量在百万级甚至亿级）、高并发实时检索（要求低延迟和高吞吐）、需要结合标量字段的复杂过滤需求，以及支持 Kubernetes 和多云部署的基础设施环境。

### 架构解析

Milvus 采用分层架构设计，自上而下分为 SDK 层、Proxy 接入层、协调层、工作节点层和底层存储。

| 层级 | 组件 | 职责 |
|------|------|------|
| SDK 层 | Python / Go / Java / Node.js / REST | 客户端接入 |
| 接入层 | Proxy | 请求解析、路由、负载均衡 |
| 协调层 | Root Coord | 全局协调，处理 DDL（创建集合、索引等） |
| 协调层 | Query Coord | 查询节点调度，负载均衡 |
| 协调层 | Data Coord | 数据节点调度，segment 管理 |
| 协调层 | Index Coord | 索引构建任务调度 |
| 工作层 | Query / Data / Index Node | 执行查询、数据写入、索引构建 |
| 存储层 | etcd + MinIO | 元数据存储 + 对象存储 |

这种架构的好处是各组件可以独立扩缩容。查询节点不够可以单独加 Query Node，不需要连带扩数据节点和索引节点。

### 索引选型实战

不同规模和场景，索引选择策略不同：

| 数据规模 | 内存预算 | 推荐索引 | 参数建议 |
|----------|----------|----------|----------|
| < 100万 | 充足 | FLAT | 精确搜索，召回率100% |
| 100万-1000万 | 充足 | HNSW | M=16, efConstruction=256 |
| 100万-1000万 | 紧张 | IVF-FLAT | nlist=1024 |
| > 1000万 | 紧张 | IVF-PQ | nlist=1024, m=8, nbits=8 |
| > 1亿 | 极紧张 | DISKANN | 磁盘索引，SSD必备 |

```python
from pymilvus import MilvusClient, IndexType, MetricType

# 创建 HNSW 索引
index_params = MilvusClient.prepare_index_params()
index_params.add_index(
    field_name="vector",
    index_type=IndexType.HNSW,
    metric_type=MetricType.COSINE,
    params={"M": 16, "efConstruction": 256}
)

# 查询参数：动态调整 ef 提高召回率
search_params = {"params": {"ef": 64}}  # ef越大，召回率越高，延迟越长
```

### 集合设计与过滤查询

创建集合时需要定义向量字段和标量字段的 schema，标量字段用于后续的过滤查询。建议对高频过滤的标量字段单独创建索引以加速查询。

```python
from pymilvus import MilvusClient

client = MilvusClient("http://localhost:19530")

# 创建集合：向量字段 + 标量字段
client.create_collection(
    collection_name="products",
    dimension=1536,  # OpenAI text-embedding-3-small 维度
    metric_type="COSINE",
    auto_id=False,
    fields=[
        {"name": "id", "dtype": "VARCHAR", "max_length": 64, "is_primary": True},
        {"name": "vector", "dtype": "FLOAT_VECTOR", "dim": 1536},
        {"name": "title", "dtype": "VARCHAR", "max_length": 256},
        {"name": "category", "dtype": "VARCHAR", "max_length": 64},
        {"name": "price", "dtype": "FLOAT"},
        {"name": "created_at", "dtype": "INT64"}  # 时间戳
    ]
)

# 创建标量字段索引（加速过滤）
client.create_index(
    collection_name="products",
    field_name="category",
    index_type="Trie"  # 字符串用 Trie，数值用 STL_SORT
)
```

Milvus 的过滤表达式支持 AND、OR、NOT、IN、LIKE 等操作符，可以在向量相似度搜索的同时施加标量条件约束：

```python
# 基础过滤查询
results = client.search(
    collection_name="products",
    data=[[0.1, 0.2, ...]],  # 查询向量
    filter='category == "electronics" and price >= 100 and price <= 500',
    limit=10,
    output_fields=["title", "category", "price"]
)

# 复杂过滤：支持 AND、OR、NOT、IN、LIKE
filter_expr = '''
    (category in ["electronics", "books"])
    and price > 50
    and created_at > 1700000000
'''
```

### 部署方案

| 部署方式 | 适用场景 | 复杂度 |
|----------|----------|--------|
| Milvus Lite | 开发测试，pip 安装 | 最低 |
| Docker Compose | 单机生产，快速部署 | 低 |
| Docker + Kubernetes | 集群部署，高可用 | 中 |
| Zilliz Cloud | 全托管，零运维 | 无 |

```bash
# Docker Compose 快速部署（适合单机生产）
wget https://github.com/milvus-io/milvus/releases/download/v2.4.0/milvus-compose.yml
docker-compose -f milvus-compose.yml up -d

# Milvus Lite 开发测试（Python 直接使用）
pip install milvus
# 自动启动嵌入式 Milvus，无需额外部署
```

生产环境推荐 Docker Compose（单机）或 Kubernetes 集群（多节点高可用），开发阶段用 Milvus Lite 可以零部署成本直接跑。

---

## 选型决策

选型的关键维度是数据规模、过滤需求、运维能力和团队技术栈。下面按不同决策因素给出推荐：

| 决策维度 | 条件 | 推荐方案 |
|----------|------|----------|
| 数据规模 | < 10万向量 | Chroma |
| 数据规模 | 10万-100万 | Chroma 单机 / Milvus Lite |
| 数据规模 | 100万-1000万 | Milvus 单机 / Qdrant |
| 数据规模 | > 1000万 | Milvus 集群 / Pinecone Serverless |
| 过滤需求 | 简单过滤 | Chroma / Milvus |
| 过滤需求 | 复杂布尔组合 | Qdrant（性能最优） |
| 部署方式 | 必须本地 | Milvus / Qdrant / Chroma |
| 部署方式 | 可以云端 | Pinecone / Zilliz Cloud |
| 技术栈 | Python 主导 | Chroma（最友好） |
| 技术栈 | Go / Rust 主导 | Milvus / Qdrant |
| 技术栈 | 已有 MongoDB | Atlas Vector Search |
| 运维能力 | 无运维团队 | Chroma / Pinecone |
| 运维能力 | 有运维团队 | Milvus / Qdrant |

---

## 实战建议

### RAG 应用架构

一个典型的 RAG 应用中，向量数据库承担知识库检索的角色。用户查询先经过 Embedding 模型编码成向量，然后在向量数据库中检索 Top-K 条最相关的文本片段，最后将这些片段作为上下文送入 LLM 生成回答。Collection 的设计通常包含四个字段：向量字段（维度取决于 Embedding 模型）、原始文本内容、元数据（来源、页码、时间戳等）、以及 HNSW 索引（M=16 是通用起点）。

### 向量维度选择

向量维度取决于 Embedding 模型的选择，不同模型在维度、精度和成本上差异明显：

| Embedding 模型 | 维度 | 特点 | 推荐场景 |
|----------------|------|------|----------|
| text-embedding-3-small | 1536 | OpenAI，通用 | 英文为主 |
| text-embedding-3-large | 3072 | OpenAI，更精准 | 高精度需求 |
| bge-large-zh | 1024 | 中文优化 | 中文场景 |
| bge-m3 | 1024 | 多语言 | 跨语言场景 |

维度越高精度越高，但存储和计算成本也成倍增长。1536 维是目前的性价比平衡点，中文场景可以降到 1024 维。

### 内存估算

部署前的内存估算是容易被忽略的环节。单个向量的存储开销等于维度乘以 4 字节（float32），加上元数据的额外开销。HNSW 索引的额外开销大约是基础存储的 1.5 倍。以 100 万条 1536 维向量为例：基础存储约 6.14 GB（1,000,000 × 1536 × 4），加上 HNSW 索引开销约 9.2 GB，总内存需求在 10 GB 左右。如果向量规模扩大到千万级，内存预算需要提前规划，或者考虑用 IVF-PQ、DISKANN 这类压缩索引来控制成本。
