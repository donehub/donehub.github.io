---
title: 多 Agent 编排：四种代理类型与协作机制
date: 2026-04-06
tags: Multi-Agent
categories: Claude Code
---

> Claude Code 的多 Agent 系统可能是其最被低估的设计之一。它不是简单的"子代理调用"，而是一个完整的协作框架：四种 Agent 类型（Subagent、Fork、Teammate、Remote）、Teams 邮箱通信、权限同步、Worktree 隔离。这个设计让 Claude Code 能够处理单 Agent 无法完成的复杂任务。

<!-- more -->

## 导读：为什么需要多 Agent？

假设你让 Claude Code 做这件事：

> "帮我把这个项目的所有 TypeScript 文件迁移到 strict 模式，同时更新 ESLint 配置，然后运行所有测试确保没有回归。"

单 Agent 会怎么做？顺序执行：修改 tsconfig → 修改 ESLint → 修改文件 → 运行测试。每一步都要等待上一步完成。

但如果使用多 Agent：

1. **Explore Agent**：并行扫描所有 TypeScript 文件，识别需要修改的地方
2. **多个 Fork Agent**：并行修改不同的文件组
3. **Plan Agent**：协调修改顺序，避免冲突
4. **Verification Agent**：运行测试，验证修改

这就是多 Agent 编排的价值：**并行化、专业化、隔离性**。

---

## 一、五种 Agent 类型和职责

### 1.1 Agent 类型概览

```
┌─────────────────────────────────────────────────┐
│                  Agent Tool                      │
│              (入口 & 路由分发)                    │
├───────────┬───────────┬───────────┬─────────────┤
│  Subagent │  Fork     │ Teammate  │   Remote    │
│  (子代理)  │ (分叉)    │ (队友)    │   (远程)    │
│           │           │           │             │
│ 独立上下文 │ 继承上下文 │ 团队协作   │ CCR 环境   │
│ 按类型过滤 │ 缓存共享   │ 邮箱通信   │ 远程执行   │
│ 工具池     │ 字节一致   │ 权限同步   │ 轮询结果   │
└───────────┴───────────┴───────────┴─────────────┘
                        │
                  ┌─────┴─────┐
                  │ DreamTask │
                  │ (记忆整合)  │
                  │ 定时后台   │
                  └───────────┘
```

### 1.2 内置 Agent 类型

| Agent 类型 | 用途 | 工具池限制 |
|------------|------|-----------|
| **General Purpose** | 通用任务 | 全部工具 |
| **Explore** | 代码库探索 | Read, Grep, Glob, WebSearch |
| **Plan** | 制定计划 | 全部工具，但受限输出 |
| **Verification** | 验证结果 | Bash, Read, Grep |
| **Coordinator** | 编排协调 | 受限工具集 |

### 1.3 Agent 定义结构

```typescript
// src/tools/AgentTool/loadAgentsDir.ts
type AgentDefinition = {
  agentType: string              // Agent 类型标识
  description: string            // 描述
  getSystemPrompt: (context) => string  // 系统提示词
  tools?: string[]               // 允许的工具（'*' = 全部）
  disallowedTools?: string[]     // 禁止的工具
  model?: string                 // 模型选择
  permissionMode?: PermissionMode // 权限模式
  isBuiltin?: boolean            // 是否内置
}
```

---

## 二、Agent 生成流程：四条路径

### 2.1 入口：AgentTool.call()

`src/tools/AgentTool/AgentTool.tsx` 中的 `call()` 函数是所有 Agent 生成的入口：

```
AgentTool.call(input)
  │
  ├─ team_name + name? ──────→ 路径1: spawnTeammate()
  │
  ├─ run_in_background?  ────→ 路径2: registerAsyncAgent()
  │     └─ agent.background?
  │
  ├─ 省略 subagent_type? ───→ 路径3: Fork (buildForkedMessages())
  │     └─ fork 实验开启?
  │
  └─ 默认 ───────────────────→ 路径4: runAgent() 同步执行
```

### 2.2 路径1：Teammate 生成

**触发条件**：`team_name` 和 `name` 同时存在

**流程**：

```typescript
// src/tools/shared/spawnMultiAgent.ts
async function spawnTeammate(config, context) {
  // 1. 检测执行后端
  const backend = detectBackend()  // tmux / iTerm2 / in-process
  
  // 2. 生成唯一 agentId
  const agentId = formatAgentId(name, teamName)
  
  // 3. 分配颜色
  const color = assignColor(name)
  
  // 4. 创建执行环境
  if (backend === 'in-process') {
    await spawnInProcessTeammate(config, context)
  } else if (backend === 'tmux') {
    await TmuxBackend.createPane(config)
  } else if (backend === 'iTerm2') {
    await ITerm2Backend.createWindow(config)
  }
  
  // 5. 写入 TeamFile
  await updateTeamFile(teamName, { members: [...members, newMember] })
  
  return { status: 'teammate_spawned', agentId, tmuxPaneId, ... }
}
```

**In-Process 队友的隔离**：

```typescript
// src/utils/swarm/spawnInProcess.ts
async function spawnInProcessTeammate(config, context) {
  // 1. 独立的 AbortController（不随 leader 中断）
  const abortController = new AbortController()
  
  // 2. AsyncLocalStorage 上下文隔离
  runWithTeammateContext(teammateContext, async () => {
    // 3. 独立的任务状态
    // 4. 独立的消息循环
    // 5. 共享的权限管道（通过 mailbox）
  })
}
```

### 2.3 路径2：异步 Subagent

**触发条件**：`run_in_background=true` 或 Agent 定义中 `background: true`

**流程**：

```
registerAsyncAgent()
  │
  ├─ 创建 LocalAgentTask（status: 'running'）
  ├─ 注册到 agentNameRegistry（如有 name）
  ├─ 创建输出文件符号链接
  ├─ 创建 AbortController（链接到父代理）
  ├─ 发射 SDK event: task_started
  │
  └─ void runAsyncAgentLifecycle()  ← 异步分离执行
       │
       ├─ 创建 ProgressTracker
       ├─ 遍历 makeStream() 生成器
       │   ├─ 追加消息到 agentMessages[]
       │   ├─ 更新进度（tokens、tools、activities）
       │   └─ 发射 SDK progress events
       │
       └─ 完成时：
           ├─ finalizeAgentTool()（提取结果）
           ├─ completeAgentTask()（标记完成）
           ├─ 清理 worktree（如有隔离）
           └─ enqueuePendingNotification()（通知主代理）
```

### 2.4 路径3：Fork Subagent

**触发条件**：省略 `subagent_type` 且 Fork 实验开启

**核心优化**：通过字节级一致的 API 请求前缀，实现 **prompt cache 命中**。

```
buildForkedMessages(directive, assistantMessage)
  │
  ├─ 保留父代理完整的 assistant message（所有 tool_use 块）
  ├─ 构建 user message：
  │   ├─ 对每个 tool_use 创建占位 tool_result（字节一致）
  │   └─ 追加 per-child directive（唯一差异部分）
  │
  └─ 结果：字节级一致的 API 前缀 → prompt cache 命中！
```

**Fork 子代理的行为约束**（通过 `FORK_BOILERPLATE_TAG` 注入）：

```
1. 你是分叉的工作进程，不是主代理
2. 不要对话、提问或建议后续步骤
3. 直接使用工具（Bash、Read、Write 等）
4. 如修改文件，在报告前提交更改
5. 工具调用之间不要输出文本
6. 严格限制在指令范围内
7. 报告控制在 500 词以内
8. 响应必须以 "Scope:" 开头
```

### 2.5 路径4：同步 Subagent

**触发条件**：默认路径（无 team_name、无 background、非 fork）

**流程**：

```
runAgent(promptMessages, toolUseContext, options)
  │
  ├─ 解析 Agent 定义（getSystemPrompt、tools、permissions）
  ├─ 构建系统提示词（buildEffectiveSystemPrompt）
  ├─ 创建隔离的 ToolUseContext（createSubagentContext）
  ├─ 启动查询循环（query() async generator）
  │   ├─ 发送 API 请求
  │   ├─ 处理流式事件
  │   ├─ 执行工具调用
  │   └─ 累积消息和 usage
  │
  └─ 返回 AgentToolResult
       ├─ content: 最后 assistant 消息的文本
       ├─ totalToolUseCount
       ├─ totalDurationMs
       └─ totalTokens
```

---

## 三、工具池系统：三层过滤

### 3.1 第一层：全局禁止

`ALL_AGENT_DISALLOWED_TOOLS` — 对所有 Agent 禁止的工具：

| 工具 | 禁止原因 |
|------|----------|
| TaskOutput | 仅主代理可读取任务输出 |
| ExitPlanMode | 仅主代理可退出计划模式 |
| EnterPlanMode | 仅主代理可进入计划模式 |
| AskUserQuestion | 子代理不应直接问用户 |
| TaskStop | 仅主代理可终止任务 |
| Agent | 防止递归生成（Ant 内部例外） |

### 3.2 第二层：Agent 类型过滤

```typescript
// src/tools/AgentTool/agentToolUtils.ts
function filterToolsForAgent(tools, agentDef) {
  // 1. 移除 ALL_AGENT_DISALLOWED_TOOLS
  // 2. 如果非内置 Agent，额外移除 CUSTOM_AGENT_DISALLOWED_TOOLS
  // 3. 如果是异步 Agent，限制为 ASYNC_AGENT_ALLOWED_TOOLS
  // 4. MCP 工具始终允许
}
```

**ASYNC_AGENT_ALLOWED_TOOLS**（15 个）：

```
Read, WebSearch, TodoWrite, Grep, WebFetch, Glob,
Bash/PowerShell, FileEdit, FileWrite, NotebookEdit,
Skill, SyntheticOutput, ToolSearch, EnterWorktree, ExitWorktree
```

### 3.3 第三层：Agent 定义过滤

```typescript
function resolveAgentTools(agentDef, availableTools) {
  if (tools === ['*'] || undefined)  → 通配符，全部允许
  if (tools === ['Read', 'Grep'])    → 仅允许列表中的工具
  if (disallowedTools === ['Agent']) → 从可用工具中减去
}
```

**过滤流程图**：

```
所有可用工具
  │
  ├─ 减去 ALL_AGENT_DISALLOWED_TOOLS ──→ 通用禁止
  │
  ├─ 非内置？减去 CUSTOM_AGENT_DISALLOWED_TOOLS
  │
  ├─ 异步？限制为 ASYNC_AGENT_ALLOWED_TOOLS
  │
  ├─ 有 tools 列表？取交集
  │
  ├─ 有 disallowedTools？取差集
  │
  └─ 最终工具池
```

---

## 四、上下文传递机制

### 4.1 CacheSafeParams — 缓存安全参数

```typescript
// src/utils/forkedAgent.ts
type CacheSafeParams = {
  systemPrompt: SystemPrompt       // 系统提示词
  userContext: { [k: string]: string }  // 目录结构、CLAUDE.md 等
  systemContext: { [k: string]: string } // git status、环境信息
  toolUseContext: ToolUseContext    // 工具配置、模型、选项
  forkContextMessages: Message[]   // Fork 上下文消息（用于缓存共享）
}
```

**缓存共享原理**：

```
┌─────────────────────────────────────────┐
│         共享前缀（字节一致）              │
│  ┌──────────────────────────────────┐   │
│  │ System Prompt                    │   │
│  │ User Context                     │   │
│  │ System Context                   │   │
│  │ Tool Use Context                 │   │
│  │ 对话历史 Messages                │   │
│  │ Assistant Message (all tool_use) │   │
│  │ User Message (placeholder results)│  │
│  └──────────────────────────────────┘   │
├─────────────────────────────────────────┤
│  唯一差异：per-child directive text      │
└─────────────────────────────────────────┘
```

### 4.2 SubagentContext — 子代理上下文隔离

```typescript
type SubagentContextOverrides = {
  options?: ToolUseContext['options']           // 自定义工具、模型
  agentId?: AgentId                            // 子代理 ID
  agentType?: string                           // Agent 类型
  messages?: Message[]                         // 自定义消息历史
  readFileState?: ToolUseContext['readFileState'] // 文件读取缓存
  abortController?: AbortController            // 中止控制器

  // 显式 opt-in 共享（默认隔离）
  shareSetAppState?: boolean                   // 共享 AppState 写入
  shareSetResponseLength?: boolean             // 共享响应长度度量
  shareAbortController?: boolean               // 共享中止控制器

  // 实验性注入
  criticalSystemReminder_EXPERIMENTAL?: string // 每轮重新注入的提醒
  contentReplacementState?: ContentReplacementState
}
```

**隔离 vs 共享**：

| 资源 | 默认 | 说明 |
|------|------|------|
| readFileState | 克隆 | 文件读取缓存独立 |
| messages | 新建 | 消息历史独立 |
| abortController | 新建（链接父） | 父取消时子也取消 |
| setAppState | No-op | 默认不影响父状态 |
| contentReplacementState | 克隆 | 内容替换状态独立 |

---

## 五、Agent Teams：邮箱通信

### 5.1 TeamFile 结构

```typescript
// 存储路径：~/.claude/teams/{team_name}/config.json
{
  name: string                        // 团队名称
  description?: string                // 团队描述
  createdAt: number                   // 创建时间戳
  leadAgentId: string                 // Team Lead 的 Agent ID
  leadSessionId?: string              // Lead 的会话 UUID
  hiddenPaneIds?: string[]            // UI 中隐藏的 pane
  teamAllowedPaths?: TeamAllowedPath[] // 团队级共享权限
  members: Array<{
    agentId: string                   // 成员 Agent ID
    name: string                      // 显示名称
    agentType?: string                // 角色类型
    model?: string                    // 使用的模型
    prompt?: string                   // 初始任务
    color?: string                    // UI 颜色
    planModeRequired?: boolean        // 是否需要 plan 审批
    joinedAt: number                  // 加入时间
    tmuxPaneId: string                // 终端 pane ID
    cwd: string                       // 工作目录
    worktreePath?: string             // Worktree 路径
    sessionId?: string                // 会话 ID
    subscriptions: string[]           // 消息订阅
    backendType?: 'tmux'|'iterm2'|'in-process'
    isActive?: boolean                // false=空闲, true/undefined=活跃
    mode?: PermissionMode             // 当前权限模式
  }>
}
```

### 5.2 邮箱系统

**存储路径**：`~/.claude/teams/{team_name}/inboxes/{agent_name}.json`

```typescript
type TeammateMessage = {
  from: string        // 发送者名称
  text: string        // 消息内容（纯文本或 JSON）
  timestamp: string   // ISO 时间戳
  read: boolean       // 是否已读
  color?: string      // 发送者颜色
  summary?: string    // 5-10 词摘要
}
```

**并发安全**：使用 `proper-lockfile` 文件锁，10 次重试，5-100ms 指数退避。

### 5.3 收件箱轮询

```typescript
// src/hooks/useInboxPoller.ts
// 轮询间隔：1000ms

useEffect(() => {
  const interval = setInterval(async () => {
    const messages = await readUnreadMessages(agentName, teamName)
    
    for (const msg of messages) {
      if (isShutdownRequest(msg.text)) {
        // 处理关停请求
      } else if (isPlanApprovalResponse(msg.text)) {
        // 处理 plan 审批
      } else if (isPermissionRequest(msg.text)) {
        // 路由到权限系统
      } else {
        // 纯文本消息 → 提交为新对话轮
        onSubmitMessage(formatted)
      }
    }
  }, INBOX_POLL_INTERVAL_MS)
}, [])
```

### 5.4 消息路由

```
SendMessage({ to, message })
  │
  ├─ to === "*" → 广播
  │   └─ 遍历所有队友，逐个写入 mailbox
  │
  ├─ agentNameRegistry.has(to) → in-process 子代理
  │   └─ 通过 AppState pending messages 队列路由
  │
  ├─ teamFile.members.find(to) → 进程级队友
  │   └─ writeToMailbox(to, message, teamName)
  │
  ├─ to.startsWith("bridge:") → 远程会话
  │   └─ postInterClaudeMessage(sessionId, message)
  │
  └─ to.startsWith("uds:") → Unix Domain Socket
      └─ sendToUdsSocket(socketPath, message)
```

---

## 六、Worktree 隔离

### 6.1 创建流程

```typescript
// src/utils/worktree.ts
async function createAgentWorktree(slug) {
  // 1. 校验 slug（防目录逃逸攻击）
  validateWorktreeSlug(slug)
  
  // 2. 创建 git worktree
  git worktree add {path} -b {branch}
  
  // 3. 符号链接大目录（节省磁盘）
  symlink(node_modules, worktree/node_modules)
  
  // 4. 应用 sparse-checkout（如配置）
  if (sparseCheckoutPaths) {
    git sparse-checkout set {paths}
  }
  
  // 5. 返回 WorktreeSession
  return { worktreePath, worktreeBranch, headCommit }
}
```

### 6.2 清理机制

- Agent 完成后自动检测是否有改动（`hasWorktreeChanges()`）
- 有改动：返回 worktree 路径和分支名给用户
- 无改动：自动删除 worktree（`removeAgentWorktree()`）
- 异常退出：通过 `registerTeamForSessionCleanup()` 确保清理

---

## 七、权限同步机制

### 7.1 团队级权限

```typescript
type TeamAllowedPath = {
  path: string        // 绝对目录路径
  toolName: string    // 适用的工具（如 "Edit", "Write"）
  addedBy: string     // 添加者名称
  addedAt: number     // 添加时间
}
```

队友启动时，自动继承团队级权限规则。

### 7.2 Bubble 模式

Fork Agent 使用 `bubble` 权限模式 — 权限提示冒泡到父代理终端：

```
Fork Agent 需要权限
  │
  └─ bubble 模式 → 权限请求发送到父代理
       │
       └─ 父代理的 ToolUseConfirm 对话框显示
            │
            ├─ 用户批准 → 结果回传给 Fork Agent
            └─ 用户拒绝 → Fork Agent 收到拒绝
```

---

## 八、关键源文件索引

| 文件 | 职责 |
|------|------|
| `src/tools/AgentTool/AgentTool.tsx` | 主工具实现，路由分发 |
| `src/tools/AgentTool/runAgent.ts` | 执行引擎，查询循环 |
| `src/tools/AgentTool/agentToolUtils.ts` | 工具池解析，结果终结 |
| `src/tools/AgentTool/forkSubagent.ts` | Fork 语义，消息继承 |
| `src/tools/AgentTool/loadAgentsDir.ts` | Agent 定义类型，解析加载 |
| `src/tools/AgentTool/builtInAgents.ts` | 内置 Agent 注册表 |
| `src/tools/shared/spawnMultiAgent.ts` | 队友生成入口 |
| `src/utils/swarm/spawnInProcess.ts` | 进程内队友生成 |
| `src/utils/swarm/teamHelpers.ts` | 团队文件读写 |
| `src/utils/teammateMailbox.ts` | 邮箱消息队列 |
| `src/utils/forkedAgent.ts` | 缓存安全参数，子代理上下文 |
| `src/utils/worktree.ts` | Git worktree 隔离 |
| `src/tasks/LocalAgentTask/LocalAgentTask.tsx` | 本地 Agent 任务 |

---

## 九、总结

Claude Code 的多 Agent 系统设计体现了几个核心原则：

1. **分层编排**：四种 Agent 类型，满足不同场景需求
2. **上下文隔离**：子代理默认独立上下文，显式 opt-in 共享
3. **缓存优化**：Fork Agent 通过字节一致前缀实现 prompt cache 共享
4. **邮箱通信**：Teams 通过文件系统邮箱实现异步协作
5. **权限同步**：团队级权限自动继承，Bubble 模式支持权限冒泡
6. **Worktree 隔离**：安全的实验性修改环境

这个设计使得 Claude Code 能够处理单 Agent 无法完成的复杂任务，同时保持系统的稳定性和可观测性。

---

**系列文章导航：**
- 上一篇：[工具系统设计：从定义到执行的七步管道](/claude-code-tool-system/)
- 下一篇：[Context 管理：四级压缩与无限对话的秘密](/claude-code-context-compression/)