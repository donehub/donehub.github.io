---
title: "The Seven-Step Tool Pipeline, from Definition to Execution"
date: 2026-04-06
tags: Tool System
categories: Claude Code
lang: en
label: 087_claude-code-tool-system
---

## Tools Are More Than Function Calls

In most agent frameworks, a tool is just a decorated function — take parameters, return results. Claude Code goes well beyond that. Each tool is a self-describing entity that exposes identity, capabilities, lifecycle hooks, rendering logic, and smart features through one interface. The framework doesn't need to know a tool's internal implementation — it calls standard interfaces to complete validation, permission checks, execution, and result handling.

<!-- more -->

```typescript
type Tool<Input, Output> = {
  // Identity
  name: string
  aliases?: string[]
  searchHint?: string

  // Capability declarations
  isEnabled(): boolean
  isConcurrencySafe(input): boolean
  isReadOnly(input): boolean
  isDestructive(input): boolean

  // Lifecycle
  validateInput(input, context)
  checkPermissions(input, context)
  call(input, context, canUseTool, parentMessage, onProgress)

  // Output and rendering
  renderToolUseMessage(input)
  renderToolResultMessage(content)
  mapToolResultToToolResultBlockParam()

  // Smart features
  inputSchema: Zod schema
  maxResultSizeChars: number
  getToolUseSummary?(input): string
  shouldDefer?: boolean
  toAutoClassifierInput?(input): string
}
```

`src/Tool.ts` runs about 792 lines and defines this complete interface. The capability declarations (isReadOnly, isDestructive, isConcurrencySafe) let the framework make scheduling and permission decisions without knowing a tool's implementation. For example, parallel execution only selects tools where `isConcurrencySafe` returns true, and the permission system's fast path relies on the `isReadOnly` check.

## Tool Registration: A Three-Stage Pipeline

The tool pool is built in three stages. Stage one collects all 48+ built-in tools while applying feature flag filtering (for instance, removing the Agent tool when Fork Subagent isn't enabled). Stage two filters based on runtime context: permission mode (`dontAsk` mode keeps only read-only tools), REPL mode compatibility, and each tool's own `isEnabled()` check. Stage three merges MCP tools — tools from connected MCP servers get named in `mcp__{serverName}__{toolName}` format, then merge with built-in tools and go through deduplication and sorting.

```typescript
export function assembleToolPool(baseTools, mcpClients): Tools {
  const mcpTools = []
  for (const client of mcpClients) {
    if (client.type !== 'connected') continue
    for (const mcpTool of client.tools) {
      const name = `mcp__${normalizeNameForMCP(client.name)}__${mcpTool.name}`
      mcpTools.push(convertMcpToolToTool(name, mcpTool, client))
    }
  }
  // Built-in first, deduplicate, sort (ensures cache stability)
  return mergeAndDeduplicate(baseTools, mcpTools)
}
```

Sorting is there for cache stability. If tool order shuffled on every request, the API's prompt cache would miss because the tool definitions looked different. Fixed sorting keeps tool definitions consistent across requests.

## The Seven-Step Execution Pipeline

A single tool call starts when the model emits a `tool_use` block and passes through seven pipeline steps before reaching actual execution.

**Step 1 — Tool Lookup**: Exact name match first. If that fails, try aliases (for backward compatibility), then check the MCP tool namespace. `findToolByName()` returns the tool object or undefined.

**Step 2 — Input Parsing**: Zod schemas validate the model-generated input for type correctness. On validation failure, the Zod error gets formatted and returned to the model so it can fix the input and retry. This runs before the permission check, ensuring invalid input never triggers a permission dialog.

```typescript
const parseResult = tool.inputSchema.safeParse(input)
if (!parseResult.success) {
  return {
    type: 'tool_result',
    content: formatZodValidationError(parseResult.error),
    is_error: true,
    tool_use_id: toolUseId,
  }
}
```

**Step 3 — Custom Validation**: Zod handles type-level validation, but some tools need business-level checks on top. FileEditTool verifies file existence, file size (1 GiB limit), whether the file has been read, and whether it was modified externally after being read. These checks complete before permission checks, avoiding permission prompts for invalid operations.

**Step 4 — Pre-Tool Hook**: Runs user-defined PreToolUse hooks. Exit code 0 means success (possibly with modified input parameters), exit code 2 means block (error message returned to model), other exit codes get shown to the user. Hooks can intercept tool calls, modify input parameters, or pass through directly.

**Step 5 — Permission Check**: Five-layer permission decision (rules, mode, hooks, classifier, user confirmation). Deny rules have highest priority, bypass mode passes through directly, and unresolved operations use `behavior: 'ask'` to show a confirmation dialog. The permission check result includes the decision reason (rule/mode/hook/classifier/user) for debugging and auditing.

**Step 6 — Actual Execution**: Calls `tool.call()` with the validated input, context, permission callback, parent message, and progress callback. Execution time gets recorded in statistics. Errors are classified (network errors, timeouts, permission errors, etc.), and the classification affects the model's subsequent decisions.

**Step 7 — Post-Tool Hook**: Runs user-defined PostToolUse hooks, typically for automated checks (lint, format, test). The hook receives the tool name, input, and result (including whether it was an error), and can trigger follow-up actions accordingly.

The ordering of these seven steps follows clear logic: validation runs first so permission checks don't trigger for invalid input, hooks before permissions can modify input, permissions intercept dangerous operations before execution, and post-hooks handle side effects after execution.

## Lazy Tool Loading

The schemas for 48+ built-in tools total around 15,000 tokens. Loading all of them into every API request would be excessive overhead for short conversations. The lazy loading mechanism lists infrequently-used tools by name only in the initial prompt. When the model needs one, it fetches the full schema through the ToolSearch tool.

```
Model sees: "The following tools are available but deferred: NotebookEdit, ..."
Model calls: ToolSearch({ query: "notebook" })
Returns:     Full schema and usage instructions for NotebookEdit
Model calls: NotebookEdit({ ... })
```

Tools declare lazy loading through `shouldDefer: true` and `searchHint`. The initial prompt only contains core tools (about 5,000 tokens), and lazy loading saves roughly 66% of tool-related tokens. For long conversations, this saving gets diluted by the conversation itself. But for frequent short requests (like one-off queries), lazy loading delivers significant benefits.

## Tool Result Management

Large tool results (over 20,000 characters) don't get injected directly into context. Instead, they're saved to disk, and the context retains only the first 4,096 characters as a preview plus the file path. The model can use the Read tool to view the full content. This design prevents a single tool call from consuming a large chunk of the context budget.

```typescript
const TOOL_RESULT_PERSIST_THRESHOLD_CHARS = 20_000

async function processToolResultBlock(tool, result, toolUseID): Promise<ToolResultBlockParam> {
  if (result.length > TOOL_RESULT_PERSIST_THRESHOLD_CHARS) {
    const filePath = getToolResultPath(toolUseID)
    await writeFile(filePath, result)
    const preview = result.slice(0, 4096)
    return {
      content: `${preview}\n\n[Output saved to ${filePath}. Use Read tool to view full output.]`,
      tool_use_id: toolUseID,
    }
  }
  return { content: result, tool_use_id: toolUseID }
}
```

File read state caching (FileStateCache) records each file's read timestamp and content, which FileEditTool uses to detect concurrent modifications. Before editing, it verifies the file hasn't been externally modified since the last read, preventing overwrites of other people's changes.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/Tool.ts` | Tool type definition and builder |
| `src/tools.ts` | Tool discovery and registration |
| `src/services/tools/toolExecution.ts` | Execution pipeline |
| `src/services/tools/toolOrchestration.ts` | Parallel/serial strategies |
| `src/services/tools/toolHooks.ts` | Hook execution |
| `src/utils/toolResultStorage.ts` | Result storage |
| `src/utils/fileStateCache.ts` | File state cache |

---

**Series Navigation:**
- Previous: [Breaking the ReAct Myth: Async Generator State Machine](/2026/04/06/077_claude-code-async-generator-state-machine/)
- Next: [Four Approaches to Multi-Agent Orchestration](/2026/04/06/082_claude-code-multi-agent/)
