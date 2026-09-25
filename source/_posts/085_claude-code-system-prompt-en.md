---
title: System Prompt Dynamic Assembly and Three-Level Cache
date: 2026-04-06
tags: System Prompt
categories: Claude Code
lang: en
label: 085_claude-code-system-prompt
---

## The 20k Token Cache Challenge

Claude Code's system prompt is roughly 20k tokens, sent with every API call. That alone isn't daunting, but layer on two constraints and it becomes an engineering problem. First, dynamism: the system prompt needs to include current date, project structure, Git status, MCP server instructions, CLAUDE.md user directives — content that can change every turn. Second, cost: without cache optimization, a 20k token prompt means multiplied latency and API fees per session.

The solution is splitting the system prompt into static cacheable regions and dynamic mutable regions, separated by cache boundary markers. Static parts (role definition, system rules, task guidance, tool descriptions, style constraints) get cached globally. Dynamic portions (session guidance, memory system, environment info, MCP instructions, token budget) cache at session level. Each API call reuses the static portion from cache — only the dynamic part needs recalculation.

<!-- more -->

## Cache Boundaries and Section Types

System prompt assembly relies on an explicit cache boundary marker:

```typescript
export const SYSTEM_PROMPT_DYNAMIC_BOUNDARY = '__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__'
```

Content above the boundary is cross-user, cross-organization universal, cached with `scope: 'global'`. Content below is user- or session-specific, cached with `scope: 'ephemeral'`. The API layer splits the prompt into two blocks along this boundary when building requests, each marked with `cache_control`, letting the server cache them independently.

Each prompt component is wrapped as a Section, divided into two types. Cached Sections are computed once and reused for the entire session:

```typescript
systemPromptSection('memory', async () => {
  return buildMemoryLines()
}, { scope: 'ephemeral' })
```

Cache-busting Sections are recalculated every turn. This applies to MCP instructions (servers may connect/disconnect mid-session), current date (different every turn), Git status (can change rapidly), token budget (recalculated per turn), etc.:

```typescript
DANGEROUS_uncachedSystemPromptSection('mcp_instructions', async () => {
  return getMcpInstructions()
}, 'MCP servers can connect/disconnect mid-session')
```

The distinction between these two types is key to cache efficiency. Putting dynamic content in the static region causes the entire static cache to invalidate frequently; marking static content as dynamic wastes cache opportunities. The explicit cache boundary marker gives this problem a clear engineering solution.

## Three-Level Cache System

System prompt caching has three levels, covering different time scales.

Global Cache is shared across the organization, storing static system prompt (role definitions, rules, tool descriptions, etc.), never expiring. This content is identical across all users, all sessions — cache hit rate approaches 100%.

Ephemeral Cache is session-level cache, storing dynamic system prompt (memory content, environment info, etc.). It rebuilds when CLAUDE.md files change, and also rebuilds when MCP connection state changes.

Section Cache is turn-level cache, with each Section independently memoized. Even if a Section is marked cache-busting, it still has internal memoize optimization — multiple accesses within the same turn don't recalculate.

```typescript
function buildSystemPromptBlocks(systemPrompt: SystemPrompt): ContentBlockParam[] {
  const blocks: ContentBlockParam[] = []
  const [staticPart, dynamicPart] = splitAtBoundary(systemPrompt)

  if (staticPart) {
    blocks.push({
      type: 'text', text: staticPart,
      cache_control: { type: 'ephemeral' },
    })
  }

  if (dynamicPart) {
    blocks.push({
      type: 'text', text: dynamicPart,
      cache_control: { type: 'ephemeral' },
    })
  }

  return blocks
}
```

The practical effect of this three-level design: in a typical session, the static portion (roughly 12k tokens) achieves nearly 100% cache hit rate, and the dynamic portion (roughly 8k tokens) maintains high hit rates as long as CLAUDE.md doesn't change. Only when MCP connections change or Git status updates frequently does the dynamic cache rebuild often.

## Priority Resolution Chain

The system prompt has multiple sources, with final content determined by `buildEffectiveSystemPrompt()` following priority:

```
Override System Prompt     ← Highest priority, complete replacement
  ↓
Coordinator System Prompt  ← Coordinator mode specific
  ↓
Agent System Prompt        ← agentDefinition.getSystemPrompt()
  ↓                          proactive mode: append to default
  ↓                          other modes: replace default
Custom System Prompt       ← --system-prompt argument
  ↓
Default System Prompt      ← Claude Code standard prompt
  ↓
Append System Prompt       ← Always appended to end
```

Override and Coordinator are exclusive modes, replacing the entire prompt directly. Agent prompts have two behaviors: proactive mode appends to the default prompt (keeping default rules), other modes completely replace the default prompt. The difference between Custom and Append: Custom inserts after the default prompt, Append is always at the very end.

```typescript
export async function buildEffectiveSystemPrompt(options): Promise<SystemPrompt> {
  if (options.overrideSystemPrompt) return asSystemPrompt(options.overrideSystemPrompt)
  if (isCoordinatorMode() && options.coordinatorSystemPrompt) return asSystemPrompt(options.coordinatorSystemPrompt)

  const sections: SystemPromptSection[] = await buildDefaultSections()

  if (options.agentDefinition?.getSystemPrompt) {
    const agentPrompt = await options.agentDefinition.getSystemPrompt(options)
    if (options.agentDefinition.promptMode === 'proactive') {
      sections.push({ type: 'text', text: agentPrompt })
    } else {
      return asSystemPrompt(agentPrompt)
    }
  }

  if (options.customSystemPrompt) sections.push({ type: 'text', text: options.customSystemPrompt })
  if (options.appendSystemPrompt) sections.push({ type: 'text', text: options.appendSystemPrompt })

  return resolveSystemPromptSections(sections)
}
```

This priority chain covers all scenarios from test coverage (Override) to multi-agent orchestration (Agent Prompt) to user customization (Custom/Append).

## CLAUDE.md Loading and Recursive References

CLAUDE.md is the user custom directive system, loaded by path hierarchy from low to high:

| Path | Scope | Priority |
|------|-------|----------|
| `/etc/claude-code/CLAUDE.md` | Global admin config | Lowest |
| `~/.claude/CLAUDE.md` | User global directives | Low |
| `Project root/CLAUDE.md` | Project-level directives | Medium |
| `Project root/.claude/CLAUDE.md` | Project-level directives | Medium |
| `Project root/.claude/rules/*.md` | Project rule files | Medium |
| `Project root/CLAUDE.local.md` | Local private directives | Highest |

Local private directives (`.local.md`) are typically added to `.gitignore`, used for personal preferences (like "reply in Chinese"), not committed to the repository. Project-level directives can be committed to the repository as team-shared coding standards.

CLAUDE.md supports `@path` syntax for recursive file references, enabling modular directive organization:

```markdown
# Project Configuration

## Coding Standards
@./docs/coding-standards.md

## API Documentation
@./docs/api-spec.md
```

Recursive references have circular reference detection. The system maintains a visited Set, checking if the path has been visited before each load. If circular reference is detected, it prints a warning and returns an empty string, preventing infinite recursion.

```typescript
async function loadClaudeMdFile(path: string, visited: Set<string> = new Set()): Promise<string> {
  if (visited.has(path)) {
    console.warn(`Circular reference detected: ${path}`)
    return ''
  }
  visited.add(path)

  let content = await readFile(path, 'utf-8')
  const references = extractReferences(content)
  for (const ref of references) {
    const refPath = resolveReference(path, ref)
    const refContent = await loadClaudeMdFile(refPath, visited)
    content = content.replace(`@${ref}`, refContent)
  }

  return content
}
```

## Agent Prompt Enhancement

Subagent system prompts have two enhancement layers on top of the base definition. The first layer is environment detail injection, including working directory, enabled tool list, model info, and environment variables. The second layer is behavioral constraint injection — Fork Agents receive extra behavioral rules: no conversation, no questions, no text output between tool calls, responses must start with "Scope:", reports limited to 500 words.

These constraints ensure Fork Agents are efficient worker processes, not generating unnecessary conversation overhead in the Fork context.

## Prompt Structure Overview

The final system prompt consists of static and dynamic portions, separated by the cache boundary. The static portion contains role definition ("You are an interactive agent..."), system rules (tool execution methods, permission modes), task guidance (use tools, follow code standards, don't summarize completed tasks), tool descriptions (each tool's functional description), and style constraints. The dynamic portion contains current date, project context (working directory, Git branch, Git status), CLAUDE.md user directives, MCP server instructions, and token budget info.

The key design decision in this structure is the cache boundary position. Tool descriptions are placed in the static region (because tool definitions rarely change), while token budget is in the dynamic region (because it needs recalculation every turn). This split point choice directly determines cache efficiency.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/constants/prompts.ts` | System prompt assembly |
| `src/constants/systemPromptSections.ts` | Section definitions and caching |
| `src/utils/systemPrompt.ts` | Priority resolution |
| `src/utils/claudemd.ts` | CLAUDE.md loading |
| `src/context.ts` | System and user context |
| `src/utils/api.ts` | Cache boundary splitting |
| `src/services/api/claude.ts` | API cache block construction |

---

**Series Navigation:**
- Previous: [Four-Level Context Compression Strategy](/2026/04/06/080_claude-code-context-compression/)
- Next: [The Skills System: Conditional Activation and Dynamic Discovery](/2026/04/06/084_claude-code-skills-system/)
