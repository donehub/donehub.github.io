---
title: Claude Code 为什么不用 LangChain
date: 2026-04-15
tags: Architecture
categories: Claude Code
---

Anthropic 开源 Claude Code 之后，社区里一个常见的疑问是：为什么不用 LangChain 或者 LangGraph？这两个框架在 Agent 开发领域已经是事实标准，跳过它们自己造轮子，总得有个理由。读完源码后，我发现这个选择背后的原因比多数人猜测的更具体。不是框架好不好的问题，而是 Claude Code 的产品形态和 LangChain 的设计前提存在根本性的不匹配。

<!-- more -->

## 产品形态决定架构选择

在展开技术分析之前，有必要先厘清 Claude Code 和大多数用 LangChain 构建的 Agent 之间最本质的区别。LangChain 面对的场景是：开发者构建一个应用，用户提交一个请求，应用返回一个结果。整个过程是 request-response 模型，延迟在秒级完全可以接受。

Claude Code 面对的场景完全不同：用户在一个持续交互的终端里工作，每一次按键、每一条指令都期望即时反馈。模型在思考的过程中，用户需要实时看到进展；工具调用的结果需要在毫秒级内呈现到终端。这是一个对延迟极度敏感的 CLI 交互场景，而不是一个可以慢慢等的 Web 应用。

这个产品形态的差异，直接决定了架构层面的分叉。

## ReAct 模式的串行问题

LangChain 和 LangGraph 的核心执行逻辑都基于 ReAct 模式（Reasoning + Acting）：模型先完成一轮完整的思考，输出要调用的工具和参数，框架解析这段输出，执行工具，把结果追加到上下文中，再送入模型进行下一轮思考。这个循环在逻辑上很清晰，但有一个固有的问题。每一步都是串行的，模型必须等工具执行完才能继续思考，用户必须等模型完整输出后才能看到工具开始运行。

对于 Web 应用或者后台批处理任务，这种串行不会造成明显的体验问题。但对于 CLI 交互场景，用户盯着终端等待模型完整输出、再等待工具开始执行，这段空白时间会直接影响使用感受。当任务复杂度上升、需要连续调用多个工具时，这种等待会累积成显著的延迟。

### 流式状态机

Claude Code 用 AsyncGenerator 实现了一个流式状态机，核心逻辑在 `src/query.ts` 中，约 1730 行。它用一个 `while (true)` 循环和状态赋值来驱动整个 Agent 的运行：

```typescript
export async function* query(params: QueryParams): AsyncGenerator<QueryUpdate> {
  let state: State = {
    messages: [...],
    toolUseContext: {...},
    turnCount: 0,
    transition: undefined,
  }

  while (true) {
    // 阶段1: 消息压缩（自动处理 Token 溢出）
    // 阶段2: 流式 API 调用（工具即时执行）
    // 阶段3: 决策点（继续还是结束）
    // 阶段4: 工具编排（并行只读，串行写入）
    // 阶段5: 状态更新

    state = next  // 通过赋值驱动循环
    continue
  }
}
```

这个设计的关键区别在于：工具不是等模型完整输出后才开始执行的，而是在模型流式输出的过程中，一旦检测到 `tool_use` 块，就立即触发执行。用户的感知是模型思考和工具运行在同时发生，而不是先后发生。

### StreamingToolExecutor

这个能力由 StreamingToolExecutor 来支撑。当模型开始流式输出时，Executor 会实时解析输出流，一旦识别到完整的 `tool_use` 块（工具名和参数齐全），就立即启动工具执行，不等模型本轮输出结束。

延迟差异在这里体现得很明显。ReAct 的总延迟是模型生成时间和工具执行时间的累加；Claude Code 的延迟是两者中的较大值，因为它们在执行时间线上有重叠。模型还在生成后续文本的时候，Read 工具已经在读取文件了。对于一个需要连续调用多个工具的任务，这个差异会被放大。

## API 原生特性的利用率

### 通用框架的适配成本

LangChain 要支持 OpenAI、Anthropic、Google 等多家模型 API，必须在这些 API 之间建立一层抽象。这层抽象的价值是降低了切换模型供应商的成本，但代价是各家 API 的独有能力被抹平或延迟支持。

Anthropic API 有几个能力在 Claude Code 中被重度依赖：

| 特性 | 说明 | 对 Claude Code 的意义 |
|------|------|----------------------|
| Prompt Caching | 提示词缓存，缓存命中后 Token 成本降低约 90% | 系统提示词体积大，缓存直接影响调用成本 |
| 原生 tool_use 块 | 模型输出中直接包含结构化的工具调用块 | 无需文本解析，可靠性高于 OutputParser |
| 原生流式 tool_use | 流式传输中工具调用块可以即时触发 | 支撑流式即时执行的核心能力 |
| Extended Thinking | 思维链输出 | 复杂推理任务的推理过程可视化 |

LangChain 后来也逐步支持了这些特性，但支持的时效性和精细度与原生集成有差距。以 Prompt Caching 为例，Anthropic 在 2024 年底推出这个能力时，LangChain 花了数周才完成适配，且初始实现中缓存边界的划分不够精细。

### 原生集成的具体收益

Claude Code 直接使用 Anthropic SDK，可以精确控制缓存边界的划分。系统提示词被分为两个区域：静态区域（角色定义、系统规则、工具说明）使用全局缓存，动态区域（当前环境、用户记忆）使用会话级缓存。

```typescript
// 静态可缓存区域 - 跨会话复用
const systemPrompt = {
  type: 'text',
  text: `...`,
  cache_control: { type: 'ephemeral' }
}

// 动态区域 - 每次会话不同
const dynamicPrompt = {
  type: 'text',
  text: `...`,
  cache_control: { type: 'ephemeral' }
}
```

第一次调用按完整 Token 计费，后续调用中静态部分全部缓存命中。考虑到 Claude Code 的系统提示词体积通常在数万 Token，这个缓存机制对成本的影响很大。

工具调用方面，Anthropic API 的原生 `tool_use` 块让 Claude Code 不需要做任何文本解析。模型输出中直接包含了结构化的工具名和参数，框架拿到后可以直接执行。LangChain 在没有原生 tool_use 支持时，需要用 OutputParser 从模型的自然语言输出中提取工具调用信息。这个解析过程本身是脆弱的，模型格式稍有变化就可能解析失败。

## 性能层面：抽象层的代价

LangChain 的一次 Agent 调用，从用户代码到实际 API 请求，中间经过的抽象链是：用户代码 → Chain → AgentExecutor → LLM → Memory → Tools → OutputParser → API 调用。每一层都有自己的处理逻辑：参数校验、状态序列化、回调触发、日志记录。对于 Web 应用，这些开销在整体请求周期中占比很小。但 CLI 交互场景对延迟的容忍度很低，用户在终端里等待的每一秒都能感知到。

Claude Code 的调用链是：用户输入 → query() AsyncGenerator → Anthropic SDK → 工具执行。没有中间抽象层。API 响应以流的方式直接传递给渲染层，工具执行结果也实时回流。

### 工具编排的并发策略

Claude Code 在工具编排上做了自动化的并发控制。框架会根据工具的 `isReadOnly` 和 `isConcurrencySafe` 声明来判断哪些工具可以并行执行、哪些必须串行。只读工具（Read、Grep、Glob、WebFetch）默认并行，写入工具（FileEdit、Write、Bash）严格串行。

LangChain 默认串行执行所有工具，并行执行需要开发者自行配置。这个差异在工具数量较多时影响明显：一个需要同时读取 5 个文件的任务，Claude Code 可以并行完成，LangChain 默认要串行等待 5 次。

## 可控性：自研带来的控制精度

使用 LangChain 或 LangGraph 时，框架内部的决策过程对开发者是不透明的。工具执行的顺序、错误恢复的策略、Token 溢出时的处理方式，这些关键行为都封装在框架内部，开发者只能通过有限的配置接口来调整。当出现框架没有覆盖到的边界情况时，往往只能绕过框架自己处理，或者等框架更新。

Claude Code 选择了完全自研，换来的是对每个环节的控制精度。

**权限系统。** 工具权限检查不是一个简单的 allow/deny 开关，而是一个四级决策管道：deny 规则最高优先级，然后是工具自身的权限检查，接着是 allow 规则匹配，最后才是询问用户。这个管道可以精确控制到具体工具的具体操作类型。

```typescript
async function checkPermissions(tool, input, context) {
  if (matchesDenyRule(tool.name)) return { behavior: 'deny' }
  if (tool.checkPermissions) {
    const result = await tool.checkPermissions(input, context)
    if (result.behavior !== 'passthrough') return result
  }
  if (matchesAllowRule(tool.name, input)) return { behavior: 'allow' }
  return { behavior: 'ask' }
}
```

**上下文压缩。** 当对话历史超过 Token 限制时，Claude Code 采用四级渐进式压缩：先删除旧消息中的冗余内容（Snip），再修改已缓存消息的内容（Micro），接着分阶段摘要历史消息（Collapse），最后通过模型生成完整摘要（Auto Compact）。每一级的压缩力度和成本不同，系统会根据当前上下文长度自动选择合适的级别。LangChain 的默认处理方式是截断或简单摘要，精细度上有差距。

**钩子系统。** 允许用户在工具执行的前后注入自定义逻辑（执行 Bash 命令前跑安全检查，执行 FileEdit 后跑测试）。这个机制通过 settings.json 配置，不需要修改源码。LangChain 要实现类似功能需要继承类或包装回调，复杂度更高。

## 能力映射

LangChain 和 LangGraph 提供的那些能力，Claude Code 用自己的实现来替代：

| LangChain/LangGraph 能力 | Claude Code 的替代实现 | 对应文件 |
|---------------------------|----------------------|----------|
| Agent 循环（ReAct） | AsyncGenerator 状态机 | `src/query.ts` |
| 工具定义 | Tool 类型 + buildTool() | `src/Tool.ts` |
| Memory | Channel 系统 + 文件记忆 | `src/state/`, `src/memdir/` |
| OutputParser | 原生 tool_use 块 | 无需解析 |
| Callbacks | 钩子系统 | `src/hooks/` |
| StateGraph（LangGraph） | State 对象 + 状态赋值 | `src/query.ts` |
| Checkpoint（LangGraph） | 消息历史 + 文件系统 | `src/assistant/` |
| 多 Agent 编排 | AgentTool + 子代理系统 | `src/tools/AgentTool/` |

Claude Code 并不是缺少什么能力才自研的。LangChain 能做的事情它都能做，只是实现方式不同。差异主要在执行模型（流式 vs 串行）、控制精度（原生集成 vs 框架抽象）和性能特征（零中间层 vs 多层抽象）上。

## 什么时候该用 LangChain

讨论完 Claude Code 的选择，有必要客观说明：不用 LangChain 不代表 LangChain 不好。Claude Code 的自研路线有几个前提条件：顶级工程团队有能力维护自研架构、只需要支持单一模型 API、产品形态对延迟极度敏感。

如果你的场景不满足这些条件，LangChain 或 LangGraph 大概率是更合适的选择。小团队快速验证时，LangChain 的开箱即用能力可以节省大量基础设施搭建时间。需要支持多种模型时，LangChain 的多模型抽象层是真正的优势。Web 应用延迟不敏感的场景下，ReAct 模式的串行问题影响不大。需要可视化 Agent 流程时，LangGraph 的 StateGraph 有现成方案。没有专业基础设施团队时，自研意味着要自己处理错误恢复、缓存策略、权限控制等所有细节。

Claude Code 选择自研，是因为它的产品定位和团队条件让这条路线的投入产出比合理。对于大多数团队来说，用 LangChain 把精力集中在业务逻辑上，而不是重新实现 Agent 框架，可能是更务实的选择。

## 收束

Claude Code 不用 LangChain 的核心原因，可以归结为产品形态和框架设计前提的不匹配。LangChain 面向通用的 Agent 开发场景设计，追求跨模型的兼容性和开发效率；Claude Code 面向单一的 CLI 交互场景，追求极致的响应速度和控制精度。前者是通用工具，后者是为特定场景做到最好的专用系统。

这个选择没有绝对的对错。关键判断在于：你的产品形态是否值得为一个 Agent 框架做专用优化。如果答案是肯定的，Claude Code 的路线提供了一个参考；如果答案是否定的，LangChain 仍然是更高效的起步方式。

---

**系列文章导航：**
- 上一篇：[Claude Code 整体架构概览](/2026/04/07/089_claude-code-architecture-overview/)
- 下一篇：[打破 ReAct 迷思：Async Generator 状态机](/2026/04/06/077_claude-code-async-generator-state-machine/)
