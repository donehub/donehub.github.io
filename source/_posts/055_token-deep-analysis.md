---
title: Token 深度解析
date: 2025-10-08
categories: Token
tags: [AI]
---

很多刚开始接触大模型的朋友，经常会看到"消耗了 XXX tokens"、"超出 token 限制"这样的提示。Token 是大模型处理文本的最小单位，模型不是逐字逐句读取，而是先把文本拆成一块块 Token，再逐块处理。这个设计背后有明确的技术原因。

<!-- more -->

## Token 是什么

可以把它理解为文本世界的乐高积木块。模型不是直接理解整段话，而是先把文本拆解成 Token 序列，再对每个 Token 做数学运算。Token 级别的处理方式介于字符级别和单词级别之间，是效率与能力的平衡点。

字符级别（一个字母一个字母读）太慢，无法高效理解语义；单词级别（一个单词一个单词读）看似合理，但英语有超过 100 万个单词，词汇量太大且不断增长。Token 级别的切分恰好处于中间地带：常见词整体保留，罕见词拆成子词，既保证了效率，又能处理未知词汇。

以英文句子 `I love artificial intelligence` 为例，按字符算有 20 个字符，按单词算是 4 个词，按 Token 算约 5-6 个（取决于分词器）。中文句子 `我爱人工智能` 按字符算是 6 个汉字，按 Token 算约 6-10 个，因为每个汉字可能单独成一个 Token。

## 为什么不用整段话处理

计算机只能处理数字，不能直接理解文字。大模型的完整工作流程是：文字 → Token → 数字（向量）→ 计算 → 预测 → Token → 文字。每一步都必须是有限、可枚举的，整段话处理在技术上不可行。

如果模型要直接处理整段话，会面临四个核心问题：一段话可能有任意长度和任意组合，无法穷举；同一段话的空格处理不一致（"我爱AI"和"我 爱 AI"），无法对齐；神经网络本质是矩阵乘法，需要固定维度的输入；要存储所有可能的句子组合，内存直接不够。

Token 方案的优势在于：常用 Token 约 5-10 万个，可以穷举并编号；每个 Token 对应一个向量（如 4096 维），可以做数学计算；像乐高一样，有限积木块能拼出无限造型；Token 序列可以处理任意长度的文本。

语言有一个核心特点：有限符号，无限组合。英语 26 个字母能组成无数句子，中文几千常用字能组成无数句子，几万个 Token 同样能组合出无数句子。大模型只需要学会这 5 万个 Token 的表示和关系，就能理解所有可能的句子。这比试图记忆所有句子要高效得多。

## 子词分词的历史

早期自然语言处理确实尝试过按单词处理，但遇到两个问题。一是词汇量爆炸，英语有超过 100 万个单词且每天增加新词，词汇表会无限膨胀。二是罕见词无法处理，遇到没见过的单词（如 `unprecedented`），模型直接不认识。

研究者提出子词分词的概念：常见词整体作为一个 Token，罕见词拆成多个子词 Token，新词用已知 Token 组合表示。比如 `unprecedented` 拆成 `un` + `pre` + `ced` + `ented`，`chatgpt` 拆成 `chat` + `g` + `pt`。

| 单词类型 | 处理方式 | 例子 |
|---------|---------|------|
| 常见词 | 整体作为一个 Token | `the`, `is`, `hello`, `love` |
| 罕见词 | 拆成多个 Token | `unprecedented` → `un` + `pre` + `ced` + `ented` |
| 新词 | 用已知 Token 组合表示 | `chatgpt` → `chat` + `g` + `pt` |

目前主流的分词算法有三类：BPE（Byte Pair Encoding）通过合并频率最高的相邻符号来构建词汇表，GPT 系列使用；WordPiece 基于概率的分词，用 `##` 标记子词，BERT 系列使用；Unigram 基于统计概率选择最优分词，T5 和 XLNet 使用。

BPE 的核心思路是迭代合并。初始状态每个字符都是一个 Token，然后反复合并频率最高的相邻符号对。以 `unprecedented` 为例，初始 13 个字符 Token，第一步合并 "e" + "d" 为 "ed"，第二步合并 "un"，经过 N 次迭代最终得到 `["un", "pre", "ced", "ented"]`。通过这种方式，模型既能高效处理常见词，又能认识从未见过的罕见词。

## Token 计量规则

不同语言的 Token 效率差异很大，这是很多中文用户最容易困惑的地方。

| 语言 | Token 效率 | 估算公式 |
|-----|-----------|---------|
| 英文 | 1 Token ≈ 0.75 个单词 ≈ 4 个字符 | Token 数 ≈ 单词数 × 1.3 |
| 中文 | 1 Token ≈ 0.6-0.8 个汉字 | Token 数 ≈ 字数 × 1.5-2 |
| 代码 | 1 Token ≈ 4 个字符 | Token 数 ≈ 字符数 ÷ 4 |

中文 Token 数更多的原因在于分词器的训练数据。主流分词器（如 GPT 系列）主要基于英文语料训练，英文常见词如 `artificial` 可能是 1 个 Token，而中文每个汉字可能各自成为 1 个 Token。同样内容，中文 Token 数通常是英文的 1.5-2 倍。

以同样内容为例，`The future of artificial intelligence is bright` 英文约 7-8 个 Token，`人工智能的未来很光明` 中文约 10-12 个 Token。这就是为什么用中文对话可能更快消耗 Token 配额。

不同模型对中文的 Token 效率也有差异。GPT-4 英文优化较深，中文约 2 字/Token；Claude 多语言平衡，约 1.5 字/Token；DeepSeek 和 Qwen 做了中文专项优化，约 1 字/Token。

## Token 在大模型中的作用方式

以句子 `人工智能很强大` 为例，完整的处理流程分为六步。第一步分词，将文本拆成 `["人工", "智能", "很", "强大"]`。第二步编号，在词汇表中查找每个 Token 对应的整数 ID。第三步向量化，每个 ID 对应一个高维向量（如 4096 维）。第四步神经网络计算，向量输入 Transformer 模型，通过注意力机制计算 Token 之间的关联关系，通过前馈网络提取和变换语义信息。第五步预测输出，模型输出概率分布，选择概率最高的下一个 Token。第六步 Token 转文字，输出最终结果。

向量化是理解 Token 的关键。每个 Token 都有一个向量表示，可以理解为这个 Token 的数学身份证，由数千个数值组成，每个数值代表 Token 在某个语义维度上的坐标。语义相似的 Token，向量也相似。比如"狗"和"猫"的向量高相似度（都是动物），而"狗"和"汽车"的向量低相似度（语义差异大）。

Token 方案相比单词方案的核心优势在于覆盖能力。单词方案词汇表 5 万个，遇到新词直接不认识；Token 方案词汇表 5 万个子词，遇到新词可以用已知 Token 组合表示。比如新词 `deepseek` 可以拆成已知的 `deep` 和 `seek`。有限词汇表加上无限组合能力，这就是 Token 设计的精髓。

## Token 量化方法

最直观的方式是使用官方提供的 Tokenizer 工具。OpenAI Tokenizer（https://platform.openai.com/tokenizer）可以做 GPT 模型的分词可视化，Anthropic Console（https://console.anthropic.com）可以查看 Claude 模型的分词情况。

使用 Python 代码可以做精确计算。OpenAI 官方库 tiktoken 支持按模型查询分词：

```python
import tiktoken

enc = tiktoken.encoding_for_model("gpt-4")
text = "我爱人工智能"
tokens = enc.encode(text)
print(f"Token 数量: {len(tokens)}")
print(f"Token 列表: {tokens}")
print(f"Token 文本: {[enc.decode([t]) for t in tokens]}")
```

通用方案可以使用 transformers 库的 AutoTokenizer，支持所有 HuggingFace 模型。

调用大模型 API 时，返回结果通常包含 Token 使用量，通过 `response.usage` 可以获取输入 Token、输出 Token 和总 Token 数。

没有工具时可以用经验公式快速估算：英文 Token ≈ 单词数 × 1.3，中文 Token ≈ 字数 × 1.5-2，代码 Token ≈ 字符数 ÷ 4，混合内容各部分分别估算再相加。

## Token 限制与成本

各模型的上下文窗口和最大输出限制不同。GPT-4o 和 GPT-4 Turbo 都是 128K 上下文窗口，最大输出分别为 16K 和 4K Token。Claude 3.5 Sonnet 和 Claude Opus 4.6 都是 200K 上下文窗口，最大输出分别为 8K 和 32K Token。DeepSeek V3 是 200K 上下文窗口，最大输出 8K Token。

API 费用按 Token 计算，公式为：成本 = 输入 Token × 输入单价 + 输出 Token × 输出单价。以 GPT-4o 为例，输入 $2.5/1M Token，输出 $10/1M Token，一次对话消耗 1000 输入 Token + 500 输出 Token，成本约 $0.0075。

超出 Token 限制有两种情况。输入超出上下文窗口时，API 报错 `context_length_exceeded`，需要截断历史消息或分段处理。输出超出最大输出限制时，输出被截断不完整，需要设置合理的 `max_tokens` 或分段生成。

## 节省 Token 的实用技巧

同样的内容，用英文表达 Token 数更少。`请帮我写一篇关于人工智能的文章` 中文约 15-20 Token，对应的英文表达约 8-10 Token。如果不需要输出中文，可以用英文提问和回答。

Prompt 精简也很关键。冗长版本"请帮我写一篇非常详细的、包含多个方面的、内容丰富的关于人工智能发展历史的文章，要涵盖从早期研究到现在的发展历程"约 50 Token，精简版本"写一篇 AI 发展史，涵盖早期到现在的关键节点"约 15 Token，效果几乎相同。

每次对话都会带上历史消息，Token 消耗会累积。第 1 轮 100 Token 输入，第 2 轮 150 Token（加了 50 Token 历史），第 3 轮 200 Token，线性增长。应对方法是定期开启新对话清除历史、只保留必要的历史消息、使用 System Prompt 存储固定指令。

System Prompt 只计算一次，不会像用户消息那样每轮重复。把所有固定指令放在 System Prompt 里，比在每条用户消息中重复指令要高效得多。

图片也会消耗 Token。1024×1024 图片约 340 Token（大致估算），压缩图片尺寸、只传必要的图片、使用低分辨率版本都可以减少消耗。

## Token 与上下文窗口

上下文窗口是模型能记住的最大 Token 数。128K Token 的上下文窗口意味着输入、历史对话和输出的总 Token 数不能超过 128K，超过部分会被截断或报错。

不同场景对上下文的需求差异很大。简单问答需要 100-500 Token，代码分析需要 5K-20K Token，长文档总结需要 50K-100K Token，复杂 Agent 任务可能需要 100K-1M Token。

上下文越长，代价也越高。Transformer 的注意力机制是 O(n²) 复杂度，上下文翻倍计算成本可能翻四倍。同时响应速度变慢，API 费用也更高。

## 附录：Token 可视化体验

想直观感受 Token 是怎么切文本的，可以试试这些工具。OpenAI Tokenizer（https://platform.openai.com/tokenizer）输入中英文混排内容，每个 Token 用不同颜色高亮显示。Anthropic Console（https://console.anthropic.com）支持 Claude 模型的 Token 计数和实时估算。也可以在本地用 Python 快速体验：

```python
import tiktoken
enc = tiktoken.encoding_for_model("gpt-4")
text = "你的测试文本"
print(enc.encode(text))
print([enc.decode([t]) for t in enc.encode(text)])
```

---

**参考资源**：
- [OpenAI Tokenizer 文档](https://platform.openai.com/docs/concepts/tokens)
- [tiktoken GitHub](https://github.com/openai/tiktoken)
- [BPE 算法原论文](https://arxiv.org/abs/1508.07909)
