---
title: Claude Code 整体架构概览
date: 2026-04-07
tags: Architecture
categories: Claude Code
---

2026 年 3 月 31 日，Anthropic 的 Claude Code 源码意外泄露。作为目前使用最广泛的 AI 编程助手之一，它的源码首次让社区有机会看到这类产品的内部实现。读完源码后，我发现它的架构设计和多数人的直觉判断有明显出入。大多数开发者最初认为它只是一个套壳 API 调用的 CLI 工具，实际代码量和工程复杂度远超这个定位。

<!-- more -->

## 技术栈与项目结构

Claude Code 的技术选型比较克制，没有引入过多的依赖。运行时选择了 Bun 而非 Node.js，终端 UI 层用 React + Ink 的组合来构建，整个终端界面实际上是用 React 组件树来渲染的。CLI 参数处理使用 Commander.js，API 层直接对接 Anthropic SDK，协议层面支持 MCP 和 LSP。

| 类别 | 技术 | 说明 |
|------|------|------|
| 运行时 | [Bun](https://bun.sh) | 高性能 JavaScript 运行时 |
| 语言 | TypeScript | 类型安全 |
| 终端 UI | React + [Ink](https://github.com/vadimdemedos/ink) | React 语法写终端应用 |
| CLI 解析 | Commander.js | 命令行参数处理 |
| API | Anthropic SDK | 原生 API 集成 |
| 协议 | MCP, LSP | 模型上下文协议、语言服务器协议 |

选择 Bun 而非 Node.js 值得留意。Bun 在启动速度和运行时性能上有明显优势，对于一个需要快速响应的 CLI 工具来说，启动延迟直接影响用户的第一印象。这个选型说明团队对终端体验的响应速度有明确要求。

### 目录结构

整个项目包含 1356 个 TypeScript 文件，源码按功能域划分。主要目录包括：`query/`（查询循环核心）、`tools/`（48+ 内置工具）、`context/`（上下文管理）、`state/`（状态管理）、`memdir/`（记忆系统）、`skills/`（Skills 系统）、`plugins/`（插件系统）、`hooks/`（React Hooks）、`services/`（核心服务层）、`components/`（React UI 组件）、`constants/`（系统提示词、常量）、`coordinator/`（协调器模式）、`bridge/`（远程桥接）、`vendor/`（Computer Use 集成）等。

从目录划分可以看出几个设计倾向。`query/` 和 `tools/` 是核心模块，对应 Agent 的主循环和工具执行能力。`context/`、`state/`、`memdir/` 三个目录独立存在，说明上下文管理、状态管理和记忆系统被视为三个不同的关注点，而非混在一起处理。`skills/`、`plugins/`、`hooks/` 各自独立，扩展机制被拆成了多个层次而非一个通用的插件系统。

## 核心架构

Claude Code 的运行流程可以概括为：用户输入经过 QueryEngine 处理后，进入核心的 `query()` 循环，这个循环在内部完成消息压缩、流式 API 调用、决策判断、工具编排和状态更新五个阶段。循环的下游连接三个子系统：工具系统（48+ 内置工具、MCP 动态工具、三层过滤机制、7步执行管道）、多 Agent 系统（Subagent、Fork、Teammate、Remote）、扩展生态（Skills、Plugins、Hooks、MCP 协议）。

这个架构的核心思路是：模型本身只负责推理和决策，所有的执行能力、状态管理、错误恢复都由外部的循环机制来承担。模型是大脑，query 循环是身体。大脑决定做什么，身体负责怎么做以及出了问题怎么兜底。

### 三个核心设计理念

通读源码后，能感受到整个架构围绕三个理念来组织。

**流式优先。** 整个架构基于 AsyncGenerator 构建，模型响应是流式的，工具在模型生成过程中就可以开始执行，进度实时更新，压缩策略也是渐进式的。用户在使用过程中的感受是：模型在思考的同时工具已经开始运行，不需要等一个完整的响应结束后才有下一步动作。这和使用传统的 request-response 模式有本质区别。

**工具驱动。** Claude Code 的哲学是把所有能力都统一为工具。子代理生成是一个工具（AgentTool），团队管理是工具（TeamCreate/SendMessage），文件编辑是工具（FileEdit），技能执行也是工具（SkillTool）。这意味着不需要显式的编排逻辑来协调这些能力，模型通过自然语言推理来决定调用哪个工具，模型本身就是编排器。这种设计的好处是新增能力只需要实现一个工具接口，不需要修改任何编排代码。

**优雅降级。** 生产环境中的 AI 工具会面对各种异常情况：Token 超限、API 超时、模型返回异常、工具执行失败。Claude Code 内置了 6 种恢复策略来应对这些情况。Token 超限自动触发压缩，API 超时自动重试，模型失败降级到备用模型，工具失败则记录错误并继续对话。这套机制保证了大部分技术异常不会直接中断用户的工作流，而是被静默处理或降级执行。

## 核心模块

### query.ts：Agent 的主循环

`src/query.ts` 是整个 Agent 的核心文件，约 1730 行。它实现的是一个流式状态机，而不是简单的"想-做-看"循环。循环通过 `state = next` 赋值来驱动状态转换，而不是递归调用。递归调用会在深层嵌套时导致栈溢出风险，赋值驱动循环的方式让内存使用保持稳定。同时，每一轮的状态转换原因都会被记录到 state 对象中，这使得问题排查时能够回溯整个执行路径。任何阶段出现错误，也可以通过修改 state 来触发恢复策略，不需要额外的异常处理框架。

```typescript
export async function* query(params: QueryParams): AsyncGenerator<...> {
  let state: State = {
    messages, toolUseContext, autoCompactTracking,
    maxOutputTokensRecoveryCount, hasAttemptedReactiveCompact,
    maxOutputTokensOverride, pendingToolUseSummary,
    stopHookActive, turnCount, transition,
  }

  while (true) {
    // 阶段1: 消息压缩
    // 阶段2: 流式 API 调用
    // 阶段3: 决策点
    // 阶段4: 工具执行
    // 阶段5: 状态更新
    state = next  // 通过赋值而非递归驱动循环
    continue
  }
}
```

### Tool.ts：工具的类型定义

`src/Tool.ts` 定义了工具的完整接口，约 792 行。每个工具需要声明自己的身份、能力、生命周期和输出格式。这种接口设计让每个工具成为自描述、自验证、自渲染的独立单元。框架不需要了解工具的内部逻辑，只需调用标准接口。

`isReadOnly` 和 `isConcurrencySafe` 这两个声明尤其重要。框架根据它们来决定哪些工具可以并行执行，哪些必须串行。这意味着工具作者只需要如实声明自己的能力，并发控制完全由框架处理。

```typescript
type Tool<Input, Output> = {
  name: string
  aliases?: string[]        // 向后兼容的旧名称
  searchHint?: string       // ToolSearch 关键词匹配

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

### 系统提示词的组装方式

`src/constants/prompts.ts`（约 577 行）实现了一个分层管道来组装系统提示词。整个提示词被划分为两个区域，中间有一个缓存边界。静态区域包含角色定义、系统规则、任务指导、工具说明和风格约束；动态区域包含会话指引、记忆系统、环境信息、MCP 指令和 Token 预算。

缓存边界的设计直接关系到调用成本。边界之上的内容跨用户、跨会话基本不变，使用 `scope: 'global'` 缓存后，这部分 Token 在多次调用中只计费一次。边界之下的内容每次会话都不同，使用 `scope: 'ephemeral'` 缓存。这个划分方式让缓存命中率保持在一个较高的水平。系统提示词的大部分体积属于静态区域，只有少量动态内容需要每次重新计算。

## 与 LangChain/ReAct 的架构差异

阅读 Claude Code 源码之前，我默认它使用的是经典的 ReAct 模式：模型先思考，再执行动作，然后观察结果，再进入下一轮思考。这个模式在 LangChain 等框架中被广泛采用，也是目前大多数 AI Agent 实现的基础范式。但 Claude Code 并没有采用这个模式。

| 维度 | LangChain | Claude Code |
|------|-----------|-------------|
| 核心模式 | ReAct（Think→Act→Observe） | Async Generator 状态机 |
| 执行模型 | 同步阻塞 | 流式非阻塞 |
| 工具执行 | 等待模型完整响应后执行 | 流式传输中即时执行 |
| 状态管理 | 外部 Memory 对象 | 内置状态赋值 + 循环 |
| 错误恢复 | 需要手动编排 | 6 种内置恢复策略 |
| 上下文压缩 | 简单截断或摘要 | 四级渐进式压缩 |
| 多 Agent | Chain/Graph 显式编排 | 统一工具接口 + 状态机 |
| 扩展机制 | Python 类继承 | 技能 + 插件 + 钩子 + MCP |
| 缓存策略 | 无 | 全局/会话/按轮三级缓存 |

### ReAct 模式的局限

ReAct 模式的根本问题在于它的串行特性。每一步都必须等待模型完成完整的思考过程，才能执行工具、获取结果、进入下一轮。在任务复杂度较低时，这个模式的延迟可以接受；但当 Agent 需要连续调用多个工具、处理大量上下文时，每一步的等待时间会累积成显著的用户体验问题。

另一个问题是缓存友好性。ReAct 模式每一轮的 prompt 结构变化较大（因为上一轮的工具执行结果会被追加到上下文中），导致 API 层面的 prompt 缓存难以命中。在 Token 计费模型下，这意味着成本的线性增长。

Claude Code 的 AsyncGenerator 模式在这些问题上做了不同的取舍：工具在模型流式输出过程中就可以开始执行（不必等完整响应），状态对象包含了所有需要的上下文信息（恢复只需修改状态），静态提示词部分走全局缓存（降低重复调用成本）。这些设计选择让它在复杂任务场景下的响应速度和成本结构都优于传统的 ReAct 实现。

当然，ReAct 模式也有它的优势：逻辑清晰、容易理解、调试简单。Claude Code 的架构复杂度更高，理解门槛也相应提升。对于简单的 Agent 场景，ReAct 可能已经足够。

## 关键源文件

| 组件 | 文件路径 | 行数 | 说明 |
|------|----------|------|------|
| 核心循环 | `src/query.ts` | ~1730 | Agent 主循环，状态机实现 |
| 查询引擎 | `src/QueryEngine.ts` | ~687 | 高层封装，参数组装 |
| 工具定义 | `src/Tool.ts` | ~792 | Tool 类型系统 |
| 工具注册 | `src/tools.ts` | ~389 | 工具发现和注册 |
| 系统提示词 | `src/constants/prompts.ts` | ~577 | 提示词分层组装 |
| 上下文管理 | `src/context.ts` | ~300 | 系统/用户上下文 |
| Agent 生成 | `src/tools/AgentTool/AgentTool.tsx` | ~600 | Agent 工具入口 |
| 技能系统 | `src/skills/bundledSkills.ts` | ~300 | 技能注册与管理 |
| 权限系统 | `src/utils/permissions/permissions.ts` | ~500 | 权限检查 |
| 状态管理 | `src/state/AppStateStore.ts` | ~400 | 全局状态 |

## 收束

回到最初的问题：Claude Code 到底是什么？从架构层面看，它的核心可以归纳为三个部分。一个 `while (true)` 驱动的状态机，一个承载所有上下文的 State 对象，一个统一所有能力的 Tool 接口。没有 LangChain 那种 Agent → AgentExecutor → Chain → Memory → Callback 的多层嵌套抽象，整个调用链路相对扁平。

这种设计让代码在理解和调试上有明显的优势，但代价是核心循环承担了过多的职责。query.ts 的 1730 行代码同时处理了压缩、调用、决策、执行和状态管理，后续如果某个环节的逻辑变复杂，这个文件会成为一个维护瓶颈。

后续会针对几个关键模块做更深入的分析。

---

**系列文章导航：**
- 下一篇：[Claude Code 为什么不用 LangChain：自研架构的技术考量](/2026/04/07/090_claude-code-why-no-langchain/)
