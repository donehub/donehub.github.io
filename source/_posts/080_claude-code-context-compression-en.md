---
title: "The Four-Level Context Compression Strategy"
date: 2026-04-06
tags: Context Compression
categories: Claude Code
lang: en
label: 080_claude-code-context-compression
---

## Context Windows Are a Real Hard Constraint

Every LLM has context limits. Claude 3.5 Sonnet advertises 200k tokens, but the system prompt takes about 20k, tool definitions take about 15k — fixed overhead consumes roughly 35k before anything else. That leaves around 165k tokens for conversation. At an average of 4k tokens per turn, 50 turns will exhaust the window.

Traditional truncation bluntly drops early messages. The problems are obvious: important info vanishes, the model re-asks answered questions, or contradicts earlier context. In long conversations, this information loss directly causes task failure.

Claude Code addresses this with a four-level progressive compression strategy. The four levels trigger from lightest to heaviest. The goal: preserve as much task-useful info as possible within a tight token budget.

<!-- more -->

## Four-Level Strategy Overview

| Level | Name | Trigger | Compression Method | Information Loss |
|-------|------|---------|--------------------|-----------------| 
| 1 | Snip | Every turn, automatic | Deduplication + truncation | Very low |
| 2 | Micro | Every turn, automatic | In-place optimization of cached content | None |
| 3 | Context Collapse | Context approaching limit | Progressive segmented summarization | Low |
| 4 | Auto Compact | Context critically low | Model generates global summary | Moderate |

The first two levels are routine operations that execute every turn — small compression amplitude but virtually lossless. The last two are emergency measures that kick in when token pressure increases, at the cost of varying degrees of information compression.

## Snip Compression: Deduplication and Truncation

Snip is the lightest level, executing automatically after each turn. Its logic is straightforward: iterate through processed messages and clean up redundant content.

Repeated file content gets replaced with a reference marker `[Duplicate file content, see earlier in conversation]`. Oversized tool outputs keep only the first 4KB with a truncation notice. Base64 images retain only metadata.

```typescript
function snipMessages(messages: Message[]): Message[] {
  const seen = new Set<string>()

  return messages.map(msg => {
    if (msg.type === 'user') {
      // Detect duplicate file content, keep only the first complete version
      const content = extractFileContent(msg)
      if (seen.has(content)) {
        return { ...msg, content: `[Duplicate file content, see earlier in conversation]` }
      }
      seen.add(content)
    }

    if (msg.type === 'tool_result') {
      // Truncate oversized tool outputs
      if (msg.content.length > MAX_TOOL_RESULT_SIZE) {
        return {
          ...msg,
          content: msg.content.slice(0, MAX_TOOL_RESULT_SIZE) +
            `\n... [truncated, ${msg.content.length} total chars]`
        }
      }
    }

    return msg
  })
}
```

In a typical coding session, you'll read the same file multiple times — after edits, when comparing versions, and so on. Snip deduplicates these repeated file contents, keeping only the first complete occurrence. This step's token recovery efficiency is quite high — in practice, for conversations over 30 turns, Snip alone recovers 15–25% of message volume.

## Micro Compression: In-Place Optimization Without Breaking Cache Keys

Micro compression operates at the text level of message content. It re-processes cached messages, removing excess whitespace, duplicate tool_use descriptions, and similar noise.

```typescript
function microCompactMessages(messages: Message[]): Message[] {
  return messages.map(msg => {
    if (msg.type === 'assistant') {
      const compressed = compressContent(msg.content)
      const deduped = deduplicateToolUses(compressed)
      return { ...msg, content: deduped }
    }
    return msg
  })
}
```

The key design constraint here: cache keys are calculated based on message ID and position, not content. Micro compression changes message content but doesn't change the cache key, so the next API request still hits the cache. This means Micro compression achieves token savings without disrupting prompt caching — the two don't interfere with each other.

## Context Collapse: Progressive Summarization

When context approaches the limit and the first two levels aren't enough, the system triggers Context Collapse. The core idea is staged summarization of historical messages, processing the oldest parts first while preserving full detail in recent messages.

```typescript
async function contextCollapse(
  messages: Message[],
  options: CollapseOptions
): Promise<Message[]> {
  // Identify collapsible segments, sorted from oldest to newest
  const segments = identifyCollapsibleSegments(messages)
  const sortedSegments = segments.sort((a, b) => a.startIndex - b.startIndex)

  // Generate summary for each segment, progressively replacing original messages
  const summaries: Message[] = []
  for (const segment of sortedSegments) {
    if (shouldCollapse(segment, options)) {
      const summary = await generateSummary(segment.messages)
      summaries.push(createSummaryMessage(summary, segment))
    }
  }

  return replaceSegmentsWithSummaries(messages, summaries)
}
```

Assuming a 200k token model context limit, the collapse process advances through multiple thresholds:

```
Original message sequence:
[Msg1] [Msg2] [Msg3] [Msg4] [Msg5] [Msg6] [Msg7] [Msg8] [Msg9] [Msg10]

First collapse (context > 150k):
[Summary1] [Msg6] [Msg7] [Msg8] [Msg9] [Msg10]
  ↑ Summarizes Msg1-Msg5

Second collapse (context > 180k):
[Summary1] [Summary2] [Msg8] [Msg9] [Msg10]
            ↑ Summarizes Msg6-Msg7

Third collapse (context > 195k):
[Summary1] [Summary2] [Summary3] [Msg10]
                           ↑ Summarizes Msg8-Msg9
```

Older messages get summarized earlier and compressed more aggressively; newer messages retain more original detail. This matches the information decay pattern in coding tasks: an architectural decision from thirty minutes ago is more important to remember than code details from ten minutes ago.

The summary format follows a fixed template that requires preserving four categories of key information: completed task list, modified file paths and their changes, current system state, and pending to-do items. This template design determines whether the compressed context can support the model continuing to work.

```markdown
## Summary of Previous Work

### Tasks Completed
- Implemented user authentication with JWT
- Added password reset functionality

### Files Modified
- src/auth/auth.service.ts: Added JWT token generation
- src/user/user.controller.ts: Added profile endpoints

### Current State
- Authentication system is fully functional

### Pending Items
- Need to add email verification
- Need to implement rate limiting
```

## Auto Compact: The Last-Resort Global Summary

When token usage exceeds 90% and the minimum interval since the last compact has passed, the system triggers Auto Compact. This is the final level — Claude itself generates a complete conversation summary that replaces all historical messages.

```typescript
async function autoCompact(
  messages: Message[],
  context: ToolUseContext
): Promise<Message[]> {
  const compactPrompt = buildCompactPrompt(messages)

  // Call Claude with a dedicated system prompt to generate summary
  const summary = await query({
    messages: [createUserMessage(compactPrompt)],
    systemPrompt: COMPACT_SYSTEM_PROMPT,
    toolUseContext: context,
    maxTurns: 1,
  })

  return [createSummaryMessage(summary)]
}
```

Three conditions must all be met: token usage ratio exceeds 90%, Auto Compact hasn't been attempted this round, and the minimum interval since the last compact has elapsed. All three are required to prevent frequent triggering that would cause excessive information compression.

```typescript
function shouldTriggerAutoCompact(state: AutoCompactTracking): boolean {
  const usageRatio = state.currentTokens / state.maxTokens
  if (usageRatio < 0.9) return false
  if (state.hasAttemptedAutoCompact) return false
  if (state.turnsSinceLastCompact < MIN_TURNS_BETWEEN_COMPACT) return false
  return true
}
```

Auto Compact's system prompt requires the summary to preserve five categories of information: conversation overview, key decisions and their rationale, list of modified files, pending tasks, and context needed to continue work. This information represents the minimum the model needs to maintain task continuity in a fresh context window.

## Recovery Chain: How the Four Levels Work Together

The four compression levels don't run independently — they form a recovery chain. When a `prompt_too_long` error occurs, the system tries each level from lightest to heaviest:

```
prompt_too_long error
  │
  ├─ Try Snip compression → retry
  │   └─ Success → continue conversation
  │
  ├─ Try Micro compression → retry
  │   └─ Success → continue conversation
  │
  ├─ Try Context Collapse → retry
  │   └─ Success → continue conversation
  │
  └─ Try Auto Compact → retry
      └─ Success → continue conversation
      └─ Failure → report error to user
```

Each level is a precondition for the next. In most cases, Snip and Micro recover enough space. Only when conversations are exceptionally long and the first two levels can't free enough room for new messages does the system escalate to Context Collapse or Auto Compact.

## Token Budget Management

Before each API call, the system calculates the available token budget:

```typescript
function calculateTokenBudget(
  model: string, messages: Message[],
  systemPrompt: string, tools: Tools,
): TokenBudget {
  const contextLimit = getModelContextLimit(model)
  const fixedCost = countTokens(systemPrompt) + countToolsTokens(tools)
  const messagesTokens = countMessagesTokens(messages)
  const outputReserve = 8192

  return {
    total: contextLimit,
    fixed: fixedCost,
    messages: messagesTokens,
    available: contextLimit - fixedCost - messagesTokens - outputReserve,
  }
}
```

Available budget equals model context limit minus fixed costs, current message consumption, and output reserve (default 8192 tokens). Based on message consumption ratio, the system issues warnings at three levels: below 70% is normal, above 85% enters warning state, above 95% triggers critical. These thresholds correspond to compression strategy trigger points.

## Context Injection

Beyond compression, the composition of context is worth understanding. The system injects two types of context each turn: system context includes Git status (current branch, recent commits, file changes) and current date; user context includes merged CLAUDE.md content, MCP server instructions, and memory system content.

System reminders are injected as `<system-reminder>` tags into tool return results or user messages, carrying information like file safety warnings, memory timeliness reminders, and deferred tool availability notifications. This injection approach lets system information blend naturally into the message flow without requiring a separate communication channel.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/services/compact/autoCompact.ts` | Auto-compression triggering and management |
| `src/services/compact/compact.ts` | Compression implementation |
| `src/services/compact/reactiveCompact.ts` | Reactive compression (error-triggered) |
| `src/services/contextCollapse/index.ts` | Context collapse implementation |
| `src/services/compact/snipCompact.ts` | Snip compression |
| `src/utils/tokens.ts` | Token counting and budget management |
| `src/context.ts` | System and user context |
| `src/utils/attachments.ts` | System reminder attachments |

---

**Series Navigation:**
- Previous: [Multi-Agent Orchestration: Four Proxy Types and Collaboration Mechanisms](/2026/04/06/082_claude-code-multi-agent/)
- Next: [System Prompt Engineering: Dynamic Assembly and Cache Optimization](/2026/04/06/085_claude-code-system-prompt/)
