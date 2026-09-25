---
title: "Beyond Prompts: The Agent Runtime"
date: 2026-04-06
tags: Code Agent
categories: Claude Code
lang: en
label: 088_claude-code-why-better
---

## Same Model, Different Experience

Here's an odd thing: use GPT-4 with OpenAI's Codex CLI and you get decent results. Use GPT-4 with Anthropic's Claude Code and you get better results. You'd expect a model plus its own vendor's agent to be the best combo — but it actually underperforms paired with a competitor's agent.

The common assumption is that Claude Code just has a better prompt. Prompts matter, but they're not the deciding factor. Claude Code's source reveals something more fundamental: it's not a prompt wrapper. It's a full agent runtime. This framework understands the model's capability boundaries, tool execution risks, context compression strategies, and intent flow. The model is the brain, and Claude Code is the body. The analogy is rough, but it captures the core relationship.

<!-- more -->

## Competitive Landscape

The current market of AI code agents splits into two categories: terminal-based CLI tools and AI-native IDEs.

| Product | Company | Form Factor | Core Characteristic |
|---------|---------|-------------|---------------------|
| Claude Code | Anthropic | CLI | Agent runtime, MCP extensible |
| Codex CLI | OpenAI | CLI | Direct competitor, GPT-model driven |
| Cursor | Anysphere | AI IDE | VS Code fork, deep context awareness |
| Trae | ByteDance | AI IDE | Adaptive learning |
| GitHub Copilot | Microsoft | IDE Extension | Industry pioneer, mature ecosystem |
| Qoder | Alibaba Cloud | IDE Extension | Tongyi Lingma, Alibaba Cloud ecosystem |

Claude Code and Codex CLI are direct competitors, both terminal-based CLI tools. The IDE products (Cursor, Trae, Copilot, Qoder) have different interaction patterns, but they all face similar agent engineering challenges under the hood.

## State Machine vs. ReAct

Most code agents use the ReAct (Reasoning + Acting) pattern: Thought → Action → Observation loop. It's simple and intuitive, but has three structural problems: it's prone to infinite thought loops, lacks recovery mechanisms after tool failures, and context grows unboundedly until truncation.

Claude Code replaces the ReAct loop with an Async Generator state machine. Each `step()` call advances one state with clear boundaries — no infinite looping. The state machine has six built-in error recovery strategies: after a tool failure, it can automatically retry, degrade, or fall back. The generator pattern natively supports streaming interaction, where model output and tool execution can interleave without waiting for a complete Thought-Action-Observation cycle.

| Feature | ReAct Pattern | State Machine Pattern |
|---------|---------------|-----------------------|
| Infinite loop risk | High (unbounded loop) | Low (state transitions have endpoints) |
| Error recovery | None (failure = termination) | Yes (6 recovery strategies) |
| Streaming interaction | Difficult (must wait for full cycle) | Native (Generator) |
| Context management | Simple truncation | Four-level compression |

## The Safety Pipeline for Tool Execution

Most agents execute tools directly: pass parameters, run, return results. No validation, no permission checks, no post-processing. This works in controlled environments, but it's risky in real development scenarios — a wrong `rm -rf` command can cause irreversible damage.

Claude Code's tool execution goes through a seven-step pipeline: lookup → input parsing (Zod schema) → custom validation → pre-tool hook → permission check (five-layer decision chain) → actual execution → post-tool hook. Validation runs before permissions, ensuring invalid input never triggers permission dialogs. Permissions intercept dangerous operations before execution. Hooks let users inject custom logic at any stage.

The lazy tool loading mechanism further reduces token overhead. The schemas for 48+ built-in tools total around 15,000 tokens. With lazy loading, the initial prompt only contains core tools (about 5,000 tokens), saving 66%. Infrequently used tools load their full schema on demand through ToolSearch.

The MCP protocol provides unlimited extensibility. Any developer can write an MCP Server in any language to extend the agent's toolset. This open architecture means Claude Code's capabilities are no longer bounded by its built-in tool count.

## Four-Level Context Compression

Most agents manage context with brute-force truncation: when you exceed the token limit, discard the oldest messages. It's simple but brutal — important information gets lost, and the model "forgets" earlier key decisions.

Claude Code uses four-level progressive compression, triggered from lightest to heaviest: Snip (deduplication truncation, automatic each turn) → Micro (in-place optimization of cached content) → Context Collapse (progressive segmented summarization, processing oldest messages first) → Auto Compact (model generates a global summary, replacing all history). Each level preserves information useful to the task (decisions, file modifications, action items) rather than simply discarding it.

This compression mechanism makes long conversations viable. In coding sessions exceeding 50 turns, the first two compression levels typically recover enough space. Only exceptionally long tasks trigger the latter two levels. The compressed context still supports continued work because critical information survives in summaries.

## Multi-Agent Collaboration

Most code agents use a single-agent design: one model plus one toolset handles everything. Complex tasks resist decomposition, a single model gets stuck in fixed thinking patterns, and there's no way to parallelize.

Claude Code defines four agent spawning methods: Subagent (synchronous/asynchronous child agents, short-lived), Fork (inherits parent agent context, shares prompt cache), Teammate (independent context, asynchronous communication via mailbox), Remote (CCR environment remote execution). The Fork Agent's byte-level identical prefix design lets multiple child agents share the same prompt cache, cutting token consumption significantly. Teams mailbox communication supports parallel task distribution and result aggregation.

Combining these four methods covers everything from simple subtasks to complex parallel collaboration. An Explore Agent scans the codebase, multiple Fork Agents modify files in parallel, a Plan Agent coordinates ordering, and a Verification Agent runs tests. This is a complete collaboration framework, not simple task dispatch.

## Layered Permission Control

Most agents implement security as a simple allow/deny toggle. Once you grant dangerous command permissions, everything is allowed. Turn it off and everything is blocked. There's no middle ground.

Claude Code's five-layer permission decision chain (rules → mode → hooks → classifier → user confirmation) provides fine-grained control. `git status` is automatically allowed (Git whitelist). `rm -rf node_modules` requires confirmation (dangerous command). `rm -rf /` is always rejected (deny rule). Writing to `.git/config` is rejected (sensitive path). Every decision has an audit trail for debugging.

In `auto` mode, the AI classifier can automatically judge operation safety. Scores above 0.8 get auto-approved, below 0.2 get auto-rejected, and the middle range asks the user. After three consecutive rejections, it falls back to user approval to prevent rejection loops.

## Memory System

Most agents start from zero every conversation. Users need to repeatedly explain the same background information.

Claude Code's Memory system categorizes knowledge into four types: User (user profile), Feedback (behavioral feedback), Project (project dynamics), and Reference (external references). Memories persist in YAML frontmatter + Markdown format. An automatic extraction mechanism analyzes and saves valuable information after conversations end. Smart retrieval uses the Sonnet model to dynamically select relevant memories, and freshness warnings annotate older memories with timeliness reminders.

This system lets the agent accumulate knowledge across sessions. User coding preferences, project architecture decisions, team work assignments — none of this needs to be repeated every time. Memory remembers it.

## Channel Remote Control

Most agents only work in a local terminal. Users must sit at their computer for the agent to work.

Claude Code's Channel system supports remote control through IM tools like Telegram. Users issue commands from their phone, the agent executes on the local computer, and results come back to the IM. Six layers of access control (capability declarations, runtime switches, OAuth authentication, organization policies, session whitelists, Marketplace verification) ensure security.

This design removes the geographic constraint on agents. You can dispatch tasks remotely when you're out, approve operations from your phone for urgent fixes, and receive progress updates through IM in real time.

## Terminal UI

Most agents render to plain stdout output. When information density is high, it's hard to read, and there's no way to make interactive selections.

Claude Code builds its terminal UI with React + Ink. The Yoga engine provides Flexbox layout, double-buffered rendering eliminates flicker, and componentized design (Header, MessageList, ToolBar, ContextPanel, InputBox, PermissionDialog) delivers structured display. Keyboard navigation supports interactive selection, and permission dialogs let users approve operations one by one.

## System Prompt Cache Optimization

Most agents use static system prompts sent in full with every request — no caching.

Claude Code's system prompt runs about 20k tokens, split into static and dynamic regions by cache boundary markers. The static region (role definition, rules, tool descriptions) shares a global cache across all users. The dynamic region (date, Git status, MCP instructions, CLAUDE.md) caches at the session level. A three-tier cache hierarchy (Global → Ephemeral → Section) covers different time scales.

The practical effect: static region cache hit rate approaches 100%, and the dynamic region maintains high hit rates when CLAUDE.md doesn't change. Per-session latency and API costs drop significantly as a result.

## What Sets It Apart

Claude Code's competitive advantage isn't any single feature — it's the depth of systems engineering. State machine architecture replaces ReAct loops. Seven-step tool pipelines replace bare execution. Four-level compression replaces brute-force truncation. Five-layer permissions replace simple toggles. A memory system replaces starting from zero every time. Every design decision points at the same goal: making the agent work reliably in real development scenarios.

These mechanisms aren't individually complex, but together they form a complete runtime framework. Other agents provide an interface to a model. Claude Code provides an environment for running a model.

---

**Series Navigation:**
- Series start: [Claude Code Architecture Overview](/2026/04/07/089_claude-code-architecture-overview/)
