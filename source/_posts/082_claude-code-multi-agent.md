---
title: 多 Agent 编排的四种路径
date: 2026-04-06
tags: Multi-Agent
categories: Claude Code
---

<!-- more -->

## 单 Agent 的瓶颈

考虑一个典型场景：把项目的所有 TypeScript 文件迁移到 strict 模式，同时更新 ESLint 配置，然后运行测试确认无回归。单 Agent 只能顺序执行——修改 tsconfig、修改 ESLint、修改文件、运行测试，每一步等上一步完成。对于一个有 200 个文件的项目，这个过程可能需要十几分钟。

多 Agent 的价值在于把这类任务拆解为可并行的子任务。Explore Agent 扫描文件识别修改点，多个 Fork Agent 并行修改不同文件组，Plan Agent 协调顺序避免冲突，Verification Agent 运行测试验证结果。并行化、专业化、隔离性，这是多 Agent 编排解决的核心问题。

## Agent 类型与职责

Claude Code 定义了四种 Agent 生成方式和五类内置角色。

四种生成方式决定了 Agent 的运行环境和隔离程度：

| 生成方式 | 上下文来源 | 执行环境 | 通信方式 |
|----------|-----------|----------|----------|
| Subagent（子代理） | 独立上下文 | 同步/异步执行 | 返回值传递 |
| Fork（分叉） | 继承父代理上下文 | 共享 prompt cache | 返回值传递 |
| Teammate（队友） | 独立上下文 | tmux/iTerm2/进程内 | 邮箱通信 |
| Remote（远程） | 独立上下文 | CCR 环境 | 轮询结果 |

五类内置角色定义了工具权限和行为边界：

| 角色 | 用途 | 工具池 |
|------|------|--------|
| General Purpose | 通用任务 | 全部工具 |
| Explore | 代码库探索 | Read, Grep, Glob, WebSearch |
| Plan | 制定计划 | 全部工具，受限输出 |
| Verification | 验证结果 | Bash, Read, Grep |
| Coordinator | 编排协调 | 受限工具集 |

Agent 的定义结构统一：

```typescript
type AgentDefinition = {
  agentType: string                       // 类型标识
  description: string                     // 描述
  getSystemPrompt: (context) => string    // 系统提示词
  tools?: string[]                        // 允许的工具（'*' = 全部）
  disallowedTools?: string[]              // 禁止的工具
  model?: string                          // 模型选择
  permissionMode?: PermissionMode         // 权限模式
}
```

## 四条生成路径

所有 Agent 生成都从 `AgentTool.call()` 入口进入，根据输入参数路由到四条不同路径。

**Teammate 生成**——当 `team_name` 和 `name` 同时存在时触发。系统检测执行后端（tmux/iTerm2/进程内），生成唯一 agentId，分配 UI 颜色，创建执行环境，最后更新 TeamFile。进程内队友使用独立的 AbortController 和 AsyncLocalStorage 实现上下文隔离，但共享权限管道。

**异步 Subagent**——当 `run_in_background=true` 或 Agent 定义中 `background: true` 时触发。系统创建 LocalAgentTask，注册到 agentNameRegistry，创建 AbortController，然后异步分离执行。执行过程中通过 ProgressTracker 追踪进度，完成时提取结果、标记完成、清理 worktree、通知主代理。

**Fork Subagent**——当省略 `subagent_type` 且 Fork 实验开启时触发。这是性能最优的路径，通过构建字节级一致的 API 请求前缀实现 prompt cache 命中。Fork 子代理保留父代理完整的 assistant message，对每个 tool_use 创建占位 tool_result，最后追加唯一的 per-child directive。前缀字节一致意味着 API 层的 prompt cache 可以直接复用，省去了重新计算缓存的开销。

Fork 子代理有严格的行为约束：不对话、不提问、不使用后续建议，直接调用工具，工具调用之间不输出文本，响应必须以 "Scope:" 开头，报告控制在 500 词以内。这些约束确保 Fork 是一个高效的工作进程而非对话伙伴。

**同步 Subagent**——默认路径。系统解析 Agent 定义，构建系统提示词，创建隔离的 ToolUseContext，启动查询循环，返回最终结果。

## 工具池的三层过滤

每个 Agent 能使用哪些工具，经过三层过滤决定。

第一层是全局禁止。TaskOutput、ExitPlanMode、EnterPlanMode、AskUserQuestion、TaskStop、Agent 这六个工具对所有子代理禁用。前五个只有主代理有权操作，Agent 工具禁用是为了防止递归生成。

第二层是 Agent 类型过滤。异步 Agent 限制为 15 个工具（Read、Grep、Glob、Bash/PowerShell、FileEdit、FileWrite、WebSearch、WebFetch、TodoWrite、NotebookEdit、Skill、SyntheticOutput、ToolSearch、EnterWorktree、ExitWorktree），MCP 工具始终允许。

第三层是 Agent 定义过滤。如果定义了 `tools` 列表，取交集；如果定义了 `disallowedTools`，取差集；如果 `tools: ['*']` 或未定义，通配全部允许。

## 上下文传递与隔离

Agent 之间的上下文传递需要在共享和隔离之间取得平衡。

Fork Agent 的设计目标是最大化缓存共享。它在 API 请求中保持字节级一致的前缀（系统提示词、用户上下文、系统上下文、工具配置、对话历史、父代理的 assistant message 和占位 tool_result），只有末尾的 per-child directive 是差异部分。这意味着多个 Fork 子代理可以共享同一份 prompt cache，大幅降低 token 消耗和响应延迟。

Subagent 的设计目标是默认隔离、显式共享。消息历史独立，文件读取缓存独立，内容替换状态独立，AbortController 独立但链接到父代理（父取消时子也取消）。如果子代理需要影响父状态，必须通过 `shareSetAppState` 等显式 opt-in 参数开启。

| 资源 | 默认行为 | 说明 |
|------|----------|------|
| readFileState | 克隆 | 文件读取缓存独立 |
| messages | 新建 | 消息历史独立 |
| abortController | 新建（链接父） | 父取消时子也取消 |
| setAppState | No-op | 默认不影响父状态 |
| contentReplacementState | 克隆 | 内容替换状态独立 |

## Teams 邮箱通信

Teammate 之间通过文件系统邮箱实现异步通信。每个团队有一个 TeamFile（`~/.claude/teams/{team_name}/config.json`），记录团队元数据和成员信息。每个成员有一个独立的收件箱文件（`~/.claude/teams/{team_name}/inboxes/{agent_name}.json`）。

```typescript
type TeammateMessage = {
  from: string        // 发送者名称
  text: string        // 消息内容
  timestamp: string   // ISO 时间戳
  read: boolean       // 是否已读
  summary?: string    // 5-10 词摘要
}
```

收件箱轮询间隔 1000ms。收到消息后，系统判断消息类型：关停请求、plan 审批响应、权限请求、还是普通文本消息。普通文本消息会被提交为新的对话轮，触发 Agent 处理。并发安全通过 `proper-lockfile` 文件锁保证，10 次重试，5-100ms 指数退避。

消息路由根据目标地址分为五种情况：`to === "*"` 广播给所有队友；`agentNameRegistry` 中的名称路由到进程内子代理；`teamFile.members` 中的名称写入对应队友的 mailbox；`bridge:` 前缀路由到远程会话；`uds:` 前缀通过 Unix Domain Socket 发送。

## Worktree 隔离

当 Agent 需要修改文件时，系统创建 git worktree 作为隔离环境。创建流程包括 slug 校验（防目录逃逸攻击）、git worktree 创建、符号链接大目录（node_modules 等节省磁盘）、以及可选的 sparse-checkout 配置。

Agent 完成后自动检测 worktree 是否有改动。有改动时返回 worktree 路径和分支名给用户，用户可以审查后决定是否合并。无改动时自动删除 worktree。异常退出通过 `registerTeamForSessionCleanup()` 确保清理。

## 权限同步

团队级权限通过 `TeamAllowedPath` 定义，包含路径、适用工具、添加者和时间戳。队友启动时自动继承这些权限规则，不需要逐个配置。

Fork Agent 使用 `bubble` 权限模式——权限提示冒泡到父代理终端。当 Fork 需要执行某个操作时，权限请求发送到父代理的 ToolUseConfirm 对话框，用户批准后结果回传给 Fork，拒绝则 Fork 收到拒绝通知。这个设计确保 Fork 的权限不会超过父代理的授权范围。

## 关键源文件

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

---

**系列文章导航：**
- 上一篇：[工具系统设计：从定义到执行的七步管道](/2026/04/06/087_claude-code-tool-system/)
- 下一篇：[Context 压缩的四级策略](/2026/04/06/080_claude-code-context-compression/)
