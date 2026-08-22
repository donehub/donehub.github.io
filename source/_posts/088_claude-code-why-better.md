---
title: 超越 Prompt 的 Agent 运行时
date: 2026-04-06
tags: Code Agent
categories: Claude Code
---

<!-- more -->

## 同样的模型，不同的体验

一个反直觉的现象：用 GPT-4 模型搭配 OpenAI 的 Codex CLI，效果尚可；用 GPT-4 模型搭配 Anthropic 的 Claude Code，效果更好。自家模型配自家 Agent 应该是最佳组合，但实际表现不如搭配竞争对手的 Agent。

常见的猜测是"Claude Code 的 Prompt 更好"。Prompt 确实有影响，但不是决定性因素。Claude Code 的源码揭示了一个更根本的差异：它不是一个 Prompt 工具，而是一个完整的 Agent 运行时框架。这个框架理解模型的能力边界、工具的执行风险、上下文的压缩策略和用户的意图流转。模型是大脑，Claude Code 是躯体——这个类比虽然粗略，但抓住了核心关系。

## 主流竞品概览

当前市面上的 AI Code Agent 产品分为两类：终端型 CLI 工具和 AI 原生 IDE。

| 产品 | 公司 | 形态 | 核心特点 |
|------|------|------|----------|
| Claude Code | Anthropic | CLI | Agent 运行时，MCP 扩展 |
| Codex CLI | OpenAI | CLI | 同类型竞品，GPT 模型驱动 |
| Cursor | Anysphere | AI IDE | VS Code fork，深度上下文感知 |
| Trae | 字节跳动 | AI IDE | 自适应学习 |
| GitHub Copilot | Microsoft | IDE 扩展 | 行业先驱，生态成熟 |
| Qoder | 阿里云 | IDE 扩展 | 通义灵码，阿里云生态 |

Claude Code 与 Codex CLI 是直接竞品，都是终端型 CLI 工具。IDE 类产品（Cursor、Trae、Copilot、Qoder）的交互方式不同，但底层都面临相似的 Agent 工程问题。

## 架构选择：状态机 vs ReAct

大多数 Code Agent 采用 ReAct（Reasoning + Acting）模式：Thought → Action → Observation 循环。这个模式简单直观，但存在三个结构性问题：容易陷入思考死循环、工具失败后缺乏恢复机制、上下文无限膨胀直到截断。

Claude Code 选择 Async Generator 状态机替代 ReAct 循环。每次 `step()` 调用推进一个状态，状态推进有明确边界，不会无限循环。状态机内置 6 种错误恢复策略，工具失败后可以自动重试、降级或回退。Generator 模式天然支持流式交互，模型输出和工具执行可以交错进行，不需要等待完整的 Thought-Action-Observation 周期。

| 特性 | ReAct 模式 | 状态机模式 |
|------|-----------|-----------|
| 死循环风险 | 高（循环无边界） | 低（状态推进有终点） |
| 错误恢复 | 无（失败即终止） | 有（6 种恢复策略） |
| 流式交互 | 困难（需等待完整周期） | 原生支持（Generator） |
| 上下文管理 | 简单截断 | 四级压缩 |

## 工具执行的安全管道

多数 Agent 的工具执行是直接调用：传入参数，执行，返回结果。没有验证、没有权限检查、没有后处理。这种设计在受控环境下可以工作，但在真实开发场景中风险很高——一个错误的 `rm -rf` 命令可能造成不可逆的损害。

Claude Code 的工具执行经过七步管道：查找 → 输入解析（Zod schema）→ 自定义验证 → Pre-Tool 钩子 → 权限检查（五层决策链）→ 实际执行 → Post-Tool 钩子。验证在权限之前执行，确保无效输入不会触发权限对话框；权限在执行之前拦截危险操作；钩子允许用户在任意阶段注入自定义逻辑。

工具延迟加载机制进一步降低了 token 开销。48+ 个内置工具的 schema 约 15000 tokens，延迟加载后初始提示词只包含核心工具（约 5000 tokens），节省 66%。不常用的工具通过 ToolSearch 按需加载完整 schema。

MCP 协议提供了无限扩展能力。任何开发者可以用任何语言编写 MCP Server，扩展 Agent 的工具集。这个开放架构让 Claude Code 的能力边界不再受限于内置工具数量。

## 上下文管理的四级策略

多数 Agent 的上下文管理是暴力截断：超过 token 限制时丢弃最早的消息。这种方式简单但粗暴，重要信息可能丢失，模型会"忘记"之前的关键决策。

Claude Code 的四级渐进式压缩从轻到重依次触发：Snip（去重截断，每轮自动）→ Micro（原地优化缓存内容）→ Context Collapse（渐进式分段摘要，优先处理最旧消息）→ Auto Compact（模型生成全局摘要，替换所有历史）。每一级都尽可能保留对任务有用的信息（决策、文件修改、待办事项），而不是简单地丢弃。

这套压缩机制使得长对话成为可能。在 50 轮以上的编码会话中，前两级压缩通常就能回收足够的空间；只有特别长的任务才会触发后两级。压缩后的上下文仍然能支撑模型继续工作，因为关键信息被保留在摘要中。

## 多代理协作

多数 Code Agent 是单 Agent 设计：一个模型加一套工具完成所有任务。复杂任务难以分解，单一模型容易思维固化，无法并行处理。

Claude Code 定义了四种 Agent 生成方式：Subagent（同步/异步子代理，短生命周期）、Fork（继承父代理上下文，共享 prompt cache）、Teammate（独立上下文，通过邮箱异步通信）、Remote（CCR 环境远程执行）。Fork Agent 的字节级一致前缀设计让多个子代理共享同一份 prompt cache，大幅降低 token 消耗。Teams 邮箱通信支持并行任务分发和结果汇总。

四种方式的组合覆盖了从简单子任务到复杂并行协作的全部场景。Explore Agent 扫描代码库，多个 Fork Agent 并行修改文件，Plan Agent 协调顺序，Verification Agent 运行测试——这是一个完整的协作框架，而不是简单的任务分发。

## 分层权限控制

多数 Agent 的安全机制是简单的 allow/deny 开关。一旦开启危险命令权限，所有操作都被允许；关闭则全部禁止。没有中间地带。

Claude Code 的五层权限决策链（规则 → 模式 → 钩子 → 分类器 → 用户确认）提供了精细控制。`git status` 自动允许（Git 白名单），`rm -rf node_modules` 需要确认（危险命令），`rm -rf /` 永远拒绝（deny 规则），写入 `.git/config` 被拒绝（敏感路径）。每个决策都有原因记录，用于调试和审计。

`auto` 模式下的 AI 分类器可以自动判断操作的安全性。分数高于 0.8 自动允许，低于 0.2 自动拒绝，中间区间询问用户。连续拒绝 3 次后回退到用户审批，防止陷入拒绝循环。

## Memory 系统

多数 Agent 每次对话从零开始，用户需要反复说明相同的背景信息。

Claude Code 的 Memory 系统将知识分为四类：User（用户画像）、Feedback（行为反馈）、Project（项目动态）、Reference（外部引用）。记忆通过 YAML frontmatter + Markdown 格式持久化，自动提取机制在对话结束后分析并保存有价值的信息。智能检索用 Sonnet 模型动态选择相关记忆，新鲜度警告对旧记忆标注时效提醒。

这个系统让 Agent 能够跨会话积累知识。用户的编码偏好、项目的架构决策、团队的工作分工——这些信息不需要每次重复说明，Memory 会记住它们。

## Channel 远程控制

多数 Agent 只能在本地终端交互，用户必须坐在电脑前才能让 Agent 工作。

Claude Code 的 Channel 系统支持通过 Telegram 等 IM 工具远程控制。用户在手机上下达指令，Agent 在本地电脑上执行，结果回复到 IM。六层访问控制（能力声明、运行时开关、OAuth 认证、组织策略、会话白名单、Marketplace 验证）确保安全。

这个设计解除了 Agent 的地理限制。外出时可以远程下达任务，紧急修复可以手机审批操作，进度可以通过 IM 实时反馈。

## Terminal UI

多数 Agent 的界面是简单的 stdout 输出，信息密集时难以阅读，无法交互式选择。

Claude Code 用 React + Ink 构建终端 UI。Yoga 引擎提供 Flexbox 布局，双缓冲渲染避免闪烁，组件化设计（Header、MessageList、ToolBar、ContextPanel、InputBox、PermissionDialog）实现结构化展示。键盘导航支持交互式选择，权限对话框让用户可以逐条审批操作。

## System Prompt 的缓存优化

多数 Agent 的 System Prompt 是静态字符串，每次请求全量发送，无法缓存。

Claude Code 的系统提示词约 20k tokens，通过缓存边界标记分为静态区域和动态区域。静态部分（角色定义、规则、工具说明）在全球范围内共享缓存，动态部分（日期、Git 状态、MCP 指令、CLAUDE.md）按会话级缓存。三级缓存体系（Global → Ephemeral → Section）覆盖不同的时间尺度。

这个设计的实际效果是：静态部分缓存命中率接近 100%，动态部分在 CLAUDE.md 不变时也能保持高命中率。每个会话的延迟和 API 费用因此显著降低。

## 核心差异

Claude Code 的竞争优势不在于单一功能，而在于系统工程的深度。状态机架构替代 ReAct 循环，七步工具管道替代裸执行，四级压缩替代暴力截断，五层权限替代简单开关，Memory 系统替代每次从零开始。每一个设计决策都指向同一个目标：让 Agent 在真实开发场景中可靠地工作。

这些机制单独看都不复杂，但组合起来形成了一个完整的运行时框架。其他 Agent 提供的是模型的接口，Claude Code 提供的是模型的运行环境。

---

**系列文章导航：**
- 系列起点：[Claude Code 源码揭秘：整体架构概览](/2026/04/07/089_claude-code-architecture-overview/)
