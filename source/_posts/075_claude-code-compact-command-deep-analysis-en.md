---
title: "Inside Claude Code's /compact Command: How Context Compression Actually Works"
date: 2026-04-02
tags: [上下文压缩]
categories: AI
lang: en
label: 075_claude-code-compact-command-deep-analysis
---

I was using Claude Code to refactor a user module. The first 30 rounds went smoothly — it remembered clearly that the database was PostgreSQL, the API style was RESTful, and the Redis cluster was under maintenance that day so sessions should fall back to the DB temporarily. Then around round 50, it suddenly asked, "Can't find the MySQL MCP info, could you provide it?" The MCP settings were right there in the file — it had known about them earlier. Once the context window gets overloaded, early critical constraints get diluted in the model's attention. This article breaks down exactly what happens inside Claude Code when you hit `/compact`.

<!-- more -->

## What's Actually in the Context Window

Before talking about compression, you need to understand what the context window really contains. Every time Claude Code sends a request to the API, the assembled payload is far more complex than "a series of conversation messages."

| Component | Approximate Size | Description |
|-----------|-----------------|-------------|
| System prompt | ~20K tokens | Role definition, behavior constraints, tool descriptions |
| CLAUDE.md instructions | Dynamically injected | User-level + project-level + directory-level config |
| Conversation history | Continuously growing | User messages + assistant replies + tool calls + tool results |
| Tool definitions | ~15K tokens | Schema descriptions for 48+ tools |
| Current state | Relatively small | TodoWrite task list, recent file read content |

The biggest chunk is conversation history. Each round adds several thousand tokens, and tool calls with their results are often 3 to 5 times the size of the conversation itself. A single `Read` call on a 500-line file consumes over 20K tokens. Read three different files and your tool results alone eat up 60K tokens. When Claude Code senses that space is running out, it needs a mechanism to clean up — that's what `/compact` does.

## The Four-Layer Progressive Compression Pipeline

`/compact` isn't simply "summarize the conversation history." When you run the command, Claude Code internally executes a four-layer pipeline, processing from lightweight to heavyweight. The system tries the cheapest option first and escalates only if needed — similar to memory management: first reclaim caches, then kill processes, and only as a last resort invoke the OOM Killer.

| Layer | Name | Core Strategy | Lossy/Lossless |
|-------|------|---------------|----------------|
| Layer 1 | Micro compact | Truncate oversized individual tool results | Lossless |
| Layer 2 | Snip | Deduplication + redundancy removal | Lossless |
| Layer 3 | Context Collapse | Fold old messages into segment summaries | Lossy |
| Layer 4 | Full Compact | Global summary replaces all history | Lossy |

### Micro Compact: Minimal Surgery Without Breaking the Cache Key

The lightest layer. Its defining characteristic is that it modifies message content without changing the cache key. The Claude API has a prompt caching mechanism: when the prefix of two consecutive requests is identical, the second request can reuse the cache to reduce cost and latency. Micro compact's modifications are "harmless" — they don't break cache hits.

```typescript
// Simplified logic
function microCompact(messages: Message[]): Message[] {
  return messages.map(msg => {
    if (msg.type === 'tool_result') {
      // Truncate oversized tool results
      if (msg.content.length > MICRO_COMPACT_THRESHOLD) {
        return {
          ...msg,
          content: msg.content.slice(0, KEEP_CHARS) + 
            `\n... [${msg.content.length} chars total, compacted]`
        }
      }
    }
    return msg
  })
}
```

Only the content length of `tool_result` messages is changed — message structure, ordering, and roles stay the same, so the cache key still matches. This layer typically frees up 10% to 20% of space at virtually zero cost.

### Snip: Deduplication and Redundancy Removal

Micro compact handles the length of individual messages. Snip handles duplication across messages. When writing code, the same file gets read repeatedly. Without processing, the same file content might appear three or four times in the context. Snip's approach is direct: for identical repeated reads, it replaces the content with `[File content already shown above]`. Newer versions with modifications are preserved as-is, determined by content hashing.

Beyond deduplication, Snip also trims several categories of special tool output. If a `Bash` command's stdout is excessively long, only the last N lines are kept — the tail usually carries more signal than the head. If `Grep` results are too numerous, only the match count statistics plus the first 20 results are retained. `Write` operation results are replaced outright with `[File written successfully]` since the content already exists in the filesystem. This layer typically frees 15% to 30%, depending on how often the task re-reads the same files.

### Context Collapse: Segment-by-Segment Folding

The first two layers are lossless — information isn't lost, just shortened. Starting here, we enter lossy compression territory.

Context Collapse groups early conversation messages and merges each group into a small summary. It doesn't summarize everything at once — it folds segment by segment. Rounds 1 through 5 might collapse into "Discussed database selection, decided on PostgreSQL." Rounds 6 through 10 become "Completed authentication module design, settled on JWT approach." The most recent rounds are preserved verbatim. The older the content, the more aggressively it gets folded. The newer the content, the more completely it's preserved — because the verbatim record of round 3 is unlikely to be needed, but round 25 might be directly relevant to the current work.

The folding granularity isn't fixed — it adjusts dynamically based on context pressure. When pressure is low, no folding happens. When pressure is high, the folding range expands.

### Full Compact: Global Summary

If the first three layers aren't enough, you reach the heaviest step. Full Compact takes all current history messages (including previously collapsed summaries) and sends them to Claude to generate a global summary. That summary then replaces all history, keeping only the most recent rounds verbatim. Pre-compact might be 180K tokens; post-compact drops to around 30K.

This global summary isn't just generated ad hoc. Claude Code gives the model a dedicated compact prompt that instructs it to preserve the user's original goals and key constraints, important decisions already made and their reasoning, completed steps and modified files, in-progress but unfinished tasks, and encountered issues with current solutions. For code changes, it requires preserving specific file paths and key implementation logic while discarding irrelevant chitchat and outdated discussions.

This layer frees 60% to 80% of space, at the cost of losing detail. Anything not mentioned in the summary is genuinely gone.

## Context Reconstruction After Compression

Compression is only the first half. The second half is reconstruction. After compression, Claude Code performs a series of recovery actions.

CLAUDE.md instructions always live in the system prompt and are unaffected by compression. But Claude Code re-checks whether CLAUDE.md has been updated after compaction. If you modified CLAUDE.md during the conversation, the new content takes effect after compact.

One easily overlooked detail is file content reconstruction. After compression, all previously read file content is lost — the summary only retains file names and rough descriptions. If the model needs those files' content during subsequent work, it re-issues Read calls. This is why you often see Claude Code suddenly reading a bunch of files right after a compact. It's not confused — it's rebuilding its file cache.

The TodoWrite task list is stored independently of conversation history. After compact, the task list automatically restores to its pre-compact state: which tasks are done, which are in progress, which are pending — all intact. This is exactly why using TodoWrite to manage long-running task progress is recommended. It's the most important state anchor after a compact.

## Automatic Trigger Mechanism

`/compact` is manually triggered, but in practice most compression happens automatically. Claude Code continuously monitors context utilization and kicks off the compression pipeline when it hits certain thresholds.

| Context Utilization | Action |
|--------------------|--------|
| < 60% | No compression |
| 60%–75% | Micro compact + Snip |
| 75%–85% | Context Collapse |
| > 85% | Full Compact (global summary) |
| 95%+ | Emergency compression, aggressive trimming |

The exact thresholds aren't fixed — they're calculated dynamically based on the model's maximum context window. A 200K model and a 1M model have different trigger points.

One historical bug is worth mentioning: Claude 3 Opus's 1M context window was incorrectly calculated as 200K, causing automatic compression to trigger too early. Users had 800K tokens of headroom left, but the system started compressing anyway. This was fixed in v2.1.117.

## Hooks: Extension Points Around Compression

Claude Code allows custom logic to be injected before and after compression.

The PreCompact Hook fires before compression executes. It has one critical capability: if the hook returns exit code 2 or outputs `{"decision":"block"}`, the compression is canceled. This is useful when you're in the middle of a critical operation and don't want compression to disrupt the current state. The hook's output is also appended to the compression pipeline, but this content may be rewritten or discarded when the summary is generated — so don't put critical information only in the hook output.

```json
{
  "hooks": {
    "PreCompact": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "echo '{\"decision\":\"block\"}' && exit 2"
      }]
    }]
  }
}
```

The PostCompact Hook fires after compression completes. It receives the `trigger` field (`"manual"` or `"auto"`) and the `compact_summary` field (the generated summary text). PostCompact cannot modify the compression result — it can only observe and utilize it. A typical use case is writing the summary to a log file for post-hoc auditing.

```json
{
  "hooks": {
    "PostCompact": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "echo 'Compact summary: ${COMPACT_SUMMARY}'"
      }]
    }]
  }
}
```

There's a community project called [Post Compact Reminder](https://github.com/Dicklesworthstone/post_compact_reminder) that re-injects key user preferences in the PostCompact hook, preventing the model from forgetting user habits after compression. Clever approach.

## Hidden Parameters and Practical Tips

`/compact` accepts arguments. For example: `/compact preserve the discussion details on database selection and API design`. This argument is passed as a compression guide to the model generating the summary, telling it to pay special attention to preserving that information. During complex refactoring with many detailed decisions, proactively guiding the summary prevents the default behavior from dropping those details. That said, if the guide is too long, it dilutes the weight of other important information. A short, precise sentence about what to preserve works best.

On when to manually compact, there are a few rules of thumb. If the model starts feeling slow, or begins repeating earlier suggestions, those are signals that the context is about to overflow. Once a conversation exceeds 30 rounds, consider compacting. It works particularly well at the end of a major phase, because phase transitions naturally produce more complete summaries. Manually triggered compact typically yields higher summary quality than automatic triggers, since by the time auto-trigger fires, the context is already nearly full — the model has less room to think about the summary itself.

Before hitting `/compact`, spend 30 seconds doing a few things to noticeably improve compression quality. Update task progress with TodoWrite to ensure the current state is recorded. Write key decisions into CLAUDE.md so they don't depend on conversation history. Confirm that important file content has been saved, because the model will need to re-read files after compact.

You can add a dedicated Compact Instructions section in CLAUDE.md to guide compression behavior:

```markdown
## Compact Instructions
When compacting, make sure to preserve:
- Current task and progress
- Database is PostgreSQL 15
- API style is RESTful, not GraphQL
- Redis cluster maintenance means sessions go through DB
- List of modified files
```

These instructions are passed to the summary model on every compression, acting as a whitelist for the summary.

One pitfall to avoid: don't immediately start reading files and running commands in bulk right after a compact. If the context fills up again quickly, the system triggers another compression. If context fills up immediately after three consecutive compactions, Claude Code stops compressing and throws an error rather than entering an infinite loop. This bug genuinely existed before v2.1.79 — the system would get stuck in a compress-then-fill-compress-then-fill death spiral. Protection is in place now, but knowing the history is still useful.

## Information Loss and Recovery

Compact always loses information. A summary can never 100% reconstruct the original conversation. What typically gets lost: specific code details (the summary says "modified xxx file" but what exactly changed is gone), early discussion reasoning (why option A was chosen over option B), full tool call return values, and image/screenshot content.

The most direct recovery strategy is to use files as memory. Write important code, configs, and design documents directly to files — the model can re-read them after compact. Don't rely on the model still remembering. TodoWrite content is stored independently and survives compact — treat it as external state storage. Hard constraints like "use PostgreSQL, not MySQL" are safest written into CLAUDE.md. They live in the system prompt on every request and can never be compressed away. Compact Instructions tell the summary model what must not be lost — far more efficient than discovering losses after the fact and trying to patch them.

The compact mechanism's design priorities are clear: don't touch what doesn't need touching, touch as little as possible when you must, preserve key information for what must be touched, and only then consider details. Understanding this priority ordering tells you when to compact, what to prepare beforehand, and how to quickly recover state afterward.
