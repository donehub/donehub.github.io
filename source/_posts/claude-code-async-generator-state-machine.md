---
title: 打破 ReAct 迷思：Async Generator 状态机
date: 2026-04-06
tags: State Machine
categories: Claude Code
---

> 当大多数人谈论 AI Agent 架构时，ReAct（Reasoning + Acting）几乎是唯一的答案。但 Claude Code 选择了一条不同的路——Async Generator 状态机。这个设计决策背后有着深刻的思考，它解决了 ReAct 的根本性限制，为流式交互和优雅恢复奠定了基础。

<!-- more -->

## 导读：ReAct 的困境

如果你熟悉 AI Agent 开发，一定对 ReAct 模式不陌生：

```
思考(Thought) → 行动(Action) → 观察(Observation) → 思考 → ...
```

这个模式直观且易于理解，已经成为 LangChain、AutoGPT 等框架的标配。但当你深入使用时，会发现它有几个难以回避的问题：

**问题一：串行瓶颈**
每一轮"思考"必须等待模型生成完整响应后才能开始执行工具。用户盯着屏幕等待，体验割裂。

**问题二：无法利用流式传输**
模型支持流式输出，但 ReAct 模式下，流式传输的价值被大大削弱——你必须等待完整的 action 才能执行。

**问题三：恢复困难**
当 API 超时、Token 溢出或工具失败时，ReAct 没有统一的状态表示来支持自动恢复。

Claude Code 的解决方案是：**放弃 ReAct，使用 Async Generator 状态机**。

---

## 一、状态机的核心设计

### 1.1 State 数据结构

`src/query.ts` 定义了状态机的核心状态（第 204-217 行）：

```typescript
type State = {
  messages: Message[]                    // 完整对话历史
  toolUseContext: ToolUseContext          // 工具执行上下文
  autoCompactTracking: AutoCompactTracking  // 自动压缩追踪
  maxOutputTokensRecoveryCount: number   // 输出恢复计数
  hasAttemptedReactiveCompact: boolean   // 是否已尝试反应式压缩
  maxOutputTokensOverride: number        // 输出 token 覆盖值
  pendingToolUseSummary: Promise<...>    // 待处理的工具摘要
  stopHookActive: boolean               // 停止钩子状态
  turnCount: number                      // 对话轮数
  transition: Continue | undefined       // 状态转换原因
}
```

**关键洞察**：`transition` 字段记录了每一轮状态转换的原因。这使得调试和测试变得非常清晰——你可以精确知道为什么 Agent 从一个状态跳转到另一个状态。

### 1.2 核心循环：五个阶段

整个 `while (true)` 循环（第 307-1728 行）分为五个阶段：

```
┌─────────────────────────────────────────────────────────────┐
│                      while (true)                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  阶段1: 消息准备与智能压缩（第 365-543 行）                  │
│    ├─ Snip 压缩：智能删除旧消息中的冗余 token               │
│    ├─ Micro 压缩：修改已缓存消息的内容                      │
│    ├─ 上下文折叠：分阶段摘要历史消息                        │
│    └─ Auto Compact：通过 Claude 生成完整摘要                │
│                                                             │
│  阶段2: 流式 API 调用（第 652-954 行）                       │
│    ├─ 构建 API 请求（含 CacheSafeParams）                   │
│    ├─ 流式处理响应                                          │
│    ├─ StreamingToolExecutor 即时执行工具                    │
│    └─ 累积 usage 指标                                       │
│                                                             │
│  阶段3: 决策点（第 1062-1358 行）                            │
│    ├─ 有工具调用？→ 继续循环（阶段 4）                      │
│    └─ 无工具调用？→ 运行 Stop 钩子 → 返回结果               │
│                                                             │
│  阶段4: 工具编排执行（第 1363-1409 行）                      │
│    ├─ 分区：只读 vs 写入                                    │
│    ├─ 只读工具 → 并行执行（最多 10 个并发）                 │
│    └─ 写入工具 → 串行执行（防止竞态条件）                   │
│                                                             │
│  阶段5: 状态更新与循环（第 1704-1728 行）                    │
│    └─ state = next → continue                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 状态更新的优雅之处

这是整个设计最优雅的部分——**通过状态赋值而非递归调用驱动循环**：

```typescript
// src/query.ts:1715-1728
const next: State = {
  messages: [...messagesForQuery, ...assistantMessages, ...toolResults],
  toolUseContext: toolUseContextWithQueryTracking,
  autoCompactTracking: tracking,
  turnCount: nextTurnCount,
  transition: { reason: 'next_turn' },
}
state = next
// 回到 while(true) 循环顶部
```

没有递归，没有回调地狱，只是简单的 `state = next` 然后 `continue`。

**为什么这很重要？**

1. **内存稳定**：不会因为深度递归导致栈溢出
2. **状态可追溯**：每一轮的状态转换原因都被记录
3. **恢复可控**：任何阶段的错误都可以通过修改 state 来恢复

---

## 二、流式优先的执行模型

### 2.1 StreamingToolExecutor 的设计

Claude Code 的一个关键创新是 `StreamingToolExecutor`——当模型生成 `tool_use` 块时，工具**立即**开始运行，而不是等模型生成完整响应。

```typescript
// src/services/tools/StreamingToolExecutor.ts
class StreamingToolExecutor {
  async *processToolUseBlocks(toolUseBlocks: ToolUseBlock[]): AsyncGenerator {
    for (const block of toolUseBlocks) {
      // 在流式传输过程中就开始执行
      const result = await this.executeTool(block)
      yield result
    }
  }
}
```

**对比 ReAct**：

| 模式 | 工具执行时机 | 用户体验 |
|------|------------|---------|
| ReAct | 等待模型完整响应 | 割裂，需要等待 |
| Async Generator | 流式传输中即时执行 | 流畅，实时反馈 |

### 2.2 工具编排策略

工具执行不是简单的逐个运行，而是有精心设计的**编排策略**（`src/services/tools/toolOrchestration.ts`）：

```
工具调用列表
  │
  ├─ 分区：只读 vs 写入
  │
  ├─ 只读工具 ──→ 并行执行（最多 10 个并发）
  │   ├─ Read
  │   ├─ Grep
  │   ├─ Glob
  │   └─ WebFetch
  │
  └─ 写入工具 ──→ 串行执行（防止竞态条件）
      ├─ FileEdit
      ├─ FileWrite
      └─ Bash (非只读)
```

**设计原理**：
- 只读工具没有副作用，可以安全并行
- 写入工具可能相互影响，必须串行保证顺序
- 10 个并发限制防止资源耗尽

---

## 三、六种故障恢复策略

这是 Claude Code 最精妙的设计之一。核心循环内置了 **6 种恢复策略**，确保用户体验的稳定性：

### 3.1 恢复策略详解

| 恢复策略 | 触发条件 | 恢复方式 |
|----------|----------|----------|
| `collapse_drain_retry` | prompt 过长 | 排空已暂存的上下文折叠，重试 |
| `reactive_compact_retry` | 仍然过长 | 通过 Claude 生成摘要，重试 |
| `max_output_tokens_escalate` | 触及 8k 默认限制 | 升级到 64k 限制重试 |
| `max_output_tokens_recovery` | 触及任何限制 | 注入"继续"提示，重试（最多 3 次） |
| `stop_hook_blocking` | Stop 钩子阻塞 | 将阻塞错误注入上下文，重试 |
| `token_budget_continuation` | 预算尚余 | 注入预算提示，继续执行 |

### 3.2 恢复代码示例

每种恢复都通过修改 `state` 实现：

```typescript
// 例：prompt 过长恢复
if (error.type === 'prompt_too_long') {
  // 排空所有暂存的折叠
  const compacted = drainStagedCollapses(state.messages)
  state = { 
    ...state, 
    messages: compacted, 
    transition: { reason: 'collapse_drain_retry' } 
  }
  continue  // 回到循环顶部重试
}

// 例：max_output_tokens 恢复
if (error.type === 'max_output_tokens') {
  state = {
    ...state,
    maxOutputTokensRecoveryCount: state.maxOutputTokensRecoveryCount + 1,
    transition: { reason: 'max_output_tokens_recovery' }
  }
  // 注入"继续"提示
  messages.push(createUserMessage({ content: 'Please continue.' }))
  continue
}
```

### 3.3 为什么这些恢复策略重要？

想象一个场景：用户正在让 Claude 修改一个大型代码库，对话已经进行了 50 轮，积累了大量上下文。突然：

1. **Token 溢出** → 自动压缩，用户无感知
2. **API 超时** → 自动重试，用户无感知
3. **模型达到输出限制** → 注入"继续"，自动续写

用户几乎感觉不到任何中断。这是 Claude Code 能提供流畅体验的关键。

---

## 四、与 LangChain Agent 的具体差异

### 4.1 代码对比

**LangChain Agent（简化）：**
```python
agent = initialize_agent(tools, llm, agent="zero-shot-react-description")
result = agent.run("do something")
# 内部：LLM → parse → tool → LLM → parse → tool → ... → final answer
# 每一步都是独立的 LLM 调用
```

**Claude Code Agent（简化）：**
```typescript
for await (const msg of query({ messages, tools, systemPrompt })) {
  yield msg  // 实时产出消息
  // 内部：流式 LLM → 流式工具执行 → 状态更新 → 继续
  // 单次 API 调用可以触发多个工具，工具在流式中执行
}
```

### 4.2 关键差异

| 维度 | LangChain | Claude Code |
|------|-----------|-------------|
| 每一轮 | 独立的 LLM 调用 | 流式 API 调用 |
| 工具解析 | OutputParser 解析文本 | 原生 `tool_use` 块 |
| 执行方式 | 等待完整响应 | 流式即时执行 |
| 错误处理 | 手动 try-catch | 内置 6 种恢复 |
| 并行工具 | 需要显式编排 | 自动分区并行 |

### 4.3 与 LangGraph 的对比

LangGraph 是 LangChain 的升级版，引入了图结构：

| 维度 | LangGraph | Claude Code |
|------|-----------|-------------|
| **状态流转** | 显式图节点 + 边 | 隐式状态机（while + continue） |
| **可视化** | 可导出为图 | 状态转换原因可追溯 |
| **持久化** | Checkpoint + State | 文件系统 + 消息历史 |
| **人机交互** | interrupt_before/after | 权限系统 + 钩子 |
| **多 Agent** | 需要显式编排 | AgentTool 统一接口 |

Claude Code 的优势在于**简单性**——不需要定义图结构，一个 while 循环就能处理所有情况。

---

## 五、设计原则总结

从源码分析中，我们可以总结出以下核心设计原则：

### 5.1 最小抽象原则

与 LangChain 的"万物皆抽象"不同，Claude Code 的核心只有：
- **一个循环**（`while (true)` in `query()`）
- **一个状态**（`State` 对象）
- **一个接口**（`Tool` 类型）

没有 Agent → AgentExecutor → Chain → Memory → Callback 的嵌套抽象层。

### 5.2 原生 API 集成

Claude Code 直接使用 Anthropic API 的原生能力：
- **原生工具调用**：无需 OutputParser，直接使用 `tool_use` 块
- **原生流式传输**：无需包装层，直接消费 SSE 流
- **原生缓存**：利用 API 的 prompt caching 特性
- **原生思维链**：直接使用 extended thinking

这避免了"框架税"——LangChain 等框架在 LLM 和开发者之间增加的抽象层。

### 5.3 可观测性设计

`transition` 字段的设计体现了对可观测性的重视：

```typescript
type Continue = {
  reason: 'next_turn' 
    | 'collapse_drain_retry'
    | 'reactive_compact_retry'
    | 'max_output_tokens_recovery'
    | 'stop_hook_blocking'
    | 'token_budget_continuation'
}
```

每一轮循环都知道自己为什么继续，这对于调试和测试至关重要。

---

## 六、关键源文件索引

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/query.ts` | ~1730 | Agent 主循环，状态机核心 |
| `src/QueryEngine.ts` | ~687 | 高层封装，对外 API |
| `src/services/tools/StreamingToolExecutor.ts` | ~200 | 流式工具执行器 |
| `src/services/tools/toolOrchestration.ts` | ~150 | 工具编排策略 |
| `src/query/transitions.ts` | ~50 | 状态转换类型定义 |
| `src/query/tokenBudget.ts` | ~100 | Token 预算管理 |
| `src/query/stopHooks.ts` | ~200 | Stop 钩子处理 |

---

## 七、总结

Claude Code 的 Async Generator 状态机设计解决了 ReAct 模式的根本性限制：

1. **流式执行**：工具在模型生成过程中就开始运行
2. **状态可控**：统一的 `State` 对象，恢复只需修改状态
3. **自动恢复**：6 种内置策略确保用户体验稳定
4. **缓存友好**：静态部分全局缓存，动态部分最小化
5. **并行能力**：只读工具自动并行，写入工具串行保序

这个设计选择体现了 Claude Code 团队对产品体验的深刻理解：**用户不应该等待，也不应该因为技术问题中断**。

---

**系列文章导航：**
- 上一篇：[Claude Code 源码揭秘：整体架构概览](/claude-code-architecture-overview/)
- 下一篇：[工具系统设计：从定义到执行的七步管道](/claude-code-tool-system/)