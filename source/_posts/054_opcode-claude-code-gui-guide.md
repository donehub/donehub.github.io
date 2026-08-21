---
title: opcode - Claude Code 的桌面 GUI 工具
date: 2025-09-11
tags: GUI(Claude Code)
categories: AI
---

> Claude Code 是 Anthropic 官方的命令行 AI 编程助手，强大的功能让它成为开发者的新宠。但命令行界面对于复杂任务管理仍有局限。opcode 作为一款基于 Tauri 2 的桌面应用，为 Claude Code 提供了可视化界面，支持自定义 Agent、会话管理、成本追踪等功能，让 AI 辅助编程更加直观高效。

<!-- more -->

## 一、项目简介

**opcode** 是由 Asterisk 团队开发的开源桌面应用，基于 Tauri 2 + React 构建，为 Claude Code CLI 提供完整的图形化管理界面。

### 核心定位

- **命令中心的可视化扩展**：将 CLI 工具转变为直观的桌面体验
- **Agent 定制平台**：创建专属 AI Agent，配置系统提示词和权限
- **使用分析仪表盘**：实时追踪 API 成本和 Token 消耗
- **本地优先**：所有数据存储在本地，无云端依赖

### 技术架构

```
opcode/
├── src/                   # React 18 + TypeScript 前端
│   ├── components/        # UI 组件（shadcn/ui + Tailwind CSS v4）
│   ├── lib/               # API 客户端与工具函数
│   └── assets/            # 静态资源
├── src-tauri/             # Rust 后端
│   ├── src/
│   │   ├── commands/      # Tauri 命令处理器
│   │   ├── checkpoint/    # 时间线管理
│   │   └── process/       # 进程管理
│   └── tests/             # Rust 测试套件
└── cc_agents/             # 预置 Agent 配置
```

**技术栈明细**：

| 层级 | 技术 |
|------|------|
| 前端框架 | React 18 + TypeScript + Vite 6 |
| UI 框架 | Tailwind CSS v4 + shadcn/ui + Radix UI |
| 状态管理 | Zustand 5 |
| 后端框架 | Rust + Tauri 2 |
| 数据存储 | SQLite (rusqlite) |
| 包管理 | Bun |

---

## 二、核心功能详解

### 1. 项目与会话管理

#### 项目浏览器

opcode 自动扫描 `~/.claude/projects/` 目录，可视化展示所有 Claude Code 项目：

- **项目列表**：显示项目名称、路径、最近活动时间
- **智能搜索**：快速定位特定项目
- **一键导航**：点击项目即可进入会话管理

#### 会话历史

每个项目下的会话完整保留：

- **会话概览**：首条消息、时间戳、模型信息
- **会话恢复**：随时继续之前的对话，保留完整上下文
- **元数据展示**：Token 使用量、成本、状态一目了然

### 2. CC Agents（自定义 Agent）

这是 opcode 最强大的功能——创建专属 AI Agent。

#### Agent 配置结构

```json
{
  "version": 1,
  "exported_at": "2025-04-12T10:00:00Z",
  "agent": {
    "name": "My Custom Agent",
    "icon": "bot",
    "model": "sonnet",
    "system_prompt": "你的 Agent 指令...",
    "default_task": "默认执行任务"
  }
}
```

#### 配置参数说明

| 参数 | 可选值 | 说明 |
|------|--------|------|
| `name` | 自定义字符串 | Agent 名称 |
| `icon` | `bot`, `shield`, `code`, `terminal`, `database`, `globe`, `file-text`, `git-branch` | 图标类型 |
| `model` | `opus`, `sonnet`, `haiku` | 使用的 Claude 模型 |
| `system_prompt` | 自定义文本 | Agent 的行为指令 |
| `default_task` | 自定义文本 | 默认执行的任务描述 |

#### Agent 运行模式

- **前台执行**：阻塞式运行，实时查看进度
- **后台执行**：独立进程运行，不阻塞主界面
- **权限控制**：配置文件读写、网络访问权限

### 3. 预置 Agent 示例

opcode 提供三个开箱即用的 Agent：

#### Git Commit Bot（自动提交）

```json
{
  "name": "Git Commit Bot",
  "icon": "bot",
  "model": "sonnet",
  "default_task": "Push all changes.",
  "system_prompt": "分析 Git 变更，生成符合 Conventional Commits 规范的提交信息并推送..."
}
```

**使用场景**：日常开发中自动化 Git 提交，生成规范的 commit message。

#### Security Scanner（安全扫描）

```json
{
  "name": "Security Scanner",
  "icon": "shield",
  "model": "opus",
  "default_task": "Review the codebase for security issues.",
  "system_prompt": "执行全面安全审计：STRIDE 威胁建模、OWASP Top 10 漏洞扫描、生成专业报告..."
}
```

**使用场景**：项目上线前的安全检查，生成详细的安全报告。

#### Unit Tests Bot（单元测试）

```json
{
  "name": "Unit Tests Bot",
  "icon": "code",
  "model": "opus",
  "default_task": "Generate unit tests for this codebase.",
  "system_prompt": "分析代码结构，生成单元测试，覆盖率目标 >80%..."
}
```

**使用场景**：为新模块快速补充测试覆盖。

### 4. 使用分析仪表盘

#### 成本追踪

实时监控 Claude API 使用情况：

- **总成本**：会话累计花费
- **模型分布**：按模型类型细分成本
- **时间趋势**：每日/每周使用图表

#### Token 分析

详细的 Token 使用明细：

| 指标 | 说明 |
|------|------|
| Input Tokens | 输入消耗 |
| Output Tokens | 输出消耗 |
| Context Usage | 上下文利用率 |
| Cache Hit Rate | 缓存命中率 |

#### 数据导出

支持导出使用数据用于财务分析或团队核算。

### 5. MCP Server 管理

Model Context Protocol（MCP）服务器统一管理：

- **服务器注册表**：集中管理所有 MCP 服务器
- **配置导入**：从 Claude Desktop 导入现有配置
- **连接测试**：验证服务器可用性
- **动态启用**：按会话选择性启用服务器

### 6. 时间线与检查点

这是 opcode 独有的版本控制功能：

#### 检查点创建

在会话任意节点创建快照：

```
Session → Create Checkpoint → 记录当前状态
```

#### 时间线导航

可视化展示会话历史：

- **分支展示**：显示会话的演进路径
- **差异对比**：查看检查点之间的代码变化
- **一键回滚**：恢复到任意历史状态
- **分支派生**：从检查点创建新的会话分支

### 7. CLAUDE.md 编辑器

内置 Markdown 编辑器管理项目配置：

- **实时预览**：左侧编辑，右侧渲染
- **语法高亮**：完整 Markdown 支持
- **项目扫描**：自动发现所有 CLAUDE.md 文件
- **即时生效**：修改后立即应用于会话

---

## 三、安装指南

### 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | Windows 10/11, macOS 11+, Linux (Ubuntu 20.04+) |
| 内存 | 最小 4GB，推荐 8GB |
| 存储 | 至少 1GB 可用空间 |
| Claude Code | 必须已安装 Claude Code CLI |

### 前置依赖安装

#### 1. Rust 环境

```bash
# macOS/Linux
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Windows: 下载 rustup-init.exe
# https://rustup.rs/
```

验证安装：

```bash
rustc --version
cargo --version
```

#### 2. Bun 运行时

```bash
# macOS/Linux
curl -fsSL https://bun.sh/install | bash

# Windows
powershell -c "irm bun.sh/install.ps1 | iex"
```

验证安装：

```bash
bun --version
```

#### 3. Claude Code CLI

从 [Claude 官网](https://claude.ai/code) 下载安装，确保 `claude` 命令在 PATH 中：

```bash
claude --version
```

#### 4. 平台特定依赖

**Linux (Ubuntu/Debian)**：

```bash
sudo apt update
sudo apt install -y \
  libwebkit2gtk-4.1-dev \
  libgtk-3-dev \
  libayatana-appindicator3-dev \
  librsvg2-dev \
  patchelf \
  build-essential \
  curl \
  wget \
  file \
  libssl-dev \
  libxdo-dev \
  libsoup-3.0-dev \
  libjavascriptcoregtk-4.1-dev
```

**macOS**：

```bash
# 安装 Xcode 命令行工具
xcode-select --install

# 可选：安装 pkg-config
brew install pkg-config
```

**Windows**：

- 安装 [Microsoft C++ Build Tools](https://visualstudio.microsoft.com/visual-cpp-build-tools/)
- 确认已安装 WebView2（Windows 11 已预装）

### 构建步骤

#### 1. 克隆仓库

```bash
git clone https://github.com/winfunc/opcode.git
cd opcode
```

#### 2. 安装前端依赖

```bash
bun install
```

#### 3. 开发模式运行

```bash
bun run tauri dev
```

这会启动开发服务器并打开应用窗口，支持热重载。

#### 4. 生产构建

```bash
bun run tauri build
```

构建产物位置：

| 平台 | 输出路径 |
|------|----------|
| Linux | `src-tauri/target/release/opcode` |
| macOS | `src-tauri/target/release/opcode.app` |
| Windows | `src-tauri/target/release/opcode.exe` |

#### 5. 特殊构建选项

**Debug 构建（更快编译，更大体积）**：

```bash
bun run tauri build --debug
```

**macOS Universal Binary（Intel + Apple Silicon）**：

```bash
bun run tauri build --target universal-apple-darwin
```

---

## 四、使用指南

### 启动与初次配置

1. **启动应用**：双击 `opcode.exe`（Windows）或运行 `./opcode`（Linux/macOS）
2. **自动检测**：opcode 会自动扫描 `~/.claude` 目录
3. **欢迎界面**：选择进入「CC Agents」或「Projects」

### 管理项目与会话

#### 查看项目

```
Projects → 项目列表 → 点击项目查看会话
```

每个项目卡片显示：
- 项目名称
- 最近活动时间
- 会话数量

#### 恢复会话

```
项目详情 → 会话列表 → 点击会话 → Resume
```

会话恢复后保持完整上下文，可直接继续对话。

### 创建自定义 Agent

#### 步骤详解

```
CC Agents → Create Agent → 配置参数 → 保存
```

1. **基本信息**：
   - 输入 Agent 名称
   - 选择图标类型
   - 选择模型（Opus/Sonnet/Haiku）

2. **系统提示词**：
   - 编写 Agent 的行为指令
   - 定义任务处理流程
   - 设置输出格式要求

3. **权限配置**：
   - 文件读权限
   - 文件写权限
   - 网络访问权限

4. **保存并测试**：点击「Create」保存 Agent

#### Agent 最佳实践

| 类型 | 推荐模型 | 提示词要点 |
|------|----------|------------|
| 简单任务 | Haiku | 简洁明确的指令 |
| 通用任务 | Sonnet | 结构化的步骤说明 |
| 复杂推理 | Opus | 详细的上下文和示例 |

### 导入预置 Agent

#### 从 GitHub 导入

```
CC Agents → Import → From GitHub → 浏览 Agent → Import Agent
```

官方仓库提供三个预置 Agent，可直接导入使用。

#### 从文件导入

```
CC Agents → Import → From File → 选择 .opcode.json 文件
```

下载 Agent 配置文件后本地导入。

### 执行 Agent 任务

#### 前台执行

```
选择 Agent → 设置任务描述 → Execute (Foreground)
```

实时查看执行进度，适合短任务。

#### 后台执行

```
选择 Agent → 设置任务描述 → Execute (Background)
```

Agent 在独立进程运行，适合长时间任务。

#### 查看执行历史

```
CC Agents → Agent 详情 → Execution History
```

显示每次执行的：
- 开始/结束时间
- 任务描述
- 执行结果
- Token 使用量

### 使用时间线功能

#### 创建检查点

在会话过程中随时创建：

```
Session → Timeline → Create Checkpoint
```

#### 回滚到检查点

```
Timeline → 选择检查点 → Restore
```

#### 查看差异

```
Timeline → 选择两个检查点 → View Diff
```

### 配置 MCP Server

```
Menu → MCP Manager → Add Server
```

#### 手动添加

输入服务器配置 JSON：

```json
{
  "name": "my-server",
  "command": "node",
  "args": ["server.js"],
  "env": {}
}
```

#### 从 Claude Desktop 导入

```
MCP Manager → Import from Claude Desktop
```

自动读取 Claude Desktop 的 MCP 配置。

### 查看使用分析

```
Menu → Usage Dashboard
```

仪表盘显示：

- **实时成本**：当前会话花费
- **Token 分布**：饼图展示输入/输出比例
- **趋势图表**：折线图展示使用趋势
- **导出功能**：下载 CSV/JSON 数据

---

## 五、进阶技巧

### Agent 提示词模板

#### 代码审查 Agent

```markdown
<role>
你是一位资深代码审查专家，专注于发现代码质量问题。
</role>

<task>
审查提交的代码变更，关注：
1. 代码风格一致性
2. 潜在的 Bug
3. 性能问题
4. 安全漏洞
</task>

<output_format>
按以下格式输出审查报告：
## 问题清单
| 文件 | 行号 | 问题类型 | 描述 | 建议 |
## 总体评价
评分：A/B/C/D
总结：...
</output_format>
```

#### 文档生成 Agent

```markdown
<role>
你是一位技术文档撰写专家。
</role>

<task>
为代码模块生成 API 文档：
1. 分析函数签名和注释
2. 生成参数说明
3. 编写使用示例
4. 补充注意事项
</task>

<output_format>
使用 Markdown 格式，包含：
- 函数名称和描述
- 参数表格
- 返回值说明
- 使用示例代码块
- 注意事项列表
</output_format>
```

### 进程隔离原理

opcode 的 Agent 运行在独立进程：

```
主进程 (Tauri)
    ├── UI 进程 (React)
    ├── Agent 进程 1 (Claude Code subprocess)
    ├── Agent 进程 2
    └── ...
```

**优势**：
- Agent 崩溃不影响主界面
- 并行执行多个任务
- 资源占用可控

### 数据存储位置

| 数据类型 | 存储路径 |
|----------|----------|
| Agent 配置 | `~/.opcode/agents/` |
| 检查点数据 | `~/.opcode/checkpoints/` |
| 使用记录 | `~/.opcode/analytics.db` |
| MCP 配置 | `~/.claude/mcp_servers.json` |

---

## 六、常见问题

### 1. 构建失败 "cargo not found"

**解决方案**：

```bash
# 确保 Rust 已安装
source ~/.cargo/env  # 或重启终端
cargo --version
```

### 2. Linux "webkit2gtk not found"

**解决方案**：

```bash
sudo apt install libwebkit2gtk-4.1-dev
```

### 3. Windows "MSVC not found"

**解决方案**：
- 安装 Visual Studio Build Tools
- 选择「C++ 构建工具」工作负载
- 重启终端

### 4. "claude command not found"

**解决方案**：

```bash
# 确保 Claude Code CLI 已安装
claude --version

# Windows: 添加到 PATH
# macOS/Linux: 确认 /usr/local/bin 在 PATH
```

### 5. 构建内存不足

**解决方案**：

```bash
# 减少并行编译
cargo build -j 2
```

---

## 七、项目资源

| 资源 | 链接 |
|------|------|
| GitHub 仓库 | [winfunc/opcode](https://github.com/winfunc/opcode) |
| Discord 社区 | [Join Discord](https://discord.com/invite/KYwhHVzUsY) |
| 许可证 | AGPL-3.0 |

---

## 八、总结

opcode 为 Claude Code 提供了完整的桌面 GUI 体验：

| 功能 | 价值 |
|------|------|
| 自定义 Agent | 定制专属 AI 工作流 |
| 会话管理 | 可视化管理所有对话 |
| 成本追踪 | 实时监控 API 开销 |
| 时间线回滚 | 版本控制式的会话管理 |
| MCP 管理 | 统一配置扩展服务 |