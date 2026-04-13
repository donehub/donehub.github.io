---
title: Claude Code 为什么不用 LangChain/LangGraph：自研架构的深层逻辑
date: 2026-04-15
tags: Architecture
categories: Claude Code
---

> LangChain 和 LangGraph 是当下最流行的 Agent 开发框架，但 Anthropic 的 Claude Code 却完全不用它们。这不是傲慢，而是基于技术本质、产品体验、API 特性和工程可控性的四重考量。本文从多个层面剖析 Claude Code 的自研架构选择，以及它用什么技术替代了 LangChain/LangGraph 的能力。

---

## 一、先说结论

Claude Code 不用 LangChain/LangGraph，原因有四个：

| 层面 | LangChain/LangGraph 的限制 | Claude Code 的选择 |
|------|---------------------------|-------------------|
| **架构层面** | ReAct 模式的串行瓶颈 | Async Generator 状态机 |
| **API 层面** | 无法充分利用 Anthropic API 特性 | 原生 SDK 直接集成 |
| **性能层面** | 抽象层增加延迟 | 零抽象，直接流式处理 |
| **可控层面** | 框架黑盒，难以定制 | 全栈自研，精准控制 |

**一句话概括**：LangChain/LangGraph 是"通用框架"，Claude Code 是"专用系统"。通用框架追求易用，专用系统追求极致体验。

---

## 二、架构层面：为什么放弃 ReAct

### 2.1 ReAct 模式的根本缺陷

LangChain 和 LangGraph 的核心都是 **ReAct 模式**（Reasoning + Acting）：

```
思考(Thought) → 行动(Action) → 观察(Observation) → 思考 → ...
```

这个模式直观易懂，但存在三个根本缺陷：

**缺陷一：串行瓶颈**

```
┌─────────────────────────────────────────────────────────────┐
│                    ReAct 串行流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  用户输入 → 等待完整响应 → 解析工具调用 → 执行工具 → 等待 →  │
│            └───────────────────────────────────┘            │
│                        用户感知到的延迟                       │
│                                                             │
│  问题：用户要等模型生成完整响应后才能看到工具执行             │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

在 CLI 交互场景中，这种延迟是致命的——用户盯着屏幕等待，不知道发生了什么。

**缺陷二：无法利用流式传输**

现代 LLM API 都支持流式输出（SSE），但 ReAct 模式下流式的价值被大大削弱：

```python
# LangChain 的 Agent 执行
agent.run("帮我分析这个项目")

# 内部流程：
# 1. LLM 生成完整响应（即使流式，也要等 action 完整）
# 2. OutputParser 解析响应文本
# 3. 提取工具名称和参数
# 4. 执行工具
# 5. 工具结果返回给 LLM
# 6. 重复...

# 流式输出的价值：实时看到模型"在想什么"
# 但工具执行：必须等完整响应后才能开始
# 两者冲突，流式体验被割裂
```

**缺陷三：状态恢复困难**

ReAct 模式没有统一的状态表示，每一步都是独立的：

```
Step 1: Thought → Action → Observation  (无状态记忆)
Step 2: Thought → Action → Observation  (重新开始)
Step 3: ...

当 API 超时、Token 溢出时：
- LangChain：抛出异常，用户需手动处理
- LangGraph：需要显式定义 checkpoint，复杂度高
- Claude Code：State 对象统一承载，自动恢复
```

### 2.2 Claude Code 的替代方案：Async Generator 状态机

Claude Code 用一个 **while(true) 循环 + State 赋值** 替代 ReAct：

```typescript
// src/query.ts 核心（简化版）
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

**核心优势对比**：

| 维度 | ReAct | Async Generator 状态机 |
|------|-------|------------------------|
| 执行方式 | 串行，等待完整响应 | 流式，工具即时执行 |
| 状态管理 | 无统一状态 | State 对象承载所有信息 |
| 错误恢复 | 手动处理 | 6 种内置恢复策略 |
| 内存安全 | 可能递归溢出 | 状态赋值，无递归风险 |
| 可观测性 | 需要额外追踪 | transition 字段记录转换原因 |

### 2.3 流式即时执行：StreamingToolExecutor

Claude Code 的关键创新是 **工具在模型生成过程中就开始执行**：

```
┌─────────────────────────────────────────────────────────────┐
│                 Claude Code 流式执行流程                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  模型流式输出：                                              │
│    "我来帮你分析这个项目..."                                 │
│    "首先读取 README..."                                     │
│    [生成 tool_use 块: Read { path: "README.md" }]           │
│                                                             │
│                    ↓ 立即执行                                │
│                                                             │
│  StreamingToolExecutor:                                     │
│    检测到 tool_use → 立即调用 Read 工具                     │
│    工具结果实时返回                                          │
│                                                             │
│  用户感知：                                                  │
│    实时看到模型思考                                          │
│    实时看到工具执行                                          │
│    无需等待完整响应                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**对比 LangChain**：

```
LangChain 流程：
  用户输入 → 等待(模型完整响应) → 解析 → 执行工具 → 等待 → ...
  总延迟 = 模型生成时间 + 解析时间 + 工具执行时间

Claude Code 流程：
  用户输入 → 流式生成(工具即时执行) → 流式输出 → ...
  总延迟 = max(模型生成时间, 工具执行时间)
```

---

## 三、API 层面：原生特性的充分利用

### 3.1 LangChain 的"框架税"

LangChain 作为通用框架，需要在多种模型 API 之间保持一致性。这意味着：

```
Anthropic API 特性          → LangChain 抽象层 → 用户代码
                                    ↓
                          被抹平或延迟支持
```

**Anthropic 独有的 API 特性**：

| 特性 | 说明 | LangChain 支持情况 |
|------|------|-------------------|
| **Prompt Caching** | 提示词缓存，降本 90% | 2024 年后才支持，使用复杂 |
| **Extended Thinking** | 思维链输出，推理透明 | LangChain 无原生支持 |
| **Computer Use** | 屏幕操作能力 | LangChain 无原生支持 |
| **原生 tool_use** | 结构化工具调用块 | LangChain 用 OutputParser 解析文本 |
| **原生流式 tool_use** | 流式传输中工具即时触发 | LangChain 需等待完整响应 |

### 3.2 Claude Code 的原生集成

Claude Code 直接使用 Anthropic SDK，充分利用所有原生特性：

**示例：Prompt Caching 的利用**

```typescript
// Claude Code 的提示词组装（src/constants/prompts.ts）

// 静态可缓存区域（scope: 'global'）
const systemPrompt = {
  type: 'text',
  text: `
    ## 角色定义
    Claude Code 是一个...
    
    ## 系统规则
    你必须遵守...
    
    ## 工具说明
    以下工具可用...
  `,
  cache_control: { type: 'ephemeral' }  // 缓存标记
}

// 动态不可缓存区域（scope: 'ephemeral'）
const dynamicPrompt = {
  type: 'text',
  text: `
    ## 当前环境
    工作目录: ${cwd}
    
    ## 用户记忆
    ${claudeMdContent}
  `,
  cache_control: { type: 'ephemeral' }  // 独立缓存
}
```

**缓存效果**：
- 第一次调用：完整 token 计费
- 后续调用：静态部分缓存命中，降本约 **90%**

LangChain 也支持 Prompt Caching，但需要用户手动配置，且无法像 Claude Code 这样精细划分缓存边界。

**示例：原生 tool_use 块**

```typescript
// Anthropic API 响应格式
{
  content: [
    { type: 'text', text: '我来帮你...' },
    {
      type: 'tool_use',
      id: 'toolu_01...',
      name: 'Read',
      input: { file_path: '/path/to/file' }
    }
  ]
}

// Claude Code 直接处理
for (const block of response.content) {
  if (block.type === 'tool_use') {
    // 立即执行，无需解析文本
    await executeTool(block.name, block.input)
  }
}
```

**对比 LangChain**：

```python
# LangChain 的工具调用
response = llm.invoke(prompt)

# OutputParser 解析文本
parsed = output_parser.parse(response.content)
# 解析可能失败，格式不固定

if parsed['action']:
    tool_name = parsed['action']['tool']
    tool_input = parsed['action']['input']
    result = tools[tool_name].run(tool_input)
```

LangChain 需要 OutputParser 解析模型输出的文本，这是脆弱的——模型格式不固定时解析会失败。

---

## 四、性能层面：零抽象的流式优先

### 4.1 LangChain 的抽象层堆叠

LangChain 的抽象层结构：

```
用户代码
  → Chain
    → AgentExecutor
      → LLM
        → Memory
          → Tools
            → OutputParser
              → 实际 API 调用
```

每一层都增加处理开销。对于 Web 应用，这些开销可以忽略；但对于 **CLI 交互工具**，延迟是致命的。

### 4.2 Claude Code 的零抽象设计

Claude Code 的结构：

```
用户输入
  → query() AsyncGenerator
    → Anthropic SDK（直接调用）
      → 工具执行（流式即时）
```

**没有中间抽象层**，API 响应直接流式传递给用户。

### 4.3 工具编排的性能优化

Claude Code 的工具编排策略：

```
工具调用列表
  │
  ├─ 分类：只读 vs 写入
  │
  ├─ 只读工具 ──→ 并行执行（最多 10 个并发）
  │   ├─ Read      ──→ 同时开始
  │   ├─ Grep      ──→ 同时开始
  │   ├─ Glob      ──→ 同时开始
  │   └─ WebFetch  ──→ 同时开始
  │
  └─ 写入工具 ──→ 串行执行（保证顺序）
      ├─ FileEdit  ──→ 等待上一个完成
      ├─ Write     ──→ 等待上一个完成
      └─ Bash      ──→ 等待上一个完成
```

**LangChain 的工具执行**：

```python
# LangChain Agent 默认串行执行
for tool_call in parsed_tool_calls:
    result = tool.run(tool_call.input)  # 一个一个执行
```

LangChain 需要显式配置并行，且配置复杂；Claude Code 自动分析工具性质，智能编排。

---

## 五、可控层面：全栈自研的精准控制

### 5.1 框架黑盒问题

使用 LangChain/LangGraph 时，你无法精准控制：

| 场景 | LangChain 行为 | 你的控制力 |
|------|---------------|-----------|
| 工具执行顺序 | 默认串行 | 需要显式配置 |
| 错误恢复 | 抛出异常 | 需要自己处理 |
| Token 溢出 | 截断或报错 | 需要自己检测 |
| 提示词组装 | 模板拼接 | 无法精细控制 |
| 流式输出 | 部分支持 | 需要适配框架 |

### 5.2 Claude Code 的精准控制

Claude Code 自研每一层，可以精确控制：

**控制一：工具执行权限**

```typescript
// Claude Code 的权限系统（src/utils/permissions）

type PermissionResult = {
  behavior: 'allow' | 'deny' | 'ask'
  message?: string
  suggestions?: string[]
}

// 精细的权限检查
async function checkPermissions(tool, input, context) {
  // 1. deny 规则最高优先级
  if (matchesDenyRule(tool.name)) {
    return { behavior: 'deny', message: 'Blocked by deny rule' }
  }
  
  // 2. 工具自定义检查
  if (tool.checkPermissions) {
    const result = await tool.checkPermissions(input, context)
    if (result.behavior !== 'passthrough') {
      return result
    }
  }
  
  // 3. allow 规则
  if (matchesAllowRule(tool.name, input)) {
    return { behavior: 'allow' }
  }
  
  // 4. 默认询问用户
  return { behavior: 'ask', message: 'Do you want to allow?' }
}
```

**控制二：自动压缩策略**

```typescript
// Claude Code 的四级压缩（src/query）

// Level 1: Snip — 删除旧消息中的冗余 token
messages = snipMessages(messages)

// Level 2: Micro — 修改已缓存消息的内容
messages = microCompact(messages)

// Level 3: Collapse — 分阶段摘要历史消息
messages = collapseMessages(messages)

// Level 4: Auto Compact — 通过 Claude 生成完整摘要
messages = await autoCompact(messages)

// LangChain 的处理方式：
// messages = messages.slice(-max_tokens)  // 简单截断
```

**控制三：钩子扩展系统**

```json
// settings.json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "security-check.sh"
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "FileEdit",
        "hooks": [
          {
            "type": "command",
            "command": "run-tests.sh"
          }
        ]
      }
    ]
  }
}
```

用户可以在工具执行的任意阶段注入自定义逻辑，LangChain 需要继承类或修改源码才能实现类似功能。

---

## 六、能力映射：Claude Code 用什么替代 LangChain/LangGraph

### 6.1 LangChain 能力 → Claude Code 替代方案

| LangChain 能力 | Claude Code 替代方案 | 实现文件 |
|---------------|---------------------|---------|
| **LLM 调用** | Anthropic SDK 直接集成 | `src/query.ts` |
| **工具定义** | `Tool` 类型 + `buildTool()` | `src/Tool.ts` |
| **工具注册** | 三阶段流水线注册 | `src/tools.ts` |
| **Agent 循环** | `while(true)` 状态机 | `src/query.ts` |
| **Memory** | Channel 系统 + 文件记忆 | `src/state/`, `src/memdir/` |
| **RAG** | 文件工具 + 向量工具（可选 MCP） | `src/tools/` |
| **OutputParser** | 原生 `tool_use` 块解析 | 无需解析 |
| **Callbacks** | 钩子系统 | `src/hooks/` |

### 6.2 LangGraph 能力 → Claude Code 替代方案

| LangGraph 能力 | Claude Code 替代方案 | 实现文件 |
|---------------|---------------------|---------|
| **StateGraph** | `State` 对象 + 状态赋值 | `src/query.ts` |
| **节点定义** | `while` 循环的阶段划分 | `src/query.ts:307-1728` |
| **边流转** | `transition` + `continue` | `src/query/transitions.ts` |
| **条件分支** | `if/switch` + `state.transition` | `src/query.ts` |
| **Checkpoint** | 消息历史 + 文件系统 | `src/assistant/` |
| **多 Agent** | `AgentTool` + 子代理系统 | `src/tools/AgentTool/` |
| **可视化调试** | `transition` 字段追踪 | 可观测性设计 |

### 6.3 核心代码映射

**LangChain Agent → Claude Code query()**

```python
# LangChain
agent = AgentExecutor.from_agent_and_tools(agent, tools)
result = agent.invoke({"input": "do something"})
```

```typescript
// Claude Code
for await (const update of query({ messages, tools, systemPrompt })) {
  console.log(update)  // 实时输出
}
```

**LangGraph StateGraph → Claude Code while 循环**

```python
# LangGraph
graph = StateGraph(AgentState)
graph.add_node("agent", agent_node)
graph.add_node("tool", tool_node)
graph.add_conditional_edges("agent", should_continue, 
    {"continue": "tool", "end": END})
app = graph.compile()
```

```typescript
// Claude Code（src/query.ts）
while (true) {
  // 阶段 2: 流式 API 调用
  const response = await callModel(state)
  
  // 阶段 3: 决策点（条件分支）
  if (hasToolUse(response)) {
    // 阶段 4: 工具执行
    const results = await executeTools(response.tool_use_blocks)
    state = { ...state, messages: [...messages, results] }
    continue  // 继续循环
  } else {
    // 结束
    yield finalResult
    return
  }
}
```

---

## 七、什么时候该用 LangChain/LangGraph

Claude Code 的自研架构不是所有人的最优解。它们的选择基于：

1. **顶级工程团队**：有能力自研高性能架构
2. **单一模型依赖**：只需要支持 Anthropic API
3. **极致体验追求**：CLI 交互需要零延迟感知
4. **深度定制需求**：权限、压缩、钩子都需要精准控制

**如果你不具备这些条件，LangChain/LangGraph 仍然是好选择**：

| 你的情况 | 推荐 |
|----------|------|
| 小团队，快速验证想法 | LangChain |
| 需要支持多种模型 | LangChain |
| 需要可视化 Agent 流程 | LangGraph |
| 需要多 Agent 协作且不想自研 | LangGraph 或 CrewAI |
| Web 应用，延迟不敏感 | LangChain/LangGraph |
| 企业级系统，有专业团队 | LangGraph 或自研 |

---

## 八、总结

Claude Code 不用 LangChain/LangGraph，不是傲慢，而是**基于产品定位的理性选择**：

```
LangChain/LangGraph 定位：通用框架
  → 易用性优先
  → 支持多种模型
  → 抽象层统一
  → 适合快速原型和通用应用

Claude Code 定位：专用系统
  → 性能优先
  → 单一模型极致利用
  → 零抽象流式处理
  → 适合 CLI 交互和专业场景
```

**Claude Code 用什么替代了 LangChain/LangGraph**：

| 替代 | 技术 |
|------|------|
| ReAct 循环 | Async Generator 状态机 |
| 工具定义 | Tool 类型 + buildTool() |
| 工具执行管道 | 七步执行管道 |
| 状态管理 | State 对象 + 状态赋值 |
| 错误恢复 | 6 种内置恢复策略 |
| 扩展机制 | 钩子系统 + MCP 协议 |

**核心启示**：框架不是必须的，适合自己的才是最好的。LangChain/LangGraph 解决了"怎么快速搭建 Agent"的问题；Claude Code 解决了"怎么搭建极致体验的 Agent"的问题。

---

## 参考资料

- [Claude Code 源码揭秘：整体架构概览](/claude-code-architecture-overview/)
- [打破 ReAct 迷思：Async Generator 状态机](/claude-code-async-generator-state-machine/)
- [工具系统设计：从定义到执行的七步管道](/claude-code-tool-system/)
- [Anthropic API 文档](https://docs.anthropic.com/)
- [LangChain 官方文档](https://python.langchain.com/docs/)
- [LangGraph 官方文档](https://langchain-ai.github.io/langgraph/)