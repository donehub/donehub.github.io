---
title: 从定义到执行的七步工具管道
date: 2026-04-06
tags: Tool System
categories: Claude Code
---

<!-- more -->

## 工具不只是函数调用

在多数 AI Agent 框架中，工具只是一个带装饰器的函数：接收参数，返回结果。Claude Code 的工具设计远超这个层次。每个工具是一个自描述的实体，通过统一接口向框架暴露身份、能力声明、生命周期钩子、渲染逻辑和智能特性。框架不需要了解工具的内部实现，只需调用标准接口即可完成验证、权限检查、执行和结果处理。

```typescript
type Tool<Input, Output> = {
  // 身份
  name: string
  aliases?: string[]
  searchHint?: string

  // 能力声明
  isEnabled(): boolean
  isConcurrencySafe(input): boolean
  isReadOnly(input): boolean
  isDestructive(input): boolean

  // 生命周期
  validateInput(input, context)
  checkPermissions(input, context)
  call(input, context, canUseTool, parentMessage, onProgress)

  // 输出与渲染
  renderToolUseMessage(input)
  renderToolResultMessage(content)
  mapToolResultToToolResultBlockParam()

  // 智能特性
  inputSchema: Zod schema
  maxResultSizeChars: number
  getToolUseSummary?(input): string
  shouldDefer?: boolean
  toAutoClassifierInput?(input): string
}
```

`src/Tool.ts` 约 792 行，定义了这个完整接口。能力声明（isReadOnly、isDestructive、isConcurrencySafe）让框架在不了解工具实现的前提下做出调度和权限决策。例如，并行执行只选择 `isConcurrencySafe` 返回 true 的工具，权限系统的快速路径依赖 `isReadOnly` 判断。

## 工具注册：三阶段流水线

工具池的构建经过三个阶段。第一阶段收集全部 48+ 个内置工具，同时应用 Feature Flag 过滤（如 Fork Subagent 功能未开启时移除 Agent 工具）。第二阶段根据运行时上下文过滤：权限模式（`dontAsk` 模式只保留只读工具）、REPL 模式兼容性、以及工具自身的 `isEnabled()` 检查。第三阶段合并 MCP 工具，已连接的 MCP 服务器提供的工具以 `mcp__{serverName}__{toolName}` 格式命名，与内置工具合并后去重排序。

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
  // 内置优先，去重，排序（保证缓存稳定性）
  return mergeAndDeduplicate(baseTools, mcpTools)
}
```

排序的目的是缓存稳定性。如果工具顺序每次都不同，API 层的 prompt cache 会因为工具定义顺序变化而失效。固定排序确保工具定义在多次请求间保持一致。

## 七步执行管道

一次工具调用从模型发出 `tool_use` 块开始，经过七步管道到达实际执行。

**Step 1 工具查找**：先精确匹配工具名称，匹配失败则尝试别名（向后兼容），最后检查 MCP 工具命名空间。`findToolByName()` 返回工具对象或 undefined。

**Step 2 输入解析**：使用 Zod schema 对模型生成的输入做类型验证。验证失败时，将 Zod 的错误信息格式化后返回给模型，让模型修正输入重新尝试。这一步在权限检查之前执行，确保无效输入不会触发权限对话框。

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

**Step 3 自定义验证**：Zod 处理类型层面的验证，某些工具需要业务层面的额外检查。FileEditTool 验证文件存在性、文件大小（上限 1 GiB）、是否已读取、以及读取后是否被外部修改。这些检查在权限检查之前完成，避免为无效操作弹出权限确认。

**Step 4 Pre-Tool 钩子**：执行用户定义的 PreToolUse 钩子。退出码 0 表示成功（可能修改了输入参数），退出码 2 表示阻塞（错误信息返回给模型），其他退出码展示给用户。钩子可以拦截工具调用、修改输入参数、或直接放行。

**Step 5 权限检查**：五层权限决策（规则、模式、钩子、分类器、用户确认）。deny 规则优先级最高，bypass 模式直接放行，最终未决的操作用 `behavior: 'ask'` 弹出确认对话框。权限检查的结果包含决策原因（rule/mode/hook/classifier/user），用于调试和审计。

**Step 6 实际执行**：调用 `tool.call()`，传入验证后的输入、上下文、权限回调、父消息和进度回调。执行时间被记录到统计中。错误会被分类（网络错误、超时、权限错误等），分类结果影响模型的后续决策。

**Step 7 Post-Tool 钩子**：执行用户定义的 PostToolUse 钩子，通常用于自动化检查（lint、format、test）。钩子接收工具名称、输入和结果（包括是否为错误），可以据此触发后续操作。

七步管道的顺序有明确的逻辑：验证前置确保权限检查不会为无效输入触发，钩子在权限之前可以修改输入，权限在执行之前拦截危险操作，Post 钩子在执行之后处理副作用。

## 工具延迟加载

48+ 个内置工具的 schema 约 15000 tokens。如果全部加载到每次 API 请求中，对短对话来说开销过大。延迟加载机制让不常用的工具只在初始提示词中列出名称，模型需要时通过 ToolSearch 工具获取完整 schema。

```
模型看到: "The following tools are available but deferred: NotebookEdit, ..."
模型调用: ToolSearch({ query: "notebook" })
返回:     NotebookEdit 的完整 schema 和使用说明
模型调用: NotebookEdit({ ... })
```

工具通过 `shouldDefer: true` 和 `searchHint` 声明延迟加载属性。初始提示词只包含核心工具（约 5000 tokens），延迟加载后节省约 66% 的工具相关 token。对于长对话，这个节省会被对话本身稀释；但对于频繁的短请求（如一次性查询），延迟加载的收益显著。

## 工具结果管理

大型工具结果（超过 20000 字符）不会直接注入上下文，而是保存到磁盘，上下文中只保留前 4096 字符的预览和文件路径。模型可以通过 Read 工具查看完整内容。这个设计防止单次工具调用吃掉大量上下文预算。

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

文件读取状态缓存（FileStateCache）记录每个文件的读取时间戳和内容，用于 FileEditTool 检测并发修改。编辑前验证文件自上次读取后未被外部修改，防止覆盖其他人的更新。

## 关键源文件

| 文件 | 职责 |
|------|------|
| `src/Tool.ts` | Tool 类型定义和构建器 |
| `src/tools.ts` | 工具发现和注册 |
| `src/services/tools/toolExecution.ts` | 执行管道 |
| `src/services/tools/toolOrchestration.ts` | 并行/串行策略 |
| `src/services/tools/toolHooks.ts` | 钩子执行 |
| `src/utils/toolResultStorage.ts` | 结果存储 |
| `src/utils/fileStateCache.ts` | 文件状态缓存 |

---

**系列文章导航：**
- 上一篇：[打破 ReAct 迷思：Async Generator 状态机](/2026/04/06/077_claude-code-async-generator-state-machine/)
- 下一篇：[多 Agent 编排的四种路径](/2026/04/06/082_claude-code-multi-agent/)
