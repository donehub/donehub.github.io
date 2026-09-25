---
title: "Why Claude Code Doesn't Use LangChain"
date: 2026-04-15
tags: Architecture
categories: Claude Code
lang: en
label: 090_claude-code-why-no-langchain
---

After Anthropic open-sourced Claude Code, a common question from the community was: why not use LangChain or LangGraph? These two frameworks are the de facto standard in agent development. Building something from scratch instead of using them must have a reason. After reading the source, the reasons are more specific than most people guess. It's not that these frameworks are bad — Claude Code's product form and LangChain's design assumptions are just fundamentally mismatched.

<!-- more -->

## Product Form Determines Architecture

Before getting into the technical analysis, it's worth clarifying the most fundamental difference between Claude Code and most agents built with LangChain. LangChain addresses this scenario: a developer builds an application, a user submits a request, the application returns a result. The entire process follows a request-response model where second-level latency is perfectly acceptable.

Claude Code faces a completely different scenario: the user works in a continuously interactive terminal. Every keystroke, every command expects immediate feedback. While the model is thinking, the user needs to see progress in real time. Tool call results need to appear on the terminal within milliseconds. This is a latency-sensitive CLI interaction scenario, not a web application where you can afford to wait.

This difference in product form directly drives the architectural fork.

## The Serial Problem with ReAct

LangChain and LangGraph both base their core execution logic on the ReAct pattern (Reasoning + Acting): the model completes a full round of thinking, outputs which tools and parameters to call, the framework parses that output, executes the tools, appends results to context, and feeds it back to the model for the next round. The loop is logically clean, but it has an inherent problem. Every step is serial. The model must wait for tool execution to finish before continuing to think. The user must wait for the model's complete output before seeing tools start running.

For web applications or background batch processing, this serial execution doesn't create noticeable experience issues. But in a CLI interaction scenario, the user stares at the terminal waiting for the model's complete output, then waits for tools to start executing. That dead time directly affects the experience. As task complexity increases and multiple tools need to be called in sequence, this waiting compounds into significant latency.

### The Streaming State Machine

Claude Code implements a streaming state machine using AsyncGenerator. The core logic lives in `src/query.ts`, roughly 1,730 lines. It uses a `while (true)` loop with state assignment to drive the entire agent:

```typescript
export async function* query(params: QueryParams): AsyncGenerator<QueryUpdate> {
  let state: State = {
    messages: [...],
    toolUseContext: {...},
    turnCount: 0,
    transition: undefined,
  }

  while (true) {
    // Phase 1: Message compression (automatic Token overflow handling)
    // Phase 2: Streaming API call (immediate tool execution)
    // Phase 3: Decision point (continue or stop)
    // Phase 4: Tool orchestration (parallel for reads, serial for writes)
    // Phase 5: State update

    state = next  // Loop driven by assignment
    continue
  }
}
```

The key difference: tools don't wait for the model to finish outputting before they start executing. During the model's streaming output, as soon as a complete `tool_use` block is detected, execution triggers immediately. What users perceive is that model thinking and tool execution happen simultaneously, not sequentially.

### StreamingToolExecutor

This capability is powered by the StreamingToolExecutor. As the model begins streaming output, the Executor parses the output stream in real time. Once it identifies a complete `tool_use` block (tool name and parameters both present), it immediately starts tool execution without waiting for the model's current turn to finish.

The latency difference is clear. ReAct's total latency is the sum of model generation time and tool execution time. Claude Code's latency is the maximum of the two, because their execution timelines overlap. While the model is still generating subsequent text, the Read tool is already reading files. For tasks requiring multiple sequential tool calls, this difference gets amplified.

## API Native Feature Utilization

### The Adaptation Cost of General Frameworks

LangChain needs to support model APIs from OpenAI, Anthropic, Google, and others, so it builds an abstraction layer between them. This abstraction's value is reducing the cost of switching model providers. The price is that each provider's unique capabilities get flattened or delayed in support.

Anthropic's API has several capabilities that Claude Code relies on heavily:

| Feature | Description | Significance for Claude Code |
|---------|-------------|------------------------------|
| Prompt Caching | Prompt cache; ~90% token cost reduction on cache hits | Large system prompt means caching directly affects costs |
| Native tool_use blocks | Structured tool call blocks directly in model output | No text parsing needed; more reliable than OutputParser |
| Native streaming tool_use | Tool call blocks can trigger immediately during streaming | Core capability enabling streaming execution |
| Extended Thinking | Chain-of-thought output | Visualization of reasoning for complex tasks |

LangChain eventually added support for these features, but the timeliness and precision lag behind native integration. Take Prompt Caching as an example: when Anthropic launched this capability in late 2024, LangChain took weeks to adapt, and the initial implementation had imprecise cache boundary划分.

### Concrete Benefits of Native Integration

Claude Code uses the Anthropic SDK directly, giving precise control over cache boundary placement. The system prompt is split into two regions: the static region (role definition, system rules, tool descriptions) uses global caching, and the dynamic region (current environment, user memory) uses session-level caching.

```typescript
// Static cacheable region - reused across sessions
const systemPrompt = {
  type: 'text',
  text: `...`,
  cache_control: { type: 'ephemeral' }
}

// Dynamic region - differs per session
const dynamicPrompt = {
  type: 'text',
  text: `...`,
  cache_control: { type: 'ephemeral' }
}
```

The first call bills at full token cost. On subsequent calls, the static region is fully cached. Given that Claude Code's system prompt typically runs tens of thousands of tokens, this caching mechanism has a major cost impact.

For tool calls, Anthropic API's native `tool_use` blocks mean Claude Code doesn't need any text parsing. The model output directly contains structured tool names and parameters that the framework can execute immediately. When LangChain lacked native tool_use support, it needed an OutputParser to extract tool call information from the model's natural language output. That parsing process is inherently fragile — slight format variations from the model can cause parse failures.

## Performance: The Cost of Abstraction Layers

A single LangChain agent call passes through this abstraction chain from user code to actual API request: User Code → Chain → AgentExecutor → LLM → Memory → Tools → OutputParser → API Call. Each layer has its own processing logic: parameter validation, state serialization, callback triggering, logging. For web applications, this overhead is a small fraction of the total request cycle. But CLI interaction scenarios have very low latency tolerance — every second the user waits in the terminal is perceptible.

Claude Code's call chain is: User Input → query() AsyncGenerator → Anthropic SDK → Tool Execution. No intermediate abstraction layers. API responses stream directly to the rendering layer, and tool execution results flow back in real time.

### Tool Orchestration Concurrency Strategy

Claude Code implements automated concurrency control in tool orchestration. The framework checks each tool's `isReadOnly` and `isConcurrencySafe` declarations to determine which tools can run in parallel and which must be serial. Read-only tools (Read, Grep, Glob, WebFetch) run in parallel by default. Write tools (FileEdit, Write, Bash) are strictly serial.

LangChain executes all tools serially by default. Parallel execution requires manual developer configuration. This difference becomes significant with many tools: a task that needs to read five files simultaneously gets done in parallel by Claude Code, while LangChain waits through five serial reads by default.

## Controllability: The Precision of Building Your Own

When using LangChain or LangGraph, the framework's internal decision processes are opaque to developers. Tool execution order, error recovery strategies, token overflow handling — these critical behaviors are encapsulated inside the framework. Developers can only adjust through limited configuration interfaces. When you hit an edge case the framework doesn't cover, you're stuck either working around the framework or waiting for an update.

Claude Code chose to build from scratch, trading that effort for control precision at every stage.

**Permission system.** Tool permission checks aren't a simple allow/deny toggle. It's a four-stage decision pipeline: deny rules at highest priority, then the tool's own permission check, then allow rule matching, and finally asking the user. This pipeline can control down to specific operation types within specific tools.

```typescript
async function checkPermissions(tool, input, context) {
  if (matchesDenyRule(tool.name)) return { behavior: 'deny' }
  if (tool.checkPermissions) {
    const result = await tool.checkPermissions(input, context)
    if (result.behavior !== 'passthrough') return result
  }
  if (matchesAllowRule(tool.name, input)) return { behavior: 'allow' }
  return { behavior: 'ask' }
}
```

**Context compression.** When conversation history exceeds the token limit, Claude Code uses four-level progressive compression: first remove redundant content from old messages (Snip), then modify already-cached message content (Micro), then progressively summarize historical messages (Collapse), and finally generate a complete summary through the model (Auto Compact). Each level differs in compression intensity and cost. The system automatically selects the appropriate level based on current context length. LangChain's default approach is truncation or simple summary — there's a precision gap.

**Hook system.** Users can inject custom logic before and after tool execution (run safety checks before Bash execution, run tests after FileEdit). This mechanism is configured through settings.json with no source code changes needed. Implementing the same in LangChain requires class inheritance or callback wrapping — higher complexity.

## Capability Mapping

LangChain and LangGraph provide certain capabilities. Claude Code replaces each with its own implementation:

| LangChain/LangGraph Capability | Claude Code's Replacement | Corresponding File |
|-------------------------------|---------------------------|--------------------|
| Agent loop (ReAct) | AsyncGenerator state machine | `src/query.ts` |
| Tool definition | Tool type + buildTool() | `src/Tool.ts` |
| Memory | Channel system + file memory | `src/state/`, `src/memdir/` |
| OutputParser | Native tool_use blocks | No parsing needed |
| Callbacks | Hook system | `src/hooks/` |
| StateGraph (LangGraph) | State object + state assignment | `src/query.ts` |
| Checkpoint (LangGraph) | Message history + filesystem | `src/assistant/` |
| Multi-agent orchestration | AgentTool + sub-agent system | `src/tools/AgentTool/` |

Claude Code didn't build from scratch because it was missing capabilities. Everything LangChain can do, it can do too — just differently. The differences lie mainly in execution model (streaming vs. serial), control precision (native integration vs. framework abstraction), and performance characteristics (zero intermediate layers vs. multi-layer abstraction).

## When You Should Use LangChain

After discussing Claude Code's choices, it's worth stating objectively: not using LangChain doesn't mean LangChain is bad. Claude Code's custom-built path has prerequisites: a top-tier engineering team capable of maintaining a custom architecture, support for only a single model API, and a product form that's extremely latency-sensitive.

If your scenario doesn't meet these conditions, LangChain or LangGraph is probably the better choice. Small teams doing rapid validation benefit from LangChain's out-of-the-box capabilities, saving significant infrastructure setup time. When you need multi-model support, LangChain's model abstraction layer is a genuine advantage. For latency-insensitive web applications, ReAct's serial problem has minimal impact. When you need to visualize agent flows, LangGraph's StateGraph has a ready-made solution. Without a dedicated infrastructure team, building from scratch means handling error recovery, caching strategies, permission control, and all the details yourself.

Claude Code chose to build from scratch because its product positioning and team conditions made the investment worthwhile. For most teams, using LangChain to focus energy on business logic rather than reimplementing an agent framework is probably the more pragmatic choice.

## Wrapping Up

The core reason Claude Code doesn't use LangChain comes down to a mismatch between product form and framework design assumptions. LangChain is designed for general agent development scenarios, pursuing cross-model compatibility and development efficiency. Claude Code targets a specific CLI interaction scenario, pursuing maximum response speed and control precision. The former is a general-purpose tool. The latter is a specialized system optimized for a specific use case.

There's no absolute right or wrong here. The key judgment is whether your product form justifies building a dedicated agent framework. If the answer is yes, Claude Code's path provides a reference. If the answer is no, LangChain remains the more efficient starting point.

---

**Series Navigation:**
- Previous: [Claude Code Architecture Overview](/2026/04/07/089_claude-code-architecture-overview/)
- Next: [Breaking the ReAct Myth: Async Generator State Machine](/2026/04/06/077_claude-code-async-generator-state-machine/)
