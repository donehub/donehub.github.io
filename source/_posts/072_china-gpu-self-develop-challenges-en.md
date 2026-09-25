---
title: "China's GPU Challenge: Twenty Years of Catching Up, and How Far Is Left?"
date: 2026-04-01
tags: GPU
categories: AI
lang: en
label: 072_china-gpu-self-develop-challenges
---

In April 2026, China's AI compute supply was tight enough to feel like rationing. Signing up for a Coding Plan meant a long waitlist just to get a slot. The reason is straightforward: high-end GPUs are banned from export, and domestic alternatives can't keep up. This article breaks down the real constraints facing China's GPU self-development effort across three dimensions: fabrication process, software ecosystem, and talent pipeline.

<!-- more -->
---

## Where Domestic GPUs Stand Today

Huawei's Ascend line is the most promising domestic AI compute product family. Here are the core products and their positioning:

| Product | Process | Status | Performance Comparable To |
|---------|---------|--------|---------------------------|
| Ascend 910B | 7nm (SMIC N+2) | Mass-produced | Roughly A100 level (2020) |
| Ascend 910C | 7nm | Small-scale production | Roughly A100/A800 level |
| Ascend 910D | 7nm+ | Mass production in H2 2025, deployment in 2026 | Targeting H100 |

If the Ascend 910D successfully matches the H100 (a 2022 product), that means China reaches in 2026 what NVIDIA shipped in 2022 — roughly a 4-year lag. Meanwhile, NVIDIA has already moved on to B200/B300 (2024–2025) and Rubin (2026), staying 2–3 generations ahead.

Other domestic GPU vendors tell a similar story:

| Vendor | Product | Process | Status | Positioning |
|--------|---------|---------|--------|-------------|
| Hygon | DCU series | 7nm | Mass-produced | CUDA-compatible, ongoing iteration |
| Biren Tech | BR100 (revised) | 7nm | Small-scale | Pivoting to inference and edge computing |
| Moore Threads | MTT S80/S4000 | 7nm | Mass-produced | Full-function GPU, consumer + professional |
| Tianshu Zhixin | TianGai 100 | 7nm | Mass-produced | AI inference |

These vendors share one thing in common: they are all stuck at 7nm. This is no coincidence — it's the shared ceiling imposed by process restrictions.

---

## Process Node Restrictions Are the Core Bottleneck

High-end GPUs require advanced process nodes, and advanced nodes depend on lithography equipment. Here's the current accessibility picture for China:

| Process Node | Manufacturer | China Accessibility |
|-------------|-------------|---------------------|
| 3nm | TSMC, Samsung | Fully blocked |
| 4nm/4NP | TSMC | Export to China prohibited |
| 5nm | TSMC, Samsung | Export to China prohibited |
| 7nm | TSMC, Samsung, SMIC | SMIC can do it, but capacity is limited |
| 14nm+ | SMIC, Hua Hong, etc. | Mature, mass-produced |

NVIDIA's process roadmap: H100 in 2022 on 4nm, B200 in 2024 on improved 4NP, Rubin in 2026 on 3nm. The best process China can access over the same period is 7nm (SMIC N+2, DUV multi-patterning) — a gap of 2–3 generations.

### EUV vs DUV: The Lithography Generation Gap

EUV (Extreme Ultraviolet) lithography is the critical equipment for sub-7nm chips. It's manufactured exclusively by ASML in the Netherlands, and the US has banned its export to China. SMIC can only use DUV (Deep Ultraviolet) lithography for 7nm, which requires multi-patterning to compensate for the resolution shortfall. The cost shows up in three dimensions:

| Metric | EUV Single Exposure | DUV Multi-Patterning |
|--------|---------------------|----------------------|
| Steps | 1 exposure | 3–4 exposures |
| Yield | 80–90% | 30–50% |
| Cost | Baseline | 2–3x |
| Throughput | Baseline | Significantly constrained |

Producing the same 7nm GPU in China costs more, yields less, and results in fewer usable chips. There's no path to volume production. And 7nm is the physical limit of the DUV approach — it can't break through to 5nm or 3nm.

### The HBM Memory Shortfall

High-end AI training requires HBM (High Bandwidth Memory), another chokepoint:

| GPU | Memory Spec | Bandwidth |
|-----|-------------|-----------|
| H100 | 80GB HBM3 | 3.35 TB/s |
| B200 | 192GB HBM3e | 8 TB/s |
| Ascend 910D | Estimated HBM2e | Estimated 1–2 TB/s |

HBM is dominated by South Korea's SK Hynix and Samsung, with extremely high technical barriers. Domestic HBM is still in R&D, and the bandwidth specs are an order of magnitude behind NVIDIA's latest products.

---

## CUDA's Twenty-Year Moat

### The Software Stack Gap

Huawei's Ascend uses CANN (Compute Architecture for Neural Networks) as its software stack. Here's how it compares to the CUDA ecosystem layer by layer:

| Layer | CUDA Ecosystem | CANN Ecosystem |
|-------|---------------|----------------|
| Framework | PyTorch / TensorFlow | MindSpore (Huawei-developed) |
| Operator library | cuDNN / cuBLAS | ACL / OP API |
| Runtime | CUDA Runtime | CANN Runtime |
| Hardware | NVIDIA GPU | Ascend NPU |

The depth gap is stark:

| Dimension | CUDA (2026) | CANN (2026) |
|-----------|-------------|-------------|
| Development history | 20 years | ~6–7 years |
| Developer count | 5 million+ | Estimated 150K–200K |
| Operator library size | 3000+ | Estimated 500–600 |
| Documentation quality | Exhaustive | Relatively lacking |
| Bug fix responsiveness | Global team support | Dependent on Huawei's internal team |

### The Framework Adaptation Dilemma

Mainstream deep learning frameworks support CUDA at the native level; Ascend support is adapter-level. Take PyTorch: CUDA gets top priority — best performance, bugs fixed first, new features shipped immediately. AMD's ROCm gets secondary support and has more issues. Ascend connects through the `torch_npu` extension, which is not official native support.

This priority gap means PyTorch's new features always land on CUDA first. Ascend adaptation always lags. Many operators have no Ascend-optimized implementation, and the open-source community's contribution in this area is essentially zero.

### The Operator Migration Workload

A single deep learning model may involve hundreds of operators. PyTorch has over 2000 CUDA operators; Ascend has adapted an estimated 500–800, leaving over 1200 operators still to migrate. Each operator requires reimplementation for Ascend's architecture, performance tuning, and bug testing. This is a massive, ongoing effort — not a one-time investment.

---

## Structural Talent Shortage

GPU core talent is globally concentrated at NVIDIA and AMD. China needs to either develop talent from scratch or recruit from overseas, but the probability of top-tier talent returning is low. GPU microarchitecture design expertise is concentrated at NVIDIA and AMD, with very little in China. The parallel computing compiler direction — CUDA's team has 20 years of deep work; China is just starting. High-performance operator optimization requires dual expertise in both hardware and algorithms, and such talent is scarce everywhere.

Even if the hardware gets built, the user-side problem is equally thorny. Over 90% of China's AI developers use CUDA. Learning CANN means rethinking your programming model, memory management, and performance optimization strategies. For companies, unless forced by policy, there's no incentive to spend months migrating to a new platform.

---

## The Catch-Up Timeline

### The Gap Is Narrowing, but the Opponent Is Running Too

In 2024, the Ascend 910B was compared against the H100 — a 6–8 year lag. By 2026, the Ascend 910D targets the B300 — the lag narrows to roughly 3–4 years. If this catch-up pace holds, 2028 might see a 2–3 year lag, and 2030 might bring it to 1–2 years.

But these projections rest on three assumptions: process restrictions don't tighten further, software ecosystem investment continues, and NVIDIA doesn't accelerate its iteration. In reality, none of these assumptions fully hold. NVIDIA's product cadence is H100 (2022) → B200/B300 (2024–2025) → Rubin R100 (H2 2026), consistently iterating every two years. On Huawei's side, the 910D targets 2026 deployment against the H100 (2022) — still separated from NVIDIA's current frontier by a 4-year product generation gap.

### Prioritizing the Challenges

The challenges facing China's GPU self-development can be ranked by urgency. The most fundamental layer is hardware architecture design — there have been breakthroughs here, with the Ascend 910D showing mature design and some metrics approaching H100 levels. Continued funding can push this forward. The next layer up is manufacturing: 3nm vs 7nm is a 2–3 generation gap, EUV lithography is fully blocked, and HBM memory technology lags. This is the hardest bottleneck to crack in the short term. Above that sits talent and knowledge accumulation — NVIDIA's GPU expert team was cultivated over 20 years. The gap in compiler team size and performance optimization experience will take 5–10 years of sustained investment to narrow. At the software stack level, the operator library gap (3000+ vs 600), PyTorch adaptation at roughly 70% of mainstream operators, and debugger/profiler gaps are significant but narrowing. The topmost and hardest layer to cross is the ecosystem network effect: CUDA's 5 million+ developers accumulated over 20 years, academia defaulting to CUDA making paper reproduction difficult, and every global open-source project being CUDA-bound. This gap is still widening.

---

## What the Compute Crisis Reveals

The direct cause of the 2026 Coding Plan shortage is a triple squeeze: NVIDIA's high-end GPUs (H100, B200, etc.) are banned, cutting off import channels; domestic GPUs face capacity constraints due to low 7nm yields; and large model training demand has exploded far beyond supply.

Beneath the surface supply shortage lies dependence across the entire technology stack. Hardware: high-end GPUs, lithography equipment, and HBM all depend on imports. Software: locked into the CUDA ecosystem, developers only know CUDA. Talent: core GPU expertise is concentrated overseas. Ecosystem: academic papers and open-source projects are all CUDA-bound. Every layer of the AI technology stack carries deep dependence on foreign technology.

Looking back at the past decade, several strategic miscalculations made today's position worse. When large models exploded in 2022, the importance of AI compute was underestimated — the industry was caught off guard. Sanctions risk was underestimated, with no stockpiling contingency plan, and shortages hit immediately after the ban. The speed of domestic substitution was overestimated — people assumed a few years would be enough, but the actual gap proved far larger than expected. Software ecosystem was also neglected: past investment focused on hardware, and software ecosystem investment fell well short.

---

## Paths Forward and Time Expectations

In the short term (2026–2027), the most realistic path is forced substitution. Government systems, state-owned enterprises, and major companies mandate domestic compute. Universities and research institutions prioritize domestic platforms. Internet companies partially substitute. This approach can quickly boost domestic GPU demand and accelerate product iteration, at the cost of efficiency — performance won't match CUDA in the near term. After large-scale Ascend 910D deployment in 2026, basic demand can be partially relieved, but high-end training demand remains tight.

In the medium term (2028–2030), a more pragmatic strategy is scenario-specific breakthroughs rather than chasing a general-purpose GPU. Inference workloads don't need top-tier compute — domestic GPUs can handle them. Edge computing prioritizes power efficiency, where domestic solutions have an advantage. Specific industries like government, finance, and healthcare can be optimized with custom solutions. The parallel targets: the next Ascend generation matching B300 with the gap narrowing to 2–3 years, CANN operator adaptation reaching 90%+, and continued 7nm yield improvement.

In the long term (2030+), the most fundamental path is ecosystem building. Investing in open-source projects so developers are willing to contribute, building developer communities with training and documentation, pushing universities to use domestic GPUs for research, and helping enterprises migrate. Whether process nodes can break through depends on lithography technology progress — high uncertainty. A differentiated path is also possible: not chasing general-purpose GPUs but focusing on domain-specific optimization.

Back to the original question: when will compute supply normalize? Basic demand relief comes in 2026–2027. High-end demand relief depends on 2028–2030 breakthroughs. Catching up to NVIDIA likely takes 10–15 years. Building a complete ecosystem could take 20. This isn't a problem that can be solved by throwing money at it in the short term — it's a systemic engineering effort requiring 10–20 years of sustained investment. Sanctions must not escalate, investment must not be interrupted, and ecosystem building must continue. All three conditions need to hold.

---

## References

- [China aims for 10% China-made GPU market share this year](https://www.reuters.com/technology/china-aims-10-china-made-gpu-market-share-this-year-state-media-2025-01-21/)
- [China's chipmakers learning to live with American sanctions](https://www.economist.com/business/2025/02/06/chinas-chipmakers-are-learning-to-live-with-american-sanctions)
- [China's lithography challenges amid US sanctions](https://www.rfa.org/english/news/china/lithography-sanctions-01132025165529.html)
- [China's Hardware Manufacturing Ecosystem](https://www.semianalysis.com/articles/chinas-hardware-manufacturing-ecosystem-part-1)
- [NVIDIA Blackwell B200/B300 specifications](https://developer.nvidia.com/blog/)
