---
title: "Vector Similarity Search: From Math to Algorithms"
date: 2025-06-30
tags: [Vector Search]
categories: AI
mathjax: true
lang: en
label: 051_vector-similarity-algorithm
---

The core problem a vector database solves is this: given a query vector, find the K most similar vectors in the database fast. This breaks down into three layers — the mathematical definition of similarity, the algorithm design for approximate nearest neighbor search, and the engineering optimizations around index structures and storage. This article covers the first two layers in depth: the math behind similarity measurement and the mechanics of the core search algorithms.

<!-- more -->
---

## Similarity Metrics

Before discussing retrieval algorithms, we need to settle a foundational question: how do you define "how similar" two vectors are in a high-dimensional space? The choice of metric directly affects both the semantic quality of search results and computational efficiency. The three mainstream options are cosine similarity, Euclidean distance, and inner product.

### Cosine Similarity

Cosine similarity measures the cosine of the angle between two vectors:

$$
\cos(\theta) = \frac{\vec{A} \cdot \vec{B}}{|\vec{A}| \times |\vec{B}|} = \frac{\sum_{i=1}^{n} A_i B_i}{\sqrt{\sum_{i=1}^{n} A_i^2} \times \sqrt{\sum_{i=1}^{n} B_i^2}}
$$

The output range is [-1, 1], where 1 means identical direction and -1 means opposite directions. Cosine similarity only cares about direction, ignoring vector magnitude. This makes it the default choice for text semantics. Embedding model outputs carry information in their magnitudes, but semantic similarity depends primarily on direction: two articles on the same topic, even if vastly different in length (different magnitudes), should point in roughly the same direction in semantic space.

```python
import numpy as np

def cosine_similarity(a, b):
    """Cosine similarity computation"""
    dot_product = np.dot(a, b)
    norm_a = np.linalg.norm(a)
    norm_b = np.linalg.norm(b)
    return dot_product / (norm_a * norm_b)

# Example
a = np.array([1, 2, 3])
b = np.array([2, 4, 6])  # b = 2a, same direction

print(cosine_similarity(a, b))  # Output: 1.0
```

Computational complexity is O(d), where d is the vector dimension.

### Euclidean Distance

Euclidean distance (L2 distance) measures the straight-line distance between two vectors in Euclidean space:

$$
d_{L2}(\vec{A}, \vec{B}) = \sqrt{\sum_{i=1}^{n} (A_i - B_i)^2}
$$

The range is [0, ∞), with smaller values meaning more similar. Unlike cosine similarity, Euclidean distance accounts for both direction and magnitude, making it suitable for scenarios where absolute distance carries meaning, such as image features and physical coordinates.

For normalized vectors, there's a monotonic relationship between Euclidean distance and cosine similarity:

$$
d_{L2} = \sqrt{2(1 - \cos(\theta))}
$$

The proof is straightforward. Given $\vec{A}$ and $\vec{B}$ both normalized ($|\vec{A}| = |\vec{B}| = 1$):

$$
|\vec{A} - \vec{B}|^2 = |\vec{A}|^2 + |\vec{B}|^2 - 2\vec{A}\cdot\vec{B} = 2 - 2\cos(\theta)
$$

The engineering implication is direct: if your vectors are already normalized, L2 and cosine produce identical rankings. Most embedding models today output normalized vectors by default, so choosing between L2 and cosine won't affect retrieval results in that case.

```python
def euclidean_distance(a, b):
    """Euclidean distance computation"""
    return np.sqrt(np.sum((a - b) ** 2))

# Relationship with cosine after normalization
a_norm = a / np.linalg.norm(a)
b_norm = b / np.linalg.norm(b)

d = euclidean_distance(a_norm, b_norm)
cos = cosine_similarity(a_norm, b_norm)

print(np.sqrt(2 * (1 - cos)))  # Equals d
```

### Inner Product

The inner product (dot product) is defined as the sum of component-wise products:

$$
\vec{A} \cdot \vec{B} = \sum_{i=1}^{n} A_i B_i
$$

The output range is unbounded, depending on vector magnitudes. Inner product is the fastest of the three because it skips the norm computation (which requires two passes over the vector), needing only a single pass. At scale, this difference shows up directly in throughput. The trade-off is that inner product requires pre-normalized vectors; without normalization, vectors of different magnitudes produce incomparable scores. After normalization, inner product becomes equivalent to cosine similarity.

```python
def dot_product(a, b):
    """Inner product computation"""
    return np.dot(a, b)

# For normalized vectors: inner product = cosine similarity
a_norm = a / np.linalg.norm(a)
b_norm = b / np.linalg.norm(b)

print(dot_product(a_norm, b_norm))  # Equals cosine_similarity(a_norm, b_norm)
```

### Comparing the Three Metrics

| Metric | Formula Complexity | Range | Speed | Best For |
|--------|-------------------|-------|-------|----------|
| Cosine | O(d) + norm | [-1, 1] | Medium | Text semantics, direction-sensitive |
| Euclidean (L2) | O(d) | [0, ∞) | Medium | Image features, physical coordinates |
| Inner Product | O(d) | Unbounded | Fastest | Normalized vectors, speed-critical |

The engineering decision is straightforward: use inner product for normalized text vectors (fastest computation), cosine or L2 for unnormalized vectors, and L2 for physical coordinates and image features. In most NLP applications, embeddings come pre-normalized, making inner product the performance-optimal choice.

---

## The Bottleneck of Exact Search

The most intuitive search approach is brute force (FLAT): iterate through every vector, compute similarity for each, sort, and take the top K.

```python
def brute_force_search(query, database, k=10):
    """Brute force search"""
    # Compute all similarities
    similarities = [cosine_similarity(query, vec) for vec in database]
    # Sort and take top-K
    indices = np.argsort(similarities)[-k:]
    return indices, [similarities[i] for i in indices]
```

Time complexity is O(N × d), where N is the number of vectors and d is the dimension. No extra index structure is needed. This works fine when N is under 100K. But at millions of vectors, a single query takes seconds, far too slow for real-time retrieval.

### The Curse of Dimensionality

High-dimensional space behaves very differently from our low-dimensional intuition. In 2D or 3D space, distance has clear physical meaning, and nearby points are genuinely close. In high-dimensional space (>100 dimensions), distances between all vector pairs converge toward a uniform value, and the gap between nearest and farthest neighbors shrinks dramatically.

Quantitatively, in a d-dimensional hypercube, the variance of distances between two random points is:

$$
\text{Var}(d) \approx \frac{d}{12}
$$

As d grows, the relative fluctuation of distances (standard deviation / mean) actually shrinks, meaning nearly all vectors fall on roughly the same distance shell. This creates a seemingly paradoxical situation: exact nearest neighbor search is computationally expensive, yet the "nearest" neighbor isn't meaningfully closer than most other vectors. This observation is the theoretical foundation for ANN algorithms: since finding the absolute nearest neighbor isn't necessary, finding an "approximately close" neighbor is good enough, and the algorithm can trade a small precision loss for an order-of-magnitude speedup.

---

## HNSW: Graph-Based Index

HNSW (Hierarchical Navigable Small World), proposed by Malkov et al. in 2016, is the most widely used ANN algorithm today. Its design draws from skip lists, transplanting the multi-level indexing idea into a graph structure.

### Multi-Layer Graph Structure

HNSW builds a multi-layer graph: the bottom layer (Layer 0) contains all nodes, and each successive layer randomly includes a subset of nodes, becoming sparser as you go up. Search starts from a single entry point at the top layer, greedily descending toward the target at each level, and finishes with a fine-grained local search at Layer 0 to return candidate results.

Each node's maximum layer is assigned by exponential decay probability: $p^l = 1 / (\ln M \times M^{level})$. Most nodes exist only in Layer 0, a few span multiple layers, and a tiny number appear at the highest layers. High-layer nodes act as long-range shortcuts for fast coarse positioning; low-layer nodes provide dense local connections for search precision. This structure brings search complexity close to O(log N).

### Build and Search

When inserting a new element, first randomly determine its maximum layer l, then greedily search from the top-level entry point down to layer l. Starting from layer l, at each descending level, search for efConstruction nearest neighbor candidates, select M nearest neighbors to form connections, and maintain the edge count per node within M.

```python
# HNSW build pseudocode
def insert(q, hnsw, M=16, ef_construction=200, mL=1/np.log(16)):
    # 1. Determine insertion layer
    level = int(-np.log(np.random.random()) * mL)
    
    # 2. Search from top layer to entry point at target level
    entry = hnsw.entry_point
    for l in range(hnsw.max_level, level + 1):
        entry = greedy_search(q, entry, ef=1, layer=l)
    
    # 3. Insert from level downward
    for l in range(level, -1, -1):
        candidates = search_layer(q, entry, ef_construction, l)
        neighbors = select_neighbors(q, candidates, M)
        connect(q, neighbors, l)
```

Search follows a similar pattern: greedily descend from the top-level entry, picking the closest node at each layer as the entry to the next. Upon reaching Layer 0, expand the search with width ef and return the top K results.

```python
def search(q, hnsw, ef=50, k=10):
    entry = hnsw.entry_point
    
    # Greedy descent from top layer
    for l in range(hnsw.max_level, 0):
        entry = greedy_search_layer(q, entry, ef=1, layer=l)
    
    # Layer 0: expanded search
    candidates = search_layer(q, entry, ef, layer=0)
    
    # Return top-K
    return sorted(candidates, key=lambda x: x.distance)[:k]
```

### Parameter Tuning

HNSW has three key parameters that control the trade-offs between precision, memory, and build speed.

| Parameter | Effect | Tuning Advice |
|-----------|--------|---------------|
| M | Higher = better precision, but more memory and build time | 16-32 works for most scenarios |
| efConstruction | Higher = better build quality, but slower build | 200-400 is sufficient for most cases |
| ef | Higher = better recall, but more query latency | 50-100 for online queries |

The ef parameter has the most direct impact on recall and latency. Here's real benchmark data from the SIFT-1M dataset:

| ef Value | Recall | Latency |
|----------|--------|---------|
| 10 | 70% | 1ms |
| 50 | 95% | 5ms |
| 100 | 98% | 10ms |
| 200 | 99.5% | 20ms |

For online query scenarios, ef between 50 and 100 typically satisfies both recall and latency requirements. If the business demands extremely high recall (>99%), pushing ef above 200 works, at the cost of roughly doubled latency.

---

## Inverted File Index (IVF)

IVF (Inverted File Index) borrows from the inverted index concept in full-text search: partition the vector space via clustering first, then perform local search within each cluster.

### Clustering and Search

During build, K-means clustering runs over all vectors to produce nlist cluster centers. Each vector is assigned to its nearest center, forming nlist inverted lists. At search time, find the nprobe nearest cluster centers to the query vector, then brute-force search only within those clusters' inverted lists, and merge results for the final top K.

| Cluster | Contains |
|---------|----------|
| C1 | vec1, vec5, vec8, vec12, ... |
| C2 | vec3, vec7, vec11, ... |
| C3 | vec2, vec4, vec6, ... |

```python
# IVF build pseudocode
def build_ivf(vectors, nlist=1024):
    # K-means clustering
    centroids = kmeans(vectors, nlist)
    
    # Assign vectors to clusters
    clusters = {i: [] for i in range(nlist)}
    for vec in vectors:
        nearest = argmin(distance(vec, centroids))
        clusters[nearest].append(vec)
    
    return centroids, clusters

# IVF search pseudocode
def search_ivf(query, centroids, clusters, nprobe=10, k=10):
    # Find nearest nprobe clusters
    nearest_clusters = argsort(distance(query, centroids))[:nprobe]
    
    # Search within those clusters
    candidates = []
    for c in nearest_clusters:
        for vec in clusters[c]:
            candidates.append((vec, distance(query, vec)))
    
    # Return top-K
    return sorted(candidates, key=lambda x: x[1])[:k]
```

### Parameters and Performance

nlist controls the number of clusters, typically set to $\sqrt{N}$ (N = total vector count). nprobe controls how many clusters to probe during search, serving as the primary knob for the recall-latency trade-off. The higher the nprobe-to-nlist ratio, the higher the recall and the higher the latency.

| nprobe/nlist Ratio | Recall |
|-------------------|--------|
| 1% | 60-70% |
| 5% | 85-90% |
| 10% | 92-96% |
| 20% | 95-98% |

IVF's strength lies in its simple implementation and fast build speed, making it suitable for build-time-sensitive scenarios. Its limitation is that it doesn't compress vectors at all, so memory consumption remains O(Nd), the same as brute force.

---

## Product Quantization Compression

The storage cost of high-dimensional vectors adds up quickly. A 1536-dimensional float32 vector takes 6KB each; a million of them need about 6GB of memory. When data scales further and memory becomes the primary bottleneck, vector compression becomes necessary.

### Quantization Basics

Product Quantization (PQ) works by splitting high-dimensional vectors into multiple low-dimensional sub-vectors, then independently clustering and quantizing each subspace. Given a vector $\vec{x} \in \mathbb{R}^d$, split it into $m$ sub-vectors, each with dimension $d/m$. Each subspace uses K* cluster centers (typically K* = 256, mapping to an 8-bit index) for K-means quantization:

$$
q^i(\vec{x}^i) = \arg\min_k ||\vec{x}^i - \vec{c}_k^i||^2
$$

The quantized vector is represented as $[q^1, q^2, ..., q^m]$, totaling m bytes. With d=1536 and m=48, the original vector needs 1536 × 4 = 6144 bytes, while the compressed version needs only 48 bytes, a 128x compression ratio. A million vectors drop from 6GB to roughly 48MB.

### ADC Distance Computation

Once vectors are compressed, a direct question arises: how do you compute distances on compressed representations? PQ's approach is to leave query vectors uncompressed and only compress database vectors. Before search, precompute the distances between the query vector and every codebook center in each subspace, producing an m × K* distance table. Then for each PQ-encoded vector, approximate the distance with m table lookups and additions.

```python
def pq_distance(query, pq_code, codebooks, m=8):
    """PQ distance computation"""
    # 1. Precompute distance table
    # distance_table[i][k] = distance(query segment i, center k in codebook i)
    distance_table = precompute_distance_table(query, codebooks, m)
    
    # 2. Table lookup and accumulate
    d = 0
    for i in range(m):
        d += distance_table[i][pq_code[i]]
    
    return d
```

Distance table construction costs $O(d \times K^*)$, and per-vector distance lookup costs O(m). Compared to raw distance computation at O(d), PQ table lookup is much faster ($m \ll d$, typically m is just a fraction of d). The trade-off is that quantization introduces precision loss — PQ distances are approximate, not exact. In benchmarks, PQ alone typically achieves around 85% recall, suitable for scenarios that don't demand extreme precision.

---

## IVF-PQ: Combined Optimization

IVF and PQ each solve a different dimension of the problem: IVF narrows the search scope via clustering but doesn't compress vectors; PQ compresses memory aggressively but requires full-table lookups. Combining them into IVF-PQ gives you both search acceleration and memory compression.

During build, K-means first partitions the vector space into nlist clusters, then PQ compresses the vectors within each cluster. Search has three steps: find the nprobe nearest clusters using FLAT search over cluster centers, compute approximate distances using PQ table lookups within those clusters, and optionally rerank the top K candidates with original vectors to improve final precision.

```python
def search_ivf_pq(query, nprobe=10, k=10, rerank=True):
    # 1. Find clusters
    nearest_clusters = find_nearest_clusters(query, nprobe)
    
    # 2. PQ table lookup search
    candidates = pq_search(query, nearest_clusters, k * rerank_factor)
    
    # 3. Rerank (optional)
    if rerank:
        candidates = rerank_with_original_vectors(query, candidates, k)
    
    return candidates[:k]
```

Reranking is a notable design choice in IVF-PQ. PQ distances are approximate, so top K results ranked by PQ distance alone may not be the true top K. By keeping original vectors (or storing them separately) and recomputing exact distances on the PQ-shortlisted candidates, you can recover 3-5 percentage points of recall. The cost is extra distance computations and storage for original vectors, but since reranking only touches a small candidate set, the overhead stays manageable.

---

## Algorithm Performance Comparison

### Theoretical Complexity

| Algorithm | Build Complexity | Search Complexity | Space Complexity |
|-----------|-----------------|-------------------|-----------------|
| FLAT | O(1) | O(Nd) | O(Nd) |
| IVF | O(Ndnlist) | O(nprobe × Nd/nlist) | O(Nd) |
| HNSW | O(Nd × efConstruction × logN) | O(d × ef × logN) | O(Nd × M) |
| PQ | O(Nd × K*) | O(dK* + Nm) | O(Nm) |
| IVF-PQ | O(Nd × nlist × K*) | O(nprobe × (dK* + N/nlist × m)) | O(Nm) |

### Benchmark Data

The following data comes from benchmarks on the SIFT-1M dataset (128 dimensions, 1 million vectors):

| Algorithm | Recall@10 | QPS | Memory |
|-----------|-----------|-----|--------|
| FLAT | 100% | 200 | 512MB |
| IVF (nlist=1024, nprobe=64) | 95% | 8000 | 512MB |
| HNSW (M=16, ef=64) | 96% | 15000 | 700MB |
| PQ (m=8) | 85% | 30000 | 16MB |
| IVF-PQ (nlist=1024, m=8) | 90% | 20000 | 16MB |

HNSW excels in both recall and speed, but its memory footprint is 1.4x that of FLAT. IVF-PQ trades 3% of the memory for 90% recall and 20,000 QPS, making it a practical choice for memory-constrained environments. When data scales past a billion vectors, DiskANN (Microsoft, 2019) offers a different approach: store vectors and indexes on SSD, keeping only cluster centers and hot data in memory, leveraging SSD's high-concurrency random reads to support billion-scale retrieval with just 16GB of RAM.

---

## Engineering Best Practices

### Index Selection

Data scale is the primary factor in choosing an index type. Under 100K vectors, FLAT exact search is sufficient — no need to introduce index complexity. Between 100K and 1M, choose HNSW if memory is plentiful (best speed and recall) or IVF-PQ if memory is tight. Above 1M, HNSW remains the top choice but memory pressure grows, and IVF-PQ's cost-effectiveness becomes more apparent. At massive scale (billions+), consider DiskANN or a sharding strategy.

### Parameter Tuning

| Goal | Parameter Adjustment |
|------|---------------------|
| Improve recall | Increase ef (HNSW) or nprobe (IVF) |
| Reduce latency | Decrease M and ef (HNSW); increase nlist and decrease nprobe (IVF) |
| Reduce memory | Enable PQ compression, or decrease HNSW's M |
| Speed up build | Decrease HNSW's efConstruction |

Parameter tuning is fundamentally a three-way trade-off between recall, latency, and memory. In practice, fix the memory budget first, then adjust ef or nprobe to balance recall against latency.

### Common Troubleshooting

| Problem | Where to Look |
|---------|--------------|
| Recall too low | Increase ef/nprobe; check vector quality — poor vectors cause clustering to fail |
| Latency too high | Reduce candidate count; check for unnecessary reranking |
| Memory exceeds expectations | Confirm PQ compression is enabled; check if HNSW's M is set too high |
| Build takes too long | Lower efConstruction; consider batched builds with index merging |

Troubleshooting typically follows a fixed path: first check if parameters are within reasonable ranges, then examine the data itself for anomalies (e.g., extremely skewed vector distributions), and only then consider switching algorithms. The choice of metric depends on data characteristics, the choice of algorithm depends on scale and resource constraints, and parameter tuning depends on the business's tolerance for recall versus latency. Understanding the underlying principles matters because when the system exhibits atypical behavior, you can trace root causes back to math and algorithm mechanics rather than blindly tweaking parameters.
