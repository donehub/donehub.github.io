---
title: 向量相似度计算：从数学原理到算法实现
date: 2025-06-30
tags: 向量检索
categories: AI
mathjax: true
---

## 写在前面

向量数据库的核心问题只有一个：**给定一个查询向量，如何快速找出数据库中最相似的 K 个向量？**

这个问题看似简单，实则涉及数学、算法、工程三个层面。数学层面是相似度度量，算法层面是近似最近邻搜索（ANN），工程层面是索引结构与存储优化。

这篇文章从研究角度切入，深入剖析相似度计算的数学原理和核心算法，不谈产品选型，只谈技术本质。

---

## 一、相似度度量：三种主流方法

### 1. 余弦相似度（Cosine Similarity）

**定义**：两个向量夹角的余弦值。

$$
\cos(\theta) = \frac{\vec{A} \cdot \vec{B}}{|\vec{A}| \times |\vec{B}|} = \frac{\sum_{i=1}^{n} A_i B_i}{\sqrt{\sum_{i=1}^{n} A_i^2} \times \sqrt{\sum_{i=1}^{n} B_i^2}}
$$

**特点**：
- 值域 [-1, 1]，1 表示方向完全相同，-1 表示方向相反
- 只关注方向，忽略向量长度（magnitude）
- 对向量长度不敏感，适合文本语义相似度

**为什么文本向量用余弦**：Embedding 模型输出的向量长度（norm）本身就蕴含信息，但语义相似度主要看方向。两篇文章讨论同一话题，即使篇幅不同（向量长度不同），方向应该相近。

```python
import numpy as np

def cosine_similarity(a, b):
    """余弦相似度计算"""
    dot_product = np.dot(a, b)
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    return dot_product / (norm_a * norm_b)

# 示例
a = np.array([1, 2, 3])
b = np.array([2, 4, 6])  # b = 2a，方向完全相同

print(cosine_similarity(a, b))  # 输出 1.0
```

**计算复杂度**：O(d)，d 为向量维度。

### 2. 欧氏距离（Euclidean Distance）

**定义**：两个向量在欧氏空间中的直线距离。

$$
d_{L2}(\vec{A}, \vec{B}) = \sqrt{\sum_{i=1}^{n} (A_i - B_i)^2}
$$

**特点**：
- 值域 [0, ∞)，越小越相似
- 同时考虑方向和长度
- 适合图像特征、物理坐标等绝对距离有意义的场景

**与余弦的关系**：对归一化向量，欧氏距离和余弦相似度有单调关系：

$$
d_{L2} = \sqrt{2(1 - \cos(\theta))}
$$

证明：设 $\vec{A}$ 和 $\vec{B}$ 均归一化（$|\vec{A}| = |\vec{B}| = 1$），则：

$$
|\vec{A} - \vec{B}|^2 = |\vec{A}|^2 + |\vec{B}|^2 - 2\vec{A}\cdot\vec{B} = 2 - 2\cos(\theta)
$$

**结论**：如果向量已归一化，用 L2 或余弦结果一致。

```python
def euclidean_distance(a, b):
    """欧氏距离计算"""
    return np.sqrt(np.sum((a - b) ** 2))

# 归一化后与余弦的关系
a_norm = a / np.linalg.norm(a)
b_norm = b / np.linalg.norm(b)

d = euclidean_distance(a_norm, b_norm)
cos = cosine_similarity(a_norm, b_norm)

print(np.sqrt(2 * (1 - cos)))  # 与 d 相等
```

### 3. 内积（Inner Product / Dot Product）

**定义**：两个向量对应分量乘积之和。

$$
\vec{A} \cdot \vec{B} = \sum_{i=1}^{n} A_i B_i
$$

**特点**：
- 值域取决于向量，无固定范围
- 计算最快，无需计算 norm
- 要求向量归一化，否则结果不可比

**为什么内积最快**：省去了 norm 计算（两遍向量遍历），只需一遍遍历。在大规模检索中，这个差异很显著。

```python
def dot_product(a, b):
    """内积计算"""
    return np.dot(a, b)

# 归一化向量：内积 = 余弦相似度
a_norm = a / np.linalg.norm(a)
b_norm = b / np.linalg.norm(b)

print(dot_product(a_norm, b_norm))  # 与 cosine_similarity 相等
```

### 4. 三种度量对比

| 度量方法 | 公式复杂度 | 值域 | 计算速度 | 适用场景 |
|----------|------------|------|----------|----------|
| 余弦相似度 | O(d) + norm | [-1, 1] | 中等 | 文本语义、方向敏感 |
| 欧氏距离 | O(d) | [0, ∞) | 中等 | 图像特征、物理位置 |
| 内积 | O(d) | 不固定 | 最快 | 归一化向量、追求速度 |

**工程选择**：
- 文本向量默认归一化 → 内积或余弦，推荐内积（快）
- 未归一化向量 → 余弦或 L2
- 物理坐标、图像特征 → L2

---

## 二、精确搜索 vs 近似搜索

### 1. 暴力搜索（FLAT）

遍历所有向量，逐一计算相似度，排序取 Top-K。

```python
def brute_force_search(query, database, k=10):
    """暴力搜索"""
    # 计算所有相似度
    similarities = [cosine_similarity(query, vec) for vec in database]
    # 排序取 Top-K
    indices = np.argsort(similarities)[-k:]
    return indices, [similarities[i] for i in indices]
```

**复杂度分析**：
- 时间：O(N × d)，N 为向量数，d 为维度
- 空间：O(1)，无需额外索引

**问题**：N 达到百万级时，单次查询耗时秒级，无法满足实时需求。

### 2. 维度灾难（Curse of Dimensionality）

高维空间的几何特性与低维截然不同：

| 维度 | 特性 |
|------|------|
| 2D/3D | 距离有意义，近邻真的"近" |
| 高维（>100） | 所有向量距离趋于均匀，近邻与远邻差距缩小 |

**定量分析**：在 d 维超立方体中，随机两点距离的方差：

$$
\text{Var}(d) \approx \frac{d}{12}
$$

随着 d 增加，距离分布趋于集中，"最近"和"最远"的区分度下降。

**结论**：高维空间中，精确找到最近邻代价极高，但"足够近"的近似最近邻（ANN）足够好——这是 ANN 算法的理论基础。

---

## 三、ANN 算法：核心思想与分类

ANN（Approximate Nearest Neighbor）牺牲少量精度换取大幅提升的速度。核心思想：**构建索引结构，搜索时只考察部分候选，而非全量遍历**。

### 算法分类

```
ANN 算法家族
├── 基于树（Tree-based）
│   ├── KD-Tree：低维有效，高维失效
│   ├── Ball Tree：球形划分，中等维度
│   └── Annoy（Spotify）：多棵随机投影树
│
├── 基于图（Graph-based）
│   ├── NSW：可导航小世界图
│   ├── HNSW：分层 NSW，当前最优
│   └── NGT/ONNG：日本 Yahoo 开源
│
├── 基于量化（Quantization-based）
│   ├── PQ：乘积量化，压缩向量
│   ├── OPQ：优化乘积量化
│   └── ScaNN：Google 开源，量化+重排
│
├── 基于哈希（Hash-based）
│   ├── LSH：局部敏感哈希
│   └── Multi-probe LSH：改进版
│
└── 基于聚类（Clustering-based）
    ├── IVF：倒排文件索引
    └── IVF-PQ：倒排+量化组合
```

---

## 四、HNSW：当前最优的图索引算法

### 1. 核心思想

HNSW（Hierarchical Navigable Small World）由 Malkov 等人在 2016 年提出，是当前最主流的 ANN 算法。

**灵感来源**：跳表（Skip List）。跳表通过多层索引实现 O(log N) 查找，HNSW 将这个思想移植到图结构。

**结构设计**：
- 多层图，上层稀疏，下层密集
- 搜索从顶层开始，逐层向下逼近
- 每层内节点通过边连接，边代表"邻居关系"

```
层级结构示意：

Layer 2 (最高层，概率 p²)：    ●───────●
                                 │       │
Layer 1 (概率 p¹)：        ●───●───●───●
                           │   │   │   │
Layer 0 (全量节点)：    ●─●─●─●─●─●─●─●─●─●─●
                      (每个节点都在 Layer 0)

节点进入高层概率：p^l = 1 / (ln(M) × M^(level))
高层节点数 ≈ N / (ln M × M^level)
```

### 2. 构建算法

```
算法：INSERT(element, hnsw)
输入：新元素 q，HNSW 图
输出：更新后的 HNSW 图

1. 确定插入层数 l = floor(-ln(uniform(0,1)) × mL)
2. 从顶层 entry point 开始，贪心搜索到 l 层的入口
3. 从 l 层向下到 0 层，每层：
   a. 在当前层搜索 efConstruction 个最近邻候选
   b. 从候选中选择 M 个最近邻连接
   c. 处理连接边：保持每节点最大 M 条边
```

**关键参数**：
- **M**：每节点最大连接数（默认 16）
- **efConstruction**：构建时搜索宽度（默认 200）
- **mL**：层数乘数，通常取 $1/\ln M$

```python
# HNSW 构建伪代码
def insert(q, hnsw, M=16, ef_construction=200, mL=1/np.log(16)):
    # 1. 确定插入层数
    level = int(-np.log(np.random.random()) * mL)
    
    # 2. 从顶层搜索到 level 层的入口
    entry = hnsw.entry_point
    for l in range(hnsw.max_level, level + 1):
        entry = greedy_search(q, entry, ef=1, layer=l)
    
    # 3. 从 level 层向下插入
    for l in range(level, -1, -1):
        candidates = search_layer(q, entry, ef_construction, l)
        neighbors = select_neighbors(q, candidates, M)
        connect(q, neighbors, l)
```

### 3. 搜索算法

```
算法：SEARCH(query, hnsw, ef, K)
输入：查询向量 q，HNSW 图，搜索宽度 ef，返回数量 K
输出：K 个最近邻

1. 从顶层 entry point 开始
2. 逐层向下贪心搜索：
   - 在当前层找最近的节点作为下一层入口
3. 到达 Layer 0 后，搜索 ef 个候选
4. 从候选中取 Top-K 返回
```

```python
def search(q, hnsw, ef=50, k=10):
    entry = hnsw.entry_point
    
    # 从顶层贪心向下
    for l in range(hnsw.max_level, 0):
        entry = greedy_search_layer(q, entry, ef=1, layer=l)
    
    # Layer 0：扩展搜索
    candidates = search_layer(q, entry, ef, layer=0)
    
    # 返回 Top-K
    return sorted(candidates, key=lambda x: x.distance)[:k]
```

### 4. 参数调优指南

| 参数 | 影响 | 调优建议 |
|------|------|----------|
| M ↑ | 精度↑，内存↑，构建时间↑ | 16-32 是平衡点 |
| efConstruction ↑ | 构建质量↑，构建时间↑ | 200-400 足够 |
| ef ↑ | 召回率↑，查询延迟↑ | 动态调整：在线查询用 50-100 |

**召回率与延迟权衡**：

```
ef 值      召回率      延迟
─────────────────────────────
10         70%         1ms
50         95%         5ms
100        98%         10ms
200        99.5%       20ms
```

---

## 五、IVF：倒排文件索引

### 1. 核心思想

聚类 + 倒排：将向量空间划分为多个区域（cluster），每个区域维护一个倒排列表。

**搜索流程**：
1. 找出查询向量最近的几个聚类中心
2. 只在这些聚类内搜索，而非全量遍历

```
IVF 结构示意：

向量空间划分：
┌──────────────────────────────┐
│  ┌─────┐    ┌─────┐          │
│  │ C1  │    │ C2  │   ┌───┐  │
│  │ ●●● │    │ ●●  │   │C3 │  │
│  │ ●●  │    │  ●  │   │ ● │  │
│  └─────┘    └─────┘   └───┘  │
└──────────────────────────────┘

倒排列表：
C1 → [vec1, vec5, vec8, vec12, ...]
C2 → [vec3, vec7, vec11, ...]
C3 → [vec2, vec4, vec6, ...]
```

### 2. 算法流程

```
构建阶段：
1. 对全量向量做 K-means 聚类，得到 nlist 个聚类中心
2. 每个向量分配到最近的聚类中心
3. 每个聚类维护一个倒排列表

搜索阶段：
1. 找出查询向量最近的 nprobe 个聚类中心
2. 只在这些聚类内做 FLAT 搜索
3. 合并结果，返回 Top-K
```

**关键参数**：
- **nlist**：聚类数量（通常取 $\sqrt{N}$）
- **nprobe**：搜索时探查的聚类数

```python
# IVF 构建伪代码
def build_ivf(vectors, nlist=1024):
    # K-means 聚类
    centroids = kmeans(vectors, nlist)
    
    # 分配向量到聚类
    clusters = {i: [] for i in range(nlist)}
    for vec in vectors:
        nearest = argmin(distance(vec, centroids))
        clusters[nearest].append(vec)
    
    return centroids, clusters

# IVF 搜索伪代码
def search_ivf(query, centroids, clusters, nprobe=10, k=10):
    # 找最近的 nprobe 个聚类
    nearest_clusters = argsort(distance(query, centroids))[:nprobe]
    
    # 在这些聚类内搜索
    candidates = []
    for c in nearest_clusters:
        for vec in clusters[c]:
            candidates.append((vec, distance(query, vec)))
    
    # 返回 Top-K
    return sorted(candidates, key=lambda x: x[1])[:k]
```

### 3. 性能分析

| 参数 | 影响 |
|------|------|
| nlist ↑ | 聚类更精细，单聚类内向量更少，搜索更快 |
| nprobe ↑ | 搜索更多聚类，召回率↑，延迟↑ |

**召回率与 nprobe 关系**：

```
nprobe/nlist    召回率
────────────────────────
1%              60-70%
5%              85-90%
10%             92-96%
20%             95-98%
```

---

## 六、PQ：乘积量化压缩

### 1. 问题背景

高维向量存储和计算成本高。1536 维向量，100万个需要 6GB 内存。如何压缩？

### 2. 核心思想

将高维向量切分成多个低维子向量，每个子空间独立量化。

```
PQ 量化过程：

原始向量：[v1, v2, v3, v4, v5, v6, v7, v8]  (8维)
         ↓ 切分为 4 个子向量（每个2维）
子向量：  [v1,v2]  [v3,v4]  [v5,v6]  [v7,v8]
         ↓ 每个子空间独立聚类量化
量化码：  [P1=3]   [P2=7]   [P3=1]   [P4=5]
         ↓ 存储为码本索引
存储：    [3, 7, 1, 5]  (4字节，压缩率 50%)

码本：每个子空间 256 个中心点（8bit索引）
```

**数学表示**：

设向量 $\vec{x} \in \mathbb{R}^d$，切分为 $m$ 个子向量：

$$
\vec{x} = [\vec{x}^1, \vec{x}^2, ..., \vec{x}^m], \quad \vec{x}^i \in \mathbb{R}^{d/m}
$$

每个子空间有 $K^*$ 个中心点（通常 $K^* = 256$），量化函数：

$$
q^i(\vec{x}^i) = \arg\min_k ||\vec{x}^i - \vec{c}_k^i||^2
$$

压缩后向量表示为 $[q^1, q^2, ..., q^m]$，共 $m$ 字节。

### 3. 距离计算：ADC（Asymmetric Distance Computation）

**关键洞察**：查询向量不压缩，只压缩数据库向量。预先计算查询向量与码本中心的距离表。

```python
def pq_distance(query, pq_code, codebooks, m=8):
    """PQ 距离计算"""
    # 1. 预计算距离表
    # distance_table[i][k] = distance(query的第i段, 第i个码本的第k个中心)
    distance_table = precompute_distance_table(query, codebooks, m)
    
    # 2. 查表累加
    d = 0
    for i in range(m):
        d += distance_table[i][pq_code[i]]
    
    return d
```

**复杂度分析**：
- 距离表构建：$O(m \times K^* \times d/m) = O(d \times K^*)$
- 单向量距离查表：$O(m)$

相比原始距离计算 $O(d)$，PQ 距离查表 $O(m)$ 快得多（$m \ll d$）。

### 4. 压缩率计算

```
原始存储：d × 4 字节（float32）
PQ 存储：m 字节（m 个 uint8 码）

压缩率：d × 4 / m = 4d/m

示例：d=1536, m=48
压缩率 = 1536 × 4 / 48 = 128 倍
100万向量：6GB → 48MB
```

---

## 七、IVF-PQ：组合优化

将 IVF 和 PQ 组合，兼顾速度和内存：

```
IVF-PQ 结构：

┌────────────────────────────────────────────┐
│              IVF 聚类层                     │
│   C1    C2    C3    C4    ...    Cnlist   │
├────────────────────────────────────────────┤
│              PQ 量化层                      │
│   每个聚类内向量用 PQ 压缩存储              │
│   C1 → [pq_code1, pq_code2, ...]           │
└────────────────────────────────────────────┘

搜索流程：
1. 找最近的 nprobe 个聚类中心（FLAT）
2. 在这些聚类内用 PQ 查表计算距离
3. 可选：重排（rerank）Top-K 用原始向量精确计算
```

**重排策略**：PQ 计算的是近似距离，对 Top-K 候选用原始向量重新计算精确距离。

```python
def search_ivf_pq(query, nprobe=10, k=10, rerank=True):
    # 1. 找聚类
    nearest_clusters = find_nearest_clusters(query, nprobe)
    
    # 2. PQ 查表搜索
    candidates = pq_search(query, nearest_clusters, k * rerank_factor)
    
    # 3. 重排（可选）
    if rerank:
        candidates = rerank_with_original_vectors(query, candidates, k)
    
    return candidates[:k]
```

---

## 八、算法性能对比

### 1. 理论复杂度

| 算法 | 构建复杂度 | 搜索复杂度 | 空间复杂度 |
|------|------------|------------|------------|
| FLAT | O(1) | O(Nd) | O(Nd) |
| IVF | O(Ndnlist) | O(nprobe × Nd/nlist) | O(Nd) |
| HNSW | O(Nd × efConstruction × logN) | O(d × ef × logN) | O(Nd × M) |
| PQ | O(Nd × K^*) | O(dK^* + Nm) | O(Nm) |
| IVF-PQ | O(Nd × nlist × K^*) | O(nprobe × (dK^* + N/nlist × m)) | O(Nm) |

### 2. 实测性能（SIFT-1M 数据集）

| 算法 |召回率@10 | QPS | 内存 |
|------|----------|-----|------|
| FLAT | 100% | 200 | 512MB |
| IVF (nlist=1024, nprobe=64) | 95% | 8000 | 512MB |
| HNSW (M=16, ef=64) | 96% | 15000 | 700MB |
| PQ (m=8) | 85% | 30000 | 16MB |
| IVF-PQ (nlist=1024, m=8) | 90% | 20000 | 16MB |

---

## 九、研究前沿与新算法

### 1. ScaNN（Google，2020）

创新点：**量化 + 内积优化 + 重排**。

- 量化时考虑内积最大化的方向
- 用 SIMD 加速距离表计算
- 比 HNSW 在内积度量上更快

### 2. DiskANN（Microsoft，2019）

创新点：**磁盘索引 + SSD 优化**。

- 向量和索引存储在 SSD，内存只放聚类中心
- 利用 SSD 高并发读取特性
- 支持 10 亿级向量，内存需求 < 16GB

### 3. Faiss（Facebook，2017）

工业界最成熟的开源库：

- GPU 加速（10倍提速）
- 支持 IVF、PQ、HNSW 等多种索引
- 灵活的组合索引（IVF-PQ, IVF-HNSW）

---

## 十、工程实践要点

### 1. 索引选择决策

```
数据规模 < 10万：FLAT（精确搜索）
数据规模 10万-100万：
    - 内存充足 → HNSW（最快）
    - 内存紧张 → IVF-PQ（压缩）
数据规模 > 100万：
    - 内存充足 → HNSW
    - 内存紧张 → IVF-PQ
    - 超大规模 → DiskANN
```

### 2. 参数调优经验

| 目标 | 参数调整 |
|------|----------|
| 提高召回率 | HNSW: ef↑ / IVF: nprobe↑ |
| 降低延迟 | HNSW: M↓, ef↓ / IVF: nlist↑, nprobe↓ |
| 降低内存 | 使用 PQ 压缩 |
| 加速构建 | HNSW: efConstruction↓ |

### 3. 常见陷阱

| 问题 | 解决方案 |
|------|----------|
| 召回率不够 | ef/nprobe 调高；检查向量质量 |
| 延迟太高 | 减少候选数量；检查是否做了不必要的重排 |
| 内存爆炸 | 使用 PQ 压缩；检查索引参数 M |
| 构建太慢 | efConstruction 适度降低；分批构建 |

---

## 总结

向量相似度计算的核心要点：

1. **度量选择**：归一化向量用内积（最快），文本用余弦，物理坐标用 L2
2. **算法选择**：小数据 FLAT，大数据 HNSW 或 IVF-PQ
3. **参数调优**：ef/nprobe 控制召回率，M/nlist 控制内存
4. **压缩策略**：PQ 压缩率可达 100 倍，代价是精度下降 5-10%

数学是本质，算法是手段，工程是落地。理解原理，才能在选型和调优时做出正确决策。