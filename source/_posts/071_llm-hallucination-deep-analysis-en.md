---
title: "Why LLMs Hallucinate: A Deep Dive into the Mechanics"
date: 2026-03-28
categories: 大模型幻觉
tags: [AI]
lang: en
label: 071_llm-hallucination-deep-analysis
---

## Background

Ask an LLM "Who was the first emperor of the Ming Dynasty?" and it will answer "Zhu Yuanzhang." But ask "What was the name of Zhu Yuanzhang's third wife?" and it might answer "Empress Ma." Empress Ma was Zhu Yuanzhang's principal wife, not his third wife — the model has generated an answer that sounds plausible but is factually wrong. This is hallucination: the model speaks with confidence while getting the facts wrong. In a job interview, saying "because it's a probabilistic model" won't cut it. A probabilistic model doesn't inevitably fabricate content — you need to unpack which specific stages in the pipeline cause the problem.

<!-- more -->
---

## The Training Objective Was Never Truth

The training objective of an LLM was never to tell the truth. It's to predict the next most probable token. These two things sound similar but are fundamentally different. During training, the model never receives a supervision signal that says "this sentence is a fact" or "that sentence is fabricated." The only signal it gets is: given the preceding words, what's the most likely next word? If the input is "The founding emperor of the Ming Dynasty was," the training objective pushes the model to output "Zhu," then based on "Zhu" output "Yuan," then based on "Zhu Yuan" output "Zhang." What the model learns is the statistical regularity of language, not the actual facts of the world.

Given this training objective, the model pursues fluency and coherence, not factual correctness. Most of the time, fluent and coherent text happens to also be true, which is why the model appears to be telling the truth in most scenarios. But the moment "sounds right" conflicts with "is right," hallucination emerges. Take the question "In which chapter of Dream of the Red Chamber does Lin Daiyu uproot Lu Zhishen?" The question itself is absurd (Lin Daiyu is from Dream of the Red Chamber, Lu Zhishen is from Water Margin), but the model won't point out the error. Instead, it generates a linguistically plausible answer like "It happens in Chapter X of Dream of the Red Chamber," fabricating an event that never existed.

## No Awareness of Its Own Ignorance

Humans have metacognition — when faced with an uncertain question, we can say "I'm not sure, I don't know much about this." LLMs lack this capability. During training, the model is required to produce a coherent response; it's never given the option to decline. The training data contains very few examples of the pattern "here's a question, and the answer is 'I don't know' or 'I can't answer this.'" Even when such examples exist, they're so rare that the learned pattern is: every question deserves an answer.

So even when the model has no idea what it's talking about, it generates something that sounds reasonable. Ask "What is the name of Zhang Beihai's fourth child in The Three-Body Problem?" and the model might produce a specific name with full confidence — except Zhang Beihai doesn't have four children. The more uncertain the question, the more likely the model is to fabricate, because its training never provided the option of saying "I don't know."

## Knowledge Is Stored as Compression, Not Precision

An LLM doesn't store all knowledge verbatim like a database. It compresses massive amounts of text into statistical patterns encoded in its parameters. The difference between these two storage approaches determines the model's inherent weakness on factual precision.

| Storage Method | Characteristics |
|----------------|-----------------|
| Database storage | Precise, searchable, verbatim |
| Model parameter storage | Fuzzy, statistical, details easily confused |

This is somewhat analogous to how humans remember things: a person recalls the gist of an event but the details blur and get mixed up. The model does the same. It learns fuzzy associations and approximate patterns, not exact facts. The model might learn a fuzzy knowledge network like "Zhu Yuanzhang → Ming Dynasty, founding emperor, Nanjing, Empress Ma," along with probabilistic rules about when certain events occurred, but for precise details like "What was the name of Zhu Yuanzhang's third wife?" or "What was the exact date of this event?" it struggles to recall accurately. When forced to output such precise information, the model either mixes things up or fabricates from whole cloth.

## The Training Data Itself Has Quality Problems

The model's knowledge comes entirely from its training data, and internet data is full of problems.

| Problem Type | Example |
|--------------|---------|
| Misinformation | Rumors, fake news |
| Biased information | Partisan opinions |
| Outdated information | A 2023 news article that's no longer accurate in 2026 |
| Casual fabrication | Jokes made up by users on forums |

All of this is the model's textbook. The model can't distinguish right from wrong — it simply reproduces the erroneous patterns it learned as if they were correct outputs. Suppose the training data contains a forum joke like "Zhuge Liang invented the atomic bomb." The model might extract a statistical association between "Zhuge Liang" and "invented," and when asked "What did Zhuge Liang invent?" it could regurgitate the joke as fact. This isn't the model being stupid — it's faithfully reflecting the quality of its training data.

## Probability Sampling Compounds Errors Over Time

The answer generation process is not logical reasoning. It's guessing the next word step by step based on probability. At each step, the model picks the most likely word, but one wrong pick means all subsequent steps are built on corrupted context, and the deviation compounds.

| Generation Step | Status | Result |
|-----------------|--------|--------|
| Step 1 | Correct pick | Context stays normal |
| Step 2 | Correct pick | Still normal |
| Step 3 | Picked a suboptimal option | Small deviation appears |
| Step 4 | Continues from deviated context | Deviation amplifies |
| Step 5 | Errors accumulate | Output is seriously off |

This compounding effect is worse when the probability distribution is spread thin. Common questions have concentrated distributions, so the model usually picks correctly. Obscure questions have dispersed distributions, increasing the chance of wrong picks. Ambiguous questions have multiple candidates with similar probabilities, making it easy to pick the wrong one. Small deviations accumulate into big errors.

## Five Layers of Causes Stacked Together

Hallucination is not caused by a single factor — it's five layers compounding on top of each other. The training objective optimizes for fluency rather than correctness, which is the foundational misalignment. The model has no self-awareness about the boundaries of its knowledge, so it charges ahead answering every question regardless. Knowledge is stored in compressed form, making precise information inherently error-prone. The training data itself contains errors and noise, which the model internalizes as valid patterns. And the probability sampling during generation turns earlier small deviations into large errors over time. Stack all five together, and confident-sounding nonsense becomes the inevitable outcome.

## Mitigating Hallucination

From the user's side, there are practical techniques to reduce the chance of being misled. Probing for details forces the model to reveal where its confidence is shaky. Asking for sources pushes the model to admit it doesn't know where something came from. Setting temperature to 0 reduces randomness and makes the model more conservative. Explicitly telling the model "say 'I don't know' if you're unsure" gives it the option to decline that its training never offered.

| Layer | Method | Mechanism |
|-------|--------|-----------|
| User level | Probe for details | Forces the model to expose uncertain areas |
| User level | Ask for sources | Pushes the model to admit it doesn't know the reference |
| User level | Set temperature to 0 | Reduces randomness, more conservative output |
| User level | Explicitly allow "I don't know" | Gives the model a way out |
| Technical layer | RAG (Retrieval-Augmented Generation) | Retrieve real references first, then generate answers grounded in them |
| Technical layer | Knowledge graph grounding | Anchors answers to verifiable knowledge nodes |
| Technical layer | Cross-model validation | Multiple models answer the same question, compare differences |
| Technical layer | Fact-checking module | Secondary verification of model output |

The core idea behind all these approaches is the same: bring in external ground truth to compensate for the model's internal knowledge gaps.

An LLM is, at its core, a fluent language generator — not a precise fact database. Use it as an assistant for organizing thoughts and sparking ideas, but verify the important facts yourself.

---

**References**:
- [Hallucination in Large Language Models: A Survey](https://arxiv.org/abs/2311.05232)
- [Understanding the Limitations of LLMs](https://www.nature.com/articles/s41586-023-06400-y)
