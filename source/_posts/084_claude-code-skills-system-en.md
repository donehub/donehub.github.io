---
title: The Skills System: Conditional Activation and Dynamic Discovery
date: 2026-04-06
tags: Skills
categories: Claude Code
lang: en
label: 084_claude-code-skills-system
---

## More Than Command Aliases

Skills appear on the surface as slash commands (`/code-review`, `/commit`), but they're fundamentally a complete AI behavior definition system. A single Skill file can constrain the tool pool, pin the model, inject Hooks, and pick an execution context (inline or fork) — all at once. Combined, these capabilities turn Skills into reusable behavior templates, not simple prompt shortcuts.

<!-- more -->

```markdown
---
name: code-review
description: Expert code review with best practices
allowed-tools: ['Read', 'Grep', 'WebSearch']
model: sonnet
context: fork
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo 'Review mode: read-only'"
---

You are a code reviewer. Analyze the code for:
- Security vulnerabilities
- Performance issues
- Code style and best practices
```

This Skill defines a read-only tool pool (Read, Grep, WebSearch), uses the Sonnet model, executes in a Fork context (independent subagent), and blocks Bash calls via Hook. Four constraints ensure the Skill's behavioral boundaries are clear.

## System Architecture and Module Responsibilities

The Skills system is divided into five modules, each with distinct responsibilities:

| Module | Core File | Responsibility |
|--------|-----------|----------------|
| Discovery | `loadSkillsDir.ts` | Discover and load Skills from 6 sources |
| Prompt | `prompt.ts` + `attachments.ts` | Inject Skill list into system-reminder |
| SkillTool | `SkillTool.ts` | Validate, permission check, execute Skill |
| Activation | `loadSkillsDir.ts` | Conditional activation and dynamic discovery |
| Context | `forkedAgent.ts` | Context preparation and modification |

The Discovery module loads Skills from six sources: built-in Skills (`src/skills/bundled/*.md`), built-in plugin Skills (`src/plugins/bundled/*/skills/*.md`), managed Skills (`${MANAGED_PATH}/.claude/skills/`), user global Skills (`~/.claude/skills/`), project-level Skills (`.claude/skills/`), and plugin Skills (`~/.claude/plugins/*/skills/`). Loading sorts by priority, with built-in Skills highest and plugin Skills lowest.

Deduplication uses file identity (`realpath()` resolving symlinks). If the same file is referenced by multiple sources (e.g., symlinks), it's loaded only once, using the first discovered source.

```typescript
const seenFileIds = new Map<string, SettingSource>()
for (const entry of allSkillsWithPaths) {
  const fileId = await getFileIdentity(entry.filePath)
  const existingSource = seenFileIds.get(fileId)
  if (existingSource !== undefined) continue
  seenFileIds.set(fileId, entry.skill.source)
  deduplicatedSkills.push(entry.skill)
}
```

## Frontmatter Fields and Parsing

A Skill's behavior is defined by Frontmatter YAML, supporting these fields:

```typescript
type FrontmatterData = {
  'allowed-tools'?: string | string[] | null   // Allowed tools
  description?: string | null                  // Description
  'argument-hint'?: string | null              // Argument hint
  when_to_use?: string | null                  // Usage scenario description
  model?: string | null                        // haiku, sonnet, opus, inherit
  'user-invocable'?: string | null             // User invocable
  'disable-model-invocation'?: string | null   // Prohibit model invocation
  hooks?: HooksSettings | null                 // Hook configuration
  effort?: string | null                       // low, medium, high, max
  context?: 'inline' | 'fork' | null           // Execution context
  agent?: string | null                        // Agent type
  paths?: string | string[] | null             // Conditional activation paths
  shell?: string | null                        // bash, powershell
}
```

The parsing flow has two steps: first `parseFrontmatter()` separates YAML and Markdown content, handling special characters; then `parseSkillFrontmatterFields()` extracts each field, including model alias resolution, effort level parsing, Hook configuration validation, and tool list parsing, finally generating the Command object.

## Conditional Activation: On-Demand Discovery

Conditional activation is the Skills system's most distinctive design. Skills with `paths` frontmatter aren't exposed to the model at startup — they're only dynamically discovered when the user operates on files matching the paths.

```markdown
---
name: react-component-test
description: Generate tests for React components
paths:
  - "src/components/**/*.tsx"
  - "src/components/**/*.jsx"
allowed-tools: ['Read', 'Write', 'Bash']
model: sonnet
---

Generate comprehensive tests for this React component...
```

This Skill only appears in the available list when you're operating on `.tsx` or `.jsx` files under `src/components/`. At startup, the system places all Skills with `paths` into the `conditionalSkills` Map. At runtime, each file operation triggers `activateConditionalSkillsForPaths()`, matching file paths with the ignore library. On successful match, the Skill moves from `conditionalSkills` to `dynamicSkills` — once activated, it remains valid for the session.

This solves two problems. First, context efficiency — a project might have dozens of Skills, and loading them all burns tokens. Conditional activation ensures only relevant Skills are injected into context. Second, less noise for the model. A shorter Skill list means more accurate selection — irrelevant options don't muddy the decision.

Dynamic discovery also includes directory traversal logic. When operating on files in deep directories, the system traverses upward from the file's directory to cwd, checking `.claude/skills/` directories at each level to auto-discover new Skills. Discovered directories are sorted by depth (deepest first), ensuring local Skills have priority over global ones.

```typescript
async function discoverSkillDirsForPaths(filePaths: string[], cwd: string): Promise<string[]> {
  for (const filePath of filePaths) {
    let currentDir = dirname(filePath)
    while (currentDir.startsWith(resolvedCwd + pathSep)) {
      const skillDir = join(currentDir, '.claude', 'skills')
      if (!dynamicSkillDirs.has(skillDir)) {
        dynamicSkillDirs.add(skillDir)
        if (await exists(skillDir) && !await isGitignored(currentDir)) {
          newDirs.push(skillDir)
        }
      }
      currentDir = dirname(currentDir)
    }
  }
  return newDirs.sort((a, b) => b.split(pathSep).length - a.split(pathSep).length)
}
```

## Context Injection and Budget Control

Skills are injected into conversations via `system-reminder` messages. The system has strict budget control over the Skill list's token footprint: 1% of the context window, with an 8000-character fallback, and a 250-character limit per description.

```typescript
const SKILL_BUDGET_CONTEXT_PERCENT = 0.01
const DEFAULT_CHAR_BUDGET = 8_000
const MAX_LISTING_DESC_CHARS = 250
```

The truncation strategy prioritizes protecting built-in Skills. Bundled Skills always retain their full descriptions, with remaining Skills sharing the leftover budget. If total characters exceed the budget, descriptions are truncated to `maxDescLen` characters. This design ensures core Skills' discoverability isn't squeezed out by custom Skills.

## Execution Engine: Inline vs Fork

SkillTool's execution flow has six steps: normalize input (strip leading `/`), remote Skill check (experimental), find Command object, record usage frequency, determine execution path, apply contextModifier.

Execution paths split into two modes based on `command.context`. Inline mode injects the Skill's prompt into the current conversation, modifying context (tool pool, model, effort), and the model executes in the current session. Fork mode launches an independent subagent, the Skill executes in an isolated context, and results return via `tool_result`.

| Feature | Inline Mode | Fork Mode |
|---------|-------------|-----------|
| Context | Injected into current conversation | Independent subagent |
| Tool pool modification | Modifies current session | Subagent has independent tool pool |
| Result passing | New messages injected into conversation | Embedded in tool_result |
| Use case | Needs conversation continuity | Independent task, no context needed |

Inline mode suits scenarios requiring conversation continuity (like `/commit` needing user interaction to confirm commit messages). Fork mode suits independent tasks (like `/verify` running tests and returning results).

## Hook Integration

Skills can declare Hooks in Frontmatter, automatically registered as session-level Hooks when invoked. Hooks with `once: true` are auto-removed after one execution.

```markdown
---
name: test-runner
hooks:
  PostToolUse:
    - matcher: "Edit"
      hooks:
        - type: command
          command: "npm test"
          once: true
---
```

```typescript
function registerSkillHooks(setAppState, sessionId, hooks, skillName, skillRoot): void {
  for (const eventName of HOOK_EVENTS) {
    for (const matcher of hooks[eventName] || []) {
      for (const hook of matcher.hooks) {
        const onHookSuccess = hook.once
          ? () => removeSessionHook(setAppState, sessionId, eventName, hook)
          : undefined

        addSessionHook(
          setAppState, sessionId, eventName,
          matcher.matcher || '',
          hook, onHookSuccess, skillRoot,
        )
      }
    }
  }
}
```

The Hook registration mechanism lets Skill behavior extend into the tool lifecycle. For example, a `test-runner` Skill can automatically run tests after each file edit, ensuring modifications don't break existing functionality.

## Permission Control

Skill invocation permission checks execute five steps in priority order: Deny rule check (exact or prefix match, e.g., `review:*` matches all review-prefixed commands), remote Skill auto-allow, Allow rule check, safe attribute auto-allow (Skills with no hooks, no allowedTools, no fork are auto-allowed), default ask user.

The safe attribute whitelist includes Skill basic metadata (type, name, description, source, etc.). If a Skill only contains these attributes without tool pool modification, Hook injection, or Fork execution, the system considers it safe and auto-allows.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/tools/SkillTool/SkillTool.ts` | SkillTool definition, validation, permissions, execution |
| `src/tools/SkillTool/prompt.ts` | Tool prompt, Skill list formatting |
| `src/skills/loadSkillsDir.ts` | Directory Skill discovery, loading, deduplication, conditional activation |
| `src/skills/bundledSkills.ts` | Built-in Skill registration system |
| `src/skills/bundled/index.ts` | Built-in Skills initialization entry |
| `src/commands.ts` | Command aggregation, sorting, filtering |
| `src/utils/forkedAgent.ts` | Fork context preparation, result extraction |
| `src/utils/hooks/registerSkillHooks.ts` | Skill Hook registration |

---

**Series Navigation:**
- Previous: [System Prompt Engineering: Dynamic Assembly and Cache Optimization](/2026/04/06/085_claude-code-system-prompt/)
- Next: [Five Layers of Permission Defense](/2026/04/06/083_claude-code-permission-security/)
