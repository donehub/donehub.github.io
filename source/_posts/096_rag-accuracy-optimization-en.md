---
title: Optimizing RAG Accuracy from 60% to 85%
date: 2026-05-05
tags: [RAG]
categories: [AI]
lang: en
label: 096_rag-accuracy-optimization
---

## Background

Most developers who have built RAG systems have been through this cycle:

The demo stage goes well — a few test cases, results look promising. Then you roll it out on real business data and accuracy drops to 60% or worse. Users complain, and you can't figure out where the problem is.

I spent three consecutive weeks staring at bad case analysis spreadsheets every evening. I tweaked the prompt — no improvement. I swapped the LLM — no improvement. I adjusted TopK — still nothing. Eventually I realized the problem wasn't in the LLM at all. It was in the entire pipeline upstream of it.

This article walks through four optimization steps, each one delivering measurable accuracy gains, taking the system from 60% to 85%.

<!-- more -->

## The Full-Pipeline Optimization Map

Before touching any code, lay out the entire pipeline. A RAG system isn't two black boxes labeled "retrieve" and "generate." It's a precision assembly line where any single weak link corrupts the final output.

```
User Input
  │
  ▼
┌──────────────────────┐
│  ① Query Processing   │  ← Step 2: Rewrite + Validate
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  ② Hybrid Retrieval   │  ← Step 3: Vector + BM25 + LambdaMART rerank
│   (Vector + Keyword)  │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  ③ Context Assembly   │  ← Pack retrieval results for the LLM
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│  ④ LLM Generation     │  ← Prompt + Generation Strategy
└──────────────────────┘

        ↕ Cross-cutting ↕

┌──────────────────────┐
│  ⑤ Doc Chunking &     │  ← Step 1: Foundation, offline phase
│     Indexing          │
└──────────────────────┘
```

Below, each stage is broken down in priority order, highest first.

## Step 1: Document Chunking

### Why Chunking Is the Foundation

A lot of developers take the lazy route for document splitting: fixed token count, hard cut every 500 tokens, simple and brute-force. This works in a notebook, but it falls apart in production because a blind cut can split a single coherent piece of information in half:

- A complete knowledge point gets sliced mid-sentence
- A structured table gets separated into top half and bottom half
- A cause-and-effect pair gets split — the "because" in one chunk, the "so" in the next

When retrieval runs, it pulls back fragments of incomplete information. The LLM never sees the full context, so there's no chance it produces the right answer.

It's like looking up a word in a dictionary only to find the page torn in half. You see "this medicine is indicated for..." but the rest is gone. You know it's indicated for something, but you don't know what.

### How the Industry Does It: Semantic-Aware Dynamic Chunking

Instead of a rigid token counter, use NLP-based semantic awareness to drive dynamic splitting. The core principle is simple: never let a single semantic unit span two chunks.

Here's the three-step approach.

#### Step 1: Document Structure Parsing

Before splitting, parse the skeleton structure of the document. This requires a proper parsing model, not just regex.

```python
from langchain.text_splitter import RecursiveCharacterTextSplitter
import spacy

# Load Chinese NLP model
nlp = spacy.load("zh_core_web_sm")

def parse_document_structure(raw_text):
    """
    Parse the document's hierarchical structure, returning a structured section tree.
    Identifies heading levels, paragraph boundaries, table regions, etc.
    """
    doc = nlp(raw_text)

    # Split by sentence boundaries, preserving complete sentences
    sentences = [sent.text for sent in doc.sents]

    # Identify headings (simplified here; real scenarios need more complex rules or models)
    sections = []
    current_section = {"title": "default", "paragraphs": []}

    for sent in sentences:
        if is_heading(sent):  # Check if it's a heading
            if current_section["paragraphs"]:
                sections.append(current_section)
            current_section = {"title": sent, "paragraphs": []}
        else:
            current_section["paragraphs"].append(sent)

    if current_section["paragraphs"]:
        sections.append(current_section)

    return sections
```

#### Step 2: Semantic Integrity Protection

Once the structure is parsed, splitting must respect semantic integrity:

| Rule | Description |
|------|------|
| Headings stay with body text | A heading must be bound to its paragraphs in the same chunk |
| Cause-and-effect stays together | "because...so..." and "if...then..." must remain in one chunk |
| Tables stay whole | Structured tables should be a single chunk, or split by row/column with structured decomposition |
| Lists stay intact | Ordered or unordered lists should stay in the same chunk wherever possible |

#### Step 3: Overlapping Context Windows

Even with semantic-aware splitting, adjacent chunks can have semantic gaps at the boundaries. The fix is an overlap window: each chunk retains the first and last 10%–20% of its content as an overlap zone with neighboring chunks.

The overlap between adjacent chunks is like the exchange zone in a relay race — two runners share a stretch of track together, so the baton doesn't get dropped during the handoff.

```python
class SemanticChunker:
    """Semantic-aware document chunker"""

    def __init__(
        self,
        chunk_size: int = 512,        # Target chunk size (token count)
        overlap_ratio: float = 0.15,  # Overlap ratio 15%
        min_chunk_size: int = 100,    # Minimum chunk size
    ):
        self.chunk_size = chunk_size
        self.overlap_tokens = int(chunk_size * overlap_ratio)  # ~77 tokens
        self.min_chunk_size = min_chunk_size
        self.nlp = spacy.load("zh_core_web_sm")

    def chunk_document(self, text: str) -> list[dict]:
        """
        Perform semantic-aware chunking on the document.
        Returns a list of chunks, each containing content and metadata.
        """
        # 1. Parse document structure
        sections = self._parse_structure(text)

        # 2. Initial split along structure boundaries
        raw_chunks = self._split_by_structure(sections)

        # 3. Secondary split for oversized chunks (sentence-level granularity)
        refined_chunks = self._refine_chunks(raw_chunks)

        # 4. Add overlap windows
        final_chunks = self._add_overlap(refined_chunks)

        return final_chunks

    def _split_by_structure(self, sections: list) -> list[str]:
        """Split along document structure boundaries, preserving heading-paragraph integrity"""
        chunks = []
        for section in sections:
            # Bind heading + its paragraphs as one unit
            section_text = f"{section['title']}\n" + "\n".join(
                section["paragraphs"]
            )
            chunks.append(section_text)
        return chunks

    def _refine_chunks(self, raw_chunks: list[str]) -> list[str]:
        """Secondary split for oversized chunks along sentence boundaries"""
        refined = []
        for chunk in raw_chunks:
            doc = self.nlp(chunk)
            sentences = [sent.text for sent in doc.sents]

            current_chunk = ""
            for sent in sentences:
                # If adding this sentence exceeds chunk_size and we already have content
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
        """Add head/tail overlap windows between adjacent chunks"""
        result = []
        for i, chunk in enumerate(chunks):
            # Head overlap: take the tail of the previous chunk
            head_overlap = ""
            if i > 0:
                prev_tokens = self._tokenize(chunks[i - 1])
                head_overlap = self._detokenize(
                    prev_tokens[-self.overlap_tokens:]
                )

            # Tail overlap: take the head of the next chunk
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
        """Simple tokenization (use tiktoken or similar in production)"""
        return text.split()

    def _detokenize(self, tokens: list[str]) -> str:
        return " ".join(tokens)
```

### Impact of This Step

On top of the fixed-token baseline, without touching the LLM at all, switching from brute-force splitting to semantic-aware dynamic chunking plus overlap windows delivers a 10–15 percentage point accuracy gain. That's why I call it the highest ROI optimization in the entire pipeline.

## Step 2: Query Processing

### Real User Queries Can Be Brutally Vague

In lab testing, we tend to use well-formed questions: "What is this product's refund policy?"

Real users, on the other hand, type things like:

- "how refund"
- "invoice rules"
- "validity period"
- "can return?"

Two or three characters, semantically extremely vague. If you run "invoice rules" through vector retrieval, the embedding model will produce a vector, but that vector points in a highly uncertain direction in semantic space. It might match "how to issue invoices," or "time limits for invoice issuance," or even "instructions for using the invoicing system."

Direct retrieval on queries like these will never achieve high accuracy.

### The Standard Approach: Query Expansion

The conventional solution is to use a small model to expand the user's raw query into several synonymous or near-synonymous rewrites, run retrieval on each, then merge the results.

```python
def expand_query(original_query: str) -> list[str]:
    """Use an LLM to expand the user's query"""
    prompt = f"""
    The user entered a short query: "{original_query}"
    Generate 3 semantically equivalent but differently phrased rewrites,
    to help retrieve relevant information more comprehensively.

    Requirements:
    1. Rewrites must preserve the original meaning
    2. Cover different phrasing angles
    3. One rewrite per line, numbered

    Example:
    User input: "how refund"
    Rewrites:
    1. How to apply for a refund, what's the refund process?
    2. What conditions must be met for a refund, and how long does it take?
    3. Where do I submit a refund request, and what documents are needed?
    """
    response = llm.generate(prompt)
    return parse_expansions(response)
```

The approach is sound, but there's a serious pitfall lurking here.

### The Pitfall: Hallucination in the Rewrite Model

If the expansion model hallucinates, your entire retrieval gets derailed.

Consider these examples:

| Original Query | Correct Expansion | Hallucinated Expansion |
|-----------|---------|---------|
| how refund | How to apply for a refund | How to pay ← **Opposite meaning!** |
| invoice rules | Rules for issuing invoices | Process for not issuing invoices |
| validity period | Product validity period | What to do if expired ← **Semantic drift** |

"how refund" gets expanded to "how to pay" — one asks about refunds, the other about charges, completely opposite meanings. When this hallucinated expansion enters the retrieval pipeline, it doesn't help — it introduces noise and pushes the correct answer out of the Top-K.

The elaborate retrieval system you built gets sabotaged by its own query expansion module.

### The Safety Net: Cosine Similarity Validation

A defense layer is mandatory here: validate every expanded query against the original using semantic similarity scoring.

```python
from sentence_transformers import SentenceTransformer, util

class QueryRewriter:
    """Query expander with semantic validation"""

    # Similarity threshold: empirically validated for general use
    SIMILARITY_THRESHOLD = 0.8

    def __init__(self):
        self.embed_model = SentenceTransformer("BAAI/bge-large-zh-v1.5")

    def safe_expand(self, original_query: str) -> list[str]:
        """
        Safe expansion: expand + semantic validation, filtering out rewrites
        that drift from the original meaning.
        """
        # 1. Generate expansions via LLM
        expansions = self._llm_expand(original_query)

        # 2. Compute the original query's embedding
        original_embedding = self.embed_model.encode(
            original_query, convert_to_tensor=True
        )

        # 3. Validate each expansion
        valid_expansions = []
        for exp in expansions:
            exp_embedding = self.embed_model.encode(
                exp, convert_to_tensor=True
            )
            cosine_sim = util.cos_sim(
                original_embedding, exp_embedding
            ).item()

            if cosine_sim >= self.SIMILARITY_THRESHOLD:
                # Passes the threshold, keep it
                valid_expansions.append(exp)
            else:
                # Below threshold, the rewrite drifted from the original, discard
                print(
                    f"[Filtered] '{exp}' similarity to original query: {cosine_sim:.3f}, "
                    f"below threshold {self.SIMILARITY_THRESHOLD}, discarded"
                )

        # 4. Fallback: if all expansions are filtered, use the original query
        if not valid_expansions:
            valid_expansions = [original_query]

        return valid_expansions
```

Where does the 0.8 threshold come from?

It's an empirically validated value for general-purpose scenarios:
- **≥ 0.8**: The rewrite preserves the original meaning, safe to use
- **0.6 ~ 0.8**: Some semantic drift, needs business-specific judgment
- **< 0.6**: The rewrite has essentially drifted from the original meaning

Your mileage will vary depending on the domain. The recommended approach is to take 100 real user queries, manually label expansion quality, plot the similarity distribution, and find the optimal cutoff point.

### Value of This Step

This step's core value isn't about raising the ceiling — it's about holding the floor. It prevents the system from injecting noise through its own expansion module. Without this defense layer, the query expansion module is essentially a random noise injector, and system behavior becomes unpredictable.

## Step 3: Hybrid Retrieval and Reranking

### The Problem: Merging Scores from Two Dimensions

Everyone knows RAG needs hybrid retrieval: vector retrieval (Dense Retrieval) + keyword retrieval (BM25 Sparse Retrieval). Vector retrieval excels at semantic matching, BM25 excels at exact keyword matching — they complement each other.

But here's the problem.

| Retrieval Method | Score Range | Example Score |
|---------|---------|---------|
| Vector retrieval (cosine similarity) | [0, 1] | 0.87 |
| BM25 | [0, +∞) | 15.3 |

Vector retrieval scores are cosine similarity values between 0 and 1. BM25 scores can be tens or even hundreds. The two dimensions have completely different scales, and merging them requires resolving this scale conflict.

The naive approach is normalization followed by weighted sum:

```python
# Naive approach (not recommended)
final_score = 0.7 * normalize(vector_score) + 0.3 * normalize(bm25_score)
```

Both 0.7 and 0.3 are pulled out of thin air.

Different query types have completely different optimal weight distributions:
- For precise keyword queries like "which clause covers breach of contract," BM25 should carry more weight
- For semantically vague queries like "who is this product suitable for," vector retrieval should carry more weight

A fixed weight guessed from intuition means applying one strategy to every scenario — the results speak for themselves.

### Industry Solution: LambdaMART Learning to Rank

The industry standard is to use a Learning to Rank model, and LambdaMART is one of the most mature and widely adopted algorithms in this space.

LambdaMART's core idea: don't rely on humans to guess weights — let the model learn them.

```
                    ┌──────────────┐
  Vector score ────→│              │
                    │  LambdaMART  │──→ Unified score
  BM25 score ──────→│    Model     │
                    │              │
  Other features ──→│              │
  (doc length,     └──────────────┘
   title match,
   position info)
```

What it does: take features from all retrieval channels (vector score, BM25 score, document length, title match score, position info, etc.) and map them to a single scoring dimension, producing a principled composite ranking score.

#### Why LambdaMART

Learning to rank falls into three categories:

| Method | Representative Algorithms | Characteristics |
|---------|---------|------|
| Pointwise | Linear regression, Logistic regression | Score each document independently, ignoring relative ordering |
| Pairwise | RankSVM, RankNet | Optimize relative ordering of document pairs |
| Listwise | LambdaMART, LambdaRank | Directly optimize ranking list metrics (e.g., NDCG) |

LambdaMART is a Listwise method — it directly optimizes ranking quality metrics like NDCG rather than scoring documents one at a time or in pairs. This works best for information retrieval because users care about the quality of the entire result list, not the absolute score of any single document.

#### Implementation

```python
import lightgbm as lgb
import numpy as np

class HybridRetriever:
    """LambdaMART-based hybrid retrieval reranker"""

    def __init__(self):
        self.lambdamart_model = None
        self.vector_retriever = VectorRetriever()
        self.bm25_retriever = BM25Retriever()

    def retrieve(self, query: str, top_k: int = 10) -> list[dict]:
        """Hybrid retrieval + LambdaMART reranking"""

        # 1. Dual-channel recall
        vector_results = self.vector_retriever.search(query, top_k=50)
        bm25_results = self.bm25_retriever.search(query, top_k=50)

        # 2. Merge candidate sets (dedup)
        candidates = self._merge_candidates(vector_results, bm25_results)

        # 3. Build feature matrix
        features = self._build_features(query, candidates)

        # 4. LambdaMART reranking
        reranked_scores = self.lambdamart_model.predict(features)

        # 5. Sort by reranking scores, return Top-K
        sorted_indices = np.argsort(-reranked_scores)
        return [candidates[i] for i in sorted_indices[:top_k]]

    def _build_features(self, query: str, candidates: list) -> np.ndarray:
        """
        Build feature vectors for each candidate document.
        These features are LambdaMART's input.
        """
        features = []
        for doc in candidates:
            feature = [
                doc["vector_score"],           # Vector similarity score
                doc["bm25_score"],             # BM25 score
                doc["title_match_score"],      # Title match score
                doc["doc_length"],             # Document length
                doc["query_doc_overlap"],      # Keyword overlap rate between query and document
                doc["position_in_doc"],        # Position of matching passage within the document
                doc["section_level"],          # Section hierarchy level
            ]
            features.append(feature)
        return np.array(features)

    def train(self, train_data: lgb.Dataset, params: dict):
        """Train the LambdaMART model"""
        params.update({
            "objective": "lambdarank",     # Learning to rank objective
            "metric": "ndcg",              # Optimize NDCG metric
            "ndcg_eval_at": [5, 10],       # Evaluate at Top-5 and Top-10
            "learning_rate": 0.05,
            "num_leaves": 31,
            "max_depth": 6,
            "min_data_in_leaf": 50,
        })
        self.lambdamart_model = lgb.train(params, train_data)
```

Training data labeling isn't complicated either: for a batch of real queries, label each candidate document's relevance grade (0=irrelevant, 1=partially relevant, 2=fully relevant) and format it for learning-to-rank training.

### Impact of This Step

Compared to fixed-weight linear fusion, LambdaMART reranking typically improves Recall@10 by 5–10 percentage points, with even more pronounced gains in NDCG@10. It's also a lightweight model — inference latency is in the millisecond range, so it doesn't affect production performance.

## Step 4: Evaluation Metric Decomposition

### Why "85% Accuracy" Isn't Convincing

Boss: What's the system accuracy? You: 85%.

Boss: What about the other 15%? You: Uh...

Quoting an overall accuracy number is meaningless on its own because you don't know where the failures are: did retrieval miss the right answer? Did retrieval find it but the LLM failed to use it? Did the LLM just make something up?

Problems in different stages require completely different fixes. You need to break the metrics apart.

### Two Core Metrics

For RAG system evaluation, tracking two metrics is sufficient.

#### Metric 1: Context Recall

> **Definition**: Does the correct answer to the user's question appear in the Top-N retrieved chunks?

In other words: did the retrieval stage find the "clues to the right answer"?

- If the correct answer isn't in the Top-N → retrieval has a problem → optimize document chunking, query expansion, retrieval strategy
- If the correct answer is in the Top-N but the final answer is wrong → retrieval is fine, the problem is in the generation stage

```python
def compute_context_recall(
    question: str,
    ground_truth: str,
    retrieved_chunks: list[str],
    evaluator_llm
) -> float:
    """
    Compute Context Recall.
    Core idea: check whether key information from the ground truth
    appears in the retrieved chunks.
    """
    prompt = f"""
    Question: {question}
    Ground truth: {ground_truth}
    Retrieved context:
    {"".join([f"[{i+1}] {chunk}" for i, chunk in enumerate(retrieved_chunks)])}

    Judge: how much of the key information in the ground truth can be found
    in the retrieved context?
    Return a score between 0 and 1.
    Scoring criteria:
    - 1.0: All key information found in context
    - 0.5: Some key information found
    - 0.0: Key information completely absent
    """
    score = evaluator_llm.generate(prompt)
    return float(score)
```

#### Metric 2: Faithfulness

> **Definition**: Is the LLM's generated answer faithful to the retrieved sources? Or did it make things up?

This is what we commonly call the hallucination rate. If the retrieved sources clearly say A, but the LLM says B, that's unfaithful.

```python
def compute_faithfulness(
    answer: str,
    retrieved_chunks: list[str],
    evaluator_llm
) -> float:
    """
    Compute Faithfulness.
    Core idea: check whether every claim in the answer can be
    traced back to the retrieved sources.
    """
    # 1. Decompose the answer into independent claims
    claims_prompt = f"""
    Decompose the following answer into independent factual claims:
    {answer}
    One claim per line.
    """
    claims = evaluator_llm.generate(claims_prompt).strip().split("\n")

    # 2. Check each claim against the retrieved sources
    context = "\n".join(retrieved_chunks)
    supported_count = 0

    for claim in claims:
        check_prompt = f"""
        Claim: {claim}
        Context sources:
        {context}

        Can this claim be supported by the context sources?
        Answer "yes" or "no".
        """
        result = evaluator_llm.generate(check_prompt).strip().lower()
        if result == "yes":
            supported_count += 1

    # 3. Faithfulness = supported claims / total claims
    return supported_count / len(claims) if claims else 0.0
```

### Driving Optimization with Decomposed Metrics

Once you monitor these two metrics, precise problem localization becomes possible:

| Context Recall | Faithfulness | Diagnosis | Optimization Direction |
|:---:|:---:|------|------|
| High | High | ✅ System is healthy | Maintain status quo |
| **Low** | High | Retrieval missed the target, generation is fine | Optimize chunking, query expansion, retrieval strategy |
| High | **Low** | Retrieval found the right stuff, but the LLM hallucinated | Optimize prompt, add citation constraints, try a different model |
| **Low** | **Low** | Problems across the pipeline | End-to-end systematic debugging |

This is how you engineer the system. Not blindly tuning parameters against a single aggregate number, but using decomposed metrics to pinpoint the failing stage and optimize surgically.

## Results: Cumulative Gains from Four Steps

Stringing the four optimization steps together, here's what a typical gain curve looks like:

```
Accuracy
  │
  │                                          ● 85%
  │                                    ●─────┘
  │                              ●─────┘
  │  ● 60%               ●─────┘
  │  │  Baseline    ●─────┘
  │  │              │
  │  │    +15pp     │ +5pp
  │  │  (Chunking)  │(Hybrid rerank)
  │  │              │
  │  ●────────●─────●
  │           │
  │     Hold the floor
  │    (Query validation)
  └────────────────────────────────→
     Baseline  Step 1  Step 2  Step 3  Step 4
                               (Metric decomposition)
```

| Optimization Step | Core Action | Typical Gain |
|---------|---------|---------|
| Step 1: Chunking | Semantic-aware dynamic splitting + overlap windows | **+10–15pp** |
| Step 2: Query validation | Expansion + cosine similarity ≥ 0.8 fallback | Hold the floor, prevent regression |
| Step 3: Hybrid reranking | LambdaMART unified scoring | **+5–10pp** (Recall@10) |
| Step 4: Metric decomposition | Separate monitoring of Context Recall + Faithfulness | Precise localization, continuous iteration |

## Closing Thoughts

The four optimization steps share a common trait: none of them require a bigger model or more expensive GPUs. They're pure engineering improvements extracted from the existing pipeline. Document chunking solves the information fragmentation problem. Query validation holds the floor on input quality. LambdaMART reranking gives multi-channel retrieval scores a principled way to merge. Metric decomposition turns problem localization from guesswork into precise diagnosis.

Going from 60% to 85% after these four steps isn't surprising. What I find more valuable is the methodology this process established: lay out the full pipeline, decompose it by priority, and quantify the gain at each step. Getting a RAG system from demo to production doesn't come from a single breakthrough — it comes from engineering discipline applied across the entire pipeline.

---

**References**:

- [Anthropic Contextual Retrieval](https://www.anthropic.com/news/contextual-retrieval)
- [RAGAS — RAG Evaluation Framework](https://github.com/explodinggradients/ragas)
- [LightGBM LambdaRank Documentation](https://lightgbm.readthedocs.io/en/latest/parameters.html#learning-rate-parameters)
- [Sentence Transformers](https://www.sbert.net/)
