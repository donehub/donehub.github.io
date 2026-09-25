---
title: "Designing and Evaluating Multi-Agent Systems"
date: 2026-04-30
tags: [Multi-Agent]
categories: AI
lang: en
label: 095_multi-agent-decision-and-evaluation
---

"The more complex the task, the more you should use multi-Agent" — sounds reasonable, but this sentence hides a massive trap. Many people jump straight into multi-Agent architectures on impulse, only to end up with exploding latency, runaway costs, and logs that look like alphabet soup. Then they discover a single Agent with a tool call would have done the job. The previous post covered Multi-Agent design principles. This one takes a different angle: when should you use multi-Agent? And after you've built it, how do you evaluate whether the design is any good?

---

<!-- more -->
## 1. Complexity Isn't the Decision Criterion

When most people hear "multi-Agent," they picture this: a central orchestrator Agent sitting in the middle, with code-writing, testing, and documentation Agents branching off, each doing their own thing. Impressive to look at.

Impressive doesn't mean effective. Complexity has never been a valid reason to choose multi-Agent. The real decision criteria come down to two dimensions: concurrency benefit and context constraints.

One table to make it clear:

| Scenario Characteristic | Single Agent Enough? | Go Multi-Agent? |
|------------------------|---------------------|-----------------|
| Steps are strictly sequential, each depends on the previous result | Yes | No, pure waste |
| Multiple subtasks are independent and can run concurrently | No | Yes, clear parallelism benefit |
| Single task overflows the model's context window | No | Yes, must split |
| Subtasks need frequent exchange of intermediate state | Barely | Caution, communication overhead may eat the benefit |

But this table is too coarse. Real decisions are much more complex. Let's break it down.

---

## 2. Four Decision Dimensions

### 2.1 Task Dependency Graph: Linear or Fan-Out?

This is the most critical criterion. **Linear dependency** means tasks have a strict ordering: A's output is B's input, B's output is C's input. When a user asks "where's my refund," you identify intent, then query the order database, then compose the reply. These three steps must be sequential — there's no room for parallelism.

**Fan-out dependency** means one task can be split into multiple unrelated subtasks that execute simultaneously. "Scan this codebase for security issues" — injection vulnerability scanning, memory leak detection, and code style checking have zero data dependency between them. They can all start at the same time.

Drawn as diagrams, the difference looks like this:

```
Linear dependency (single Agent):
Intent recognition → Query database → Compose reply
       A      →       B        →      C

Fan-out dependency (multi-Agent):
              ┌→ Security scan ──┐
Orchestrator ─┤→ Performance analysis ─┤→ Consolidate
              └→ Style check ──┘
```

The judgment is straightforward: if your task dependency graph draws as a straight line, use a single Agent. If it looks like a fan, consider multi-Agent.

### 2.2 Is the Context Window a Hard Bottleneck?

Some tasks look linear but carry so much data that a single model can't handle it. Even when tasks are sequential, you still need to find ways to split them.

Example: you're given a 500,000-line codebase and asked to generate complete API documentation. This isn't a parallel task — you need to understand the overall architecture to write good docs. But 500,000 lines of code won't fit into any model's context window.

Here, multi-Agent's value isn't parallel acceleration — it's context slicing:

```
Agent-1: Scan the controller layer, extract interface definitions
Agent-2: Scan the service layer, extract business logic
Agent-3: Scan the entity layer, extract data models
Orchestrator Agent: Takes the three sliced reports, merges and generates documentation
```

Each Agent only needs to process its own layer of code, dramatically reducing context pressure. The orchestrator receives three refined reports instead of hundreds of thousands of lines of raw code.

Rule of thumb: estimate the context token count your task needs. If it exceeds 60% of the model's window, consider splitting. Reserve 40% headroom for system prompts, tool calls, and intermediate reasoning.

### 2.3 Does the Latency Budget Allow It?

This is the most easily overlooked criterion. The latency formula for multi-Agent systems is unforgiving:

```
Total latency = max(sub-Agent latencies) + orchestrator planning latency
              + orchestrator consolidation latency + communication overhead
```

Note it uses `max`, not `sum`, because sub-Agents run in parallel — total latency depends on the slowest one. But don't forget the three fixed overhead terms that follow.

In real production environments, a single LLM call typically takes 2-8 seconds. A three-tier multi-Agent system needs at least one model call each for planning and consolidation, plus sub-Agent execution time. End-to-end latency easily exceeds 15 seconds.

Compare with a single-Agent approach:

```
Single Agent: Intent recognition (2s) → Tool call (1s) → Summary reply (2s) = 5s
Multi-Agent: Planning (3s) + max(3 sub-Agents) (4s) + Consolidation (3s) + Comm (1s) = 11s
```

In practice: if your scenario is real-time user-facing interaction (chatbot, customer service), latency budgets are typically under 5 seconds. Multi-Agent will almost certainly time out in this case — single Agent + tool calls is the more pragmatic choice. If it's a background batch task (code audit, report generation), the latency budget is generous, and multi-Agent has room to shine.

### 2.4 Can the Token Budget Handle It?

Token consumption in multi-Agent systems doesn't grow linearly — it jumps in steps.

Every Agent invocation costs you:
- System prompt (same every time, but billed every time)
- Context injection (task description, history)
- Model inference (output tokens)

Suppose you have one orchestrator + 5 sub-Agents, each Agent's system prompt is 2,000 tokens, task descriptions average 1,000 tokens, and output averages 1,500 tokens. A full round of execution costs roughly:

```
Orchestrator: 2000 + 1000 + 1500 = 4500
Sub-Agents ×5: (2000 + 1000 + 1500) × 5 = 22500
Consolidation: 2000 + 3000 (sub-Agent results) + 2000 = 7000
Total: ~34,000 tokens
```

A single Agent doing the same task might need only 5,000-8,000 tokens.

In practice, do the math first: if your system handles high-concurrency requests (say, hundreds per second), the token cost difference gets amplified hundreds of times. How many times more expensive is multi-Agent versus single Agent? Can your budget absorb that multiplier?

---

## 3. Decision Walkthroughs for Four Real Scenarios

Theory only goes so far. Let's run four real scenarios through the decision process.

### 3.1 Customer Service Chatbot

User asks: "Where's my refund for order #12345?"

**Dependency graph**: Identify intent → Query order → Reply. Strictly linear, no parallelism possible.

**Context analysis**: A single conversation's context is tiny, nowhere near the window limit.

**Latency analysis**: User is waiting for a reply, latency budget is 3 seconds.

**Token analysis**: High-concurrency scenario (thousands of users consulting simultaneously), cost-sensitive.

All four criteria point to single Agent. Going multi-Agent would be over-engineering.

### 3.2 Enterprise Code Security Audit

Requirement: Scan a 100,000-line codebase and output a security vulnerability report.

**Dependency graph**: Injection scanning, memory leak detection, dependency vulnerability checking, code style review — four subtasks are completely independent.

**Context analysis**: 100,000 lines of code far exceeds any single model's window. Must slice.

**Latency analysis**: Background batch processing, user can wait minutes, latency budget is generous.

**Token analysis**: Low concurrency (might run a few times a day), cost is manageable.

All four criteria point to multi-Agent.

### 3.3 Long Document Summarization

Requirement: Condense a 200-page technical document into a 5-page summary.

At first glance, 200 pages definitely won't fit in context, so multi-Agent splitting seems right.

But think more carefully: document summarization has global coherence requirements. You can't have Agent-A summarize pages 1-50, Agent-B summarize pages 51-100, then stitch them together. The resulting summary will have massive duplication, omissions, and logical breaks.

A better approach is **single Agent + iterative segmented strategy**:

```
Round 1: Single Agent processes pages 1-50, produces intermediate summary A
Round 2: Single Agent carries summary A, processes pages 51-100, produces intermediate summary B
Round 3: Single Agent carries summary B, processes pages 101-150, produces intermediate summary C
Round 4: Single Agent carries summary C, processes pages 151-200, produces final summary
```

Each round preserves the essence of prior context, maintaining coherence. This produces much better results than multi-Agent parallel splitting.

**Lesson**: Context overflow doesn't automatically mean multi-Agent. Sometimes **sequential segmentation + state passing** suits coherence-dependent tasks better than parallel splitting.

### 3.4 Multilingual Translation Pipeline

Requirement: Translate a technical document into English, Japanese, and Korean.

**Surface analysis**: Three languages are independent, can run in parallel — looks like multi-Agent territory.

**Deeper analysis**: The prerequisite steps for translation (terminology extraction, style normalization) are shared. If three Agents each extract terminology independently, the resulting translations will have inconsistent style.

**Optimal approach**: Hybrid architecture.

```
Phase 1 (single Agent): Extract terminology + define translation style guide
Phase 2 (multi-Agent parallel): Three Agents translate three languages, sharing the terminology
Phase 3 (single Agent): Review consistency across all three translations
```

**Lesson**: Most tasks aren't purely "use multi-Agent" or "don't." They use multi-Agent at certain pipeline stages and not others. Hybrid architecture is the most common production pattern.

---

## 4. How to Evaluate Whether a Multi-Agent Design Is Any Good?

Choosing the right scenario is just step one. Even with the right decision, a multi-Agent system can still be badly designed. Here's an evaluation framework scoring across five dimensions.

### 4.1 Task Decomposition Quality

This is the most fundamental and most critical dimension. If decomposition is wrong, everything built on top is a house of cards. **Good decomposition** has three traits:

| Trait | Description | Counter-example |
|-------|-------------|-----------------|
| Low coupling between subtasks | Each sub-Agent can do its work independently, doesn't need another's output | Agent-A needs Agent-B's output before it can start |
| Moderate subtask granularity | Not too coarse (one Agent can't finish) and not too fine (splitting too finely makes communication overhead eat the benefit) | Splitting "query database" into "establish connection," "send SQL," "parse result" as three Agents |
| Clear subtask boundaries | Each Agent's responsibility is explicit, no two Agents doing the same thing | Both the security Agent and the performance Agent scanning the same function in the same code |

**Quick check**: Take a piece of paper and write down each sub-Agent's task. If you find two sub-Agent task descriptions overlap more than 30%, your decomposition has problems.

### 4.2 Communication Overhead Ratio

Total cost of a multi-Agent system = compute cost + communication cost.

Communication cost includes:
- Tokens for the orchestrator passing task descriptions to sub-Agents
- Tokens for sub-Agents returning results to the orchestrator
- Tokens for the orchestrator consolidating all results
- If sub-Agents communicate with each other (not recommended), cross-communication tokens too

**Healthy system**: Communication overhead accounts for under 20% of total token consumption.

**Problematic system**: Communication overhead exceeds 40%. You're spending a lot of tokens on Agents "passing notes" instead of doing real work.

Calculation:

```
Communication overhead ratio = (task dispatch tokens + result return tokens
                              + consolidation tokens) / total token consumption × 100%
```

If this ratio comes out high, either subtasks are split too finely (too many small Agents passing messages) or result compression isn't done well (sub-Agents bring back overly verbose information).

### 4.3 Parallel Efficiency

The core value of multi-Agent is parallelism. If parallel efficiency is low, multi-Agent serves no purpose.

**Parallel efficiency** definition:

```
Parallel efficiency = Single-Agent sequential completion time / Multi-Agent parallel completion time
```

Theoretically, N Agents running in parallel should yield efficiency close to N. In practice, that's hard to achieve because:
- Sub-Agent workloads are unbalanced (the slowest one determines total time)
- Orchestrator planning and consolidation have fixed latency
- Communication carries network overhead

| Parallel Efficiency | Assessment | Recommendation |
|--------------------|------------|----------------|
| > 2.0x | Excellent | Multi-Agent approach is worth the investment |
| 1.5x - 2.0x | Mediocre | Depends on scenario — if cost-sensitive, consider single Agent |
| < 1.5x | Poor | Multi-Agent benefit doesn't cover extra overhead, fall back to single Agent |

**Key to improving parallel efficiency**: Balance each sub-Agent's workload as much as possible. If one sub-Agent finishes in 1 second and another takes 10 seconds, your parallel efficiency is being dragged down by the straggler.

### 4.4 Fault Tolerance and Observability

This is the dimension where engineering implementations most often fall apart. **Fault tolerance** assessment checklist:

- When a sub-Agent times out or fails, what happens? Does the whole system fail outright, or can it degrade gracefully?
- When a sub-Agent returns a wrong result (hallucination), can the orchestrator detect it?
- Is there a maximum retry count? Is there an upper bound on retry token costs?

**Observability** assessment checklist:

- When something breaks, can you identify in the logs which Agent failed at which step?
- Is every Agent's input and output fully recorded?
- Can you replay a complete execution for debugging?

A harsh reality: most multi-Agent system logs are a mess. The orchestrator calls 5 sub-Agents, each sub-Agent calls various tools, and when something goes wrong you see only a generic "execution failed" with no way to trace which step was hallucinating.

**Good design**: Assign each Agent execution a unique trace ID, tag all logs with it, enable end-to-end tracing.

### 4.5 Diminishing Returns Point

This is the dimension that requires the most engineering intuition. The number of sub-Agents in a multi-Agent system isn't "more is better." There's a diminishing returns point — past it, the parallel benefit of adding another Agent is less than the added communication overhead and coordination cost.

```
                Benefit
                 ↑
                 │        ╭───────── Benefit curve
                 │      ╱
                 │    ╱
                 │  ╱
                 │╱
                 ├──────────────────→ Number of Agents
                 ↑
          Diminishing returns point
```

**Rule of thumb**: In most scenarios, keeping sub-Agent count between 3-8 is reasonable. Beyond 10, coordination costs rise sharply.

**How to find this point?** The most reliable method is benchmarking.

1. Start with 2 sub-Agents, record execution time and token consumption
2. Gradually increase to 3, 4, 5...
3. Plot "Agent count vs end-to-end latency" and "Agent count vs token cost" curves
4. Find the inflection point where latency stops decreasing significantly but token cost keeps rising

That inflection point is your optimal Agent count.

---

## 5. A Complete Evaluation Checklist

Distill the five dimensions above into an actionable checklist. For any multi-Agent system design, score it against this table:

```
Task decomposition quality              □ Pass  □ Fail
├─ Low coupling between subtasks?       □ Yes   □ No
├─ Moderate granularity?                □ Yes   □ No
└─ Clear boundaries?                    □ Yes   □ No

Communication overhead ratio            □ Pass  □ Fail
├─ Communication token ratio < 20%?     □ Yes   □ No
└─ Sub-Agent results compressed?        □ Yes   □ No

Parallel efficiency                     □ Pass  □ Fail
├─ Parallel speedup > 1.5x?            □ Yes   □ No
└─ Sub-Agent workloads balanced?        □ Yes   □ No

Fault tolerance & observability         □ Pass  □ Fail
├─ Sub-Agent failure allows degradation? □ Yes  □ No
├─ Each Agent has a trace ID?           □ Yes   □ No
└─ Can replay complete execution?       □ Yes   □ No

Marginal returns                        □ Pass  □ Fail
├─ Sub-Agent count in reasonable range (3-8)? □ Yes □ No
└─ Benchmarking done to find optimum?   □ Yes   □ No
```

All 5 dimensions pass — this is a qualified multi-Agent system design. 1-2 failing — needs targeted optimization. 3 or more failing — go back and reconsider whether this scenario actually needs multi-Agent at all.

---

## Final Thoughts

Multi-Agent systems aren't a silver bullet. The scenarios where they're truly irreplaceable are when you hit two ceilings at once: a single model's context can't hold the data, and sequential execution latency is intolerable. Hitting just one of those, single Agent plus segmented strategy or async tool calls is usually enough.

Evaluating a multi-Agent system design comes down to five core dimensions: whether task decomposition is loosely coupled, whether communication overhead is controllable, whether parallel efficiency meets targets, whether fault tolerance and observability are solid, and whether sub-Agent count has passed the diminishing returns point. All of these have concrete quantitative metrics — no need to rely on gut feeling.

From an engineering practice perspective, multi-Agent system success rarely depends on how elegant the architecture design is. It depends on whether communication overhead control and fault tolerance handling are solid. A system where communication overhead exceeds 40% — no matter how beautiful the architecture diagram — will pay for it in cost and latency once it hits production.
