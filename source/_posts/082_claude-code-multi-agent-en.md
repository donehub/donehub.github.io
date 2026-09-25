---
title: Four Paths for Multi-Agent Orchestration
date: 2026-04-06
tags: Multi-Agent
categories: Claude Code
lang: en
label: 082_claude-code-multi-agent
---

## The Single-Agent Bottleneck

Consider a typical scenario: migrate all TypeScript files in a project to strict mode, update ESLint config, then run tests to confirm no regressions. A single agent can only execute sequentially — modify tsconfig, modify ESLint, modify files, run tests, each step waiting for the previous one to finish. For a project with 200 files, this could take over ten minutes.

Multi-agent orchestration breaks this kind of task into parallelizable subtasks. An Explore Agent scans files to identify modification points, multiple Fork Agents modify different file groups in parallel, a Plan Agent coordinates order to avoid conflicts, and a Verification Agent runs tests to validate results. Parallelization, specialization, isolation — that's what multi-agent orchestration is for.

<!-- more -->

## Agent Types and Responsibilities

Claude Code defines four agent generation methods and five built-in roles.

The four generation methods determine an agent's runtime environment and isolation level:

| Generation Method | Context Source | Execution Environment | Communication |
|-------------------|----------------|------------------------|---------------|
| Subagent | Independent context | Sync/async execution | Return value passing |
| Fork | Inherits parent agent context | Shares prompt cache | Return value passing |
| Teammate | Independent context | tmux/iTerm2/in-process | Mailbox communication |
| Remote | Independent context | CCR environment | Polling results |

The five built-in roles define tool permissions and behavioral boundaries:

| Role | Purpose | Tool Pool |
|------|---------|-----------|
| General Purpose | General tasks | All tools |
| Explore | Codebase exploration | Read, Grep, Glob, WebSearch |
| Plan | Planning | All tools, restricted output |
| Verification | Result validation | Bash, Read, Grep |
| Coordinator | Orchestration | Restricted tool set |

Agent definitions follow a unified structure:

```typescript
type AgentDefinition = {
  agentType: string                       // Type identifier
  description: string                     // Description
  getSystemPrompt: (context) => string    // System prompt
  tools?: string[]                        // Allowed tools ('*' = all)
  disallowedTools?: string[]              // Forbidden tools
  model?: string                          // Model selection
  permissionMode?: PermissionMode         // Permission mode
}
```

## Four Generation Paths

All agent generation enters through `AgentTool.call()`, routing to four different paths based on input parameters.

**Teammate Generation** — Triggered when both `team_name` and `name` are present. The system detects the execution backend (tmux/iTerm2/in-process), generates a unique agentId, assigns UI colors, creates the execution environment, then updates the TeamFile. In-process teammates use independent AbortController and AsyncLocalStorage for context isolation, but share the permission pipeline.

**Async Subagent** — Triggered when `run_in_background=true` or `background: true` in the Agent definition. The system creates a LocalAgentTask, registers it with agentNameRegistry, creates an AbortController, then executes asynchronously. During execution, ProgressTracker monitors progress. On completion, it extracts results, marks complete, cleans up the worktree, and notifies the main agent.

**Fork Subagent** — Triggered when `subagent_type` is omitted and the Fork experiment is enabled. This is the most performant path, achieving prompt cache hits by constructing byte-identical API request prefixes. The Fork subagent retains the parent agent's complete assistant messages, creates placeholder tool_results for each tool_use, then appends a unique per-child directive. Byte-identical prefixes mean the API's prompt cache can be reused directly — no recalculation overhead.

Fork subagents have strict behavioral constraints: no conversation, no questions, no follow-up suggestions, call tools directly, no text output between tool calls, responses must start with "Scope:", reports limited to 500 words. These constraints ensure Fork is an efficient worker process, not a conversational partner.

**Sync Subagent** — The default path. The system resolves the Agent definition, builds the system prompt, creates an isolated ToolUseContext, starts the query loop, and returns the final result.

## Three-Layer Tool Pool Filtering

Which tools each agent can use is determined by three layers of filtering.

The first layer is global prohibition. TaskOutput, ExitPlanMode, EnterPlanMode, AskUserQuestion, TaskStop, and Agent — these six tools are forbidden for all subagents. The first five can only be operated by the main agent, and Agent is disabled to prevent recursive generation.

The second layer is agent type filtering. Async agents are limited to 15 tools (Read, Grep, Glob, Bash/PowerShell, FileEdit, FileWrite, WebSearch, WebFetch, TodoWrite, NotebookEdit, Skill, SyntheticOutput, ToolSearch, EnterWorktree, ExitWorktree), with MCP tools always allowed.

The third layer is agent definition filtering. If a `tools` list is defined, take the intersection; if `disallowedTools` is defined, take the difference; if `tools: ['*']` or undefined, wildcard allows all.

## Context Passing and Isolation

Context passing between agents needs to balance sharing and isolation.

Fork Agent's design goal is maximizing cache sharing. It maintains byte-identical prefixes in API requests (system prompt, user context, system context, tool configuration, conversation history, parent agent's assistant messages and placeholder tool_results), with only the trailing per-child directive differing. This means multiple Fork subagents can share the same prompt cache, significantly reducing token consumption and response latency.

Subagent's design goal is default isolation with explicit sharing. Message history is independent, file read cache is independent, content replacement state is independent, AbortController is independent but linked to the parent (parent cancellation cascades to children). If a child agent needs to affect parent state, it must be explicitly opt-in via parameters like `shareSetAppState`.

| Resource | Default Behavior | Notes |
|----------|------------------|-------|
| readFileState | Cloned | File read cache is independent |
| messages | New | Message history is independent |
| abortController | New (linked to parent) | Parent cancellation cascades to child |
| setAppState | No-op | Doesn't affect parent state by default |
| contentReplacementState | Cloned | Content replacement state is independent |

## Team Mailbox Communication

Teammates communicate asynchronously via file system mailboxes. Each team has a TeamFile (`~/.claude/teams/{team_name}/config.json`) recording team metadata and member information. Each member has an independent inbox file (`~/.claude/teams/{team_name}/inboxes/{agent_name}.json`).

```typescript
type TeammateMessage = {
  from: string        // Sender name
  text: string        // Message content
  timestamp: string   // ISO timestamp
  read: boolean       // Read status
  summary?: string    // 5-10 word summary
}
```

Inbox polling interval is 1000ms. Upon receiving a message, the system determines the message type: shutdown request, plan approval response, permission request, or plain text message. Plain text messages are submitted as new conversation turns, triggering agent processing. Concurrency safety is guaranteed via `proper-lockfile` file locks, with 10 retries and 5-100ms exponential backoff.

Message routing handles five cases based on target address: `to === "*"` broadcasts to all teammates; names in `agentNameRegistry` route to in-process subagents; names in `teamFile.members` write to the corresponding teammate's mailbox; `bridge:` prefix routes to remote sessions; `uds:` prefix sends via Unix Domain Socket.

## Worktree Isolation

When an agent needs to modify files, the system creates a git worktree as an isolation environment. The creation process includes slug validation (preventing directory escape attacks), git worktree creation, symlinking large directories (node_modules, etc. to save disk space), and optional sparse-checkout configuration.

After agent completion, the system automatically checks if the worktree has changes. If changes exist, it returns the worktree path and branch name to the user, who can review and decide whether to merge. If no changes, the worktree is automatically deleted. Abnormal exits are cleaned up via `registerTeamForSessionCleanup()`.

## Permission Synchronization

Team-level permissions are defined via `TeamAllowedPath`, including path, applicable tools, adder, and timestamp. Teammates automatically inherit these permission rules on startup, no need to configure each one individually.

Fork Agents use the `bubble` permission mode — permission prompts bubble up to the parent agent's terminal. When a Fork needs to execute an operation, the permission request is sent to the parent agent's ToolUseConfirm dialog. User approval passes the result back to the Fork; denial sends a rejection notification. This design ensures Fork's permissions never exceed the parent agent's authorization scope.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/tools/AgentTool/AgentTool.tsx` | Main tool implementation, routing dispatch |
| `src/tools/AgentTool/runAgent.ts` | Execution engine, query loop |
| `src/tools/AgentTool/agentToolUtils.ts` | Tool pool resolution, result termination |
| `src/tools/AgentTool/forkSubagent.ts` | Fork semantics, message inheritance |
| `src/tools/AgentTool/loadAgentsDir.ts` | Agent definition types, parsing and loading |
| `src/tools/AgentTool/builtInAgents.ts` | Built-in agent registry |
| `src/tools/shared/spawnMultiAgent.ts` | Teammate generation entry point |
| `src/utils/swarm/spawnInProcess.ts` | In-process teammate generation |
| `src/utils/swarm/teamHelpers.ts` | Team file read/write |
| `src/utils/teammateMailbox.ts` | Mailbox message queue |
| `src/utils/forkedAgent.ts` | Cache safety parameters, subagent context |
| `src/utils/worktree.ts` | Git worktree isolation |

---

**Series Navigation:**
- Previous: [Tool System Design: Seven-Step Pipeline from Definition to Execution](/2026/04/06/087_claude-code-tool-system/)
- Next: [Four-Level Context Compression Strategy](/2026/04/06/080_claude-code-context-compression/)
