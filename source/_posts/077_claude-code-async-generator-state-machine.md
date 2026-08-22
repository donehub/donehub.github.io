---
title: 打破 ReAct 迷思：Async Generator 状态机
date: 2026-04-06
tags: State Machine
categories: Claude Code
---

Claude Code 没有使用 ReAct 模式来驱动 Agent 循环。这个选择在 2025 年的 AI Agent 领域几乎是反直觉的，因为 ReAct（Reasoning + Acting）已经是 LangChain、AutoGPT 等框架的默认范式。但 Claude Code 选择了 Async Generator 状态机，用一套 `while (true)` + `state = next` + `continue` 的结构替代了传统的思考-行动-观察循环。这个设计决策解决了 ReAct 在流式交互和故障恢复上的根本性限制。

<!-- more -->

## ReAct 为什么不够用

ReAct 模式的核心流程是"思考 → 行动 → 观察 → 思考"，每一步都需要等模型生成完整响应后才能进入下一阶段。这个模式在演示场景中表现良好，但在生产环境中暴露出三个结构性问题。

第一是串行瓶颈。每一轮思考必须等待完整的模型输出，用户只能盯着光标闪烁。模型明明在流式生成 token，但工具执行必须等到响应结束才能开始，流式传输的价值被大幅削弱。第二是恢复能力缺失。当 API 超时、Token 溢出或工具执行失败时，ReAct 模式没有统一的状态表示来支持自动恢复，开发者只能在循环外部手动编写重试逻辑。第三是工具调度的局限。ReAct 模式下工具调用是严格串行的，一次只能执行一个工具，无法利用只读工具之间天然的可并行性。

Claude Code 的方案是放弃 ReAct 的整体框架，用 Async Generator 状态机来重构整个 Agent 循环。

## 状态机的核心设计

`src/query.ts` 定义了一个 `State` 类型作为状态机的核心数据结构，其中包含了对话历史（`messages`）、工具执行上下文（`toolUseContext`）、自动压缩追踪（`autoCompactTracking`）、输出恢复计数（`maxOutputTokensRecoveryCount`）、对话轮数（`turnCount`）等字段。这个状态对象贯穿整个 Agent 生命周期，所有的执行逻辑都围绕它展开。

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

`transition` 字段是整个设计中值得关注的一个细节。它记录了每一轮状态转换的原因，使得调试和测试时可以精确追踪 Agent 为什么从一个状态跳转到另一个状态。后续的 `Continue` 类型定义了这个字段的全部可选值，包括 `next_turn`、`collapse_drain_retry`、`reactive_compact_retry` 等六种原因。

整个 Agent 主循环位于 `src/query.ts` 的第 307-1728 行，是一个 `while (true)` 结构，内部划分为五个阶段。

**消息准备与智能压缩**（第 365-543 行）负责处理上下文膨胀问题。它包含四级压缩机制：Snip 压缩删除旧消息中的冗余 token，Micro 压缩修改已缓存消息的内容，上下文折叠分阶段摘要历史消息，Auto Compact 通过 Claude 生成完整摘要。这四级压缩逐级触发，确保上下文窗口不会溢出。

**流式 API 调用**（第 652-954 行）构建请求并消费流式响应。与传统 ReAct 不同，工具调用不需要等待模型输出完毕，`StreamingToolExecutor` 会在接收到 `tool_use` 块的流式数据时立即开始执行工具。

**决策点**（第 1062-1358 行）判断当前轮次的走向。如果模型返回了工具调用，进入工具编排阶段；如果没有工具调用，运行 Stop 钩子后返回结果。

**工具编排执行**（第 1363-1409 行）将工具调用分区处理。只读工具（Read、Grep、Glob、WebFetch）并行执行，最多 10 个并发；写入工具（FileEdit、FileWrite、非只读 Bash）串行执行，防止竞态条件。

**状态更新与循环**（第 1704-1728 行）构建下一个 State 对象，赋值给 `state` 变量，然后 `continue` 回到循环顶部。

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

这个循环结构的关键特征是驱动方式。没有递归调用，没有回调嵌套，只有一行 `state = next` 加一个 `continue`。带来的直接收益是内存稳定（不会栈溢出）、状态可追溯（每轮转换原因都有记录）、恢复可控（任何阶段出错都可以通过修改 state 重试）。

## 流式优先的工具执行

`StreamingToolExecutor` 是 Claude Code 与 ReAct 模式拉开差距的核心组件。在 ReAct 模式下，工具执行必须等待模型输出完整的 action 指令后才能开始。Claude Code 的做法是在模型流式生成 `tool_use` 块的过程中就启动工具执行，不需要等待响应结束。

```typescript
// src/services/tools/StreamingToolExecutor.ts
class StreamingToolExecutor {
  async *processToolUseBlocks(toolUseBlocks: ToolUseBlock[]): AsyncGenerator {
    for (const block of toolUseBlocks) {
      const result = await this.executeTool(block)
      yield result
    }
  }
}
```

这种设计的效果从下面的对比中可以直接看出：

| 模式 | 工具执行时机 | 用户体验 |
|------|------------|---------|
| ReAct | 等待模型完整响应后执行 | 每轮有明显的等待间隔 |
| Async Generator | 流式传输中即时执行 | 工具调用几乎无感延迟 |

工具编排层面，`src/services/tools/toolOrchestration.ts` 实现了一套分区调度策略。当模型在一轮响应中返回多个工具调用时，系统首先将它们按副作用特征分为只读和写入两组。只读工具（Read、Grep、Glob、WebFetch）没有副作用，可以安全地并行执行，上限是 10 个并发。写入工具（FileEdit、FileWrite、非只读 Bash）可能修改文件或系统状态，必须串行执行以保证顺序一致性。这个分区策略不需要用户或开发者手动指定，系统根据工具类型自动判断。

## 六种内置故障恢复

Claude Code 的主循环内置了六种恢复策略，覆盖了 Agent 运行中最常见的故障场景。每种恢复都通过修改 `state` 对象并 `continue` 实现，不需要跳出循环或抛异常。

| 恢复策略 | 触发条件 | 恢复方式 |
|----------|----------|----------|
| `collapse_drain_retry` | prompt 过长 | 排空已暂存的上下文折叠，重试 |
| `reactive_compact_retry` | 仍然过长 | 通过 Claude 生成摘要，重试 |
| `max_output_tokens_escalate` | 触及 8k 默认限制 | 升级到 64k 限制重试 |
| `max_output_tokens_recovery` | 触及任何输出限制 | 注入"继续"提示，重试（最多 3 次） |
| `stop_hook_blocking` | Stop 钩子阻塞 | 将阻塞错误注入上下文，重试 |
| `token_budget_continuation` | 预算尚余 | 注入预算提示，继续执行 |

恢复逻辑的实现方式统一且简洁。以 prompt 过长为例，系统首先尝试排空所有暂存的上下文折叠（`drainStagedCollapses`），缩短消息列表后重试。如果仍然超长，则升级到反应式压缩（`reactive_compact`），通过 Claude 对历史消息生成摘要来缩减 token 数。

```typescript
// prompt 过长恢复
if (error.type === 'prompt_too_long') {
  const compacted = drainStagedCollapses(state.messages)
  state = { 
    ...state, 
    messages: compacted, 
    transition: { reason: 'collapse_drain_retry' } 
  }
  continue
}

// max_output_tokens 恢复
if (error.type === 'max_output_tokens') {
  state = {
    ...state,
    maxOutputTokensRecoveryCount: state.maxOutputTokensRecoveryCount + 1,
    transition: { reason: 'max_output_tokens_recovery' }
  }
  messages.push(createUserMessage({ content: 'Please continue.' }))
  continue
}
```

这套机制的实际效果是：当用户在一个 50 轮的长对话中遇到 Token 溢出，系统会自动触发压缩，用户无感知；API 超时时自动重试；模型达到输出上限时注入"继续"提示自动续写。整个过程中用户几乎不会遇到中断。

## 与 LangChain 和 LangGraph 的差异

LangChain 的 Agent 实现基于 ReAct 模式，每一轮都是独立的 LLM 调用，工具解析依赖 OutputParser 从文本中提取 action 指令，错误处理需要开发者手动编写 try-catch。Claude Code 则直接使用 Anthropic API 的原生 `tool_use` 块进行工具调用，无需 OutputParser 层，流式响应中即时执行工具，并内置六种自动恢复策略。

| 维度 | LangChain | Claude Code |
|------|-----------|-------------|
| 每一轮 | 独立的 LLM 调用 | 流式 API 调用 |
| 工具解析 | OutputParser 解析文本 | 原生 `tool_use` 块 |
| 执行方式 | 等待完整响应 | 流式即时执行 |
| 错误处理 | 手动 try-catch | 内置 6 种恢复 |
| 并行工具 | 需要显式编排 | 自动分区并行 |

LangGraph 作为 LangChain 的升级版，引入了显式的图结构来描述状态流转。它在状态管理上更加形式化（图节点 + 边），支持 Checkpoint 持久化和 `interrupt_before/after` 人机交互。但代价是需要预先定义图结构，开发复杂度更高。

| 维度 | LangGraph | Claude Code |
|------|-----------|-------------|
| 状态流转 | 显式图节点 + 边 | 隐式状态机（while + continue） |
| 可视化 | 可导出为图结构 | transition 字段可追溯 |
| 持久化 | Checkpoint + State | 文件系统 + 消息历史 |
| 人机交互 | interrupt_before/after | 权限系统 + 钩子 |
| 多 Agent | 需要显式编排 | AgentTool 统一接口 |

Claude Code 的选择偏向简单性：不定义图结构，一个 while 循环处理所有状态转换。对于 Claude Code 这类以单 Agent 为核心的产品，这种简洁性直接转化为更低的维护成本和更快的迭代速度。LangGraph 的图结构在需要复杂多分支流程的场景中更有优势，但对于"用户提需求 → Agent 执行工具 → 返回结果"这类线性交互，状态机方案足够胜任。

## 最小抽象与原生集成

从源码结构来看，Claude Code 的 Agent 核心只有三个组件：一个循环（`while (true)` in `query()`）、一个状态（`State` 对象）、一个工具接口（`Tool` 类型）。没有 Agent → AgentExecutor → Chain → Memory → Callback 的嵌套抽象层。

在 API 集成层面，Claude Code 直接使用 Anthropic API 的原生能力：原生工具调用（无需 OutputParser，直接使用 `tool_use` 块）、原生流式传输（无需包装层，直接消费 SSE 流）、原生缓存（利用 prompt caching 特性）、原生思维链（直接使用 extended thinking）。这避免了 LangChain 等框架在 LLM 和开发者之间增加的抽象层带来的性能损耗和调试复杂度。

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

`transition` 字段的设计让每一轮循环都知道自己为什么继续。这不是一个装饰性的字段，它在测试中可以直接作为断言依据，在日志中可以作为问题定位的起点。一个 Agent 系统的可观测性，往往就取决于这类细节的积累。

## 关键源文件

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

**系列文章导航：**
- 上一篇：[Claude Code 为什么不用 LangChain：自研架构的技术考量](/2026/04/07/090_claude-code-why-no-langchain/)
- 下一篇：[工具系统设计：从定义到执行的七步管道](/2026/04/06/087_claude-code-tool-system/)
