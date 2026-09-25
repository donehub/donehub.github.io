---
title: "Tokens Demystified: How LLMs Read Text"
date: 2025-10-08
categories: Token
tags: [AI]
lang: en
label: 055_token-deep-analysis
---

If you're new to large language models, you've probably seen messages like "consumed XXX tokens" or "exceeded token limit." A token is the smallest unit an LLM uses to process text. The model doesn't read text character by character or sentence by sentence. Instead, it first splits text into chunks of tokens, then processes them chunk by chunk. There are solid technical reasons behind this design.

<!-- more -->

## What Is a Token

Think of tokens as LEGO bricks for text. The model doesn't comprehend a paragraph as a whole. It first breaks text into a sequence of tokens, then runs math on each one. Token-level processing sits between character-level and word-level — a sweet spot balancing efficiency and capability.

Character-level processing (reading one letter at a time) is too slow and can't capture semantics efficiently. Word-level processing (reading one word at a time) seems reasonable on the surface, but English has over a million words, and the vocabulary keeps growing. Token-level splitting lands in the middle: common words stay intact as single tokens, rare words get split into sub-word pieces. This gives you both efficiency and the ability to handle unknown vocabulary.

Take the English sentence `I love artificial intelligence`. It's 20 characters, 4 words, and roughly 5-6 tokens (depending on the tokenizer). The Chinese sentence `我爱人工智能` is 6 characters and roughly 6-10 tokens, because each Chinese character may become its own token.

## Why Not Process Whole Sentences

Computers can only handle numbers, not raw text. The full LLM workflow is: text → tokens → numbers (vectors) → computation → prediction → tokens → text. Every step must be finite and enumerable. Processing whole sentences is technically infeasible.

If a model tried to process raw sentences directly, it would hit four fundamental problems. A sentence can have arbitrary length and arbitrary combinations, making exhaustive enumeration impossible. The same sentence with inconsistent spacing ("我爱AI" vs "我 爱 AI") can't be aligned. Neural networks are fundamentally matrix multiplication, requiring fixed-dimension inputs. Storing all possible sentence combinations would require more memory than exists.

The token approach solves these neatly: there are roughly 50,000-100,000 common tokens, which can be enumerated and indexed. Each token maps to a vector (e.g., 4096 dimensions) that supports mathematical operations. Like LEGO, a finite set of bricks can build infinite structures. Token sequences can handle text of any length.

Language has a core property: finite symbols, infinite combinations. English's 26 letters can form countless sentences. Chinese's few thousand common characters can form countless sentences. Tens of thousands of tokens can similarly combine into unlimited sentences. The model only needs to learn the representations and relationships of those 50,000 tokens to understand every possible sentence. That's far more efficient than trying to memorize every sentence.

## A Brief History of Subword Tokenization

Early NLP did try word-level processing, but ran into two problems. Vocabulary explosion: English has over a million words with new ones appearing daily, so the vocabulary table would grow without bound. Unseen words: encountering an unfamiliar word (like `unprecedented`) meant the model simply couldn't handle it.

Researchers proposed subword tokenization: common words stay as single tokens, rare words get split into multiple sub-word tokens, and new words are represented as combinations of known tokens. For example, `unprecedented` splits into `un` + `pre` + `ced` + `ented`, and `chatgpt` splits into `chat` + `g` + `pt`.

| Word Type | Treatment | Example |
|-----------|----------|---------|
| Common words | Kept as a single token | `the`, `is`, `hello`, `love` |
| Rare words | Split into multiple tokens | `unprecedented` → `un` + `pre` + `ced` + `ented` |
| New words | Represented as known token combinations | `chatgpt` → `chat` + `g` + `pt` |

Three mainstream tokenization algorithms exist today. BPE (Byte Pair Encoding) builds the vocabulary by iteratively merging the most frequent adjacent symbol pairs — used by the GPT family. WordPiece uses probability-based tokenization with `##` marking subwords — used by BERT variants. Unigram selects optimal tokenization based on statistical probabilities — used by T5 and XLNet.

BPE's core idea is iterative merging. Start with each character as its own token, then repeatedly merge the most frequent adjacent symbol pair. Take `unprecedented`: it starts as 13 character tokens. The first merge combines "e" + "d" into "ed". The next merge combines "un". After N iterations, you end up with `["un", "pre", "ced", "ented"]`. This way, the model handles common words efficiently while still recognizing rare words it has never seen before.

## Token Counting Rules

Token efficiency varies significantly across languages, which trips up many Chinese-speaking users.

| Language | Token Efficiency | Estimation Formula |
|----------|-----------------|-------------------|
| English | 1 token ≈ 0.75 words ≈ 4 characters | Tokens ≈ word count × 1.3 |
| Chinese | 1 token ≈ 0.6-0.8 characters | Tokens ≈ character count × 1.5-2 |
| Code | 1 token ≈ 4 characters | Tokens ≈ character count ÷ 4 |

The reason Chinese tokens run higher comes down to tokenizer training data. Mainstream tokenizers (like those in the GPT family) are trained primarily on English corpora. A common English word like `artificial` might be a single token, while in Chinese each character may become its own token. For equivalent content, Chinese token counts are typically 1.5-2x those of English.

Take the same content in both languages: `The future of artificial intelligence is bright` is roughly 7-8 tokens in English. `人工智能的未来很光明` is roughly 10-12 tokens in Chinese. This is why conversing in Chinese burns through your token quota faster.

Different models also handle Chinese token efficiency differently. GPT-4 is optimized more heavily for English, at roughly 2 characters per token for Chinese. Claude balances multilingual performance at about 1.5 characters per token. DeepSeek and Qwen have Chinese-specific optimizations, achieving about 1 character per token.

## How Tokens Flow Through an LLM

Take the sentence `人工智能很强大` (AI is very powerful). The complete processing pipeline has six steps. Step 1: tokenization — split the text into `["人工", "智能", "很", "强大"]`. Step 2: indexing — look up each token's integer ID in the vocabulary. Step 3: vectorization — each ID maps to a high-dimensional vector (e.g., 4096 dimensions). Step 4: neural network computation — vectors enter the Transformer model, where the attention mechanism computes relationships between tokens, and the feed-forward network extracts and transforms semantic information. Step 5: prediction — the model outputs a probability distribution and selects the highest-probability next token. Step 6: detokenization — convert the output token back to text.

Vectorization is the key to understanding tokens. Each token has a vector representation — think of it as the token's mathematical ID card, composed of thousands of numbers, each representing the token's coordinate on some semantic dimension. Semantically similar tokens have similar vectors. "Dog" and "cat" have high vector similarity (both are animals), while "dog" and "car" have low similarity (large semantic gap).

The core advantage of the token approach over the word approach is coverage. A word-level vocabulary of 50,000 entries fails completely on new words. A token-level vocabulary of 50,000 subwords can represent new words as combinations of known tokens. A new word like `deepseek` can be split into known tokens `deep` and `seek`. A finite vocabulary with infinite combinatorial power — that's the essence of token design.

## How to Count Tokens

The most intuitive approach is using official tokenizer tools. The OpenAI Tokenizer (https://platform.openai.com/tokenizer) provides visual tokenization for GPT models. The Anthropic Console (https://console.anthropic.com) shows tokenization for Claude models.

For precise calculation, use Python code. OpenAI's official tiktoken library supports per-model tokenization:

```python
import tiktoken

enc = tiktoken.encoding_for_model("gpt-4")
text = "我爱人工智能"
tokens = enc.encode(text)
print(f"Token count: {len(tokens)}")
print(f"Token list: {tokens}")
print(f"Token text: {[enc.decode([t]) for t in tokens]}")
```

For a general solution, the transformers library's AutoTokenizer supports all HuggingFace models.

When calling LLM APIs, the response typically includes token usage. Access input tokens, output tokens, and total tokens through `response.usage`.

Without tools, use empirical formulas for quick estimation: English tokens ≈ word count × 1.3, Chinese tokens ≈ character count × 1.5-2, code tokens ≈ character count ÷ 4. For mixed content, estimate each part separately and add them up.

## Token Limits and Costs

Each model has different context window and maximum output limits. GPT-4o and GPT-4 Turbo both have 128K context windows, with maximum outputs of 16K and 4K tokens respectively. Claude 3.5 Sonnet and Claude Opus 4.6 both have 200K context windows, with maximum outputs of 8K and 32K tokens respectively. DeepSeek V3 has a 200K context window with 8K maximum output.

API costs are calculated per token: cost = input tokens × input price + output tokens × output price. For GPT-4o, input is $2.5/1M tokens and output is $10/1M tokens. A conversation consuming 1000 input tokens + 500 output tokens costs about $0.0075.

Exceeding token limits happens in two ways. When input exceeds the context window, the API returns `context_length_exceeded` — you need to truncate history or process in segments. When output exceeds the maximum output limit, the output gets truncated — set a reasonable `max_tokens` or generate in segments.

## Practical Tips for Saving Tokens

Expressing the same content in English uses fewer tokens. `请帮我写一篇关于人工智能的文章` is about 15-20 tokens in Chinese, while the equivalent English expression is about 8-10 tokens. If you don't need Chinese output, asking and answering in English saves tokens.

Keeping prompts concise matters too. A verbose version like "Please write me a very detailed article covering multiple aspects with rich content about the history of artificial intelligence development, covering the journey from early research to the present" uses about 50 tokens. A concise version like "Write a history of AI, covering key milestones from early days to now" uses about 15 tokens — with nearly the same result.

Every conversation turn carries history, and token consumption accumulates. Turn 1: 100 tokens input. Turn 2: 150 tokens (added 50 tokens of history). Turn 3: 200 tokens. Linear growth. Countermeasures: periodically start new conversations to clear history, keep only necessary history messages, and use System Prompt to store fixed instructions.

System Prompt is counted only once, unlike user messages that repeat every turn. Putting all fixed instructions in the System Prompt is far more efficient than repeating them in every user message.

Images also consume tokens. A 1024×1024 image costs roughly 340 tokens (rough estimate). Compressing image sizes, only sending necessary images, and using low-resolution versions all reduce consumption.

## Tokens and Context Windows

The context window is the maximum number of tokens the model can "remember." A 128K token context window means the total tokens of input, conversation history, and output cannot exceed 128K. Anything beyond gets truncated or triggers an error.

Different scenarios have vastly different context needs. Simple Q&A needs 100-500 tokens. Code analysis needs 5K-20K tokens. Long document summarization needs 50K-100K tokens. Complex Agent tasks may need 100K-1M tokens.

The longer the context, the higher the cost. Transformer attention has O(n²) complexity — doubling the context can quadruple computation. Response speed also drops, and API costs rise.

## Appendix: Visualize Tokenization Yourself

To see firsthand how tokens split text, try these tools. The OpenAI Tokenizer (https://platform.openai.com/tokenizer) highlights each token in a different color when you enter mixed Chinese-English content. The Anthropic Console (https://console.anthropic.com) supports token counting and real-time estimation for Claude models. You can also quickly experiment locally with Python:

```python
import tiktoken
enc = tiktoken.encoding_for_model("gpt-4")
text = "your test text here"
print(enc.encode(text))
print([enc.decode([t]) for t in enc.encode(text)])
```

---

**References**:
- [OpenAI Tokenizer Documentation](https://platform.openai.com/docs/concepts/tokens)
- [tiktoken GitHub](https://github.com/openai/tiktoken)
- [BPE Algorithm Original Paper](https://arxiv.org/abs/1508.07909)
