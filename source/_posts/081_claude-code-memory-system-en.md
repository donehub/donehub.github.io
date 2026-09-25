---
title: Cross-Session Memory: Four Types and Auto-Extraction
date: 2026-04-06
tags: Memory
categories: Claude Code
lang: en
label: 081_claude-code-memory-system
---

## The Starting Problem

Every conversation with a coding assistant starts from scratch. Users repeat the same context over and over: their role, coding preferences, recent project decisions. This information can't be inferred from the repository, but without it, the AI can't provide truly coherent assistance.

Claude Code's Memory system solves this with a persistent, structured knowledge base. It's not a chat log archive. It's a knowledge management system with explicit types, automatic extraction, and intelligent retrieval.

<!-- more -->

## Four Memory Types

Memory categorizes knowledge into four types, each with clear boundaries and purposes:

| Type | Records | Example |
|------|---------|---------|
| User (persona) | Role, goals, skill level, preferences | "User is a data scientist focused on logging systems" |
| Feedback (behavioral) | Corrections or approvals of Claude's approach | "Use real databases for integration tests, no mocks" |
| Project (dynamics) | Who's doing what, why, deadlines | "Merge freeze from 3/5, mobile team releasing" |
| Reference (external) | Pointers to external systems: dashboards, tickets, Slack channels | "Pipeline bug tracked in Linear INGEST project" |

These four types cover essentially everything a human needs to transfer to an AI for coding work. The persona shapes how the model interacts, feedback constrains technical decisions, project dynamics provide temporal context, and external references bridge internal toolchains.

### What's Not Stored

Memory has a clear filtering principle: only record what can't be inferred from the repository.

| Remember | Don't Remember |
|----------|----------------|
| You're a data scientist focused on logging | Code architecture, file structure |
| "Don't mock the database" | Git history, who changed what |
| Non-critical merges freeze after Thursday | Existing CLAUDE.md content |
| Bug tracking is in Linear's INGEST project | Debug solutions (the fix is already in code) |

If the code already says it, Memory doesn't need to repeat it. Git history, file structure, dependencies — these are all context the repository already carries. Memory only fills the gaps code can't cover.

## Storage Format

Memory files live in `~/.claude/projects/{project-path-hash}/memory/`, using YAML frontmatter + Markdown format:

```markdown
---
name: testing_policy
description: Integration tests must use real databases, no mocks
type: feedback
---

**Rule:** Integration tests must connect to a real database. Mocks are prohibited.

**Why:** Last Q4, mock tests passed but production migrations failed.

**How to apply:** All files marked as integration tests should use test database connections.
```

This format requires every memory to include three elements: what it is, why it matters, how to use it. The "Why" and "How to apply" fields ensure memories aren't isolated fact records — they're knowledge units with actionable guidance.

### MEMORY.md Index

A MEMORY.md file in the directory acts as an index, always loaded into context:

```markdown
# Memory Index

- [User Role](user_role.md) — Data scientist focused on observability/logging
- [Testing Strategy](feedback_testing.md) — Integration tests use real databases, no mocks
- [Merge Freeze](project_freeze.md) — Non-critical merges frozen from 2026-03-05
- [Bug Tracking](reference_linear.md) — Pipeline bug tracked in Linear INGEST project
```

This index file has hard limits: 200 lines or 25KB max, beyond which it gets truncated. This design forces the index to stay concise, with detailed content loaded on-demand through intelligent retrieval.

## Auto-Extraction Mechanism

Memory doesn't require manual maintenance. The system automatically checks whether to extract new memories each time the model completes a response (without tool_use).

The extraction process goes through four gates: confirming it's the main agent executing, auto-memory is enabled, frequency control (default: once per turn), and mutual exclusion check (skip if the main agent already wrote memories in the current turn). After passing the gates, the system launches a forked agent to perform extraction. This forked agent shares the parent session's prompt cache, executes at most 5 turns, and has strictly limited tool permissions.

```typescript
function createAutoMemCanUseTool(memoryDir: string): CanUseToolFn {
  return (toolName, input) => {
    // Allow read tools for scanning existing memories
    if (['Read', 'Grep', 'Glob'].includes(toolName)) return true

    // Bash allows only read-only commands
    if (toolName === 'Bash' && isReadOnlyCommand(input.command)) return true

    // Write tools restricted to memory directory
    if (['Edit', 'Write'].includes(toolName)) {
      return isInsideMemoryDir(input.file_path, memoryDir)
    }

    // MCP, Agent, non-read-only Bash all denied
    return false
  }
}
```

This permission design has clear security intent: the extraction agent can only read project files and write to the memory directory. It can't modify project code, call external services, or spawn sub-agents. Even if extraction goes wrong, the impact is contained within the memory directory.

The mutual exclusion mechanism prevents duplicate saves. If the main agent already operated on the memory directory via Write/Edit in the current turn, auto-extraction skips, avoiding the same information being recorded twice.

```typescript
function hasMemoryWritesSince(messages: Message[], sinceUuid: string): boolean {
  for (const msg of messages) {
    if (msg.uuid === sinceUuid) break
    if (msg.type === 'assistant') {
      for (const block of msg.content) {
        if (block.type === 'tool_use' &&
            ['Edit', 'Write'].includes(block.name) &&
            isMemoryPath(block.input.file_path)) {
          return true
        }
      }
    }
  }
  return false
}
```

## Intelligent Retrieval and Freshness Management

Memory isn't loaded into context in full. The system uses a Sonnet model as a selector, dynamically filtering the most relevant memories for each user query.

```typescript
async function findRelevantMemories(
  query: string, memoryDir: string, recentTools: string[] = [],
): Promise<RelevantMemory[]> {
  const files = await scanMemoryFiles(memoryDir)
  const candidates = await Promise.all(files.map(f => parseMemoryFile(f)))

  // Use Sonnet model to select relevant memories from candidates
  const selected = await sideQuery({
    model: 'claude-sonnet-4-5',
    systemPrompt: MEMORY_SELECTOR_PROMPT,
    messages: [{ role: 'user', content: query }],
    context: { candidates, recentTools },
  })

  return selected.map(s => ({ path: s.path, mtimeMs: s.mtimeMs }))
}
```

The selector picks at most 5 memories, and doesn't select if uncertain whether they're useful. This design controls the extra token overhead while keeping irrelevant memories from interfering with the model.

Memories have a shelf life. A "merge freeze" recorded three months ago was likely lifted long ago, and project decisions from half a year back may have been overturned. The system attaches freshness warnings to old memories:

```typescript
function memoryFreshnessText(mtimeMs: number): string {
  const days = memoryAgeDays(mtimeMs)
  if (days <= 1) return ''  // Today/yesterday: no warning
  return `This memory is ${days} days old. Memories are point-in-time
observations that may become stale. Verify against current code before
asserting as fact.`
}
```

Memories older than a day get flagged with a timeliness reminder, requiring the model to verify current code state before citing them. This solves the core tension in any memory system: keep information across sessions without letting stale data mislead current decisions.

## Team Synchronization

Team members' memories can be synced and shared via API:

```
GET  /api/claude_code/team_memory?repo={owner/repo}  ← Pull
PUT  /api/claude_code/team_memory?repo={owner/repo}  ← Push
```

Sync uses server-first semantics: Pull overwrites local content with server content, Push only uploads incremental content with different hashes. Local deletions don't delete remote records — they'll be restored on the next Pull. Conflicts trigger retries via 412 status codes, up to 2 attempts.

```typescript
async function pushTeamMemory(state): Promise<PushResult> {
  const localFiles = await readLocalMemoryFiles()
  const localHashes = computeHashes(localFiles)
  const delta = computeDelta(localHashes, state.serverChecksums)

  const response = await api.pushTeamMemory(delta)

  // 412 conflict: fetch latest checksums and retry
  if (response.status === 412) {
    const latest = await api.getTeamMemoryHashes()
    const newDelta = computeDelta(localHashes, latest)
    return pushTeamMemory({ ...state, serverChecksums: latest })
  }

  return { success: true }
}
```

For security, single files are capped at 250KB, upload bodies at 200KB, and gitleaks rules scan for credentials. If keys or passwords are detected, the file is skipped to prevent sensitive information from leaking into the team shared space.

## AutoDream: Background Memory Consolidation

As conversations accumulate, the Memory directory grows. AutoDream is a background task that periodically consolidates, deduplicates, and prunes memories.

Trigger conditions have four gates: at least 24 hours since last consolidation, at least 5 sessions in between, no other process currently consolidating, and a 10-minute scan throttle.

```typescript
async function shouldTriggerAutoDream(): Promise<boolean> {
  if (hoursSinceLastConsolidation < minHours) return false          // Default 24h
  if (sessionsSinceLastConsolidation < minSessions) return false    // Default 5 sessions
  if (otherProcessConsolidating) return false                       // Mutual exclusion lock
  if (timeSinceLastScan < 10 * 60 * 1000) return false              // 10-minute throttle
  return true
}
```

The consolidation process has four phases: Orientation (determine sessions to review), Collection (extract candidate memories from sessions), Consolidation (merge, deduplicate, update memory files), and Pruning (delete outdated or duplicate memories). This flow mirrors human memory consolidation during sleep, transforming fragmented short-term memories into structured long-term knowledge.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/memdir/paths.ts` | Path resolution, priority chain |
| `src/memdir/memdir.ts` | Prompt construction, MEMORY.md truncation |
| `src/memdir/memoryScan.ts` | Directory scanning, frontmatter parsing |
| `src/memdir/memoryTypes.ts` | Four memory type definitions |
| `src/memdir/findRelevantMemories.ts` | Sonnet intelligent retrieval |
| `src/services/extractMemories/` | Auto-extraction service |
| `src/services/teamMemorySync/` | Team memory sync |
| `src/services/autoDream/` | AutoDream background consolidation |
| `src/utils/frontmatterParser.ts` | YAML frontmatter parsing |

---

**Series Navigation:**
- Previous: [Permissions & Security: Layered Model and Human-AI Collaboration](/2026/04/06/083_claude-code-permission-security/)
- Next: [Channel System: Remote IM Control of Agents](/2026/04/06/078_claude-code-channel-system/)
