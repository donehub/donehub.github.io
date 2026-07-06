---
title: RAG 准确率优化
date: 2026-05-05
tags: [RAG]
categories: [AI]
---

## 背景

做 RAG 系统的开发者，大概都会经历过这样一个过程：

Demo 阶段跑几个测试用例，效果惊艳。一上真实业务数据，准确率直接掉到 60% 甚至更低，用户投诉不断，自己也说不清问题出在哪。

我曾经连续三周每天晚上对着 Bad Case 分析表发呆，改了 Prompt 没用，换了大模型没用，调了 TopK 还是没用。最后发现，问题根本不在大模型那一环，而是在大模型之前的整条链路上。

这篇文章通过深度讲解四步优化，每一步都能量化地拉高准确率，最终从 60% 做到 85%。

<!-- more -->

## 先看全局：RAG 全链路优化地图

在动手之前，先把整个链路摊开来看。RAG 系统不是"检索 + 生成"两个黑盒，而是一条精密的流水线，任何一个环节出问题，最终输出都会崩。

```
用户输入
  │
  ▼
┌──────────────────────┐
│  ① Query 预处理       │  ← 第二环：改写 + 校验
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  ② 混合检索          │  ← 第三环：向量 + BM25 + LambdaMART 重排
│     (向量 + 关键词)    │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  ③ 上下文组装         │  ← 检索结果拼装，喂给大模型
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  ④ 大模型生成         │  ← Prompt + 生成策略
└──────────────────────┘

        ↕ 贯穿全链路 ↕

┌──────────────────────┐
│  ⑤ 文档分块 & 索引    │  ← 第一环：地基，离线阶段
└──────────────────────┘
```

下面按优先级从高到低，逐环拆解。

## 第一环：文档分块 —— 全链路性价比最高的优化

### 为什么文档分块是地基

很多人做文档切分图省事，直接固定 Token 数一刀切——每 500 Token 切一段，简单粗暴。这是典型的实验室玩法，上线必出问题。因为你一刀下去，很可能把一件完整的事情切成两半：

- 一个完整的知识点被拦腰截断
- 一张结构化表格被切成上半截和下半截
- 一段"因为...所以..."的因果关系，"因为"在上一个 chunk，"所以"在下一个 chunk

检索的时候，召回的全是碎片化的残缺信息。大模型连完整上下文都看不到，更没法指望它给出正确答案。

这就好比你要查字典找一个词的完整释义，结果字典被人从中间撕开了，你只看到前半句——"此药适用于"——后面的内容没了。你知道它适用，但你不知道适用于什么。

### 工业界怎么做：语义感知的动态切分

我们不用死板的 Token 计数器，而是用NLP 语义感知的方式做动态切分。核心思路是：绝不让一个完整的语义单元被拆到两个 chunk 里。

具体怎么做？分三步走。

#### 第一步：文档结构解析

在切分之前，先解析文档的骨架结构。这一步要用专业的解析模型，而不是简单的正则匹配。

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter
import spacy

# 加载中文 NLP 模型
nlp = spacy.load("zh_core_web_sm")

def parse_document_structure(raw_text):
    """
    解析文档的层级结构，返回结构化的章节树。
    识别标题层级、段落边界、表格区域等。
    """
    doc = nlp(raw_text)

    # 按句子边界切分，保留完整句子
    sentences = [sent.text for sent in doc.sents]

    # 识别标题（这里简化处理，实际场景需要更复杂的规则或模型）
    sections = []
    current_section = {"title": "default", "paragraphs": []}

    for sent in sentences:
        if is_heading(sent):  # 判断是否是标题
            if current_section["paragraphs"]:
                sections.append(current_section)
            current_section = {"title": sent, "paragraphs": []}
        else:
            current_section["paragraphs"].append(sent)

    if current_section["paragraphs"]:
        sections.append(current_section)

    return sections
```

#### 第二步：语义完整性保护

解析完结构后，切分时必须遵循语义完整性原则：

| 规则 | 说明 |
|------|------|
| 标题和正文不分离 | 标题必须和它下面的段落绑定在同一个 chunk |
| 因果不断裂 | "因为...所以..."、"如果...那么..."必须在同一 chunk |
| 表格整体化 | 结构化表格要么整体作为一个 chunk，要么按行/列做结构化拆分 |
| 列表不割裂 | 一个有序列表或无序列表尽量保持在同一 chunk |

#### 第三步：上下文重叠窗口

即使做了语义感知切分，相邻 chunk 之间也可能存在语义断层。所以必须加重叠窗口：每个 chunk 保留头部和尾部 10%~20% 的内容作为重叠区。

打个比方，就像接力赛的交棒区：前一个选手和后一个选手有一段距离是共同持有的，这样交接的时候不会掉棒。

```python
class SemanticChunker:
    """语义感知的文档分块器"""

    def __init__(
        self,
        chunk_size: int = 512,        # 目标 chunk 大小（Token 数）
        overlap_ratio: float = 0.15,  # 重叠比例 15%
        min_chunk_size: int = 100,    # 最小 chunk 大小
    ):
        self.chunk_size = chunk_size
        self.overlap_tokens = int(chunk_size * overlap_ratio)  # ~77 tokens
        self.min_chunk_size = min_chunk_size
        self.nlp = spacy.load("zh_core_web_sm")

    def chunk_document(self, text: str) -> list[dict]:
        """
        对文档进行语义感知分块。
        返回 chunk 列表，每个 chunk 包含内容和元数据。
        """
        # 1. 解析文档结构
        sections = self._parse_structure(text)

        # 2. 按结构边界进行初步切分
        raw_chunks = self._split_by_structure(sections)

        # 3. 对过长的 chunk 做二次切分（以句子为最小单位）
        refined_chunks = self._refine_chunks(raw_chunks)

        # 4. 添加重叠窗口
        final_chunks = self._add_overlap(refined_chunks)

        return final_chunks

    def _split_by_structure(self, sections: list) -> list[str]:
        """按文档结构边界切分，保证标题-段落完整性"""
        chunks = []
        for section in sections:
            # 标题 + 所属段落绑定为一个单元
            section_text = f"{section['title']}\n" + "\n".join(
                section["paragraphs"]
            )
            chunks.append(section_text)
        return chunks

    def _refine_chunks(self, raw_chunks: list[str]) -> list[str]:
        """对超长 chunk 按句子边界二次切分"""
        refined = []
        for chunk in raw_chunks:
            doc = self.nlp(chunk)
            sentences = [sent.text for sent in doc.sents]

            current_chunk = ""
            for sent in sentences:
                # 如果加上这句话超过 chunk_size，且当前已有内容
                if (
                    len(self._tokenize(current_chunk + sent))
                    > self.chunk_size
                    and current_chunk
                ):
                    refined.append(current_chunk.strip())
                    current_chunk = sent
                else:
                    current_chunk += sent

            if current_chunk and len(current_chunk.strip()) > self.min_chunk_size:
                refined.append(current_chunk.strip())

        return refined

    def _add_overlap(self, chunks: list[str]) -> list[dict]:
        """为相邻 chunk 添加头尾重叠窗口"""
        result = []
        for i, chunk in enumerate(chunks):
            # 头部重叠：取上一个 chunk 的尾部
            head_overlap = ""
            if i > 0:
                prev_tokens = self._tokenize(chunks[i - 1])
                head_overlap = self._detokenize(
                    prev_tokens[-self.overlap_tokens:]
                )

            # 尾部重叠：取下一个 chunk 的头部
            tail_overlap = ""
            if i < len(chunks) - 1:
                next_tokens = self._tokenize(chunks[i + 1])
                tail_overlap = self._detokenize(
                    next_tokens[:self.overlap_tokens]
                )

            result.append({
                "content": chunk,
                "metadata": {
                    "head_overlap": head_overlap,
                    "tail_overlap": tail_overlap,
                    "chunk_index": i,
                },
            })

        return result

    def _tokenize(self, text: str) -> list[str]:
        """简单的 Token 化（实际场景用 tiktoken 等专业工具）"""
        return text.split()

    def _detokenize(self, tokens: list[str]) -> str:
        return " ".join(tokens)
```

### 这一步的效果

在固定 Token 切分的基线上，不用动大模型分毫，光是把切分策略从一刀切换成语义感知动态切分 + 重叠窗口，准确率就能直接拉升 10~15 个百分点。

这就是为什么我说它是全链路性价比最高的优化——投入产出比太高了。

## 第二环：Query 预处理 —— 上线后准确率跳水的主因

### 真实用户的提问会比较离谱

实验室里测试的时候，习惯用完整的问句："请问这个产品的退款政策是什么？"

但真实用户可能是这样问的：

- "怎么退费"
- "开票规则"
- "有效期"
- "能不能退"

两三个字，语义极度模糊。你拿"开票规则"四个字去做向量检索，embedding 模型能给你算出一个向量，但这个向量在语义空间里指向的方向是极其不确定的——它可能匹配到"如何开发票"，也可能匹配到"发票开具的时间规定"，甚至匹配到"开票系统的使用说明"。

直接检索，准确率不可能高。

### 标准做法：Query 扩写

常规的解法是用一个小模型对用户原始 Query 做扩写，生成几个同义或近义的问句，然后分别检索，最后合并结果。

```python
def expand_query(original_query: str) -> list[str]:
    """用 LLM 对用户 Query 进行扩写"""
    prompt = f"""
    用户输入了一个简短的问题："{original_query}"
    请生成 3 个语义相近但表述不同的改写版本，
    帮助用户更全面地检索相关信息。

    要求：
    1. 改写后的问题必须和原问题语义一致
    2. 覆盖不同的表述角度
    3. 每个改写独立一行，用数字编号

    示例：
    用户输入："怎么退费"
    改写：
    1. 如何申请退款，退费的流程是什么？
    2. 退款需要满足什么条件，多久能到账？
    3. 退费申请在哪里提交，需要哪些材料？
    """
    response = llm.generate(prompt)
    return parse_expansions(response)
```

思路没错，但这里藏着一个非常容易踩到的巨坑。

### 巨坑：改写模型的幻觉

扩写模型一旦出现幻觉，你的整个检索就会被带偏。

举个例子：

| 原始 Query | 正确扩写 | 幻觉扩写 |
|-----------|---------|---------|
| 怎么退费 | 如何申请退款 | 如何收费 ← **反义了！** |
| 开票规则 | 发票开具的规定 | 不开票的流程 |
| 有效期 | 产品的有效期限 | 过期了怎么办 ← **语义偏移了** |

"怎么退费"被扩写成"怎么收费"——一个是问退款，一个是问收费，语义完全相反。这种扩写结果参与检索，不仅不会帮忙，反而会引入大量噪声，把正确答案从 Top-K 里挤出去。

你花大力气做的检索系统，被自己加的 Query 扩写模块给废了。

### 兜底机制：余弦相似度校验

这里必须加一道防线：对所有扩写后的 Query，做语义相似度校验。

```python
from sentence_transformers import SentenceTransformer, util

class QueryRewriter:
    """带语义校验的 Query 扩写器"""

    # 相似度阈值：通用场景的黄金值
    SIMILARITY_THRESHOLD = 0.8

    def __init__(self):
        self.embed_model = SentenceTransformer("BAAI/bge-large-zh-v1.5")

    def safe_expand(self, original_query: str) -> list[str]:
        """
        安全扩写：扩写 + 语义校验，过滤掉偏离原意的改写。
        """
        # 1. 用 LLM 生成扩写结果
        expansions = self._llm_expand(original_query)

        # 2. 计算原始 Query 的 embedding
        original_embedding = self.embed_model.encode(
            original_query, convert_to_tensor=True
        )

        # 3. 逐条校验
        valid_expansions = []
        for exp in expansions:
            exp_embedding = self.embed_model.encode(
                exp, convert_to_tensor=True
            )
            cosine_sim = util.cos_sim(
                original_embedding, exp_embedding
            ).item()

            if cosine_sim >= self.SIMILARITY_THRESHOLD:
                # 相似度达标，保留
                valid_expansions.append(exp)
            else:
                # 相似度不达标，说明改写偏离了原意，废弃
                print(
                    f"[过滤] '{exp}' 与原 Query 相似度仅 {cosine_sim:.3f}，"
                    f"低于阈值 {self.SIMILARITY_THRESHOLD}，已丢弃"
                )

        # 4. 兜底：如果所有扩写都被过滤了，至少用原始 Query 检索
        if not valid_expansions:
            valid_expansions = [original_query]

        return valid_expansions
```

0.8 这个阈值是怎么来的？

这是通用场景下经过大量实验验证的经验值：
- **≥ 0.8**：改写基本保持了原意，可以安全使用
- **0.6 ~ 0.8**：有一定语义偏移，需要根据具体业务判断
- **< 0.6**：基本可以认为改写偏离了原意

当然，你的业务场景不同，这个阈值需要微调。建议拿 100 条真实用户 Query，人工标注扩写质量，画出相似度分布图，找到最佳切分点。

### 这一步的价值

这一步的核心价值不在于"提升上限"，而在于守住下限：从源头杜绝我们自己给系统引入噪声。不加这道防线，你的 Query 扩写模块就是一个随机的噪声注入器，系统表现会极不稳定。

## 第三环：混合检索与重排序 —— 解决量纲冲突

### 问题：两个维度的分数怎么合并

大家都知道 RAG 要做混合检索：向量检索（Dense Retrieval）+ 关键词检索（BM25 Sparse Retrieval）。向量检索擅长语义匹配，BM25 擅长精确关键词匹配，两者互补。

但问题来了——

| 检索方式 | 打分范围 | 示例分数 |
|---------|---------|---------|
| 向量检索（余弦相似度） | [0, 1] | 0.87 |
| BM25 | [0, +∞) | 15.3 |

向量检索的打分是 0~1 之间的余弦相似度，BM25 的打分可能是十几甚至几十。两个维度的量纲完全不一样，我们怎么合并？

最朴素的做法是归一化，然后加权求和：

```python
# 朴素做法（不推荐）
final_score = 0.7 * normalize(vector_score) + 0.3 * normalize(bm25_score)
```

0.7 和 0.3 都是拍脑袋定的。

不同的 Query 类型，最优权重完全不一样：
- 对于"合同违约条款第几条"这种精确关键词查询，BM25 的权重应该更高
- 对于"这个产品适合什么人用"这种语义模糊查询，向量检索的权重应该更高

拍脑袋定一个固定权重，等于用一种策略应对所有场景，效果不可能好。

### 工业界解法：LambdaMART 排序学习

工业界的标准做法是用排序学习（Learning to Rank）模型，其中 LambdaMART 是最成熟、应用最广泛的算法之一。

LambdaMART 的核心思想是：不靠人拍脑袋定权重，而是让模型自己学。

```
                    ┌──────────────┐
  向量检索分数 ─────→│              │
                    │  LambdaMART  │──→ 统一打分
  BM25 分数 ───────→│   模型       │
                    │              │
  其他特征 ────────→│              │
  (文档长度、       └──────────────┘
   标题匹配度、
   位置信息等)
```

它做的事情是：把所有检索通道的特征（向量分数、BM25 分数、文档长度、标题匹配度、位置信息等）统一映射到同一个打分维度，输出一个科学合理的综合排序分数。

#### 为什么是 LambdaMART

排序学习有三大类方法：

| 方法类别 | 代表算法 | 特点 |
|---------|---------|------|
| Pointwise | 线性回归、逻辑回归 | 逐条打分，不考虑文档间的相对顺序 |
| Pairwise | RankSVM、RankNet | 优化文档对的相对顺序 |
| Listwise | LambdaMART、LambdaRank | 直接优化整个排序列表的指标（如 NDCG） |

LambdaMART 属于 Listwise 方法，它直接优化 NDCG 这样的排序质量指标，而不是逐条或逐对优化。这在信息检索场景下效果最好，因为用户关心的是整个结果列表的质量，而不是某一条结果的绝对分数。

#### 实操代码

```python
import lightgbm as lgb
import numpy as np

class HybridRetriever:
    """基于 LambdaMART 的混合检索重排序器"""

    def __init__(self):
        self.lambdamart_model = None
        self.vector_retriever = VectorRetriever()
        self.bm25_retriever = BM25Retriever()

    def retrieve(self, query: str, top_k: int = 10) -> list[dict]:
        """混合检索 + LambdaMART 重排序"""

        # 1. 双路召回
        vector_results = self.vector_retriever.search(query, top_k=50)
        bm25_results = self.bm25_retriever.search(query, top_k=50)

        # 2. 合并候选集（去重）
        candidates = self._merge_candidates(vector_results, bm25_results)

        # 3. 构建特征矩阵
        features = self._build_features(query, candidates)

        # 4. LambdaMART 重排序
        reranked_scores = self.lambdamart_model.predict(features)

        # 5. 按重排序分数排序，返回 Top-K
        sorted_indices = np.argsort(-reranked_scores)
        return [candidates[i] for i in sorted_indices[:top_k]]

    def _build_features(self, query: str, candidates: list) -> np.ndarray:
        """
        为每个候选文档构建特征向量。
        这些特征就是 LambdaMART 的输入。
        """
        features = []
        for doc in candidates:
            feature = [
                doc["vector_score"],           # 向量相似度分数
                doc["bm25_score"],             # BM25 分数
                doc["title_match_score"],      # 标题匹配度
                doc["doc_length"],             # 文档长度
                doc["query_doc_overlap"],      # Query 与文档的关键词重叠率
                doc["position_in_doc"],        # 匹配片段在文档中的位置
                doc["section_level"],          # 所在章节层级
            ]
            features.append(feature)
        return np.array(features)

    def train(self, train_data: lgb.Dataset, params: dict):
        """训练 LambdaMART 模型"""
        params.update({
            "objective": "lambdarank",     # 排序学习目标
            "metric": "ndcg",              # 优化 NDCG 指标
            "ndcg_eval_at": [5, 10],       # 在 Top-5 和 Top-10 处评估
            "learning_rate": 0.05,
            "num_leaves": 31,
            "max_depth": 6,
            "min_data_in_leaf": 50,
        })
        self.lambdamart_model = lgb.train(params, train_data)
```

训练数据的标注也不复杂：对于一批真实的 Query，标注每个候选文档的相关性等级（0=不相关，1=部分相关，2=完全相关），构造成排序学习的训练格式即可。

### 这一步的效果

相比固定权重的线性融合，LambdaMART 重排序通常能把 Recall@10 提升 5~10 个百分点，NDCG@10 提升更明显。而且它是轻量模型，推理延迟在毫秒级，不会影响线上性能。

## 第四环：评估指标拆解 —— 不做"笼统评分"

### 为什么"准确率 85%"没有说服力

老板：系统准确率多少？你说：85%。

老板：那剩下的 15% 是什么问题？你说：呃...

只说整体准确率，完全没有意义。 因为你不知道问题出在哪——是检索没找到正确答案？还是检索找到了，但大模型没用好？还是大模型瞎编了？

不同环节的问题，优化方向完全不同。你必须把指标拆开看。

### 两个核心指标

RAG 系统的评估，核心盯两个指标就够了：

#### 指标一：Context Recall（上下文召回率）

> **定义**：用户问题的正确答案，是否出现在检索回来的 Top-N 切片里

换句话说：检索环节是否把"正确答案的线索"给找回来了？

- 如果正确答案不在 Top-N 里 → 检索环节出了问题 → 去优化文档分块、检索策略
- 如果正确答案在 Top-N 里但最终回答错了 → 检索没问题，问题在生成环节

```python
def compute_context_recall(
    question: str,
    ground_truth: str,
    retrieved_chunks: list[str],
    evaluator_llm
) -> float:
    """
    计算 Context Recall。
    核心思路：检查 ground_truth 中的关键信息是否出现在 retrieved_chunks 中。
    """
    prompt = f"""
    问题：{question}
    标准答案：{ground_truth}
    检索到的上下文：
    {"".join([f"[{i+1}] {chunk}" for i, chunk in enumerate(retrieved_chunks)])}

    请判断：标准答案中的关键信息，有多少能在检索到的上下文中找到？
    请返回一个 0~1 之间的分数。
    评分标准：
    - 1.0：所有关键信息都能在上下文中找到
    - 0.5：部分关键信息能找到
    - 0.0：关键信息完全找不到
    """
    score = evaluator_llm.generate(prompt)
    return float(score)
```

#### 指标二：Faithfulness（忠实度）

> **定义**：大模型生成的回答，是否忠实于检索到的资料？有没有脱离资料瞎编？

这就是我们常说的幻觉率。检索回来的资料里明明写的是 A，大模型偏偏说是 B，这就是不忠实。

```python
def compute_faithfulness(
    answer: str,
    retrieved_chunks: list[str],
    evaluator_llm
) -> float:
    """
    计算 Faithfulness。
    核心思路：检查回答中的每个声明，是否都能从检索到的资料中找到依据。
    """
    # 1. 把回答拆解成独立的声明（claims）
    claims_prompt = f"""
    请将以下回答拆解为独立的事实声明：
    {answer}
    每行一个声明。
    """
    claims = evaluator_llm.generate(claims_prompt).strip().split("\n")

    # 2. 逐条检查每个声明是否有资料支撑
    context = "\n".join(retrieved_chunks)
    supported_count = 0

    for claim in claims:
        check_prompt = f"""
        声明：{claim}
        上下文资料：
        {context}

        这个声明能否从上下文资料中得到支撑？
        回答 "yes" 或 "no"。
        """
        result = evaluator_llm.generate(check_prompt).strip().lower()
        if result == "yes":
            supported_count += 1

    # 3. Faithfulness = 有依据的声明数 / 总声明数
    return supported_count / len(claims) if claims else 0.0
```

### 用指标拆解驱动优化

把这两个指标监控起来之后，你就能精准定位问题了：

| Context Recall | Faithfulness | 诊断 | 优化方向 |
|:---:|:---:|------|------|
| 高 | 高 | ✅ 系统健康 | 维持现状 |
| **低** | 高 | 检索没找对，但生成没问题 | 优化文档分块、Query 扩写、检索策略 |
| 高 | **低** | 检索找对了，但大模型瞎编 | 优化 Prompt、加引用约束、换模型 |
| **低** | **低** | 全链路都有问题 | 从头到尾逐步排查 |

**这才是工程化的做法**——不是看着一个笼统的分数盲目调参，而是用指标拆解精确定位问题环节，针对性优化。

## 效果总结：四步优化的累计收益

把四步优化串起来，看一个典型的收益曲线：

```
准确率
  │
  │                                          ● 85%
  │                                    ●─────┘
  │                              ●─────┘
  │  ● 60%               ●─────┘
  │  │  基线        ●─────┘
  │  │              │
  │  │    +15pp     │ +5pp
  │  │  (文档分块)  │(混合重排)
  │  │              │
  │  ●────────●─────●
  │           │
  │      守住下限
  │     (Query校验)
  └────────────────────────────────→
     基线    第一步   第二步   第三步   第四步
                                 (指标拆解)
```

| 优化步骤 | 核心动作 | 典型收益 |
|---------|---------|---------|
| 第一步：文档分块 | 语义感知动态切分 + 重叠窗口 | **+10~15pp** |
| 第二步：Query 校验 | 扩写 + 余弦相似度 ≥ 0.8 兜底 | 守住下限，防退化 |
| 第三步：混合重排 | LambdaMART 统一打分 | **+5~10pp**（Recall@10） |
| 第四步：指标拆解 | Context Recall + Faithfulness 分开监控 | 精准定位，持续迭代 |

## 总结

> **切分**不搞一刀切，动态语义加重叠。
> **改写**不丢原语义，相似度校验做兜底。
> **排序**不拍脑袋定，LambdaMART 来统一。
> **优化**不看笼统分，召回忠实拆分明。

RAG 系统从 Demo 到工业级，不是靠换一个更大的模型就能解决的。它是一条精密的流水线，每一个环节都需要工程化的思维和可量化的优化。把上面这四步做透，RAG 系统就能真正扛住线上流量的考验。

---

**参考资源**：

- [Anthropic Contextual Retrieval](https://www.anthropic.com/news/contextual-retrieval)
- [RAGAS — RAG 评估框架](https://github.com/explodinggradients/ragas)
- [LightGBM LambdaRank 文档](https://lightgbm.readthedocs.io/en/latest/parameters.html#learning-rate-parameters)
- [Sentence Transformers](https://www.sbert.net/)
