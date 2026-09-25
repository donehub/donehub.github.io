---
title: "Deep Dive into Vector Databases"
date: 2025-05-19
tags: Vector Database
categories: AI
lang: en
label: 050_vector-database-deep-analysis
---

When building RAG (Retrieval-Augmented Generation) applications, a vector database is the core component you can't avoid. There are plenty of products on the market (Milvus, Qdrant, Weaviate, Chroma, Pinecone), and each one claims to be the best. This article goes from底层 principles to practical selection, with a重点 analysis of Chroma and Milvus as representative products, to help you make the right choice for your specific scenario.

<!-- more -->
---

## What Problem Do Vector Databases Solve?

Traditional databases excel at exact matching: `WHERE name = 'Zhang San'`. Semantic search is a completely different requirement. A user asks "how to improve team collaboration efficiency" and the system needs to find documents with similar meaning, even if none of those exact keywords appear anywhere in the document. This is where vector databases deliver value: they convert unstructured data like text, images, and audio into vectors in high-dimensional space (strings of floating-point numbers), measure semantic similarity by computing distances between vectors, and retrieve the most semantically close content.

The process has three steps: raw text is encoded into vectors by an Embedding model and stored in the vector database. At query time, user input is encoded the same way, then the database computes similarity and returns the Top-K closest results.

```
Text → Embedding model → Vector [0.12, -0.34, 0.56, ...] → Vector database
Query → Embedding model → Vector [0.15, -0.30, 0.52, ...] → Similarity computation → Top-K results
```

---

## Core Technical Metrics

### Index Algorithms Determine the Performance Ceiling

The index algorithm of a vector database directly determines query speed and recall rate. Here are the characteristics and suitable scenarios for mainstream index types:

| Index Type | Principle | Query Speed | Memory Usage | Suitable Scenario |
|------------|-----------|-------------|--------------|-------------------|
| FLAT | Brute-force traversal, exact computation | Slowest | Highest | Small datasets, requires 100% recall |
| IVF-FLAT | Clustering + inverted index | Medium | Medium | Millions-scale, balanced approach |
| IVF-PQ | Clustering + product quantization compression | Fast | Low | Memory-constrained, trades accuracy |
| HNSW | Hierarchical Navigable Small World graph | Fastest | Relatively high | High-performance real-time queries |
| DISKANN | Disk index + SSD optimization | Slower | Very low | Ultra-large scale, cost-sensitive |

HNSW is the current mainstream choice. It builds a multi-layer graph structure. During search, it quickly jumps to the target area through the sparse top-layer graph, then progressively descends through denser lower layers for precise search — similar in concept to the layered lookup mechanism of a skip list. Building HNSW involves three key parameters: M controls the maximum number of connections per node (default 16) — higher values improve recall but increase memory usage; efConstruction determines the search range during index building (default 200); efSearch dynamically adjusts search width at query time and is the primary knob for balancing recall and latency at runtime.

### Distributed Architecture Determines Scalability

| Architecture Type | Representative Products | Characteristics |
|-------------------|------------------------|-----------------|
| Single-machine embedded | Chroma, Faiss | No deployment cost, limited by data volume |
| Single-machine service | Qdrant standalone | Independent process, supports persistence |
| Distributed cluster | Milvus, Qdrant cluster | Horizontal scaling, high availability |

### Metadata Filtering Capability

In real business scenarios, vector search often needs to combine conditional filtering — for example, finding similar products where "price is between 100-500 and category is electronics." The capability differences across databases here are significant:

| Database | Filtering Capability | Implementation |
|----------|---------------------|----------------|
| Qdrant | Strongest | Native complex filter support, best performance |
| Milvus | Strong | Scalar field filtering supported |
| Chroma | Basic | Simple where conditions |
| Pinecone | Strong | Metadata namespaces |

---

## Horizontal Comparison of Mainstream Vector Databases

### Open-Source Product Comparison

| Database | Language | Architecture | Index Support | Filtering | Community Activity |
|----------|----------|-------------|---------------|-----------|-------------------|
| Milvus | Go | Distributed | HNSW/IVF/DISKANN | Strong | Active (CNCF project) |
| Qdrant | Rust | Single/Distributed | HNSW | Strongest | Active |
| Weaviate | Go | Single/Distributed | HNSW | Strong | Active |
| Chroma | Python | Embedded | HNSW | Basic | Active |

### Cloud Service Comparison

| Product | Positioning | Advantages | Disadvantages |
|---------|-------------|------------|---------------|
| Pinecone | Fully managed serverless | Zero ops, auto-scaling | Vendor lock-in, uncontrollable costs |
| Zilliz Cloud | Milvus managed edition | Enterprise support, Milvus API compatible | Higher price |
| MongoDB Atlas Vector | MongoDB ecosystem | Reuse existing infrastructure | Limited vector capabilities |

### Performance Benchmarks (Million-scale Vectors, HNSW Index)

| Database | QPS | P99 Latency | Memory Usage |
|----------|-----|-------------|--------------|
| Milvus | ~15000 | ~10ms | High |
| Qdrant | ~12000 | ~8ms | Medium |
| Weaviate | ~8000 | ~15ms | Medium |
| Chroma | ~3000 | ~30ms | Low |

---

## Chroma: The Go-To for Lightweight Entry

### Suitable Scenarios

Chroma's design philosophy is minimalism: Python-native, embedded execution, and a friendly API. It excels in four scenarios: rapid RAG demo prototyping (runs in a few lines of code), small-scale applications with under 100K documents, local development where data should not leave the machine, and research scenarios for learning vector database fundamentals.

### Core API

```python
# Chroma's minimalist API design
import chromadb

# Initialize: embedded, no server needed
client = chromadb.PersistentClient(path="./chroma_db")

# Create a collection
collection = client.create_collection(
    name="documents",
    metadata={"hnsw:space": "cosine"}  # Supports l2, ip, cosine
)

# Add documents: auto-embedding (uses built-in default model)
collection.add(
    documents=["Document content 1", "Document content 2"],
    ids=["doc1", "doc2"]
)

# Query: all in one step
results = collection.query(
    query_texts=["Query content"],
    n_results=5
)
```

Chroma uses `all-MiniLM-L6-v2` as the default Embedding model built in, but you can swap it for third-party models like OpenAI or Cohere:

```python
from chromadb.utils import embedding_functions

# Use OpenAI Embedding
openai_ef = embedding_functions.OpenAIEmbeddingFunction(
    api_key="your-key",
    model_name="text-embedding-3-small"
)

collection = client.create_collection(
    name="docs",
    embedding_function=openai_ef
)
```

### Metadata Filtering

```python
# Add documents with metadata
collection.add(
    documents=["Technical doc", "Product doc"],
    ids=["d1", "d2"],
    metadatas=[
        {"category": "tech", "author": "Zhang San"},
        {"category": "product", "author": "Li Si"}
    ]
)

# Filter at query time
results = collection.query(
    query_texts=["How to deploy"],
    n_results=5,
    where={"category": "tech"}  # Only search in technical documents
)
```

### Limitations

| Limitation | Impact |
|-----------|--------|
| Single-machine architecture | Cannot scale horizontally, data volume caps around millions |
| Single index type | Only supports HNSW, no switching based on scenario |
| Simple filtering | No complex boolean combinations, mediocre performance |
| No distribution | No replication or sharding, single point of failure risk |

Chroma is the SQLite of vector databases — simple, pleasant to use, ideal for rapid prototyping and small-to-medium applications. Just do not expect it to handle production-grade traffic.

---

## Milvus: Production-Grade, Large-Scale First Choice

### Suitable Scenarios

Milvus is positioned as a cloud-native distributed vector database and is currently a CNCF sandbox project. It fits large-scale production applications (millions to hundreds of millions of vectors), high-concurrency real-time retrieval (low latency, high throughput requirements), complex filtering needs combining scalar fields, and infrastructure environments supporting Kubernetes and multi-cloud deployment.

### Architecture Breakdown

Milvus uses a layered architecture design, from top to bottom: SDK layer, Proxy access layer, Coordination layer, Worker node layer, and underlying Storage.

| Layer | Component | Responsibility |
|-------|-----------|---------------|
| SDK Layer | Python / Go / Java / Node.js / REST | Client access |
| Access Layer | Proxy | Request parsing, routing, load balancing |
| Coordination Layer | Root Coord | Global coordination, handles DDL (create collections, indexes, etc.) |
| Coordination Layer | Query Coord | Query node scheduling, load balancing |
| Coordination Layer | Data Coord | Data node scheduling, segment management |
| Coordination Layer | Index Coord | Index build task scheduling |
| Worker Layer | Query / Data / Index Node | Execute queries, data writes, index building |
| Storage Layer | etcd + MinIO | Metadata storage + object storage |

The advantage of this architecture is that components can scale independently. If you need more query capacity, add Query Nodes without expanding Data Nodes or Index Nodes.

### Index Selection in Practice

Different scales and scenarios call for different index strategies:

| Data Scale | Memory Budget | Recommended Index | Parameter Guidance |
|------------|--------------|-------------------|-------------------|
| < 1M | Ample | FLAT | Exact search, 100% recall |
| 1M-10M | Ample | HNSW | M=16, efConstruction=256 |
| 1M-10M | Tight | IVF-FLAT | nlist=1024 |
| > 10M | Tight | IVF-PQ | nlist=1024, m=8, nbits=8 |
| > 100M | Very tight | DISKANN | Disk index, SSD required |

```python
from pymilvus import MilvusClient, IndexType, MetricType

# Create HNSW index
index_params = MilvusClient.prepare_index_params()
index_params.add_index(
    field_name="vector",
    index_type=IndexType.HNSW,
    metric_type=MetricType.COSINE,
    params={"M": 16, "efConstruction": 256}
)

# Search parameters: dynamically adjust ef to improve recall
search_params = {"params": {"ef": 64}}  # Higher ef = better recall, higher latency
```

### Collection Design and Filtered Queries

When creating a collection, you define the schema for both vector fields and scalar fields. Scalar fields are used for subsequent filtered queries. It is recommended to create separate indexes on frequently filtered scalar fields to speed up queries.

```python
from pymilvus import MilvusClient

client = MilvusClient("http://localhost:19530")

# Create collection: vector fields + scalar fields
client.create_collection(
    collection_name="products",
    dimension=1536,  # OpenAI text-embedding-3-small dimension
    metric_type="COSINE",
    auto_id=False,
    fields=[
        {"name": "id", "dtype": "VARCHAR", "max_length": 64, "is_primary": True},
        {"name": "vector", "dtype": "FLOAT_VECTOR", "dim": 1536},
        {"name": "title", "dtype": "VARCHAR", "max_length": 256},
        {"name": "category", "dtype": "VARCHAR", "max_length": 64},
        {"name": "price", "dtype": "FLOAT"},
        {"name": "created_at", "dtype": "INT64"}  # Timestamp
    ]
)

# Create scalar field index (accelerates filtering)
client.create_index(
    collection_name="products",
    field_name="category",
    index_type="Trie"  # Trie for strings, STL_SORT for numerics
)
```

Milvus filter expressions support AND, OR, NOT, IN, LIKE and other operators, allowing scalar conditions to be applied alongside vector similarity search:

```python
# Basic filtered query
results = client.search(
    collection_name="products",
    data=[[0.1, 0.2, ...]],  # Query vector
    filter='category == "electronics" and price >= 100 and price <= 500',
    limit=10,
    output_fields=["title", "category", "price"]
)

# Complex filtering: supports AND, OR, NOT, IN, LIKE
filter_expr = '''
    (category in ["electronics", "books"])
    and price > 50
    and created_at > 1700000000
'''
```

### Deployment Options

| Deployment Method | Suitable Scenario | Complexity |
|-------------------|-------------------|------------|
| Milvus Lite | Development/testing, pip install | Lowest |
| Docker Compose | Single-machine production, quick deploy | Low |
| Docker + Kubernetes | Cluster deployment, high availability | Medium |
| Zilliz Cloud | Fully managed, zero ops | None |

```bash
# Docker Compose quick deploy (suitable for single-machine production)
wget https://github.com/milvus-io/milvus/releases/download/v2.4.0/milvus-compose.yml
docker-compose -f milvus-compose.yml up -d

# Milvus Lite for development/testing (use directly from Python)
pip install milvus
# Automatically starts embedded Milvus, no additional deployment needed
```

For production environments, Docker Compose (single machine) or Kubernetes cluster (multi-node HA) is recommended. During development, Milvus Lite runs with zero deployment overhead.

---

## Selection Decision

The key dimensions for selection are data scale, filtering needs, ops capability, and team tech stack. Here are recommendations based on different decision factors:

| Decision Dimension | Condition | Recommended Solution |
|-------------------|-----------|---------------------|
| Data scale | < 100K vectors | Chroma |
| Data scale | 100K-1M | Chroma standalone / Milvus Lite |
| Data scale | 1M-10M | Milvus standalone / Qdrant |
| Data scale | > 10M | Milvus cluster / Pinecone Serverless |
| Filtering needs | Simple filtering | Chroma / Milvus |
| Filtering needs | Complex boolean combinations | Qdrant (best performance) |
| Deployment | Must be local | Milvus / Qdrant / Chroma |
| Deployment | Cloud is acceptable | Pinecone / Zilliz Cloud |
| Tech stack | Python-dominant | Chroma (most developer-friendly) |
| Tech stack | Go / Rust-dominant | Milvus / Qdrant |
| Tech stack | Already on MongoDB | Atlas Vector Search |
| Ops capability | No ops team | Chroma / Pinecone |
| Ops capability | Has ops team | Milvus / Qdrant |

---

## Practical Advice

### RAG Application Architecture

In a typical RAG application, the vector database serves as the knowledge base retrieval layer. User queries are first encoded into vectors by the Embedding model, then the vector database retrieves the Top-K most relevant text segments, and finally those segments are fed as context to the LLM for answer generation. Collection design typically includes four fields: the vector field (dimension depends on the Embedding model), raw text content, metadata (source, page number, timestamp, etc.), and an HNSW index (M=16 is a good universal starting point).

### Vector Dimension Selection

Vector dimension depends on the Embedding model choice. Different models vary significantly in dimension, accuracy, and cost:

| Embedding Model | Dimension | Characteristics | Recommended Scenario |
|----------------|-----------|-----------------|---------------------|
| text-embedding-3-small | 1536 | OpenAI, general-purpose | Primarily English |
| text-embedding-3-large | 3072 | OpenAI, more precise | High-accuracy needs |
| bge-large-zh | 1024 | Chinese-optimized | Chinese scenarios |
| bge-m3 | 1024 | Multilingual | Cross-language scenarios |

Higher dimensions give better accuracy, but storage and computation costs grow proportionally. 1536 dimensions is the current sweet spot for cost-effectiveness. Chinese-language scenarios can drop to 1024 dimensions.

### Memory Estimation

Pre-deployment memory estimation is a step that often gets overlooked. Per-vector storage cost equals dimension count times 4 bytes (float32), plus additional overhead for metadata. HNSW index overhead is approximately 1.5x the base storage. For 1 million vectors at 1536 dimensions: base storage is roughly 6.14 GB (1,000,000 x 1536 x 4), plus HNSW index overhead brings it to about 9.2 GB, with total memory requirement around 10 GB. If vector scale grows to tens of millions, the memory budget needs upfront planning — or consider using compression indexes like IVF-PQ or DISKANN to control costs.
