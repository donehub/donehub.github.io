---
title: Claude Code 源码揭秘：整体架构概览
date: 2026-04-06
tags: Architecture
categories: Claude Code
---

> 2026年3月31日，Anthropic 的 Claude Code 源码意外泄露。这个全球最流行的 AI 编程助手，其背后的架构设计远超外界想象——它不是简单的 Prompt 包装，而是一个精心设计的流式状态机系统。本文将从整体架构视角，为你揭开 Claude Code 的神秘面纱。

<!-- more -->

## 导读：一个根本性的问题

在深入源码之前，我们需要回答一个根本性的问题：**Claude Code 到底是什么？**

很多人的第一反应是："不就是一个调用 Claude API 的 CLI 工具吗？加了一些 Prompt，让模型能读写文件、执行命令。"

这种理解大大低估了 Claude Code 的复杂度。当你打开源码，会发现：

- **1356 个 TypeScript 文件**
- **48+ 个内置工具**，每个工具都有完整的生命周期管理
- **4 种 Agent 类型**，支持复杂的协作编排
- **4 级上下文压缩**，实现"无限对话"
- **6 种故障恢复策略**，确保用户体验的稳定性
- **3 级提示词缓存**，大幅降低成本和延迟

这不是一个"简单的 Prompt 工具"，而是一个**深度集成的 AI 编程环境**。

---

## 一、技术栈与项目结构

### 1.1 核心技术栈

Claude Code 的技术选型非常精简但高效：

| 类别 | 技术 | 说明 |
|------|------|------|
| 运行时 | [Bun](https://bun.sh) | 高性能 JavaScript 运行时 |
| 语言 | TypeScript | 类型安全 |
| 终端 UI | React + [Ink](https://github.com/vadimdemedes/ink) | React 语法写终端应用 |
| CLI 解析 | Commander.js | 命令行参数处理 |
| API | Anthropic SDK | 原生 API 集成 |
| 协议 | MCP, LSP | 模型上下文协议、语言服务器协议 |

### 1.2 目录结构概览

```
src/
├── assistant/          # 会话历史管理
├── bootstrap/          # 启动初始化、全局状态
├── bridge/             # 远程桥接系统（Bridge）
├── buddy/              # 交互伴侣（动画、观察者）
├── cli/                # CLI 入口、传输层
├── commands/           # 60+ 斜杠命令
├── components/         # React UI 组件
├── constants/          # 系统提示词、常量
├── context/            # 上下文管理
├── coordinator/        # 协调器模式
├── entrypoints/        # 入口文件（CLI、SDK）
├── hooks/              # React Hooks
├── ink/                # Ink 框架扩展
├── memdir/             # 记忆系统
├── migrations/         # 数据迁移
├── native-ts/          # 原生模块（Yoga 布局等）
├── outputStyles/       # 输出样式配置
├── plugins/            # 插件系统
├── proactive/          # 主动模式
├── query/              # 查询循环核心
├── remote/             # 远程会话管理
├── schemas/            # JSON Schema 定义
├── screens/            # 全屏页面
├── server/             # 内置服务器
├── services/           # 核心服务层
├── skills/             # Skills 系统
├── state/              # 状态管理
├── tasks/              # 后台任务系统
├── tools/              # 48+ 内置工具
├── types/              # TypeScript 类型定义
├── utils/              # 工具函数
├── vendor/             # 第三方集成（Computer Use）
├── vim/                # Vim 模式
└── voice/              # 语音模式
```

这个结构体现了**模块化设计**的精髓：每个目录职责清晰，边界明确。

---

## 二、核心架构设计

### 2.1 整体架构图

```
┌─────────────────────────────────────────────────────────────┐
│                      用户输入                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   QueryEngine (入口)                         │
│  - 构建系统提示词 (prompts.ts + context.ts + claudemd.ts)   │
│  - 组装工具池 (tools.ts + MCP)                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              query() AsyncGenerator 循环                    │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ 阶段1: 消息压缩 (snip → micro → collapse → compact)  │  │
│  │ 阶段2: 流式 API 调用 (callModel + StreamingToolExec) │  │
│  │ 阶段3: 决策点 (继续 or 完成)                          │  │
│  │ 阶段4: 工具编排 (并行只读 + 串行写入)                 │  │
│  │ 阶段5: 状态更新 (state = next → continue)            │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
│    工具系统      │  │   多 Agent 系统  │  │   扩展生态      │
│  48+ 内置工具    │  │  Subagent       │  │  Skills         │
│  MCP 动态工具    │  │  Fork           │  │  Plugins        │
│  三层过滤机制    │  │  Teammate       │  │  Hooks           │
│  7步执行管道     │  │  Remote         │  │  MCP 协议        │
└─────────────────┘  └─────────────────┘  └─────────────────┘
```

### 2.2 核心设计理念

Claude Code 的架构体现了三个核心理念：

#### 理念一：流式优先（Streaming First）

整个架构围绕 `AsyncGenerator` 设计，一切都是流式的：
- 模型响应是流式的
- 工具在模型生成过程中就开始执行
- 进度实时更新
- 压缩策略是渐进式的

这意味着用户**永远不需要等待**——看到模型在思考、工具在执行、结果在产出。

#### 理念二：工具驱动（Tool-Driven）

Claude Code 的哲学是：**Agent 的能力等于其工具的能力**。

- 子代理生成？是一个工具（`AgentTool`）
- 团队管理？是一个工具（`TeamCreate`/`SendMessage`）
- 文件编辑？是一个工具（`FileEdit`）
- 技能执行？是一个工具（`SkillTool`）

这意味着**所有能力都通过统一的工具接口暴露**，模型通过自然语言推理来决定使用哪个工具。不需要显式的编排逻辑——模型本身就是编排器。

#### 理念三：优雅降级（Graceful Degradation）

6 种恢复策略确保 Claude Code **几乎不会因为技术问题中断用户的工作流**：
- Token 超限？自动压缩
- API 超时？自动重试
- 模型失败？降级到备用模型
- 工具失败？记录错误，继续对话

---

## 三、核心模块解析

### 3.1 query.ts - Agent 的心脏

`src/query.ts` 是整个 Agent 的核心，约 1730 行。它不是简单的"想-做-看"循环，而是一个**流式状态机**：

```typescript
export async function* query(params: QueryParams): AsyncGenerator<...> {
  let state: State = {
    messages,
    toolUseContext,
    autoCompactTracking,
    maxOutputTokensRecoveryCount,
    hasAttemptedReactiveCompact,
    maxOutputTokensOverride,
    pendingToolUseSummary,
    stopHookActive,
    turnCount,
    transition,
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

**关键设计**：通过 `state = next` 赋值驱动循环，而非递归调用。这保证了：
- **内存稳定**：不会因为深度递归导致栈溢出
- **状态可追溯**：每一轮的状态转换原因都被记录
- **恢复可控**：任何阶段的错误都可以通过修改 state 来恢复

### 3.2 Tool.ts - 工具的定义

`src/Tool.ts` 定义了工具的完整接口（约 792 行）：

```typescript
type Tool<Input, Output> = {
  // 身份
  name: string
  aliases?: string[]        // 向后兼容的旧名称
  searchHint?: string       // ToolSearch 关键词匹配

  // 能力声明
  isEnabled(): boolean
  isConcurrencySafe(input): boolean   // 是否可并行
  isReadOnly(input): boolean          // 是否只读
  isDestructive(input): boolean       // 是否破坏性

  // 生命周期
  validateInput(input, context)       // 输入验证
  checkPermissions(input, context)    // 权限检查
  call(input, context, ...)           // 实际执行

  // 输出与渲染
  renderToolUseMessage(input)         // 渲染调用信息
  renderToolResultMessage(content)    // 渲染结果信息
  mapToolResultToToolResultBlockParam()  // 映射为 API 格式

  // 智能特性
  inputSchema: Zod schema             // Zod 类型验证
  maxResultSizeChars: number           // 结果大小阈值
  getToolUseSummary?(input): string    // 工具使用摘要
}
```

这种设计使得每个工具都是**自描述、自验证、自渲染**的——框架不需要了解工具的内部逻辑，只需调用标准接口。

### 3.3 系统提示词组装

`src/constants/prompts.ts`（约 577 行）实现了**分层管道**动态组装系统提示词：

```
┌─────────────────────────────────────────────────────────────┐
│                    静态可缓存区域                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ 角色定义  │  系统规则  │  任务指导  │  工具说明  │  风格  │  │
│  └───────────────────────────────────────────────────────┘  │
├─────────────────────── 缓存边界 ────────────────────────────┤
│                    动态可变区域                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ 会话指引 │ 记忆系统 │ 环境信息 │ MCP 指令 │ Token 预算 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**缓存边界**是一个关键设计：
- **边界之上**：跨用户、跨组织通用的内容，使用 `scope: 'global'` 缓存
- **边界之下**：用户/会话特定的内容，使用 `scope: 'ephemeral'` 缓存

---

## 四、与 LangChain/ReAct 的本质区别

这是理解 Claude Code 架构的关键。大多数人认为 Claude Code 使用的是经典的 **ReAct** 模式：

```
思考(Thought) → 行动(Action) → 观察(Observation) → 思考 → ...
```

**实际上，Claude Code 没有采用这个模式。**

### 4.1 架构范式对比

| 维度 | LangChain | Claude Code |
|------|-----------|-------------|
| **核心模式** | ReAct（Think→Act→Observe） | Async Generator 状态机 |
| **执行模型** | 同步阻塞 | 流式非阻塞 |
| **工具执行** | 等待模型完整响应后执行 | 流式传输中即时执行 |
| **状态管理** | 外部 Memory 对象 | 内置状态赋值 + 循环 |
| **错误恢复** | 需要手动编排 | 6 种内置恢复策略 |
| **上下文压缩** | 简单截断或摘要 | 四级渐进式压缩 |
| **多 Agent** | Chain/Graph 显式编排 | 统一工具接口 + 状态机 |
| **扩展机制** | Python 类继承 | 技能 + 插件 + 钩子 + MCP |
| **缓存策略** | 无 | 全局/会话/按轮三级缓存 |

### 4.2 为什么不用 ReAct？

ReAct 模式有几个固有限制：

1. **串行瓶颈**：每一步必须等待完整的"思考→行动→观察"循环
2. **无流式能力**：模型生成完整响应后才能开始执行工具
3. **恢复困难**：没有统一的状态表示，难以实现自动恢复
4. **缓存不友好**：每次循环的 prompt 结构变化大，难以利用缓存

Claude Code 的 Async Generator 模式解决了所有这些问题：
- **流式执行**：工具在模型生成过程中就开始运行
- **状态可控**：`State` 对象包含所有需要的信息，恢复只需修改状态
- **缓存优化**：静态提示词全局缓存，动态部分最小化
- **并行能力**：只读工具自动并行，写入工具串行保序

---

## 五、关键源文件索引

| 组件 | 文件路径 | 行数 | 说明 |
|------|----------|------|------|
| 核心循环 | `src/query.ts` | ~1730 | Agent 主循环 |
| 查询引擎 | `src/QueryEngine.ts` | ~687 | 高层封装 |
| 工具定义 | `src/Tool.ts` | ~792 | Tool 类型系统 |
| 工具注册 | `src/tools.ts` | ~389 | 工具发现和注册 |
| 系统提示词 | `src/constants/prompts.ts` | ~577 | 提示词组装 |
| 上下文管理 | `src/context.ts` | ~300 | 系统/用户上下文 |
| Agent 生成 | `src/tools/AgentTool/AgentTool.tsx` | ~600 | Agent 工具入口 |
| 技能系统 | `src/skills/bundledSkills.ts` | ~300 | 技能注册与管理 |
| 权限系统 | `src/utils/permissions/permissions.ts` | ~500 | 权限检查 |
| 状态管理 | `src/state/AppStateStore.ts` | ~400 | 全局状态 |

---

## 六、总结

Claude Code 的架构设计体现了**简洁与强大的平衡**：

1. **一个循环**：`while (true)` 驱动的状态机
2. **一个状态**：`State` 对象承载所有上下文
3. **一个接口**：`Tool` 类型统一所有能力

没有 Agent → AgentExecutor → Chain → Memory → Callback 的嵌套抽象层，这使得代码**易于理解、调试和扩展**。

在接下来的系列文章中，我们将深入每个模块，揭示更多设计细节。

---

**系列文章导航：**
- 下一篇：[打破 ReAct 迷思：Async Generator 状态机](/claude-code-async-generator-state-machine/)