---
title: "Breaking the ReAct Pattern — The Async Generator State Machine"
date: 2026-04-06
tags: State Machine
categories: Claude Code
lang: en
label: 077_claude-code-async-generator-state-machine
---

Claude Code doesn't use the ReAct pattern to drive its agent loop. In 2025's agent landscape, this is a surprising choice. ReAct had become the default for frameworks like LangChain and AutoGPT. But Claude Code went with an Async Generator state machine instead, replacing the traditional think-act-observe loop with a `while (true)` + `state = next` + `continue` structure. This design decision solved fundamental limitations that ReAct has with streaming interaction and fault recovery.

<!-- more -->

## Why ReAct Falls Short

ReAct's core flow is "think → act → observe → think," where each step must wait for the model to generate a complete response before moving to the next phase. This works fine in demos but exposes three structural problems in production.

The first is the serial bottleneck. Each thinking step waits for the full model output while the user watches a blinking cursor. The model is clearly streaming tokens, but tools can't start until the response finishes — which defeats much of the point of streaming. The second problem is the lack of recovery capability. When API timeouts, token overflows, or tool execution failures occur, ReAct has no unified state representation to support automatic recovery. Developers end up writing retry logic manually outside the loop. The third limitation is tool scheduling: under ReAct, tool calls are strictly serial — one tool at a time, with no way to exploit the natural parallelism between read-only tools.

Claude Code's approach was to abandon the ReAct framework entirely and rebuild the agent loop as an Async Generator state machine.

## State Machine Core Design

`src/query.ts` defines a `State` type as the state machine's core data structure, containing conversation history (`messages`), tool execution context (`toolUseContext`), auto-compression tracking (`autoCompactTracking`), output recovery count (`maxOutputTokensRecoveryCount`), turn count (`turnCount`), and other fields. This state object spans the entire agent lifecycle, and all execution logic revolves around it.

```typescript
type State = {
  messages: Message[]                    // Full conversation history
  toolUseContext: ToolUseContext          // Tool execution context
  autoCompactTracking: AutoCompactTracking  // Auto-compression tracking
  maxOutputTokensRecoveryCount: number   // Output recovery count
  hasAttemptedReactiveCompact: boolean   // Whether reactive compact was attempted
  maxOutputTokensOverride: number        // Output token override value
  pendingToolUseSummary: Promise<...>    // Pending tool summary
  stopHookActive: boolean               // Stop hook state
  turnCount: number                      // Conversation turn count
  transition: Continue | undefined       // State transition reason
}
```

The `transition` field is a detail worth highlighting. It records the reason for each state transition, enabling precise tracking during debugging and testing of why the agent moved from one state to another. The `Continue` type below defines all possible values for this field: `next_turn`, `collapse_drain_retry`, `reactive_compact_retry`, and three other reasons.

The entire agent main loop lives at lines 307–1728 of `src/query.ts`. It's a `while (true)` structure divided internally into five phases.

**Message preparation and smart compression** (lines 365–543) handles context bloat. It includes a four-level compression mechanism: Snip compression removes redundant tokens from old messages; Micro compression modifies cached message content in place; Context Collapse progressively summarizes historical messages; Auto Compact generates a complete summary via Claude. These four levels trigger progressively to ensure the context window never overflows.

**Streaming API calls** (lines 652–954) build requests and consume streaming responses. Unlike traditional ReAct, tool calls don't wait for the model to finish outputting. `StreamingToolExecutor` starts executing tools as soon as it receives streaming `tool_use` block data.

**Decision point** (lines 1062–1358) determines the current turn's direction. If the model returned tool calls, it enters the tool orchestration phase; if no tool calls, it runs Stop hooks and returns the result.

**Tool orchestration** (lines 1363–1409) partitions tool calls by side-effect profile. Read-only tools (Read, Grep, Glob, WebFetch) execute in parallel with up to 10 concurrent. Write tools (FileEdit, FileWrite, non-read-only Bash) execute serially to prevent race conditions.

**State update and loop** (lines 1704–1728) constructs the next State object, assigns it to the `state` variable, then `continue` back to the top of the loop.

```typescript
// src/query.ts:1715-1728
const next: State = {
  messages: [...messagesForQuery, ...assistantMessages, ...toolResults],
  toolUseContext: toolUseContextWithQueryTracking,
  autoCompactTracking: tracking,
  turnCount: nextTurnCount,
  transition: { reason: 'next_turn' },
}
state = next
// Back to the top of while(true)
```

What makes this loop structure work is how it's driven. No recursion, no callback nesting — just `state = next` then `continue`. The payoff: stable memory (no stack overflow), traceable state (every transition records why it happened), and controllable recovery (any phase can retry by tweaking state on error).

## Streaming-First Tool Execution

`StreamingToolExecutor` is the core component that sets Claude Code apart from ReAct. Under ReAct, tool execution must wait for the model to output a complete action instruction. Claude Code starts executing tools while the model is still streaming the `tool_use` block — no need to wait for the response to finish.

```typescript
// src/services/tools/StreamingToolExecutor.ts
class StreamingToolExecutor {
  async *processToolUseBlocks(toolUseBlocks: ToolUseBlock[]): AsyncGenerator {
    for (const block of toolUseBlocks) {
      const result = await this.executeTool(block)
      yield result
    }
  }
}
```

The effect of this design is immediately visible in comparison:

| Pattern | Tool Execution Timing | User Experience |
|---------|----------------------|-----------------|
| ReAct | Execute after full model response | Noticeable wait between turns |
| Async Generator | Execute during streaming | Near-zero perceived delay on tool calls |

At the tool orchestration level, `src/services/tools/toolOrchestration.ts` implements a partitioned scheduling strategy. When the model returns multiple tool calls in a single response, the system first splits them into read-only and write groups based on side-effect characteristics. Read-only tools (Read, Grep, Glob, WebFetch) have no side effects and can safely execute in parallel, capped at 10 concurrent. Write tools (FileEdit, FileWrite, non-read-only Bash) may modify files or system state and must execute serially to maintain sequential consistency. This partitioning happens automatically based on tool type — no manual specification from users or developers needed.

## Six Built-In Recovery Strategies

Claude Code's main loop includes six recovery strategies covering the most common failure scenarios in agent execution. Each recovery works by modifying the `state` object and calling `continue` — no loop exits or exception throws required.

| Recovery Strategy | Trigger Condition | Recovery Method |
|-------------------|-------------------|-----------------|
| `collapse_drain_retry` | Prompt too long | Drain staged context collapses, retry |
| `reactive_compact_retry` | Still too long | Generate summary via Claude, retry |
| `max_output_tokens_escalate` | Hits 8k default limit | Escalate to 64k limit, retry |
| `max_output_tokens_recovery` | Hits any output limit | Inject "continue" prompt, retry (up to 3 times) |
| `stop_hook_blocking` | Stop hook blocks | Inject blocking error into context, retry |
| `token_budget_continuation` | Budget remaining | Inject budget prompt, continue execution |

The recovery logic implementation is uniform and clean. For prompt-too-long errors, the system first tries draining all staged context collapses (`drainStagedCollapses`) to shorten the message list, then retries. If still too long, it escalates to reactive compact (`reactive_compact`), which has Claude generate summaries of historical messages to reduce token count.

```typescript
// Prompt too long recovery
if (error.type === 'prompt_too_long') {
  const compacted = drainStagedCollapses(state.messages)
  state = { 
    ...state, 
    messages: compacted, 
    transition: { reason: 'collapse_drain_retry' } 
  }
  continue
}

// max_output_tokens recovery
if (error.type === 'max_output_tokens') {
  state = {
    ...state,
    maxOutputTokensRecoveryCount: state.maxOutputTokensRecoveryCount + 1,
    transition: { reason: 'max_output_tokens_recovery' }
  }
  messages.push(createUserMessage({ content: 'Please continue.' }))
  continue
}
```

The practical effect: when a user hits token overflow in a 50-turn conversation, the system automatically triggers compression with no user-visible disruption. API timeouts trigger automatic retries. When the model hits its output limit, a "continue" prompt gets injected for automatic continuation. Throughout this process, the user almost never encounters an interruption.

## How It Differs from LangChain and LangGraph

LangChain's agent implementation is built on ReAct. Each turn is an independent LLM call, tool parsing relies on OutputParser extracting action instructions from text, and error handling requires developers to write try-catch manually. Claude Code uses Anthropic API's native `tool_use` blocks directly for tool calls — no OutputParser layer, tools execute during streaming, and six automatic recovery strategies are built in.

| Dimension | LangChain | Claude Code |
|-----------|-----------|-------------|
| Each turn | Independent LLM call | Streaming API call |
| Tool parsing | OutputParser parses text | Native `tool_use` blocks |
| Execution | Wait for complete response | Streaming, immediate execution |
| Error handling | Manual try-catch | 6 built-in recoveries |
| Parallel tools | Requires explicit orchestration | Automatic partitioned parallelism |

LangGraph, as LangChain's upgrade, introduces an explicit graph structure for state transitions. It's more formal in state management (graph nodes + edges) and supports checkpoint persistence and `interrupt_before/after` human-in-the-loop interaction. The tradeoff is needing to predefine graph structures, which increases development complexity.

| Dimension | LangGraph | Claude Code |
|-----------|-----------|-------------|
| State transitions | Explicit graph nodes + edges | Implicit state machine (while + continue) |
| Visualization | Exportable as graph structure | `transition` field provides traceability |
| Persistence | Checkpoint + State | Filesystem + message history |
| Human-in-the-loop | interrupt_before/after | Permission system + hooks |
| Multi-agent | Requires explicit orchestration | Unified AgentTool interface |

Claude Code's choice leans toward simplicity: no graph definitions, a single while loop handling all state transitions. For a product like Claude Code built around a single agent, this simplicity directly translates to lower maintenance cost and faster iteration. LangGraph's graph structure shines in scenarios requiring complex multi-branch workflows, but for "user requests → agent executes tools → returns results" linear interactions, the state machine approach is more than adequate.

## Minimal Abstraction, Native Integration

Looking at the source structure, Claude Code's agent core has just three components: one loop (`while (true)` in `query()`), one state (`State` object), and one tool interface (`Tool` type). There's no Agent → AgentExecutor → Chain → Memory → Callback nesting of abstraction layers.

On the API integration side, Claude Code uses Anthropic API's native capabilities directly: native tool calls (no OutputParser, direct `tool_use` blocks), native streaming (no wrapper layer, direct SSE stream consumption), native caching (leveraging prompt caching), and native chain-of-thought (direct use of extended thinking). This avoids the performance overhead and debugging complexity that abstraction layers like LangChain introduce between the LLM and the developer.

```typescript
type Continue = {
  reason: 'next_turn' 
    | 'collapse_drain_retry'
    | 'reactive_compact_retry'
    | 'max_output_tokens_recovery'
    | 'stop_hook_blocking'
    | 'token_budget_continuation'
}
```

The `transition` field design means every loop iteration knows why it's continuing. This isn't a decorative field — in tests it can serve directly as assertion basis, and in logs it provides a starting point for issue diagnosis. An agent system's observability often comes down to the accumulation of details like this.

## Key Source Files

| File | Lines | Responsibility |
|------|-------|----------------|
| `src/query.ts` | ~1730 | Agent main loop, state machine core |
| `src/QueryEngine.ts` | ~687 | High-level wrapper, external API |
| `src/services/tools/StreamingToolExecutor.ts` | ~200 | Streaming tool executor |
| `src/services/tools/toolOrchestration.ts` | ~150 | Tool orchestration strategy |
| `src/query/transitions.ts` | ~50 | State transition type definitions |
| `src/query/tokenBudget.ts` | ~100 | Token budget management |
| `src/query/stopHooks.ts` | ~200 | Stop hook handling |

---

**Series Navigation:**
- Previous: [Why Claude Code Doesn't Use LangChain: Technical Considerations Behind a Custom Architecture](/2026/04/07/090_claude-code-why-no-langchain/)
- Next: [Tool System Design: The Seven-Step Pipeline from Definition to Execution](/2026/04/06/087_claude-code-tool-system/)
