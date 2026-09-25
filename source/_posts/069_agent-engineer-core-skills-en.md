---
title: Core Skills for AI Agent Engineers
date: 2026-03-21
tags: [Agent Practices]
categories: AI
lang: en
label: 069_agent-engineer-core-skills
---

A video circulating in tech circles the other day listed four core skills for AI Agent engineers: programming fundamentals, Prompt Engineering, systems thinking, and domain knowledge. The comments section was full of people bookmarking it saying "so true." I don't dispute that framework, but after shipping several Agent projects to production, I've found the real bottleneck skills are ones that video never mentioned.

<!-- more -->

## Programming Fundamentals

All the Agent platforms out there promise the moon — drag and drop to build an Agent. But when you hit complex scenarios, you'll find the platform's abstractions aren't enough. You need to write your own tool functions, handle async concurrency, manage state transitions. Python is the mainstream choice, and LangChain and LangGraph are unavoidable, but I'd suggest understanding the core concepts before touching frameworks — otherwise you end up being someone who can call APIs but doesn't understand the underlying mechanics.

Specifically, a few fundamentals need to be solid. Async programming: Agent tool calls are mostly I/O-bound; if you're not comfortable with `async/await`, performance will suffer. State management: maintaining context across multi-turn conversations, choosing storage backends, setting expiration policies — these need to be thought through before writing code. Tool abstraction: wrapping any HTTP API or Python function into a Tool the Agent can call, handling return value formatting — this is recurring daily work.

LangGraph's StateGraph is a great learning entry point. It forces you to think about what state each Agent node holds, what conditions the edges represent, how to exit if you hit an infinite loop. Once these basics are clear, picking up frameworks becomes much more efficient.

## Prompt Engineering

Many people's understanding of Prompt Engineering still stops at "write the question more clearly." That's not wrong, but it's shallow. In practice, Prompt design is more like designing an interaction protocol — you need to specify input format, output format, error behavior, and even plan for what happens when the model doesn't follow instructions.

Structured output is far more reliable than free-form generation. If you can constrain output with JSON Schema, don't let the model generate free text. Function Calling is essentially built for this. Few-shot isn't just throwing in a few random examples either — example selection needs to be representative, covering both happy paths and edge cases. The most typical production failure I've seen was a Few-shot set containing only successful call examples; when the production Agent encountered abnormal parameters, it just made up return values.

Multi-turn conversation context design is a technical discipline of its own. You can't stuff all history into the context — the window is limited, and even though more expensive models have longer contexts, it's still not infinite. A common pattern: keep the last N turns verbatim, summarize-compress earlier turns, and maintain a separate working memory for key information like user preferences and confirmed constraints. LangGraph's Memory module has off-the-shelf implementations, but understand the principles before using it directly — you'll need that knowledge when debugging.

## Systems Thinking

When your Agent runs, it's essentially a state machine: receives input, decides whether to call a tool, gets tool results, decides next step. This loop might execute once or ten times, depending on task complexity.

Task orchestration isn't a linear flow. Some steps can run in parallel — like checking weather and checking routes simultaneously; some must be serial — like checking user permissions before querying data. LangGraph's DAG orchestration can handle this, but you need to be able to draw that graph first.

Exception handling is ten times more important than the happy path. Agents hallucinate, tools time out, APIs return unexpected data. Every node you design needs a fallback plan: on tool call failure, retry or skip? If the model returns malformed output, can you retry once, and how many retries before giving up? If the Agent enters a loop, how do you detect it and force exit?

I once built an Agent that auto-generated SQL queries from user descriptions. Worked fine normally, but when user input was vague, the Agent would keep generating bad SQL, execution would fail, it would regenerate, looping until it hit the API call limit before stopping. I ended up adding a counter — max 3 retries per user intent, after which it returns a prompt asking the user to be more specific. That lesson completely changed my priority ranking for exception handling.

## Domain Knowledge

Knowing the tech but not the domain produces demos, not production systems. Domain knowledge integration isn't just about learning some business knowledge — it's about transforming business knowledge into something the Agent can understand and use.

There are several concrete approaches. RAG (Retrieval-Augmented Generation) vectorizes industry documents, SOPs, and knowledge bases; the Agent retrieves relevant context before making decisions. A rule engine + LLM combination suits scenarios with hard rules — like amounts over a certain threshold requiring approval. Don't expect the LLM to remember these; hardcode them in code, only delegating to the model where flexible judgment is needed. Tool selection should also fit the scenario: a customer service Agent needs tools for checking orders, tracking shipments, checking return policies; a code Agent needs code search, linting, test running. The tool set defines the Agent's capability boundary.

## Observability

The four above were the basic skills that video also mentioned. The next four are where I think the real gap opens up in practice.

When traditional code has bugs, you add logs, check stacks, debug with breakpoints. When an Agent has problems, it's different — its execution path is dynamic; the same input might take a different route every time. Without observability, an Agent is a black box — you can only see input and output; what happened in between is guesswork.

You need to know what decisions the Agent made and why it chose this tool over that, what the tool call inputs and outputs were and how long they took, which step started deviating from the expected path, how the unsatisfactory result the user got was produced step by step.

Tools like LangSmith and LangFuse can help trace the Agent's execution chain. Don't rely entirely on third-party tools though — even if it's just your own logging, make sure every key node has a trace_id that can stitch together a complete Agent execution chain.

```python
# Give each Agent execution a trace_id
import uuid

def run_agent_with_trace(user_input):
    trace_id = str(uuid.uuid4())[:8]
    logger.info(f"[trace:{trace_id}] Agent start, input: {user_input[:50]}...")
    
    # Log before and after each tool call
    result = execute_tool_with_logging(tool_name, args, trace_id)
    
    logger.info(f"[trace:{trace_id}] Agent complete")
    return result
```

With this, when a user complains, you can look up exactly what the Agent did that day, instead of giving a non-answer like "we'll look into it."

## Evaluation Framework

Traditional code quality is easy — run unit tests. Agent quality lacks an objective measure. Iterating an Agent without an evaluation framework is guessing. You changed the Prompt and think it's better — but is "better" your feeling or does the data say so? You need a quantifiable mechanism to answer that.

Metrics to track: tool call accuracy (didn't call when it shouldn't have, called correctly when it should), output quality (format correctness, factual accuracy, user satisfaction), and comparative data between different Prompt versions.

Implementation can follow three steps. First, build a Golden Dataset — collect 50-100 typical real user inputs, annotate expected behavior (which tool to call, expected output). Second, run regression tests after every Prompt change to see if pass rate dropped. Third, run A/B tests in production — new Prompt gets a percentage of traffic, compare metrics. Doesn't need to be perfect from day one; start with a few core use cases running, add more over time.

## Cost Awareness

Every LLM call in an Agent costs money. A complex multi-step Agent might call the model 10+ times in a single conversation, costs stacking with each call.

A few practical cost-saving approaches. Mix large and small models — not every decision needs GPT-4; intent classification, format validation — use a small model or just plain code for those; only bring in the big model for steps that genuinely need reasoning. Cache results — the same question shouldn't be asked repeatedly; if a user asks about today's weather in Beijing, the second ask the same day should return cached results, not call the API again. Trim your Prompts — check how many tokens your system prompt has, how much of it is required every time, compress what you can — every call burns money. Cap max steps — set an upper limit on Agent loop iterations (say 10 steps), terminate if exceeded; otherwise a task it can't solve will keep burning money until timeout.

I ran a comparison myself: one Agent flow averaged $0.12 per conversation before optimization, dropped to $0.03 after. Not because the model changed — fewer calls, shorter context, unnecessary steps cut.

## Boundary Control

An Agent that agrees to everything ends up doing nothing well. A good Agent isn't omnipotent — it knows what it can't do.

Tool permission boundaries: not all tools should be open to everyone. Reading public info is fine; deleting data is not. This can't rely on Prompt constraints (the model might not comply) — permission checks must happen at the code level. Prompt injection defense: if user input contains injected content like "ignore previous instructions," your Agent might fall for it. Input filtering and instruction isolation are mandatory security measures. Capability boundaries: when an Agent encounters a problem outside its scope, it should say directly "I can't handle this" instead of fabricating an answer. This requires intent recognition at the system level — questions outside the Agent's domain get rejected or routed to a human.

The gap between running a demo and shipping to production is observability, evaluation framework, cost control, and security boundaries. None of these are sexy, but they determine whether your Agent goes from toy to product. What makes an Agent engineer valuable isn't making AI work — it's making it work reliably.
