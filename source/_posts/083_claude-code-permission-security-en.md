---
title: Five Layers of Permission Defense
date: 2026-04-06
tags: Permission
categories: Claude Code
lang: en
label: 083_claude-code-permission-security
---

## The Core Contradiction of Agent Execution Permissions

AI agents need to execute commands, modify files, and access networks to complete programming tasks, but these operations all carry destructive risk. The permission system has to balance agent efficiency against safety. Too permissive and you risk irreversible damage. Too restrictive and the agent gets stuck waiting for human approval on everything.

Claude Code's permission system solves this with a five-layer decision mechanism. Each layer can independently interrupt tool calls, progressing from deterministic rule matching to probabilistic AI classifiers, with the user as the final backstop.

<!-- more -->

## Five-Layer Decision Architecture

Permission decisions execute in a fixed order, divided into deny phase, allow phase, and default phase.

The first layer is permission rules. The system checks if tool names and input parameters match deny or allow rules. Deny rules have highest priority — any match results in immediate rejection. Rules support exact matching (`Bash`), argument pattern matching (`Bash(git *)` allows all git commands, `Bash(rm -rf *)` forbids deletion), and wildcards (`File*` matches all file tools). Rules come from eight sources: user global settings, project settings, local settings, policy settings, feature flags, CLI arguments, commands, and session-level temporary rules.

The second layer is permission mode. Seven modes correspond to different automation levels: in `default` mode all write operations require confirmation; in `acceptEdits` mode edits within the working directory are auto-allowed; `bypassPermissions` completely bypasses permission checks; `dontAsk` auto-rejects all operations; `plan` mode auto-allows read operations but requires confirmation for writes; `auto` mode delegates to the AI classifier; `bubble` mode bubbles permission requests to the parent agent's terminal.

| Mode | Read Operations | Write Operations | Dangerous Operations |
|------|-----------------|------------------|----------------------|
| `default` | May ask | Ask | Ask |
| `acceptEdits` | Auto | Auto (within working directory) | Ask |
| `bypassPermissions` | Auto | Auto | Auto |
| `dontAsk` | Auto-reject | Auto-reject | Auto-reject |
| `plan` | Auto | Ask | Ask |
| `auto` | Classifier decision | Classifier decision | Ask |
| `bubble` | Bubble to parent | Bubble to parent | Bubble to parent |

The third layer is hook interception. PreToolUse hooks run before tool execution and can intercept, modify, or block operations. Hook exit code 0 indicates success (may have modified input), exit code 2 indicates blocking (displays error message to model), other exit codes are displayed to the user.

The fourth layer is the safety classifier. In `auto` mode, an AI classifier evaluates the safety of tool calls, returning a score between 0-1. Scores above 0.8 are auto-allowed, below 0.2 are auto-rejected, and the middle range asks the user. The classifier has a rejection counter — after 3 consecutive rejections, it falls back to user approval to prevent getting stuck in a rejection loop.

The fifth layer is user confirmation. If the first four layers haven't made a decision, the system pops up a dialog showing operation details for the user to make the final judgment.

## Decision Reason Tracing

Every permission decision records its reason for debugging and auditing:

```typescript
type DecisionReason =
  | { type: 'rule'; source: PermissionRuleSource; pattern: string }
  | { type: 'mode'; mode: PermissionMode }
  | { type: 'hook'; hookName: string }
  | { type: 'classifier'; score: number }
  | { type: 'user'; temporary: boolean }
```

This design makes the permission system's behavior fully explainable. When users encounter unexpected allows or denials, they can trace back through the decision reason to which layer, which rule, which score made the judgment.

## Bash Command Safety Parsing

The Bash tool is the most complex scenario for permission control because command syntax is flexible — pipes, redirects, command substitution can all hide dangerous operations.

Safety wrapper stripping is the first line of processing. Commands like `nohup rm -rf /`, `timeout 10 rm -rf /`, `nice rm -rf /` — the wrappers don't change the underlying operation's danger level. The system strips wrappers like timeout, time, nice, stdbuf, nohup, inspecting the core command directly.

Compound command decomposition is the second line. For pipe or chain commands like `cmd1 && cmd2 | cmd3`, the system uses tree-sitter to parse the command AST, extracts all subcommands, and checks each subcommand's permissions independently. If any subcommand is rejected, the entire command is rejected.

Tree-sitter AST parsing also catches sneakier danger patterns: `eval` and `source` commands can execute arbitrary code, `$(...)` and backtick command substitution can inject malicious commands, `${...}` variable expansion can leak sensitive information, zsh special builtins have side effects. Commands containing command substitution or complex expansion are flagged as "too-complex" and require manual user confirmation.

Path constraint checking is the third line. Output redirect targets must be within allowed working directories and can't write to dangerous directories like `.git`, `.vscode`, `.claude`. The system also detects `cd` combined with `git` compound commands to prevent bare repository RCE attacks.

## File Operation Safety Constraints

File editing has a hard prerequisite: the file must be read first. `readFileState` records each file's read timestamp, and editing checks if the file was modified after being read. If the file was externally modified after reading, the edit is rejected to prevent overwriting concurrent updates.

Dangerous files and directories have extra protection. Files like `.gitconfig`, `.gitmodules`, `.bashrc`, `.zshrc`, `.claude.json`, and directories like `.git`, `.vscode`, `.idea`, `.claude` trigger additional safety checks when modification is attempted.

Path safety checks also cover multiple attack vectors: suspicious Windows path characters (`<>:"|?*`), ADS (Alternate Data Stream) attacks (`::` syntax), short name bypasses (`~1` and other 8.3 formats), long path prefixes (`\\?\`), etc. These checks prevent agents from bypassing permissions through path tricks.

## Auto Mode Classifier Logic

`auto` mode lets the AI classifier make permission decisions on behalf of the user. The classifier first checks the fast path: if the operation is within `acceptEdits` scope, or is a known safe tool (read-only operations), it's allowed directly. Otherwise, the classifier API is called to evaluate the operation's safety.

```typescript
async function classifyWithAI(tool, input, context): Promise<PermissionResult> {
  // Fast path: acceptEdits or safe tool whitelist
  if (isAcceptEditsAllowed(tool, input, context)) return { behavior: 'allow' }
  if (isSafeTool(tool)) return { behavior: 'allow' }

  // Call classifier API
  const score = await callClassifierAPI(tool.toAutoClassifierInput?.(input) || JSON.stringify(input))

  if (score > 0.8) return { behavior: 'allow', decisionReason: { type: 'classifier', score } }
  if (score < 0.2) return { behavior: 'deny', decisionReason: { type: 'classifier', score } }

  // Uncertainty range, ask user
  return { behavior: 'ask' }
}
```

The classifier's rejection counter prevents the system from getting stuck in loops. If rejected 3 consecutive times, the system falls back to user approval mode, letting the user decide whether to continue. This design avoids the agent repeatedly trying and being rejected on classifier boundary cases.

## Hook Interception Mechanism

Hooks let users inject custom logic before and after tool execution. PreToolUse hooks run before tool execution and can inspect, modify input parameters, or directly block operations. PostToolUse hooks run after tool execution, typically used for automated checks (like lint, format).

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash(rm *)",
      "hooks": [{
        "type": "command",
        "command": "echo 'Deletion blocked' && exit 2"
      }]
    }],
    "PostToolUse": [{
      "matcher": "Edit",
      "hooks": [{
        "type": "command",
        "command": "npm run lint"
      }]
    }]
  }
}
```

Matchers support the same pattern matching syntax as permission rules, allowing precision down to specific tool arguments. This mechanism makes the permission system highly extensible — users can define their own safety policies based on project needs without modifying core code.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/types/permissions.ts` | Permission type definitions |
| `src/utils/permissions/permissions.ts` | Core permission check logic |
| `src/utils/permissions/filesystem.ts` | File system permission control |
| `src/utils/permissions/shellRuleMatching.ts` | Shell rule matching |
| `src/utils/permissions/bashClassifier.ts` | Bash classifier |
| `src/utils/permissions/yoloClassifier.ts` | Auto mode classifier |
| `src/tools/BashTool/bashPermissions.ts` | Bash permission checks |
| `src/tools/BashTool/pathValidation.ts` | Bash path validation |
| `src/tools/FileEditTool/FileEditTool.ts` | File edit tool implementation |
| `src/services/tools/toolHooks.ts` | Tool hooks |

---

**Series Navigation:**
- Previous: [Skills System: Conditional Activation and Dynamic Discovery](/2026/04/06/084_claude-code-skills-system/)
- Next: [Cross-Session Memory: Four Types and Auto-Extraction](/2026/04/06/081_claude-code-memory-system/)
