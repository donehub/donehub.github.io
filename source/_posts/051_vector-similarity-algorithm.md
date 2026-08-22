---
title: 向量相似度计算：从数学原理到算法实现
date: 2025-06-30
tags: 向量检索
categories: AI
mathjax: true
---

向量数据库面临的核心问题是：给定一个查询向量，如何快速找出数据库中最相似的 K 个向量。这个问题涉及三个层面——相似度度量的数学定义、近似最近邻搜索的算法设计、索引结构与存储的工程优化。本文从原理层面切入，剖析相似度计算的数学基础和核心算法机制。

<!-- more -->
---

## 相似度度量

在讨论检索算法之前，需要先确定一个基础问题：在高维向量空间中，如何定义两个向量的"相似程度"？不同的度量方式直接影响检索结果的语义质量，也影响计算效率。目前主流的方案有余弦相似度、欧氏距离和内积三种。

### 余弦相似度

余弦相似度（Cosine Similarity）通过计算两个向量夹角的余弦值来衡量相似程度，公式为：

$$
\cos(\theta) = \frac{\vec{A} \cdot \vec{B}}{|\vec{A}| \times |\vec{B}|} = \frac{\sum_{i=1}^{n} A_i B_i}{\sqrt{\sum_{i=1}^{n} A_i^2} \times \sqrt{\sum_{i=1}^{n} B_i^2}}
$$

它的值域为 [-1, 1]，1 表示方向完全相同，-1 表示方向相反。余弦相似度只关注向量的方向而忽略长度（magnitude），这个特性使它在文本语义场景中成为默认选择。Embedding 模型输出的向量长度本身蕴含信息，但语义相似度主要取决于方向：两篇讨论同一话题的文章，即使篇幅差异很大（向量长度不同），它们在语义空间中的方向应该是相近的。

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

计算复杂度为 O(d)，d 为向量维度。

### 欧氏距离

欧氏距离（Euclidean Distance）衡量的是两个向量在欧氏空间中的直线距离：

$$
d_{L2}(\vec{A}, \vec{B}) = \sqrt{\sum_{i=1}^{n} (A_i - B_i)^2}
$$

值域为 [0, ∞)，越小越相似。与余弦相似度不同，欧氏距离同时考虑向量的方向和长度，适合图像特征、物理坐标等绝对距离有实际意义的场景。

对于归一化向量，欧氏距离和余弦相似度之间存在单调关系：

$$
d_{L2} = \sqrt{2(1 - \cos(\theta))}
$$

证明过程如下：设 $\vec{A}$ 和 $\vec{B}$ 均归一化（$|\vec{A}| = |\vec{B}| = 1$），则：

$$
|\vec{A} - \vec{B}|^2 = |\vec{A}|^2 + |\vec{B}|^2 - 2\vec{A}\cdot\vec{B} = 2 - 2\cos(\theta)
$$

这个结论的工程意义很直接：如果向量已经归一化，用 L2 或余弦排序结果完全一致。目前多数 Embedding 模型默认输出归一化向量，此时选 L2 还是余弦不会对检索结果产生影响。

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

### 内积

内积（Inner Product / Dot Product）的定义是两个向量对应分量乘积之和：

$$
\vec{A} \cdot \vec{B} = \sum_{i=1}^{n} A_i B_i
$$

它的值域没有固定范围，取决于向量本身的量级。内积的计算速度是三者中最快的，因为它省去了 norm 计算（两遍向量遍历），只需一遍遍历即可完成。在大规模检索中，这个差异直接体现在吞吐量上。不过内积要求向量预先归一化，否则不同量级的向量混合计算会导致结果不可比。归一化后，内积等价于余弦相似度。

```python
def dot_product(a, b):
    """内积计算"""
    return np.dot(a, b)

# 归一化向量：内积 = 余弦相似度
a_norm = a / np.linalg.norm(a)
b_norm = b / np.linalg.norm(b)

print(dot_product(a_norm, b_norm))  # 与 cosine_similarity 相等
```

### 三种度量对比

| 度量方法 | 公式复杂度 | 值域 | 计算速度 | 适用场景 |
|----------|------------|------|----------|----------|
| 余弦相似度 | O(d) + norm | [-1, 1] | 中等 | 文本语义、方向敏感 |
| 欧氏距离 | O(d) | [0, ∞) | 中等 | 图像特征、物理位置 |
| 内积 | O(d) | 不固定 | 最快 | 归一化向量、追求速度 |

工程选择的判断很明确：文本向量默认归一化时用内积（计算最快），未归一化时用余弦或 L2，物理坐标和图像特征用 L2。在多数 NLP 应用中，文本经过 Embedding 模型后已经归一化，此时内积是性能最优的选择。

---

## 精确搜索的瓶颈

最直接的搜索方式是暴力搜索（FLAT）：遍历所有向量，逐一计算相似度，排序后取 Top-K。

```python
def brute_force_search(query, database, k=10):
    """暴力搜索"""
    # 计算所有相似度
    similarities = [cosine_similarity(query, vec) for vec in database]
    # 排序取 Top-K
    indices = np.argsort(similarities)[-k:]
    return indices, [similarities[i] for i in indices]
```

时间复杂度为 O(N × d)，N 为向量数，d 为维度，空间上不需要额外索引。当 N 在万级以内时，暴力搜索完全够用。但当 N 达到百万级，单次查询耗时进入秒级，无法满足实时检索的需求。

### 维度灾难

高维空间的几何特性与低维直觉有很大差异。在 2D/3D 空间中，距离有明确的物理意义，近邻确实"近"；但在高维空间（>100 维）中，所有向量之间的距离趋于均匀，近邻和远邻的差距急剧缩小。

定量来看，在 d 维超立方体中，随机两点距离的方差为：

$$
\text{Var}(d) \approx \frac{d}{12}
$$

随着 d 增大，距离的相对波动（标准差/均值）反而缩小，所有向量几乎落在同一个距离层上。这意味着精确最近邻搜索的计算代价极高，但找到的"最近邻"与其他向量的距离差异其实很小。这个看似矛盾的结论构成了 ANN 算法的理论基础：既然不需要找到绝对最近邻，只要找到"足够近"的近似最近邻就足够好了，那么算法就可以用精度上的微小损失换取数量级的速度提升。

---

## HNSW 图索引算法

HNSW（Hierarchical Navigable Small World）由 Malkov 等人在 2016 年提出，是目前应用最广泛的 ANN 算法。它的设计灵感来自跳表（Skip List），将跳表的多层索引思想移植到了图结构上。

### 多层图结构

HNSW 构建一个多层图：最底层（Layer 0）包含所有节点，往上每一层只随机包含一部分节点，越往上越稀疏。搜索从顶层的唯一入口点开始，逐层向下贪心逼近目标，最终在 Layer 0 完成精细的局部搜索并返回候选结果。

每个节点的最高层级按指数衰减概率分配，公式为 $p^l = 1 / (\ln M \times M^{level})$。这意味着大多数节点只存在于 Layer 0，少数节点跨越多个层，极少数节点出现在最高层。高层节点充当远距离跳板，实现快速粗定位；低层节点提供密集的局部连接，保证搜索精度。这种结构使搜索的时间复杂度接近 O(log N)。

### 构建与搜索

插入新元素时，先随机确定其最高层级 l，然后从顶层入口贪心搜索到 l 层的位置。从 l 层开始向下，每一层都搜索 efConstruction 个最近邻候选，从中选择 M 个最近邻建立连接，同时维护每个节点的边数不超过 M。

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

搜索过程与插入类似：从顶层入口贪心向下，每层只找最近的节点作为下一层入口。到达 Layer 0 后，以 ef 的宽度搜索候选，最终返回 Top-K。

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

### 参数调优

HNSW 有三个关键参数需要调整，它们分别控制精度、内存和构建速度之间的权衡。

| 参数 | 影响 | 调优建议 |
|------|------|----------|
| M | 增大则精度提升，但内存和构建时间也增加 | 16-32 是多数场景的平衡点 |
| efConstruction | 增大则构建质量更好，但构建时间增加 | 200-400 对多数场景足够 |
| ef | 增大则召回率提升，但查询延迟增加 | 在线查询通常用 50-100 |

ef 对召回率和延迟的影响最为直接，实测数据如下（SIFT-1M 数据集）：

| ef 值 | 召回率 | 延迟 |
|-------|--------|------|
| 10 | 70% | 1ms |
| 50 | 95% | 5ms |
| 100 | 98% | 10ms |
| 200 | 99.5% | 20ms |

对于在线查询场景，ef 设在 50-100 之间通常能同时满足召回率和延迟要求。如果业务对召回率有极高要求（比如 >99%），可以将 ef 提高到 200 以上，代价是延迟翻倍。

---

## 倒排文件索引（IVF）

IVF（Inverted File Index）的思路与全文检索中的倒排索引类似：先对向量空间做聚类划分，再在每个聚类内做局部搜索。

### 聚类划分与搜索

构建阶段，对全量向量执行 K-means 聚类，得到 nlist 个聚类中心，每个向量分配到最近的聚类中心，形成 nlist 个倒排列表。搜索阶段，先找出查询向量最近的 nprobe 个聚类中心，然后只在这些聚类的倒排列表内做暴力搜索，最后合并结果返回 Top-K。

| 聚类 | 包含向量 |
|------|----------|
| C1 | vec1, vec5, vec8, vec12, ... |
| C2 | vec3, vec7, vec11, ... |
| C3 | vec2, vec4, vec6, ... |

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

### 参数与性能

nlist 控制聚类数量，通常取 $\sqrt{N}$（N 为向量总数）。nprobe 控制搜索时探查的聚类数量，是召回率和延迟之间的主要调节旋钮。nprobe 占 nlist 的比例越大，召回率越高，延迟也越高。

| nprobe/nlist 比例 | 召回率 |
|-------------------|--------|
| 1% | 60-70% |
| 5% | 85-90% |
| 10% | 92-96% |
| 20% | 95-98% |

IVF 的优势在于实现简单、构建速度快，适合对构建时间敏感的场景。局限在于它不压缩向量本身，内存占用和暴力搜索一样是 O(Nd)。

---

## 乘积量化压缩

高维向量的存储成本不容忽视。1536 维 float32 向量，单个需要 6KB，100 万个需要约 6GB 内存。当数据规模进一步扩大，内存成为主要瓶颈时，需要对向量进行压缩。

### 量化原理

乘积量化（Product Quantization, PQ）的核心思路是将高维向量切分成多个低维子向量，每个子空间独立聚类量化。具体来说，设向量 $\vec{x} \in \mathbb{R}^d$，切分为 $m$ 个子向量，每个子向量维度为 $d/m$。每个子空间用 K* 个聚类中心（通常 K* = 256，对应 8bit 索引）做 K-means 量化，量化函数为：

$$
q^i(\vec{x}^i) = \arg\min_k ||\vec{x}^i - \vec{c}_k^i||^2
$$

量化后的向量用 $[q^1, q^2, ..., q^m]$ 表示，共 m 字节。以 d=1536、m=48 为例，原始向量需要 1536 × 4 = 6144 字节，压缩后只需 48 字节，压缩率达到 128 倍。100 万个向量的存储从 6GB 降到约 48MB。

### ADC 距离计算

向量压缩后面临一个直接问题：如何在压缩表示上计算距离？PQ 的做法是查询向量不压缩，只压缩数据库向量。搜索前，先计算查询向量与每个子空间码本中心的距离，得到一个 m × K* 的距离表。之后对每个 PQ 编码向量，只需查表累加 m 次即可得到近似距离。

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

距离表构建的复杂度为 $O(d \times K^*)$，单向量距离查表的复杂度为 O(m)。相比原始距离计算 O(d)，PQ 查表快得多（$m \ll d$，通常 m 只有 d 的几十分之一）。代价是量化引入了精度损失，PQ 距离是近似距离而非精确距离。在实测中，PQ 单独使用的召回率通常在 85% 左右，适合对精度要求不极端的场景。

---

## IVF-PQ 组合优化

IVF 和 PQ 各解决了一个维度的问题：IVF 通过聚类缩小搜索范围但不压缩向量，PQ 大幅压缩内存但需要全量查表。将两者组合成 IVF-PQ，可以同时获得搜索加速和内存压缩。

构建阶段，先用 K-means 将向量空间划分为 nlist 个聚类，然后在每个聚类内用 PQ 压缩存储向量。搜索分三步：先用 FLAT 方式在聚类中心中找最近的 nprobe 个，然后在这些聚类内用 PQ 查表计算近似距离，最后可选地对 Top-K 候选做重排（rerank），用原始向量重新计算精确距离以提高最终精度。

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

重排是 IVF-PQ 中一个值得注意的设计。PQ 距离是近似的，直接用 PQ 距离排序得到的 Top-K 可能不是真正的 Top-K。通过保留原始向量（或用额外存储），对 PQ 粗筛后的候选重新计算精确距离，可以挽回 3-5 个百分点的召回率。重排的代价是额外的距离计算和原始向量的存储，但因为只对少量候选操作，开销可控。

---

## 算法性能对比

### 理论复杂度

| 算法 | 构建复杂度 | 搜索复杂度 | 空间复杂度 |
|------|------------|------------|------------|
| FLAT | O(1) | O(Nd) | O(Nd) |
| IVF | O(Ndnlist) | O(nprobe × Nd/nlist) | O(Nd) |
| HNSW | O(Nd × efConstruction × logN) | O(d × ef × logN) | O(Nd × M) |
| PQ | O(Nd × K*) | O(dK* + Nm) | O(Nm) |
| IVF-PQ | O(Nd × nlist × K*) | O(nprobe × (dK* + N/nlist × m)) | O(Nm) |

### 实测数据

以下数据来自 SIFT-1M 数据集（128 维，100 万向量）的基准测试：

| 算法 | 召回率@10 | QPS | 内存 |
|------|----------|-----|------|
| FLAT | 100% | 200 | 512MB |
| IVF (nlist=1024, nprobe=64) | 95% | 8000 | 512MB |
| HNSW (M=16, ef=64) | 96% | 15000 | 700MB |
| PQ (m=8) | 85% | 30000 | 16MB |
| IVF-PQ (nlist=1024, m=8) | 90% | 20000 | 16MB |

HNSW 在召回率和速度上都表现优异，但内存占用是 FLAT 的 1.4 倍。IVF-PQ 用 3% 的内存换来了 90% 的召回率和 20000 QPS，是内存受限场景下的实用选择。当数据规模超过十亿级，DiskANN（Microsoft, 2019）提供了另一个思路：将向量和索引存储在 SSD 上，内存只保留聚类中心和热数据，利用 SSD 的高并发随机读取能力，16GB 内存即可支撑十亿级向量的检索。

---

## 工程实践要点

### 索引选择

数据规模是选择索引类型的首要依据。10 万向量以下，FLAT 精确搜索足够，不需要引入索引的复杂性。10 万到 100 万之间，内存充足选 HNSW（速度和召回率最优），内存紧张选 IVF-PQ。超过 100 万，HNSW 仍是首选但内存压力增大，IVF-PQ 的性价比开始显现。超大规模（十亿级以上）需要考虑 DiskANN 或者分片方案。

### 参数调优

| 调优目标 | 参数调整方向 |
|----------|-------------|
| 提高召回率 | HNSW 增大 ef，IVF 增大 nprobe |
| 降低延迟 | HNSW 减小 M 和 ef，IVF 增大 nlist 并减小 nprobe |
| 降低内存 | 引入 PQ 压缩，或减小 HNSW 的 M |
| 加速构建 | 减小 HNSW 的 efConstruction |

参数调优的本质是在召回率、延迟、内存三个维度之间做取舍。实际工程中，通常先固定内存预算，再通过调节 ef 或 nprobe 来平衡召回率和延迟。

### 常见问题排查

| 问题 | 排查方向 |
|------|----------|
| 召回率不够 | 提高 ef/nprobe；检查向量质量，低质量向量会导致聚类失效 |
| 延迟太高 | 减少候选数量；检查是否做了不必要的重排 |
| 内存超出预期 | 确认是否启用了 PQ 压缩；检查 HNSW 的 M 是否设得过大 |
| 构建时间过长 | 适当降低 efConstruction；考虑分批构建后合并索引 |

这些问题的排查通常遵循一个固定路径：先看参数是否在合理范围内，再看数据本身是否有异常（比如向量分布极度不均匀），最后才考虑更换算法。度量方式的选择归根到底取决于数据特性，算法选择取决于规模和资源约束，参数调优则取决于业务对召回率和延迟的容忍度。理解原理的意义在于，当系统出现非典型问题时，能够从数学和算法层面定位根因，而不是盲目试参。
