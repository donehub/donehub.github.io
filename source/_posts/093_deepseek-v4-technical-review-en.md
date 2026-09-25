---
title: "DeepSeek V4: A Technical Deep Dive"
date: 2026-04-24 16:30:00
updated: 2026-04-24 16:30:00
categories: DeepSeek
tags: [AI]
lang: en
label: 093_deepseek-v4-technical-review
---

## Background

On April 24, 2026, DeepSeek officially released the V4 model series. This isn't a routine version bump — it tackles a fundamental problem that's plagued the AI industry for years: **the long-context efficiency bottleneck**.

This post breaks down the core technical innovations in DeepSeek V4 and explains why this release deserves attention.

---

<!-- more -->
## 1. Model Specs: Bigger Without Being Pricier

DeepSeek V4 ships in two variants:

| Model | Total Params | Active Params | Context Length |
|-------|-------------|---------------|----------------|
| **DeepSeek-V4-Pro** | 1.6T | 49B | 1M tokens |
| **DeepSeek-V4-Flash** | 284B | 13B | 1M tokens |

Compared to the previous V3.2 (671B total, 37B active), V4-Pro has 2.4x the total parameters but only 32% more active parameters. More importantly, **both natively support 1M token context** — something no open-source model had achieved before.

### The "Bigger but Not Pricier" Principle

Thanks to the MoE (Mixture-of-Experts) architecture, each inference step activates only a fraction of the parameters. V4-Pro's activation rate is just **3%** (49B/1.6T), which means:

- Inference cost is close to a 50B-parameter dense model
- But it has the knowledge capacity and expressive power of 1.6T parameters

This is the technical direction DeepSeek has pursued since V2. V4 takes that strategy to a new level.

---

## 2. Core Architecture Innovation: Breaking the O(n²) Curse

Standard Transformer attention has O(n²) complexity — double the sequence length, quadruple the compute. At million-token scale, this becomes prohibitive.

DeepSeek V4 solves this completely with a **hybrid attention architecture**.

### 2.1 CSA (Compressed Sparse Attention)

CSA's core idea: **compress + sparse selection**.

```
Original sequence: n tokens
     ↓ Compress (every m tokens merged into one KV entry)
Compressed sequence: n/m compressed KV entries
     ↓ Sparse selection (Lightning Indexer picks top-k)
Computed: k compressed KV entries
```

The specific flow:

1. **KV Cache compression**: Every m tokens' KV entries are compressed into one entry via weighted aggregation, reducing sequence length to 1/m
2. **Lightning Indexer**: Generates indexer queries for each query token, computes similarity against compressed KV entries, selects the top-k most relevant compressed blocks
3. **Core Attention**: Full attention computation runs only on the selected k compressed blocks

Key parameters (V4-Pro):
- Compression ratio m = 4 (every 4 tokens compressed to 1)
- Indexer heads = 64, head dimension = 128
- Top-k = 1024 (each query attends to only 1024 compressed blocks)

### 2.2 HCA (Heavily Compressed Attention)

HCA is a more aggressive compression strategy for handling "historical information that doesn't need fine-grained attention":

```
Compression ratio m' = 128 (every 128 tokens merged into one KV entry)
     ↓
Full attention directly on compressed KV (no sparse selection)
```

HCA's philosophy: **distant information can be handled roughly; nearby information needs fine-grained attention**.

### 2.3 Hybrid Architecture Design

V4 doesn't use all CSA or all HCA — it **alternates** between them:

- **First 2 layers**: Pure sliding window attention (preserving fine-grained detail for recent information)
- **Subsequent layers**: CSA and HCA alternate, forming a "coarse-and-fine" information processing pipeline

This design lets the model handle long contexts efficiently while maintaining precise retrieval of critical information.

### 2.4 Efficiency Gains

The official data for 1M token context scenarios is compelling:

| Metric | V4-Pro vs V3.2 | V4-Flash vs V3.2 |
|--------|----------------|------------------|
| Per-token FLOPs | **27%** (3.7x savings) | **10%** (10x savings) |
| KV Cache size | **10%** (9.5x savings) | **7%** (13.7x savings) |

Translation: million-token context tasks that were previously too expensive to run can now **run on a single GPU**.

---

## 3. mHC: A Mathematical Upgrade to Residual Connections

Residual connections `x + F(x)` are foundational to Transformers, but they cause problems when stacked deep:

- Signals can amplify layer by layer → numerical explosion
- Signals can attenuate layer by layer → vanishing gradients

DeepSeek V4 introduces **Manifold-Constrained Hyper-Connections (mHC)** to solve this with mathematical constraints.

### Core Idea

Traditional residual connection:
```
X_next = X + F(X)  // Simple addition
```

mHC:
```
X_next = B·X + C·F(A·X)  // A, B, C are linear mapping matrices
         ↑
      B is constrained to the doubly stochastic matrix manifold
      (row sums=1, column sums=1, elements≥0)
```

Key constraint: **B's spectral norm ≤ 1**, meaning signal propagation is "non-expansive" — it can't explode.

### What "Manifold Constraint" Means

The space of doubly stochastic matrices forms a **manifold** — specifically, the Birkhoff Polytope. mHC projects matrix B onto this manifold using the Sinkhorn-Knopp algorithm:

```
1. Take exponential of B (guarantees positive elements)
2. Iteratively normalize rows, then columns
3. Converges to a doubly stochastic matrix
```

This math ensures stability during deep stacking while preserving the model's expressive power.

---

## 4. Muon Optimizer: A New Recipe for Trillion-Parameter Training

Training trillion-parameter models pushes AdamW past its limits. V4 introduces the **Muon** optimizer.

### Core Algorithm

```
G = gradient
M = momentum_buffer
M = μ·M + G  // Momentum accumulation
O = HybridNewtonSchulz(μ·M + G)  // Nesterov trick + orthogonalization
W = W·(1 - ηλ) - η·O  // Weight decay + update
```

The key step is the **Hybrid Newton-Schulz iteration**, which orthogonalizes the gradient matrix:

```python
# 10 iterations in two stages
# Stage 1 (first 8 steps): Fast convergence
M_k = 3.4445·M_{k-1} - 4.7750·(M·M^T)·M + 2.0315·(M·M^T)^2·M

# Stage 2 (last 2 steps): Precise projection onto orthogonal matrix
M_k = 2·M_{k-1} - 1.5·(M·M^T)·M + 0.5·(M·M^T)^2·M
```

Benefits of orthogonalization:
- Prevents "drift" — gradient directions become more definite
- Prevents "numerical explosion" — matrix spectral norm is bounded
- Faster convergence — no need for Adam's second-moment estimation

### Stability Techniques

V4 also uses two techniques to prevent loss spikes:

1. **Anticipatory Routing**: Routing decisions use "historical parameters" instead of "current parameters," breaking vicious cycles in MoE routing
2. **SwiGLU Clamping**: The linear component of SwiGLU is clamped to [-10, 10], directly suppressing outliers

---

## 5. FP4 Quantization-Aware Training: Built for Low Precision

Previous quantization was "post-training remediation" — train the model in high precision, then forcibly reduce precision at inference, with inevitable performance loss.

V4's innovation: **make the model adapt to FP4 during training**.

### Application Scope

- **MoE expert weights**: Most of the model's parameters — FP4 compression saves significant VRAM
- **QK path** (Lightning Indexer's indexer component): Core computation for long-context retrieval — FP4 accelerates this

### Key Technical Detail

**Lossless FP4 → FP8 dequantization**:

```
FP4 (E2M1) → FP8 (E4M3)
          ↑
FP8 has 2 more exponent bits, larger dynamic range
As long as scale factor differences within a block don't exceed threshold,
information is fully preserved
```

This means:
- Training uses FP8 for computation (simulating FP4)
- Inference uses FP4 weights directly, zero performance loss
- The entire pipeline can reuse existing FP8 training frameworks

---

## 6. Training Infrastructure: Engineering at Scale

V4's infrastructure investment reflects long-term engineering thinking.

### 6.1 TileLang: A DSL for Kernel Development

Traditional CUDA kernel development is slow and hard to iterate on. V4 uses **TileLang**, a domain-specific language:

- Declarative syntax describes kernel logic, Z3 SMT Solver performs formal analysis (proving correctness), and high-performance CUDA code is generated automatically. Development speed and runtime performance, both achieved.

### 6.2 Deterministic Training

The same token produces bitwise-identical output regardless of its position in the batch. Special design avoids atomic addition nondeterminism, making training reproducible and debugging evidence-based. This is critical for debugging and problem diagnosis at large-scale training.

### 6.3 Fine-Grained Overlap for MoE Expert Parallelism

Expert Parallelism carries heavy communication overhead. V4 splits MoE layers into **4 stages**:

```
Dispatch (comm) → Linear-1 (compute) → Activation → Linear-2 (compute) → Combine (comm)
```

Key insight: **compute time > communication time**, so communication can be hidden behind computation.

V4 groups experts into "waves," pipelining communication and compute within each wave, achieving **1.5-1.96x speedup**.

---

## 7. Benchmarks: A New Standard for Open-Source Models

### Knowledge Tasks

| Benchmark | V4-Pro-Max | K2.6 | GLM-5.1 | Gemini 3.1 Pro |
|-----------|------------|------|---------|----------------|
| SimpleQA Verified | **57.9** | 36.9 | 38.1 | 75.6 |
| Chinese-SimpleQA | **84.4** | 75.9 | 75.0 | 85.9 |

V4-Pro-Max **leads open-source competitors by 20+ points** on knowledge tasks, though there's still a gap to Gemini 3.1 Pro.

### Agent Capabilities: Best in Open-Source

This is one of V4's most significant capability jumps. Official disclosures:

- **Agentic Coding**: V4-Pro reaches the best level among current open-source models
- **Internal testing**: Has become the go-to Agentic Coding model for DeepSeek employees
- **Comparison**: Outperforms Claude Sonnet 4.5, with delivery quality approaching Claude Opus 4.6 non-thinking mode

V4 has been specifically optimized for mainstream Agent products like **Claude Code, OpenClaw, OpenCode, and CodeBuddy**, with notable improvements in code tasks and document generation.

### Reasoning and Code

| Benchmark | V4-Pro-Max | GPT-5.4 | Gemini 3.1 Pro |
|-----------|------------|---------|----------------|
| Codeforces Rating | **3206** | 3168 | 3052 |
| Apex Shortlist | **90.2** | 78.1 | 89.1 |

**This is the first time an open-source model has caught up to closed-source models in code competitions**. V4-Pro-Max ranks 23rd among human competitors on Codeforces.

### Long Context

| Benchmark | V4-Pro-Max | Claude Opus 4.6 | Gemini 3.1 Pro |
|-----------|------------|-----------------|----------------|
| MRCR 1M (MMR) | 83.5 | **92.9** | 76.3 |
| CorpusQA 1M | **62.0** | 71.7 | 53.8 |

V4-Pro surpasses Gemini 3.1 Pro on the real-world CorpusQA benchmark and approaches Claude Opus 4.6 on MRCR.

---

## 8. V4-Flash: The Cost-Effective Option

V4-Flash is an important complement, ensuring users with different needs find a suitable option.

### Comparison with V4-Pro

| Dimension | V4-Flash | V4-Pro |
|-----------|----------|--------|
| Active params | 13B | 49B |
| Inference speed | Faster | Slower |
| API cost | Lower | Higher |
| World knowledge | Slightly behind | Far ahead of open-source |
| Reasoning ability | Close to Pro | Best in open-source |
| Agent simple tasks | Comparable | Better |
| Agent hard tasks | Noticeable gap | Best |

**Use cases**:

- **V4-Flash**: Daily conversation, simple code tasks, cost-sensitive scenarios
- **V4-Pro**: Complex Agent tasks, deep reasoning, high-quality output requirements

---

## 9. Three Inference Modes: Flexible Cost-Quality Tradeoff

V4 supports three inference modes, letting users choose based on their cost tolerance:

| Mode | Characteristics | Use Case |
|------|----------------|----------|
| **Non-Think** | Fast intuitive response, no thinking tokens | Daily chat, low-stakes decisions |
| **Think** | Logical analysis, moderate thinking budget | Complex problems, planning tasks |
| **Think Max** | Maximum reasoning, long thinking budget | Math proofs, high-difficulty tasks |

Think Max mode injects a special instruction into the system prompt:

```
Reasoning Effort: Absolute maximum with no shortcuts permitted.
You MUST be very thorough in your thinking...
```

This pushes the model to "take reasoning to the limit," performing best on hard benchmarks like HLE and IMO.

---

## 10. API Usage Guide

### Model Invocation

The DeepSeek API now offers both V4-Pro and V4-Flash, supporting the OpenAI ChatCompletions interface and Anthropic interface:

```python
# OpenAI format
from openai import OpenAI

client = OpenAI(
    api_key="your-api-key",
    base_url="https://api.deepseek.com"
)

response = client.chat.completions.create(
    model="deepseek-v4-pro",  # or deepseek-v4-flash
    messages=[{"role": "user", "content": "Hello"}]
)
```

### Key Parameters

| Parameter | Description |
|-----------|-------------|
| `model` | `deepseek-v4-pro` or `deepseek-v4-flash` |
| `max_tokens` | Maximum output length, default 8K |
| `reasoning_effort` | Thinking intensity: `high` or `max` (thinking mode only) |

### Thinking Mode

For complex Agent scenarios, use thinking mode with intensity set to `max`:

```python
response = client.chat.completions.create(
    model="deepseek-v4-pro",
    messages=[{"role": "user", "content": "Complex task..."}],
    reasoning_effort="max"  # Maximum reasoning
)
```

### ⚠️ Important Notice

Legacy API model names `deepseek-chat` and `deepseek-reasoner` will be **discontinued on July 24, 2026**:

- Currently `deepseek-chat` → points to V4-Flash non-thinking mode
- Currently `deepseek-reasoner` → points to V4-Flash thinking mode

Migrate to the new model names as soon as possible.

---

## 11. Open Source and Local Deployment

### Weight Downloads

| Platform | Link |
|----------|------|
| HuggingFace | https://huggingface.co/collections/deepseek-ai/deepseek-v4 |
| ModelScope | https://modelscope.cn/collections/deepseek-ai/DeepSeek-V4 |

### Local Deployment Recommendations

Given V4-Pro's 1.6T parameters, local deployment requires:

- **Multi-GPU inference**: At least 8× A100 80GB or equivalent VRAM
- **Quantized inference**: FP4 quantization significantly reduces VRAM requirements
- **V4-Flash**: Can run on a single A100 80GB

### Technical Report

For complete technical details, see the official technical report:
- [DeepSeek V4 Technical Report (PDF)](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro/blob/main/DeepSeek_V4.pdf)

---

## 12. Industry Implications: The New Paradigm V4 Brings

### 12.1 Long Context Is No Longer a Luxury

Previously, million-token context was "theoretically possible but economically unfeasible." V4 brings costs down to **10-30% of previous levels**, making these scenarios viable:

- **Test-time Scaling**: Inference can think for extended periods without context constraints
- **Long-horizon Agents**: Complex multi-turn tasks (like software engineering pipelines) have enough "memory space"
- **Online learning**: Continuously absorb new information without full retraining

### 12.2 Shifting Open-Source vs. Closed-Source Dynamics

V4 sends a signal: **open-source models have caught up not just in capability, but in efficiency-per-dollar**.

V4-Flash with 13B active parameters reaches reasoning levels close to GPT-5.2. On code tasks, open-source has caught up to closed-source for the first time. The moat around closed-source models is shrinking.

### 12.3 Long-Term Value of Architecture Innovation

V4's innovations aren't "benchmark tricks" — they're **fundamental architectural improvements**:

- CSA/HCA solve Transformer's O(n²) bottleneck
- mHC makes residual connections more stable and stackable deeper
- Muon optimizer could become the new standard for trillion-parameter training

These innovations will inspire further research and push the entire industry forward.

---

## 13. Limitations and Outlook

The team openly acknowledges several limitations:

1. **Relatively complex architecture**: To reduce risk, many proven V3 components were retained; future versions will streamline
2. **Training stability principles not fully understood**: Anticipatory Routing and SwiGLU Clamping work, but the mathematical foundations are still being explored
3. **Multimodal not yet integrated**: Future versions will add vision capabilities

Future directions:
- Further sparsity exploration (e.g., sparse embeddings)
- Low-latency architecture optimization (making long-context interactions smoother)
- Deep optimization for long-horizon Agents

---

## Final Thoughts

The most striking aspect of DeepSeek V4 isn't a couple benchmark-topping numbers — it's the systematic resolution of the long-context efficiency problem. The CSA/HCA hybrid attention brings down O(n²) complexity, mHC makes deep stacking more stable, the Muon optimizer provides a new approach for trillion-parameter training, and FP4 quantization-aware training builds low-precision inference in from the start. Combined, these innovations turn million-token context from "theoretically possible" into "economically viable."

From an industry perspective, V4-Flash with 13B active parameters achieves reasoning levels close to GPT-5.2, and its Codeforces ranking catches up to closed-source models. For the first time, open-source models have genuine competitive ability on the efficiency dimension.

V4 does have clear limitations: high architectural complexity, incomplete mathematical understanding of some stability techniques, and no multimodal integration yet. These are problems future versions need to solve. But in terms of this release, the density of architectural innovation DeepSeek has invested is the highest among domestic large model providers.

---

**Resources**:
- [DeepSeek V4 Technical Report (PDF)](https://huggingface.co/deepseek-ai/DeepSeek-V4-Pro/blob/main/DeepSeek_V4.pdf)
- [Model Weights (HuggingFace)](https://huggingface.co/collections/deepseek-ai/deepseek-v4)
