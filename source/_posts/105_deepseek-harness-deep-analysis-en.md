---
title: "DeepSeek Harness Deep Analysis"
date: 2026-08-14
categories: AI
tags: [Harness Engineering]
lang: en
label: 105_deepseek-harness-deep-analysis
---

## 1. Background

On August 13, 2026, DeepSeek officially open-sourced the Harness developer preview. The project broke 20,000 stars on GitHub within an hour of launch, then surpassed 920,000 stars the following day — a massive impact.
![alt text](/img/deepseek-harness-star-changes.png)
From forming the Harness team in May, to opening internal beta testing in July, to fully open-sourcing under the MIT license in August — the entire process took less than 3 months. This pace signals that DeepSeek isn't just releasing a new tool here — it's making a directional shift in product strategy.

---

<!-- more -->
## 2. The Harness Engineering Concept
![alt text](/img/deepseek-harness-introduction.png)
The word "harness" originally refers to horse tack — the collective term for reins, saddles, bridles, and other horse-control equipment. No matter how capable a horse is, without a harness, the rider can't control the direction or accomplish specific work.

In the AI agent context, DeepSeek defines the relationship as: **Agent = Model + Harness**

The Model handles thinking, reasoning, and content generation. The Harness makes the model's capabilities operational — calling external tools, managing context state, executing code, maintaining conversation memory, and coordinating multiple subtasks.

The model determines the system's reasoning ceiling; the Harness determines the system's execution floor. Over the past two years, the industry's attention has been focused on model capability — larger parameter counts, higher benchmark scores, faster inference speed. But when developers actually deploy models in production, they find the model itself accounts for a limited portion of the overall system. The vast majority of engineering work — tool integration, security controls, state management, error handling — all falls under the Harness umbrella.

---

## 3. Three Paradigm Shifts in AI Engineering

The rise of Harness isn't accidental. Looking back at the development of AI engineering in recent years reveals a clear evolution path.
![alt text](/img/prompt-context-harness.png)
### 3.1 Prompt Engineering (2022-2023)

This phase's core goal was getting the model to correctly understand task instructions. Typical approaches included adjusting wording, adding few-shot examples, and specifying output formats. Fundamentally, it was solving "how to express requirements clearly." For a time, Prompt Engineer even became a hot job title.

This approach worked well for simple tasks. But when task complexity increases — like analyzing an entire codebase for security vulnerabilities and generating a fix plan — a single prompt can't handle it. The model needs to read code files, call analysis tools, and remember which modules it has already checked. A single input has an information capacity ceiling.

### 3.2 Context Engineering (2024-2025)

The industry then realized that getting the right information to the model at the right moment is equally critical. This phase's core is context engineering — using RAG to retrieve relevant documents, managing memory systems, compressing conversation history, and injecting key information into the model's context window.

An intuitive analogy: a Prompt is the task briefing given to a new employee; Context is the reference material at their desk. No matter how clearly the briefing is written, if the reference material isn't available, the task can't be completed properly.

Context Engineering solved the information supply problem, but it only governs "what the model sees" — it doesn't intervene in "what the model does." If the model decides to execute a dangerous system command, Context Engineering alone can't intercept it.

### 3.3 Harness Engineering (2026-)

Harness Engineering moves the focus further up to the system level: not what the model says or sees, but what the entire execution environment can do, how it does it, and what happens when things go wrong.

Its core coverage areas include:

| Domain | Specifics |
|--------|-----------|
| **Tool Orchestration** | Which tools the model can call, in what order, retry or skip strategies on failure |
| **Safety Guardrails** | Prohibited command lists, human confirmation for file operations |
| **Context Management** | Conversation history compression strategies, key information persistence schemes |
| **Task Planning** | How to decompose complex tasks, coordination mechanisms between subtasks |
| **Memory Systems** | Short-term working memory maintenance, long-term memory retrieval strategies |
| **Execution Sandbox** | Isolated environments for code execution, resource limits and timeout controls |
| **Observability** | Execution process logging, trace replay after issues arise |

Prompt solves "how to say it," Context solves "how to see it," Harness solves "how to do it."

---

## 4. DeepSeek Harness Architecture and Features

### 4.1 Development Timeline

- **May 2026**: DeepSeek posted Agent Harness-related positions on recruitment platforms, explicitly targeting Claude Code
- **July 2026**: Limited internal beta testing begins
- **August 13, 2026**: Developer preview released, **open-sourced under MIT license**

### 4.2 Core Design Philosophy: Everything Is a Plugin

DeepSeek Harness's architecture revolves around one core principle: everything is a plugin.

Model, tools, skills, session management, sandbox, storage, Agent main loop (Agent Loop) — all capability units exist as plugins. These plugins are assembled through a plugin meta-framework called Cordis. Developers can freely replace any component in configuration files without modifying source code.

The benefit: when you need to swap the underlying model, add custom tools, or replace the execution sandbox, you only adjust configuration — no system rewrite needed. The Cordis framework itself is built on five key concepts:

1. **Plugin** — each independent capability unit
2. **Context** — the shared state space between plugins
3. **Service Dependency** — call and dependency relationships between plugins
4. **Typed Events** — the communication mechanism between plugins
5. **Revocable Side Effects** — operation rollback capability
![alt text](/img/deepseek-harness-usage.png)

### 4.3 Four Operating Modes

DeepSeek Harness provides four operating modes. They're not independent systems — they're different default plugin configurations on the same foundation.

| Mode | Positioning | Toolset | Use Case |
|------|------------|---------|----------|
| **Standard** | Daily development | Full toolset: file editing, Shell, search, Skills, sub-agents, etc. | Routine coding and project management |
| **PTC** | Programmatic Tool Calling | Everything in Standard + Code Mode SDK | Complex multi-step automation flows |
| **Minimal** | Benchmark testing | bash + str_replace_editor only | Model capability evaluation and controlled experiments |
| **Creative** | Dynamic extension | Agent can dynamically generate new tools at runtime | Innovative tasks requiring high flexibility |

PTC mode (Programmatic Tool Calling) deserves special attention.

Traditional Agent tool calling works step by step: reason → call tool → read result → reason again → call tool again. For complex tasks, this loop runs many times, and each interaction consumes tokens.

PTC mode's approach: the model writes a TypeScript program, orchestrating multiple operations in the same code block, then submits it for one-shot execution. The program supports loops, conditionals, and multi-tool combinations internally. This dramatically reduces round-trips between the model and execution environment, cutting token consumption while improving complex task efficiency.

### 4.4 Trajectory Replay Mechanism

DeepSeek Harness includes **full-process trajectory tracking and replay** built in. Every step in the Agent's execution is recorded as a JSON-format trajectory log, supporting:

- **Replay**: fully reproduce an execution process for debugging and issue diagnosis
- **Resume**: restart execution from any historical point
- **Fork**: create branches based on existing trajectories to explore different execution paths
- **Search**: query and analyze historical trajectory data

These trajectories aren't just useful for debugging. They can serve as demonstration data for subsequent model training — meaning execution records generated during actual use feed back into model optimization as training signals. This creates a data flywheel: more usage → more trajectory data → stronger model capability.

---

## 5. Comparison with Claude Code

| Dimension | DeepSeek Harness | Claude Code |
|-----------|-----------------|-------------|
| **Developer** | DeepSeek | Anthropic |
| **Product Positioning** | Agent Runtime / Agent Platform | AI Coding Assistant |
| **Open Source Strategy** | MIT license, fully open source | Closed-source commercial product |
| **Architecture** | Plugin-based, freely composable components | Integrated design, deeply tied to own models |
| **Model Binding** | Not tied to a specific model, supports switching | Deeply bound to Claude model family, but also supports other models |
| **Operating Modes** | Four modes available | Single mode |
| **Signature Features** | Trajectory replay, PTC mode, Cordis plugin framework | Mature IDE integration, Hooks system |
| **Ecosystem Maturity** | Just open-sourced, ecosystem in early build phase | Community and toolchain relatively mature |
| **Usage Cost** | DeepSeek model calls are relatively inexpensive | Relies on Claude API, relatively higher cost |

The two have distinctly different design orientations. Claude Code takes an integrated approach — good out-of-the-box experience, but components aren't replaceable and it's deeply tied to Claude models. DeepSeek Harness takes a plugin architecture — more flexible, supports model switching and custom components, but with a correspondingly higher learning curve.

For developers who need to get started quickly, Claude Code's maturity has the advantage. For scenarios requiring deep Agent system customization or avoiding single-vendor model lock-in, DeepSeek Harness's open-source approach provides more design space.

---

## 6. DeepSeek's Product Structure Shift
![alt text](/img/deepseek-harness-changes.png)
### 6.1 The Competitive Focus Is Shifting

Over the past two years, the AI industry's competitive focus has been on model capability — parameter scale, benchmark scores, inference speed. DeepSeek Harness's release reflects a trend: the competitive focus is migrating toward the execution layer.

No matter how strong a model's reasoning ability, without a solid execution framework, it can't reliably deliver in production. Internal beta data shows the same model achieving task completion rates that differ by up to 53 percentage points under different Harnesses. The quality of the execution framework's impact on final results, in some scenarios, now exceeds the choice of model itself.

### 6.2 The Real Bottleneck for Production Deployment

Model upgrades raise the capability ceiling; Harness determines production readiness. The real difficulties most enterprises face when deploying AI models into production aren't that the model isn't strong enough — they're incomplete tool chains, chaotic context management, missing error handling, and absent monitoring and debugging tools. These problems all fall under Harness.

### 6.3 The Open Source Strategy Rationale

DeepSeek chose to fully open-source under MIT rather than build a closed-source commercial product. This decision can be understood from two angles.

Ecosystem angle: Agent framework competition is fundamentally a developer ecosystem competition. Open source allows developers and tool providers to freely use, modify, and extend the framework — the most efficient way to attract external participants and build a plugin ecosystem.

Data angle: the trajectory replay feature converts execution records into training data. The larger the user base, the more trajectory data accumulates, and the more targeted model optimization becomes. Trade open source for user scale, trade user scale for data accumulation, trade data accumulation for model evolution — this mirrors Android's early strategy of using open source to gain market share, then consolidating position through ecosystem scale.

---

## 7. Current Limitations and Constraints

As a developer preview, DeepSeek Harness has several clear constraints:

1. No CLI tool: currently only offers a Web UI. Developers accustomed to terminal workflows will need to wait for a future command-line tool release.
2. Plugin ecosystem is early-stage: the architecture supports flexible plugin replacement, but the number of available third-party plugins is limited — ecosystem richness takes time to build.
3. Documentation coverage is incomplete: particularly the Cordis plugin framework's development guide. Some implementation details require consulting source code to confirm.
4. API stability is insufficient: at the v0.x stage, plugin interfaces and APIs are subject to breaking changes. Not recommended for direct production use.

---

## 8. Summary

DeepSeek Harness's positioning isn't another chatbot or a wrapper Agent product. It's DeepSeek's strategic move from model provider to AI execution-layer infrastructure.

Competition in AI during 2026 is shifting from "whose model is stronger" to "whose execution framework is more mature." DeepSeek Harness has put the first open-source entry on this track. Its "everything is a plugin" architecture and the trajectory replay data flywheel represent a technical direction in Agent engineering that deserves attention.

Whether it can maintain leadership through ecosystem building and sustained iteration remains to be seen. Since the 2026 Spring Festival, it feels like someone hit the fast-forward button — I'm witnessing AI's rapid development every month. I'm genuinely looking forward to where DeepSeek's product exploration goes next.

---

**References:**
- [DeepSeek Harness Official Site](https://www.deepseek.com/harness/?utm_source=chatgpt.com)
- [DeepSeek Harness Developer Preview Release - Sina](https://finance.sina.com.cn/tech/roll/2026-08-13/doc-inineuqe4558061.shtml)
- [DeepSeek Building Harness Team, Targeting Claude Code - JiaZhiGuangNian](https://www.21jingji.com/article/20260521/herald/d706e7b6130739114b8761d933f7e546.html)
- [Deep Dive into DeepSeek Harness — I Forgive the Price Increase - QbitAI](https://www.qbitai.com/2026/08/472208.html)
- [Understanding Harness Engineering in One Article - Zhihu](https://zhuanlan.zhihu.com/p/2036738130649330427)
- [Prompt, Context, Harness: Three-Layer Architecture Analysis for AI Agents - Tencent Cloud](https://cloud.tencent.com/developer/article/2655114)
- [DeepSeek Officially Open-Sources Harness - MIT Technology Review China](https://www.mittrchina.com/news/detail/16781)
- [Harness Officially Emerges - 36Kr](https://www.36kr.com/p/3935871461916035)
- [99.93% Cache Hit Rate! The Perfect Harness for DeepSeek - BAAI Hub](https://hub.baai.ac.cn/view/57048)
