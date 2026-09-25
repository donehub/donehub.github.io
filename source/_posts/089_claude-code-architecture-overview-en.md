---
title: "Claude Code Architecture Overview"
date: 2026-04-07
tags: Architecture
categories: Claude Code
lang: en
label: 089_claude-code-architecture-overview
---

On March 31, 2026, Anthropic's Claude Code source code was accidentally leaked. As one of the most widely used AI coding assistants, the leak gave the community its first real look at how this kind of product is built. After reading through it, the architecture differs significantly from what most people assume. Most developers assumed it was just a thin CLI wrapper around API calls. The actual codebase and engineering depth say otherwise.

<!-- more -->

## Tech Stack and Project Structure

Claude Code's technology choices are restrained — it doesn't pull in excessive dependencies. The runtime uses Bun instead of Node.js. The terminal UI layer combines React + Ink — the entire terminal interface is actually rendered as a React component tree. CLI argument parsing uses Commander.js. The API layer interfaces directly with the Anthropic SDK. Protocol support includes MCP and LSP.

| Category | Technology | Notes |
|----------|------------|-------|
| Runtime | [Bun](https://bun.sh) | High-performance JavaScript runtime |
| Language | TypeScript | Type safety |
| Terminal UI | React + [Ink](https://github.com/vadimdemedos/ink) | React syntax for terminal apps |
| CLI Parsing | Commander.js | Command-line argument handling |
| API | Anthropic SDK | Native API integration |
| Protocols | MCP, LSP | Model Context Protocol, Language Server Protocol |

The choice of Bun over Node.js is worth noting. Bun has clear advantages in startup speed and runtime performance. For a CLI tool that needs to respond quickly, startup latency directly shapes the user's first impression. This choice tells you the team had explicit requirements about terminal experience responsiveness.

### Directory Structure

The project contains 1,356 TypeScript files with source code organized by functional domain. Key directories include: `query/` (query loop core), `tools/` (48+ built-in tools), `context/` (context management), `state/` (state management), `memdir/` (memory system), `skills/` (Skills system), `plugins/` (plugin system), `hooks/` (React Hooks), `services/` (core service layer), `components/` (React UI components), `constants/` (system prompts, constants), `coordinator/` (coordinator mode), `bridge/` (remote bridging), `vendor/` (Computer Use integration), and more.

The directory layout reveals several design tendencies. `query/` and `tools/` are the core modules, corresponding to the agent's main loop and tool execution capabilities. The separate existence of `context/`, `state/`, and `memdir/` shows that context management, state management, and the memory system are treated as three distinct concerns rather than lumped together. `skills/`, `plugins/`, and `hooks/` are each independent — the extension mechanism is split into multiple layers rather than a single universal plugin system.

## Core Architecture

Claude Code's execution flow can be summarized as: user input goes through QueryEngine processing, then enters the core `query()` loop. This loop internally completes five phases: message compression, streaming API calls, decision-making, tool orchestration, and state updates. Downstream of the loop sit three subsystems: the tool system (48+ built-in tools, MCP dynamic tools, three-layer filtering, seven-step execution pipeline), the multi-agent system (Subagent, Fork, Teammate, Remote), and the extension ecosystem (Skills, Plugins, Hooks, MCP protocol).

The core idea behind this architecture: the model itself only handles reasoning and decision-making. All execution capabilities, state management, and error recovery are handled by the external loop mechanism. The model is the brain; the query loop is the body. The brain decides what to do; the body handles how to do it and what to do when things go wrong.

### Three Core Design Principles

After reading through the source code, three principles organize the entire architecture.

**Streaming first.** The architecture is built on AsyncGenerator. Model responses are streamed, tools start executing while the model is still generating, progress updates in real time, and compression strategies are progressive. What users experience: the model is thinking while tools are already running — no waiting for a complete response before the next action kicks off. This is fundamentally different from a traditional request-response pattern.

**Tool-driven.** Claude Code's philosophy is unifying everything as a tool. Sub-agent spawning is a tool (AgentTool). Team management is tools (TeamCreate/SendMessage). File editing is a tool (FileEdit). Skill execution is a tool (SkillTool). This means there's no explicit orchestration logic coordinating these capabilities — the model decides which tool to call through natural language reasoning. The model itself is the orchestrator. The advantage: adding new capabilities only requires implementing a tool interface, with no changes to orchestration code.

**Graceful degradation.** AI tools in production face all kinds of failures: token overflow, API timeouts, abnormal model responses, tool execution failures. Claude Code has six built-in recovery strategies. Token overflow triggers automatic compression. API timeouts trigger automatic retries. Model failures degrade to a backup model. Tool failures log the error and continue the conversation. This mechanism ensures most technical exceptions don't directly interrupt the user's workflow — they get silently handled or degraded.

## Core Modules

### query.ts: The Agent's Main Loop

`src/query.ts` is the agent's core file, roughly 1,730 lines. It implements a streaming state machine, not a simple think-act-observe loop. The loop drives state transitions through `state = next` assignment rather than recursive calls. Recursive calls risk stack overflow at deep nesting levels. Assignment-driven loops keep memory usage stable. Each round's state transition reason gets recorded in the state object, making it possible to trace the entire execution path during debugging. Any phase error can trigger recovery strategies by modifying state, without needing a separate exception handling framework.

```typescript
export async function* query(params: QueryParams): AsyncGenerator<...> {
  let state: State = {
    messages, toolUseContext, autoCompactTracking,
    maxOutputTokensRecoveryCount, hasAttemptedReactiveCompact,
    maxOutputTokensOverride, pendingToolUseSummary,
    stopHookActive, turnCount, transition,
  }

  while (true) {
    // Phase 1: Message compression
    // Phase 2: Streaming API call
    // Phase 3: Decision point
    // Phase 4: Tool execution
    // Phase 5: State update
    state = next  // Loop driven by assignment, not recursion
    continue
  }
}
```

### Tool.ts: Tool Type Definitions

`src/Tool.ts` defines the complete tool interface in roughly 792 lines. Every tool must declare its identity, capabilities, lifecycle, and output format. This interface design makes each tool a self-describing, self-validating, self-rendering unit. The framework doesn't need to know a tool's internal logic — it calls standard interfaces.

The `isReadOnly` and `isConcurrencySafe` declarations are especially important. The framework uses them to decide which tools can run in parallel and which must be serialized. Tool authors only need to honestly declare their capabilities — concurrency control is entirely the framework's responsibility.

```typescript
type Tool<Input, Output> = {
  name: string
  aliases?: string[]        // Backward-compatible old names
  searchHint?: string       // ToolSearch keyword matching

  // Capability declarations
  isEnabled(): boolean
  isConcurrencySafe(input): boolean
  isReadOnly(input): boolean
  isDestructive(input): boolean

  // Lifecycle
  validateInput(input, context)
  checkPermissions(input, context)
  call(input, context, ...)

  // Output and rendering
  renderToolUseMessage(input)
  renderToolResultMessage(content)
  mapToolResultToToolResultBlockParam()

  // Smart features
  inputSchema: Zod schema
  maxResultSizeChars: number
  getToolUseSummary?(input): string
}
```

### System Prompt Assembly

`src/constants/prompts.ts` (about 577 lines) implements a layered pipeline for assembling the system prompt. The entire prompt is divided into two regions with a cache boundary between them. The static region contains role definition, system rules, task guidance, tool descriptions, and style constraints. The dynamic region contains session guidance, memory system, environment info, MCP instructions, and token budget.

The cache boundary design directly impacts costs. Content above the boundary stays essentially unchanged across users and sessions. With `scope: 'global'` caching, those tokens are billed only once across multiple calls. Content below the boundary differs per session and uses `scope: 'ephemeral'` caching. This split keeps cache hit rates high. Most of the system prompt's volume is in the static region — only a small amount of dynamic content needs recalculation each time.

## Architectural Differences from LangChain/ReAct

Before reading Claude Code's source, I assumed it used the classic ReAct pattern: model thinks, then acts, then observes results, then enters the next thought cycle. This pattern is widely used in frameworks like LangChain and forms the basis for most current AI agent implementations. But Claude Code doesn't use it.

| Dimension | LangChain | Claude Code |
|-----------|-----------|-------------|
| Core pattern | ReAct (Think→Act→Observe) | Async Generator state machine |
| Execution model | Synchronous blocking | Streaming non-blocking |
| Tool execution | Execute after full model response | Immediate execution during streaming |
| State management | External Memory object | Built-in state assignment + loop |
| Error recovery | Manual orchestration needed | 6 built-in recovery strategies |
| Context compression | Simple truncation or summary | Four-level progressive compression |
| Multi-agent | Chain/Graph explicit orchestration | Unified tool interface + state machine |
| Extension mechanism | Python class inheritance | Skills + Plugins + Hooks + MCP |
| Caching strategy | None | Three-tier: global/session/per-turn |

### Limitations of the ReAct Pattern

The fundamental problem with ReAct is its serial nature. Every step must wait for the model to complete its full thought process before executing tools, getting results, and entering the next round. When task complexity is low, this latency is acceptable. But when the agent needs to call multiple tools in sequence and process large amounts of context, the per-step wait accumulates into a significant UX problem.

Another issue is cache friendliness. Each round in ReAct mode has substantial prompt structure changes (because the previous round's tool execution results get appended to context), making API-level prompt caching hard to hit. Under token-based billing, this means linear cost growth.

Claude Code's AsyncGenerator pattern makes different tradeoffs on these problems: tools start executing during the model's streaming output (no need to wait for the full response), the state object contains all needed context information (recovery just means modifying state), and the static prompt region goes through global caching (reducing repeated call costs). These design choices give it better response speed and cost structure than traditional ReAct implementations in complex task scenarios.

ReAct does have its advantages: clear logic, easy to understand, simple to debug. Claude Code's architecture carries higher complexity and a correspondingly higher learning curve. For simple agent scenarios, ReAct may be sufficient.

## Key Source Files

| Component | File Path | Lines | Description |
|-----------|-----------|-------|-------------|
| Core loop | `src/query.ts` | ~1730 | Agent main loop, state machine implementation |
| Query engine | `src/QueryEngine.ts` | ~687 | High-level wrapper, parameter assembly |
| Tool definition | `src/Tool.ts` | ~792 | Tool type system |
| Tool registration | `src/tools.ts` | ~389 | Tool discovery and registration |
| System prompt | `src/constants/prompts.ts` | ~577 | Layered prompt assembly |
| Context management | `src/context.ts` | ~300 | System/user context |
| Agent spawning | `src/tools/AgentTool/AgentTool.tsx` | ~600 | Agent tool entry point |
| Skill system | `src/skills/bundledSkills.ts` | ~300 | Skill registration and management |
| Permission system | `src/utils/permissions/permissions.ts` | ~500 | Permission checks |
| State management | `src/state/AppStateStore.ts` | ~400 | Global state |

## Wrapping Up

Back to the original question: what exactly is Claude Code? At the architecture level, its core reduces to three parts. A `while (true)` driven state machine. A State object carrying all context. A Tool interface unifying all capabilities. There's no LangChain-style multi-layer nested abstraction (Agent → AgentExecutor → Chain → Memory → Callback). The call chain stays relatively flat.

This design gives the code clear advantages in understandability and debuggability. The tradeoff is that the core loop takes on too many responsibilities. The 1,730 lines in query.ts simultaneously handle compression, API calls, decision-making, execution, and state management. If any one of these areas grows more complex, this file becomes a maintenance bottleneck.

Future posts will dive deeper into specific key modules.

---

**Series Navigation:**
- Next: [Why Claude Code Doesn't Use LangChain: Technical Considerations Behind a Custom Architecture](/2026/04/07/090_claude-code-why-no-langchain/)
