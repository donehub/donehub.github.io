---
title: opcode - Claude Code 的桌面 GUI 工具
date: 2025-09-11
tags: GUI(Claude Code)
categories: AI
---

opcode 是由 Asterisk 团队开发的开源桌面应用，基于 Tauri 2 + React 构建，为 Claude Code CLI 提供完整的图形化管理界面。它将命令行工具转变为直观的桌面体验，支持自定义 Agent 创建、会话管理、成本追踪和时间线回滚等功能，所有数据存储在本地，无云端依赖。

<!-- more -->

## 技术架构

opcode 的前端使用 React 18 + TypeScript + Vite 6 构建，UI 层基于 Tailwind CSS v4 和 shadcn/ui，状态管理选用 Zustand 5。后端是 Rust 编写的 Tauri 2 层，负责进程管理、检查点和 Tauri 命令处理。预置的 Agent 配置存放在 cc_agents 目录中。数据存储使用 SQLite（通过 rusqlite），包管理工具为 Bun。

| 层级 | 技术 |
|------|------|
| 前端框架 | React 18 + TypeScript + Vite 6 |
| UI 框架 | Tailwind CSS v4 + shadcn/ui + Radix UI |
| 状态管理 | Zustand 5 |
| 后端框架 | Rust + Tauri 2 |
| 数据存储 | SQLite (rusqlite) |
| 包管理 | Bun |

## 项目与会话管理

opcode 启动后自动扫描 `~/.claude/projects/` 目录，以可视化方式展示所有 Claude Code 项目。项目列表包含项目名称、路径和最近活动时间，支持智能搜索快速定位。点击项目即可进入该项目的会话管理界面。

每个项目下的会话历史完整保留。会话概览展示首条消息、时间戳和模型信息，元数据区域显示 Token 使用量、成本和状态。会话恢复功能允许随时继续之前的对话，完整上下文不会丢失。

## CC Agents：定制专属 AI Agent

自定义 Agent 是 opcode 的核心差异化功能。用户可以创建专属的 AI Agent，配置系统提示词、权限和默认任务，将特定工作流封装为可复用的 Agent 模板。

Agent 的配置采用 JSON 格式，包含名称、图标、模型、系统提示词和默认任务等字段。支持的图标类型包括 bot、shield、code、terminal、database 等，模型可选 opus、sonnet 或 haiku。

| 参数 | 可选值 | 说明 |
|------|--------|------|
| name | 自定义字符串 | Agent 名称 |
| icon | bot, shield, code, terminal, database, globe, file-text, git-branch | 图标类型 |
| model | opus, sonnet, haiku | 使用的 Claude 模型 |
| system_prompt | 自定义文本 | Agent 的行为指令 |
| default_task | 自定义文本 | 默认执行的任务描述 |

Agent 支持前台和后台两种执行模式。前台执行是阻塞式运行，可以实时查看进度；后台执行则在独立进程中运行，不阻塞主界面操作。权限方面可以配置文件读写和网络访问。

### 预置 Agent 示例

opcode 自带三个开箱即用的 Agent，覆盖了最常见的开发场景。

Git Commit Bot 用于自动化 Git 提交。它分析 Git 变更，生成符合 Conventional Commits 规范的提交信息并推送，模型选用 sonnet，默认任务为 "Push all changes."。日常开发中用它来替代手动编写 commit message，效率提升明显。

Security Scanner 负责项目上线前的安全审计。它执行 STRIDE 威胁建模和 OWASP Top 10 漏洞扫描，生成专业安全报告，模型选用 opus 以获得更强的推理能力。

Unit Tests Bot 为新模块快速补充测试覆盖。它分析代码结构并生成单元测试，覆盖率目标设定在 80% 以上，同样使用 opus 模型。

## 使用分析仪表盘

成本追踪模块实时监控 Claude API 的使用情况。总成本按会话累计，模型分布将成本按类型细分，时间趋势以每日或每周为粒度展示使用图表。这些数据导出后可以直接用于财务分析或团队核算。

Token 分析提供四个关键指标：Input Tokens 消耗、Output Tokens 消耗、Context Usage 利用率和 Cache Hit Rate 命中率。通过饼图和折线图可视化呈现，帮助判断哪些会话的 Token 开销偏高。

## MCP Server 管理

MCP（Model Context Protocol）服务器在 opcode 中集中管理。服务器注册表统一管理所有 MCP 配置，支持从 Claude Desktop 直接导入现有配置，连接测试功能验证服务器可用性。每个会话可以选择性启用不同的 MCP 服务器，不需要全局统一配置。

## 时间线与检查点

时间线功能为会话提供了版本控制能力。在会话任意节点可以创建检查点快照，记录当前状态。可视化时间线展示会话的演进路径，支持查看两个检查点之间的代码差异，一键回滚到任意历史状态，也可以从检查点派生新的会话分支。

这个功能的实际价值在于：当你让 Agent 执行一个高风险操作（比如大规模重构）时，可以先创建一个检查点，操作结果不满意直接回滚，零成本试错。

## CLAUDE.md 编辑器

内置的 Markdown 编辑器用于管理项目配置文件。左侧编辑、右侧实时预览，完整支持语法高亮。opcode 自动扫描发现所有 CLAUDE.md 文件，修改后立即应用于当前会话。

## 安装指南

### 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10/11, macOS 11+, Linux (Ubuntu 20.04+) |
| 内存 | 最小 4GB，推荐 8GB |
| 存储 | 至少 1GB 可用空间 |
| Claude Code | 必须已安装 Claude Code CLI |

### 前置依赖

Rust 环境通过 rustup 安装（macOS/Linux 使用 `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`，Windows 下载 rustup-init.exe）。安装后通过 `rustc --version` 和 `cargo --version` 验证。

Bun 运行时在 macOS/Linux 通过 `curl -fsSL https://bun.sh/install | bash` 安装，Windows 使用 `powershell -c "irm bun.sh/install.ps1 | iex"`。安装后通过 `bun --version` 验证。

Claude Code CLI 从 claude.ai/code 下载安装，确保 `claude` 命令在 PATH 中可用。

平台特定依赖方面，Linux (Ubuntu/Debian) 需要安装 libwebkit2gtk-4.1-dev、libgtk-3-dev 等系统库；macOS 需要 Xcode 命令行工具（`xcode-select --install`）；Windows 需要 Microsoft C++ Build Tools 和 WebView2。

### 构建步骤

克隆仓库后执行 `bun install` 安装前端依赖。开发模式通过 `bun run tauri dev` 启动，支持热重载。生产构建使用 `bun run tauri build`，构建产物位于 `src-tauri/target/release/` 目录下，不同平台输出不同格式的可执行文件。

Debug 构建使用 `bun run tauri build --debug`，编译更快但体积更大。macOS 可以通过 `--target universal-apple-darwin` 构建同时支持 Intel 和 Apple Silicon 的通用二进制。

## 使用流程

启动应用后，opcode 自动扫描 `~/.claude` 目录，欢迎界面可以选择进入 CC Agents 或 Projects。

项目管理的路径是 Projects → 项目列表 → 点击项目查看会话。每个项目卡片显示名称、最近活动时间和会话数量。恢复会话的路径是 项目详情 → 会话列表 → 点击会话 → Resume，恢复后保持完整上下文。

创建自定义 Agent 的路径是 CC Agents → Create Agent → 配置参数 → 保存。配置分为四步：填写基本信息（名称、图标、模型），编写系统提示词定义行为指令和输出格式，配置文件读写和网络访问权限，最后点击 Create 保存。

| Agent 类型 | 推荐模型 | 提示词要点 |
|------------|----------|------------|
| 简单任务 | Haiku | 简洁明确的指令 |
| 通用任务 | Sonnet | 结构化的步骤说明 |
| 复杂推理 | Opus | 详细的上下文和示例 |

导入预置 Agent 支持两种方式：从 GitHub 浏览官方仓库导入，或从本地 .opcode.json 文件导入。

执行 Agent 任务时，前台执行适合短时间任务，可以实时查看进度；后台执行适合长时间任务，Agent 在独立进程运行。执行历史记录每次任务的开始结束时间、任务描述、执行结果和 Token 使用量。

时间线功能在 Session → Timeline 中使用，创建检查点后随时可以回滚或查看差异。

MCP Server 配置在 Menu → MCP Manager 中管理，支持手动添加 JSON 配置或从 Claude Desktop 自动导入。

使用分析仪表盘在 Menu → Usage Dashboard 中查看，展示实时成本、Token 分布饼图、趋势折线图，支持导出 CSV/JSON 数据。

## 进阶技巧

### Agent 提示词模板

代码审查 Agent 的提示词结构分为三层：role 定义审查专家身份，task 列出审查关注点（代码风格、潜在 Bug、性能问题、安全漏洞），output_format 规定按文件、行号、问题类型输出表格和总体评分。这种结构化提示词让 Agent 的输出格式稳定可预期。

文档生成 Agent 的提示词同样采用 role-task-output_format 三层结构，task 部分要求分析函数签名、生成参数说明、编写使用示例和补充注意事项，输出使用 Markdown 格式包含函数名称、参数表格、返回值说明和代码示例。

### 进程隔离机制

opcode 的 Agent 运行在独立子进程中，与主 Tauri 进程和 React UI 进程分离。这种架构带来三个直接好处：Agent 崩溃不会影响主界面稳定性，多个 Agent 可以并行执行互不干扰，每个 Agent 的资源占用可以单独监控和控制。

### 数据存储位置

| 数据类型 | 存储路径 |
|----------|----------|
| Agent 配置 | ~/.opcode/agents/ |
| 检查点数据 | ~/.opcode/checkpoints/ |
| 使用记录 | ~/.opcode/analytics.db |
| MCP 配置 | ~/.claude/mcp_servers.json |

## 常见问题排查

构建时出现 "cargo not found" 错误，通常是 Rust 环境变量未加载。执行 `source ~/.cargo/env` 或重启终端，确认 `cargo --version` 正常输出即可。

Linux 上 "webkit2gtk not found" 需要安装系统依赖：`sudo apt install libwebkit2gtk-4.1-dev`。

Windows 上 "MSVC not found" 需要安装 Visual Studio Build Tools 并选择 C++ 构建工具工作负载，安装后重启终端。

"claude command not found" 说明 Claude Code CLI 未安装或不在 PATH 中。先通过 `claude --version` 确认安装状态，Windows 需要手动将安装路径添加到 PATH。

构建过程中内存不足时，可以通过 `cargo build -j 2` 减少并行编译任务数来降低内存占用。

## 项目资源

| 资源 | 链接 |
|------|------|
| GitHub 仓库 | [winfunc/opcode](https://github.com/winfunc/opcode) |
| Discord 社区 | [Join Discord](https://discord.com/invite/KYwhHVzUsY) |
| 许可证 | AGPL-3.0 |
