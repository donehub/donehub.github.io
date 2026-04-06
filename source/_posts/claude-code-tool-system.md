---
title: 工具系统设计：从定义到执行的七步管道
date: 2026-04-06
tags: Tool System
categories: Claude Code
---

> Claude Code 有 48+ 个内置工具，每个工具都是一个完整的生命周期管理单元。从定义到执行，工具要经过七步管道：查找、解析、验证、钩子、权限、执行、后处理。这个设计使得每个工具都是自描述、自验证、自渲染的——框架不需要了解工具的内部逻辑，只需调用标准接口。

<!-- more -->

## 导读：工具不只是函数调用

在很多 AI Agent 框架中，工具只是一个简单的函数：

```python
@tool
def read_file(path: str) -> str:
    with open(path) as f:
        return f.read()
```

但在 Claude Code 中，工具是一个**完整的生命周期管理单元**：

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
  call(input, context, ...)

  // 输出与渲染
  renderToolUseMessage(input)
  renderToolResultMessage(content)
  mapToolResultToToolResultBlockParam()

  // 智能特性
  inputSchema: Zod schema
  maxResultSizeChars: number
  getToolUseSummary?(input): string
}
```

这种设计使得每个工具都是**自描述、自验证、自渲染**的——框架不需要了解工具的内部逻辑，只需调用标准接口。

---

## 一、工具的定义：不只是名称和函数

### 1.1 Tool 接口详解

`src/Tool.ts`（约 792 行）定义了工具的完整接口：

```typescript
export type Tool<Input, Output, P extends ToolProgressData> = {
  // ===== 身份 =====
  name: string                    // 工具名称
  aliases?: string[]              // 向后兼容的旧名称
  searchHint?: string             // ToolSearch 关键词匹配

  // ===== 能力声明 =====
  isEnabled(): boolean            // 是否可用
  isConcurrencySafe(input): boolean   // 是否可并行执行
  isReadOnly(input): boolean          // 是否只读操作
  isDestructive?(input): boolean      // 是否破坏性操作

  // ===== 生命周期 =====
  validateInput?(input, context): Promise<ValidationResult>  // 输入验证
  checkPermissions?(input, context): Promise<PermissionResult>  // 权限检查
  call(input, context, canUseTool, parentMessage, onProgress): Promise<ToolResult<Output>>  // 执行

  // ===== 输出与渲染 =====
  renderToolUseMessage?(input): ReactNode     // 渲染调用信息
  renderToolResultMessage?(content): ReactNode  // 渲染结果
  renderToolUseProgressMessage?(...): ReactNode  // 渲染进度
  mapToolResultToToolResultBlockParam?(...): ToolResultBlockParam  // 映射为 API 格式

  // ===== 智能特性 =====
  inputSchema: Input                        // Zod schema
  outputSchema?: z.ZodType<Output>          // 输出 schema
  maxResultSizeChars?: number               // 结果大小阈值
  getToolUseSummary?(input): string         // 工具使用摘要
  shouldDefer?: boolean                     // 是否延迟加载
  alwaysLoad?: boolean                      // 是否始终加载
  toAutoClassifierInput?(input): string     // 安全分类器输入
  preparePermissionMatcher?(input): Promise<(pattern: string) => boolean>  // 权限匹配器
}
```

### 1.2 buildTool 工厂函数

`buildTool()` 函数提供了工具定义的便捷方式：

```typescript
export const BashTool = buildTool({
  name: 'Bash',
  description: async (input) => `Execute command: ${input.command}`,
  inputSchema: z.object({
    command: z.string(),
    timeout: z.number().optional(),
  }),
  isConcurrencySafe: (input) => false,  // Bash 可能修改状态
  isReadOnly: (input) => isReadOnlyCommand(input.command),
  isDestructive: (input) => isDestructiveCommand(input.command),
  validateInput: async (input, context) => { /* ... */ },
  checkPermissions: async (input, context) => { /* ... */ },
  call: async (input, context, canUseTool, parentMessage, onProgress) => { /* ... */ },
  // ...
})
```

---

## 二、工具注册：三阶段流水线

工具的发现和注册分三个阶段（`src/tools.ts`）：

### 2.1 阶段1：基础工具池

```typescript
// src/tools.ts:50-150
export function getAllBaseTools(): Tools {
  return [
    // 文件操作
    FileReadTool,
    FileEditTool,
    FileWriteTool,
    GlobTool,
    GrepTool,
    
    // Shell 执行
    BashTool,
    PowerShellTool,
    
    // 网络
    WebFetchTool,
    WebSearchTool,
    
    // Agent 编排
    AgentTool,
    TeamCreateTool,
    SendMessageTool,
    
    // 任务管理
    TaskCreateTool,
    TaskOutputTool,
    TodoWriteTool,
    
    // 其他...
    AskUserQuestionTool,
    SkillTool,
    SleepTool,
    // ... 共 48+ 个
  ].filter(tool => {
    // Feature Flag 过滤
    if (tool.name === 'Agent' && !feature('FORK_SUBAGENT')) return false
    return true
  })
}
```

### 2.2 阶段2：过滤

```typescript
// src/tools.ts:200-280
export function getTools(
  baseTools: Tools,
  permissionContext: ToolPermissionContext,
  options: GetToolsOptions,
): Tools {
  return baseTools.filter(tool => {
    // 1. 权限模式过滤
    if (permissionContext.mode === 'dontAsk' && !tool.isReadOnly?.()) {
      return false
    }
    
    // 2. REPL 模式过滤
    if (options.isReplMode && !isReplCompatible(tool)) {
      return false
    }
    
    // 3. isEnabled 检查
    if (!tool.isEnabled()) {
      return false
    }
    
    return true
  })
}
```

### 2.3 阶段3：MCP 合并

```typescript
// src/tools.ts:300-350
export function assembleToolPool(
  baseTools: Tools,
  mcpClients: MCPServerConnection[],
): Tools {
  const mcpTools: Tools = []
  
  for (const client of mcpClients) {
    if (client.type !== 'connected') continue
    
    for (const mcpTool of client.tools) {
      // MCP 工具命名：mcp__{serverName}__{toolName}
      const name = `mcp__${normalizeNameForMCP(client.name)}__${mcpTool.name}`
      mcpTools.push(convertMcpToolToTool(name, mcpTool, client))
    }
  }
  
  // 合并：内置优先，去重，排序（缓存稳定性）
  return mergeAndDeduplicate(baseTools, mcpTools)
}
```

**工具池构建流程图：**

```
getAllBaseTools()
  │  48+ 个内置工具
  │  + Feature Flag 过滤
  │
  ▼
getTools()
  │  权限模式过滤
  │  REPL 模式过滤
  │  isEnabled() 过滤
  │
  ▼
assembleToolPool()
  │  + MCP 工具
  │  去重（内置优先）
  │  排序（缓存稳定性）
  │
  ▼
最终工具池
```

---

## 三、七步执行管道

一次工具调用要经过**7 步管道**（`src/services/tools/toolExecution.ts`）：

```
┌─────────────────────────────────────────────────────────────┐
│                    工具执行管道                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step 1: 工具查找                                           │
│    └─ findToolByName(name) → 支持别名回退                   │
│                                                             │
│  Step 2: 输入解析（Zod）                                     │
│    └─ inputSchema.safeParse(input) → 类型验证               │
│                                                             │
│  Step 3: 自定义验证                                         │
│    └─ tool.validateInput?(input, context)                   │
│                                                             │
│  Step 4: Pre-Tool 钩子                                      │
│    └─ runPreToolUseHooks(tool, input, context)              │
│       ├─ 退出码 0: 成功，继续                               │
│       ├─ 退出码 2: 阻塞，展示错误                           │
│       └─ 其他: 展示给用户                                   │
│                                                             │
│  Step 5: 权限检查                                           │
│    └─ hasPermissionsToUseTool(tool, input, context)         │
│       ├─ behavior: 'allow' → 继续                           │
│       ├─ behavior: 'deny' → 返回拒绝                        │
│       └─ behavior: 'ask' → 弹出确认对话框                   │
│                                                             │
│  Step 6: 实际执行                                           │
│    └─ tool.call(input, context, canUseTool, ...)            │
│       ├─ 成功 → ToolResult                                  │
│       └─ 失败 → ToolError                                   │
│                                                             │
│  Step 7: Post-Tool 钩子                                     │
│    └─ runPostToolUseHooks(tool, input, result)              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.1 Step 1: 工具查找

```typescript
// src/Tool.ts:500-530
export function findToolByName(
  name: string,
  tools: Tools,
): Tool<unknown, unknown, ToolProgressData> | undefined {
  // 1. 精确匹配
  const exact = tools.find(t => t.name === name)
  if (exact) return exact
  
  // 2. 别名匹配（向后兼容）
  for (const tool of tools) {
    if (tool.aliases?.includes(name)) {
      return tool
    }
  }
  
  // 3. MCP 工具特殊处理
  if (name.startsWith('mcp__')) {
    return findMcpTool(name, tools)
  }
  
  return undefined
}
```

### 3.2 Step 2: 输入解析

```typescript
// src/services/tools/toolExecution.ts:200-230
const parseResult = tool.inputSchema.safeParse(input)
if (!parseResult.success) {
  const formattedError = formatZodValidationError(parseResult.error)
  return {
    type: 'tool_result',
    content: formattedError,
    is_error: true,
    tool_use_id: toolUseId,
  }
}
const validatedInput = parseResult.data
```

### 3.3 Step 3: 自定义验证

某些工具需要额外的验证逻辑：

```typescript
// src/tools/FileEditTool/FileEditTool.ts:150-200
async validateInput(input, context): Promise<ValidationResult> {
  // 1. 文件存在性检查
  if (!await fileExists(input.file_path)) {
    return { result: false, message: 'File does not exist', errorCode: 1 }
  }
  
  // 2. 文件大小限制
  const stats = await stat(input.file_path)
  if (stats.size > 1_000_000_000) {  // 1 GiB
    return { result: false, message: 'File too large', errorCode: 2 }
  }
  
  // 3. 必须先读取
  const readState = context.readFileState.get(input.file_path)
  if (!readState) {
    return { result: false, message: 'Must read file before editing', errorCode: 3 }
  }
  
  // 4. 文件未被修改
  const currentMtime = (await stat(input.file_path)).mtimeMs
  if (currentMtime > readState.timestamp) {
    return { result: false, message: 'File was modified after reading', errorCode: 4 }
  }
  
  return { result: true }
}
```

### 3.4 Step 4: Pre-Tool 钩子

```typescript
// src/services/tools/toolHooks.ts:50-100
export async function runPreToolUseHooks(
  tool: Tool,
  input: unknown,
  context: ToolUseContext,
): Promise<HookResult> {
  const hooks = getHooksForTool(tool.name, context)
  
  for (const hook of hooks) {
    const result = await executeHook(hook, {
      tool_name: tool.name,
      tool_input: input,
    })
    
    if (result.exitCode === 2) {
      // 阻塞：展示错误给模型
      return {
        blocked: true,
        message: result.stderr,
        modifiedInput: parseModifiedInput(result.stdout),
      }
    }
  }
  
  return { blocked: false }
}
```

### 3.5 Step 5: 权限检查

```typescript
// src/utils/permissions/permissions.ts:200-300
export async function hasPermissionsToUseTool(
  tool: Tool,
  input: unknown,
  context: ToolUseContext,
): Promise<PermissionResult> {
  // 1. 检查 deny 规则（最高优先级）
  const denyResult = checkDenyRules(tool.name, input, context)
  if (denyResult) return { behavior: 'deny', ...denyResult }
  
  // 2. 检查工具特定权限
  if (tool.checkPermissions) {
    const toolResult = await tool.checkPermissions(input, context)
    if (toolResult.behavior !== 'passthrough') {
      return toolResult
    }
  }
  
  // 3. 检查 bypass 模式
  if (context.permissionContext.mode === 'bypassPermissions') {
    return { behavior: 'allow', decisionReason: { type: 'mode' } }
  }
  
  // 4. 检查 allow 规则
  const allowResult = checkAllowRules(tool.name, input, context)
  if (allowResult) return { behavior: 'allow', ...allowResult }
  
  // 5. 默认：询问用户
  return {
    behavior: 'ask',
    message: generatePermissionMessage(tool, input),
    suggestions: generateSuggestions(tool, input),
  }
}
```

### 3.6 Step 6: 实际执行

```typescript
// src/services/tools/toolExecution.ts:400-500
const startTime = Date.now()
try {
  const result = await tool.call(
    validatedInput,
    context,
    canUseTool,
    parentMessage,
    onProgress,
  )
  
  const durationMs = Date.now() - startTime
  addToToolDuration(durationMs)
  
  return {
    type: 'tool_result',
    content: result.content,
    tool_use_id: toolUseId,
  }
} catch (error) {
  const classifiedError = classifyToolError(error)
  return {
    type: 'tool_result',
    content: `Error: ${classifiedError}`,
    is_error: true,
    tool_use_id: toolUseId,
  }
}
```

### 3.7 Step 7: Post-Tool 钩子

```typescript
// src/services/tools/toolHooks.ts:150-200
export async function runPostToolUseHooks(
  tool: Tool,
  input: unknown,
  result: ToolResult,
  context: ToolUseContext,
): Promise<void> {
  const hooks = getPostToolUseHooks(tool.name, context)
  
  for (const hook of hooks) {
    await executeHook(hook, {
      tool_name: tool.name,
      tool_input: input,
      tool_result: result.content,
      tool_result_is_error: result.is_error,
    })
  }
}
```

---

## 四、工具延迟加载

Claude Code 有 48+ 个内置工具。如果每次 API 调用都把所有工具定义发给模型，会浪费大量 token。

### 4.1 延迟加载设计

```typescript
// 工具可以标记为"延迟加载"
{
  shouldDefer: true,       // 只在 ToolSearch 中列出名称
  alwaysLoad: false,       // 不在初始提示词中包含完整 schema
  searchHint: "notebook"   // 搜索关键词
}
```

### 4.2 ToolSearch 工具

当模型需要使用延迟加载的工具时：

```
模型看到:
  "The following tools are available but deferred: NotebookEdit, ..."

模型调用:
  ToolSearch({ query: "notebook" })

返回:
  NotebookEdit 的完整 schema 和使用说明

模型调用:
  NotebookEdit({ ... })
```

**Token 节省**：
- 默认情况下，48 个工具的 schema 约 15000 tokens
- 延迟加载后，初始提示词只包含核心工具，约 5000 tokens
- 节省约 66% 的工具相关 token

---

## 五、工具结果处理

### 5.1 结果大小限制

```typescript
// src/utils/toolResultStorage.ts
const TOOL_RESULT_PERSIST_THRESHOLD_CHARS = 20_000

async function processToolResultBlock(
  tool: Tool,
  result: string,
  toolUseID: string,
): Promise<ToolResultBlockParam> {
  if (result.length > TOOL_RESULT_PERSIST_THRESHOLD_CHARS) {
    // 保存到磁盘
    const filePath = getToolResultPath(toolUseID)
    await writeFile(filePath, result)
    
    // 返回预览
    const preview = result.slice(0, 4096)
    return {
      content: `${preview}\n\n[Output saved to ${filePath}. Use Read tool to view full output.]`,
      tool_use_id: toolUseID,
    }
  }
  
  return { content: result, tool_use_id: toolUseID }
}
```

### 5.2 文件读取缓存

```typescript
// src/utils/fileStateCache.ts
class FileStateCache {
  private cache = new Map<string, {
    timestamp: number
    content: string
    offset?: number
    limit?: number
  }>()
  
  get(path: string) {
    return this.cache.get(path)
  }
  
  set(path: string, state: { timestamp: number, content: string }) {
    this.cache.set(path, state)
  }
  
  // 用于检测并发修改
  validate(path: string): boolean {
    const cached = this.cache.get(path)
    if (!cached) return false
    
    const currentMtime = statSync(path).mtimeMs
    return currentMtime <= cached.timestamp
  }
}
```

---

## 六、关键设计原则

### 6.1 自描述工具

每个工具通过接口暴露所有必要信息，框架无需了解内部：

```typescript
// 框架只知道接口，不知道实现
const isReadOnly = tool.isReadOnly?.(input)
const isDestructive = tool.isDestructive?.(input)

// 工具自己决定
tool.checkPermissions(input, context)
```

### 6.2 验证前置

输入验证在权限检查之前：

```
输入 → Zod 解析 → 自定义验证 → Pre-Tool 钩子 → 权限检查 → 执行
```

这确保了权限检查不会因为无效输入而触发。

### 6.3 钩子可扩展

钩子系统允许用户在任何阶段注入自定义逻辑：

```json
// settings.json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{ "type": "command", "command": "echo 'Bash called'" }]
    }]
  }
}
```

---

## 七、关键源文件索引

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/Tool.ts` | ~792 | Tool 类型定义和构建器 |
| `src/tools.ts` | ~389 | 工具发现和注册 |
| `src/services/tools/toolExecution.ts` | ~1500 | 执行管道 |
| `src/services/tools/toolOrchestration.ts` | ~200 | 并行/串行策略 |
| `src/services/tools/toolHooks.ts` | ~300 | 钩子执行 |
| `src/utils/toolResultStorage.ts` | ~200 | 结果存储 |
| `src/utils/fileStateCache.ts` | ~100 | 文件状态缓存 |

---

## 八、总结

Claude Code 的工具系统设计体现了几个核心原则：

1. **接口驱动**：统一的 Tool 接口，框架无需了解实现
2. **管道模式**：七步执行管道，每步职责清晰
3. **延迟加载**：减少初始 token 消耗
4. **钩子扩展**：用户可在任意阶段注入逻辑
5. **结果管理**：自动处理大型结果

这个设计使得添加新工具变得简单——只需实现 Tool 接口，框架会自动处理验证、权限、执行和结果处理。

---

**系列文章导航：**
- 上一篇：[打破 ReAct 迷思：Async Generator 状态机](/claude-code-async-generator-state-machine/)
- 下一篇：[多 Agent 编排：四种代理类型与协作机制](/claude-code-multi-agent/)