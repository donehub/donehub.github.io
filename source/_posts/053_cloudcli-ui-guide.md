---
title: CloudCLI UI - Claude Code 的 Web GUI 与云端方案
date: 2025-09-11
tags: GUI(Claude Code)
categories: AI
---

<!-- more -->

CloudCLI UI（又名 Claude Code UI）是一款基于 Node.js + React 的 Web 应用，为 Claude Code、Cursor CLI、Codex 和 Gemini CLI 提供统一的图形化界面。与桌面应用不同，它通过浏览器访问，支持移动端使用，并提供云端托管选项。项目由 CloudCLI 团队开源，采用 Express + WebSocket + React 构建，配置直接写入 `~/.claude` 目录，与 CLI 完全同步。

## 项目定位与对比

CloudCLI UI 的核心特点包括多 Agent 统一界面（同时支持 Claude Code、Cursor CLI、Codex、Gemini CLI）、响应式 Web 设计（桌面、平板、手机浏览器全覆盖）、云端托管选项（本地自托管或 CloudCLI Cloud 服务）、以及配置无缝同步（UI 配置直接写入 `~/.claude`，与 CLI 完全一致）。

| 对比项 | CloudCLI UI | opcode | Claude Code Remote Control |
|--------|-------------|--------|---------------------------|
| 架构 | Web 应用 | 桌面应用 | CLI 扩展 |
| 多 Agent 支持 | Claude/Cursor/Codex/Gemini | 仅 Claude | 仅 Claude |
| 移动端 | 响应式 Web | 无 | Claude App |
| 部署方式 | npx/npm/Docker/云托管 | 本地安装 | 内置功能 |
| 云端运行 | 支持（CloudCLI Cloud） | 不支持 | 不支持 |
| 会话发现 | 自动发现全部会话 | 自动发现全部会话 | 仅当前会话 |
| 配置同步 | 与 CLI 完全同步 | 与 CLI 完全同步 | 独立配置 |

## 技术架构

项目采用前后端分离架构。前端基于 React 18 + TypeScript + Vite 7 构建，UI 层使用 Tailwind CSS + Radix UI，代码编辑器采用 CodeMirror 6（带 minimap），终端模拟使用 xterm.js 5 + WebGL 渲染，Markdown 渲染依赖 react-markdown + remark-gfm + KaTeX。后端基于 Express 4 + WebSocket (ws)，通过 node-pty 创建伪终端进程，数据存储使用 SQLite + better-sqlite3，国际化方案为 i18next。

目录结构如下：

```
CloudCLI UI/
├── src/                     # React 18 前端
│   ├── components/
│   │   ├── chat/            # 聊天界面 + 工具渲染
│   │   ├── code-editor/     # CodeMirror 编辑器
│   │   ├── file-tree/       # 文件树组件
│   │   ├── git-explorer/    # Git 浏览器
│   │   ├── terminal/        # xterm.js 终端
│   │   ├── settings/        # 设置面板
│   │   └── auth/            # 认证模块
│   └── hooks/               # React Hooks
├── server/                  # Node.js 后端
│   ├── index.js             # Express 服务器
│   ├── WebSocket 实时通信
│   ├── REST API
│   ├── SQLite 数据存储
│   └── node-pty 进程管理
├── shared/                  # 共享模块
│   └── modelConstants.js    # 支持的模型列表
├── docker/                  # Docker 部署
│   ├── claude-code/
│   ├── codex/
│   └── gemini/
└── public/                  # 静态资源
```

| 层级 | 技术 |
|------|------|
| 前端框架 | React 18 + TypeScript + Vite 7 |
| UI 框架 | Tailwind CSS + Radix UI |
| 代码编辑器 | CodeMirror 6 + minimap |
| 终端模拟 | xterm.js 5 + WebGL 渲染 |
| Markdown 渲染 | react-markdown + remark-gfm + KaTeX |
| 后端框架 | Express 4 + WebSocket (ws) |
| 进程管理 | node-pty (伪终端) |
| 数据存储 | SQLite + better-sqlite3 |
| 国际化 | i18next |

## 多 Agent 支持

CloudCLI UI 是目前唯一支持多种 AI Agent CLI 的统一界面，同时集成了 Claude Code（Anthropic 官方 CLI，使用 @anthropic-ai/claude-agent-sdk）、Cursor CLI（Cursor 编辑器的 CLI，独立集成）、Codex（OpenAI Codex CLI，使用 @openai/codex-sdk）、Gemini CLI（Google Gemini CLI，独立集成）。启动时可在 CLI Selection 界面选择要使用的 Agent，确认后进入对应会话。

## 响应式聊天界面

聊天界面支持多种消息格式：Markdown 渲染（标题、列表、表格、代码块）、KaTeX 数学公式、多语言代码高亮、以及工具调用的可视化展示。实时交互通过 WebSocket 实现，包括流式响应（实时显示 Agent 输出）、交互式工具（AskUserQuestion 等交互组件）、状态同步（Agent 状态实时更新）。

聊天组件架构：

```
ChatInterface.tsx
    ├── ChatComposer.tsx         # 输入框 + 文件提及
    ├── ChatMessagesPane.tsx     # 消息列表（虚拟滚动）
    ├── MessageComponent.tsx     # 单条消息渲染
    ├── Markdown.tsx             # Markdown 解析
    ├── TokenUsagePie.tsx        # Token 使用饼图
    └── ThinkingModeSelector.tsx # 思考模式选择
```

## 集成 Shell 终端

基于 xterm.js 的完整终端，通过 node-pty 创建真实 shell 进程（伪终端 PTY），支持 ANSI 颜色转义序列、系统剪贴板集成（复制粘贴）、多 Tab 扩展（通过插件实现）。渲染层使用 WebGL addon 实现 GPU 加速，配合 Fit addon 自动调整尺寸、WebLinks addon 支持链接点击。

```
Terminal.tsx
    ├── XTerm 组件               # 终端渲染
    ├── WebGL addon              # GPU 加速渲染
    ├── Fit addon                # 自动调整大小
    ├── WebLinks addon           # 链接点击
    └── Clipboard addon          # 剪贴板支持
```

## 文件浏览器与代码编辑器

交互式文件树支持三种视图模式：Tree（树状结构，可展开目录）、List（平铺列表）、Detailed（详细信息，包含大小和修改时间）。文件操作包括点击文件在 CodeMirror 编辑器打开、拖拽上传到目录、右键菜单新建删除、实时搜索文件名过滤。

```
FileTree.tsx
    ├── FileTreeHeader.tsx       # 搜索 + 视图切换
    ├── FileTreeBody.tsx         # 文件列表
    ├── FileTreeNode.tsx         # 单个文件/目录
    ├── FileContextMenu.tsx      # 右键菜单
    └── FileTreeDetailedColumns.tsx # 详细列视图
```

CodeMirror 编辑器提供完整的代码编辑体验，支持 JavaScript、Python、CSS、HTML、JSON、Markdown 等多种语言的语法高亮，配备代码缩略图侧边栏（Minimap）、One Dark 主题、自动保存、与 Git 版本的 Diff 视图、以及 Markdown 实时预览功能。

```
CodeEditor.tsx
    ├── CodeEditorSurface.tsx    # 编辑器主体
    ├── CodeEditorHeader.tsx     # 文件路径 + 操作
    ├── CodeEditorFooter.tsx     # 状态栏
    ├── EditorSidebar.tsx        # 侧边栏大纲
    └── MarkdownPreview.tsx      # Markdown 预览
```

| 功能 | 说明 |
|------|------|
| 语法高亮 | JavaScript、Python、CSS、HTML、JSON、Markdown 等 |
| Minimap | 代码缩略图侧边栏 |
| 主题 | One Dark 主题 |
| 自动保存 | 编辑后自动保存 |
| Diff 视图 | 显示与 Git 版本的差异 |
| Markdown 预览 | 实时预览 Markdown 文件 |

## Git 浏览器

可视化 Git 操作界面包含四个核心组件：GitStatus（当前状态）、GitChanges（变更列表）、GitCommit（提交面板）、GitBranch（分支选择）。功能覆盖查看变更（显示 modified、added、deleted 文件）、暂存文件（点击暂存或取消暂存）、提交更改（输入 commit message 并提交）、分支切换（下拉选择切换分支）、Diff 对比（查看文件变更详情）。

```
GitExplorer.tsx
    ├── GitStatus.tsx            # 当前状态
    ├── GitChanges.tsx           # 变更列表
    ├── GitCommit.tsx            # 提交面板
    └── GitBranch.tsx            # 分支选择
```

## 会话管理

启动时自动扫描 `~/.claude/projects/` 目录，加载所有项目并显示会话列表。支持的会话操作包括恢复会话（继续之前的对话）、新建会话（创建新的对话）、删除会话（清理历史会话）、查看历史（查看完整对话记录）。

## MCP Server 管理

CloudCLI UI 直接读写 `~/.claude/settings.json`，实现与 Claude Code 配置的双向同步。在 UI 中添加 MCP 服务器后立即在 Claude Code CLI 中可用，在 CLI 中配置 MCP 后 UI 自动读取显示。配置入口位于 Settings → MCP → Add Server。

MCP 配置格式示例：

```json
{
  "mcpServers": {
    "my-server": {
      "command": "node",
      "args": ["server.js"],
      "env": {
        "API_KEY": "xxx"
      }
    }
  }
}
```

## 工具权限控制

所有工具默认禁用，需要在 Settings → Tools Settings 中选择性启用。工具按风险等级分为四类：文件操作（Read、Write、Edit，中等风险）、系统操作（Bash、Task，高风险）、网络操作（WebFetch、WebSearch，中等风险）、交互工具（AskUserQuestion，低风险）。推荐首次使用时仅启用基础工具（Read、AskUserQuestion），后续根据需要逐步启用其他工具，保存设置后自动持久化。

| 类别 | 工具 | 风险等级 |
|------|------|----------|
| 文件操作 | Read、Write、Edit | 中等 |
| 系统操作 | Bash、Task | 高 |
| 网络操作 | WebFetch、WebSearch | 中等 |
| 交互工具 | AskUserQuestion | 低 |

## 插件系统

可扩展的插件架构支持自定义 Tab 和后端服务。插件结构包含 manifest.json（插件配置）、frontend 目录（React 前端）、backend 目录（Node.js 后端，可选）。安装插件的路径为 Settings → Plugins → Install from Git，输入仓库 URL 即可。

```
my-plugin/
├── manifest.json           # 插件配置
├── frontend/               # React 前端
│   └── TabComponent.tsx
└── backend/                # Node.js 后端（可选）
    └── server.js
```

插件 Manifest 配置示例：

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "displayName": "My Plugin",
  "description": "Plugin description",
  "icon": "icon.png",
  "main": "backend/server.js",
  "frontend": "frontend/index.js",
  "tabs": [
    {
      "id": "my-tab",
      "title": "My Tab",
      "icon": "lucide:folder"
    }
  ]
}
```

目前可用的插件包括 Project Stats（文件统计、代码行数，仓库：cloudcli-plugin-starter）和 Web Terminal（多 Tab 终端，仓库：cloudcli-plugin-terminal）。

## 安装与部署

**npx 快速启动**（无需安装，需要 Node.js v22+）：

```bash
npx @cloudcli-ai/cloudcli
```

启动后访问 `http://localhost:3001`，自动发现所有会话。

**全局安装**（适合日常使用）：

```bash
npm install -g @cloudcli-ai/cloudcli
cloudcli
```

**Docker 部署**（适合服务器部署）：

```bash
docker build -f docker/claude-code/Dockerfile -t cloudcli-claude .
docker run -p 3001:3001 -v ~/.claude:/root/.claude cloudcli-claude
```

Docker 部署文件结构：

```
docker/
├── claude-code/Dockerfile   # Claude Code 容器
├── codex/Dockerfile         # Codex 容器
├── gemini/Dockerfile        # Gemini CLI 容器
└── shared/
    ├── install-cloudcli.sh  # 安装脚本
    └── start-cloudcli.sh    # 启动脚本
```

**PM2 生产部署**（适合长期运行）：

```bash
npm install -g pm2
pm2 start server/index.js --name cloudcli
pm2 status
pm2 startup
pm2 save
```

**远程服务器部署**需要以下步骤。首先安装依赖（Ubuntu/Debian）：

```bash
sudo apt update
sudo apt install -y nodejs npm git
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

然后克隆并构建项目：

```bash
git clone https://github.com/siteboon/claudecodeui.git
cd claudecodeui
npm install
npm run build
```

创建 `.env` 文件配置环境变量：

```env
PORT=3001
HOST=0.0.0.0
AUTH_REQUIRED=true
JWT_SECRET=your-secret-key
```

启动服务并配置防火墙：

```bash
npm run server
sudo ufw allow 3001
```

访问 `http://your-server-ip:3001` 即可。

**CloudCLI Cloud 托管服务**提供无需本地部署的云端方案，访问地址为 [cloudcli.ai](https://cloudcli.ai)。

| 特性 | 说明 |
|------|------|
| 无需安装 | 直接在浏览器使用 |
| 云端运行 | Agent 在云端持续运行 |
| 团队共享 | 团队成员可共享会话 |
| REST API | 提供 API 接口 |
| n8n 集成 | 支持 n8n 自动化节点 |
| 费用 | $7/月起 |

## 使用指南

启动服务后在终端会看到输出信息（Server running on http://localhost:3001、WebSocket connected、Discovered N projects from ~/.claude），浏览器访问 `http://localhost:3001`，首次使用需在 CLI Selection 界面选择 Agent（Claude Code / Cursor / Codex / Gemini）并确认。

界面布局方面，顶部 Header 包含 Logo、项目名称、设置入口、用户信息；左侧 Sidebar 提供 Chat、Files、Git、Terminal、MCP 等导航；中间 Main Content 区域显示消息列表（虚拟滚动）和 Chat Composer（输入框 + 附件 + 发送按钮）；底部 Footer 展示 Token 使用量、当前模型、费用统计。移动端界面会自动调整为单列显示，底部导航栏保留 Chat、Files、Git、Terminal 入口。

**聊天操作**：在 Chat Composer 输入消息后点击 Send 或按 Enter 发送；输入 `@` 可提及文件，文件内容自动附加；点击 Attach 按钮可上传图片；通过 Thinking Mode Selector 可选择 Default（正常模式）、Thinking（扩展思考模式）、Interleaved（交替思考模式）。

**文件操作**：在 Sidebar → Files 中展开折叠目录，点击文件打开；点击文件后 CodeMirror 编辑器打开，编辑内容自动保存；在 Files 目标目录拖拽文件即可上传。

**Git 操作**：Sidebar → Git 显示当前状态，包括 Modified（已修改未暂存）、Staged（已暂存待提交）、Untracked（未跟踪文件）；在 Git → Changes 中点击文件可 Stage/Unstage；输入 commit message 后点击 Commit 提交；通过 Branch dropdown 切换分支。

**终端使用**：Sidebar → Terminal 显示 xterm.js 终端，可输入命令执行、查看 ANSI 颜色输出、使用 Ctrl+Shift+C/V 复制粘贴、滚动查看历史输出。

**MCP 配置**：Settings → MCP → Add Server 填写配置后保存；也支持从 Claude Desktop 导入（Settings → MCP → Import from Claude Desktop）。

配置示例：

```json
{
  "name": "filesystem",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
}
```

**工具权限设置**：Settings → Tools Settings 选择性启用工具后 Apply。推荐配置如下：

| 工具 | 首次启用 | 高级使用 |
|------|----------|----------|
| Read | ✓ | ✓ |
| Write | - | ✓ |
| Edit | - | ✓ |
| Bash | - | ✓（谨慎） |
| WebFetch | - | ✓ |
| WebSearch | - | ✓ |

**移动端使用**：启动服务后，手机浏览器访问 `http://[你的电脑IP]:3001`，界面会自动适配移动端布局。

## 进阶配置

环境变量通过 `.env` 文件配置，主要包含：服务器配置（PORT=3001、HOST=0.0.0.0）、认证配置（AUTH_REQUIRED=true、JWT_SECRET、JWT_EXPIRY=7d）、各 Agent API Key（CLAUDE_API_KEY、OPENAI_API_KEY、GOOGLE_API_KEY）、插件配置（PLUGINS_DIR=./plugins）、日志配置（LOG_LEVEL=info）。

认证系统方面，首次访问应用时会进入 Setup Screen 创建管理员账号，之后通过 Login Screen 登录进入 Protected Routes。认证组件包括 context/AuthContext.tsx（认证状态管理）、view/LoginForm.tsx（登录表单）、view/SetupForm.tsx（设置表单）、view/ProtectedRoute.tsx（路由保护）、utils.ts（认证工具函数）。

国际化支持方面，界面已支持 English、中文、日本語、한국어、Deutsch、Русский 六种语言，通过 i18next-browser-languagedetector 自动检测浏览器语言，也可手动切换并持久化到 localStorage。

性能优化方面，消息列表使用 `@tanstack/react-virtual` 实现虚拟滚动，仅渲染可见区域的消息；WebSocket 通信采用消息队列缓冲机制，避免并发处理冲突；终端渲染使用 xterm.js WebGL addon 启用 GPU 加速。

虚拟滚动代码示例：

```tsx
// 仅渲染可见消息
const rowVirtualizer = useVirtualizer({
  count: messages.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 100,
});
```

WebSocket 消息队列示例：

```js
// 消息队列缓冲
const messageQueue = [];
let isProcessing = false;

function processQueue() {
  if (isProcessing || messageQueue.length === 0) return;
  isProcessing = true;
  const msg = messageQueue.shift();
  handleMessage(msg);
  isProcessing = false;
  processQueue();
}
```

终端渲染配置：

```js
import { WebglAddon } from '@xterm/addon-webgl';

const terminal = new Terminal();
terminal.loadAddon(new WebglAddon());
```

## 插件开发指南

创建插件的第一步是 Fork 模板仓库 https://github.com/cloudcli-ai/cloudcli-plugin-starter，然后克隆到本地：

```bash
git clone https://github.com/your-username/my-plugin.git
cd my-plugin
```

插件目录结构：

```
my-plugin/
├── manifest.json
├── frontend/
│   ├── index.tsx
│   └── TabComponent.tsx
├── backend/
│   └── server.ts
└── package.json
```

Manifest 配置需要指定插件名称、版本、显示名称、描述、图标、入口文件、前端入口、Tab 定义、RPC 方法等：

```json
{
  "name": "my-plugin",
  "version": "1.0.0",
  "displayName": "My Plugin",
  "description": "Custom plugin for CloudCLI",
  "icon": "icon.svg",
  "main": "backend/server.ts",
  "frontend": "frontend/index.tsx",
  "tabs": [
    {
      "id": "my-tab",
      "title": "My Tab",
      "icon": "lucide:star"
    }
  ],
  "rpcMethods": ["getData", "processData"]
}
```

前端组件通过 `usePluginContext` 获取项目路径和 RPC 调用能力：

```tsx
// frontend/TabComponent.tsx
import { usePluginContext } from '@cloudcli-ai/plugin-sdk';

export function MyTab() {
  const { projectPath, rpc } = usePluginContext();

  const handleAction = async () => {
    const result = await rpc.call('processData', { path: projectPath });
    console.log(result);
  };

  return (
    <div className="p-4">
      <h2>My Plugin Tab</h2>
      <button onClick={handleAction}>Process</button>
    </div>
  );
}
```

后端服务通过 `createPluginServer` 注册 RPC 方法：

```ts
// backend/server.ts
import { createPluginServer } from '@cloudcli-ai/plugin-sdk';

const server = createPluginServer();

server.registerMethod('getData', async (params) => {
  return { data: 'Hello from backend' };
});

server.registerMethod('processData', async (params) => {
  // 处理数据
  return { success: true };
});

server.start();
```

安装自定义插件的路径为 Settings → Plugins → Install from Git，输入仓库 URL 后点击 Install。

## API 接口

项目提供完整的 REST API 接口，涵盖项目管理、会话管理、文件操作、Git 操作四大模块。

**项目 API**：

```bash
GET /api/projects           # 获取项目列表，返回 [{ id, name, path, sessionsCount }]
GET /api/projects/:id       # 获取项目详情，返回 { id, name, path, sessions, config }
```

**会话 API**：

```bash
POST /api/sessions          # 创建会话，Body: { projectId, model, task }，返回 { sessionId, status }
POST /api/sessions/:id/chat # 发送消息，Body: { message, attachments }，返回 { messageId, status }
GET  /api/sessions/:id      # 获取会话详情，返回 { id, messages, model, usage }
```

**文件 API**：

```bash
GET  /api/files?path=/project  # 获取文件树，返回 [{ name, type, path, children }]
GET  /api/files/:path          # 获取文件内容，返回 { content, encoding, size }
PUT  /api/files/:path          # 更新文件，Body: { content }，返回 { success, size }
```

**Git API**：

```bash
GET  /api/git/status           # 获取状态，返回 { branch, staged, unstaged, untracked }
POST /api/git/commit           # 提交更改，Body: { message, files }，返回 { commitId, success }
```

## 与 Claude Code Remote Control 对比

官方的 Claude Code Remote Control 功能相对有限，以下是两者的详细对比：

| 对比项 | CloudCLI UI | Claude Code Remote Control |
|--------|-------------|---------------------------|
| 会话覆盖 | 全部会话自动发现 | 仅当前活动会话 |
| 配置同步 | 完全同步（双向） | 独立配置 |
| 多 Agent | 支持 4 种 CLI | 仅 Claude Code |
| UI 功能 | 文件树、Git、终端 | 仅聊天窗口 |
| 运行方式 | 可云端运行 | 本地终端必须开启 |
| 超时限制 | 无限制 | 断网约 10 分钟超时 |
| 移动端 | 响应式 Web | Claude App |

## 常见问题

**npx 启动失败**：如果 `node-pty` 编译失败，需要先安装编译工具（Windows: `npm install -g windows-build-tools`；Linux: `sudo apt install build-essential`），然后清除缓存重新安装（`npm cache clean --force && npx @cloudcli-ai/cloudcli`）。

**WebSocket 连接失败**：浏览器无法连接 WebSocket 时，检查 `.env` 中的 HOST 配置，远程访问需设置为 `HOST=0.0.0.0`，本地访问使用 `HOST=localhost`。

**移动端无法访问**：手机浏览器无法打开时，首先检查防火墙是否放行了 3001 端口（`sudo ufw allow 3001`），然后通过 `ip addr show` 确认正确的 IP 地址，最后用手机访问 `http://[正确的IP]:3001`。

**MCP 服务器不显示**：UI 中添加的 MCP 在 CLI 中不生效时，检查 `~/.claude/settings.json` 文件内容，确保 JSON 格式正确，然后重启 CloudCLI。

**终端无法输入**：xterm.js 终端无法输入命令时，执行 `npm rebuild node-pty` 重建伪终端模块，在 Linux/macOS 上还需确保 shell 有执行权限。

## 项目资源

| 资源 | 链接 |
|------|------|
| GitHub 仓库 | [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) |
| 官方文档 | [cloudcli.ai/docs](https://cloudcli.ai/docs) |
| CloudCLI Cloud | [cloudcli.ai](https://cloudcli.ai) |
| Discord 社区 | [Discord](https://discord.gg/buxwujPNRE) |
| NPM 包 | [@cloudcli-ai/cloudcli](https://www.npmjs.com/package/@cloudcli-ai/cloudcli) |
| 许可证 | AGPL-3.0-or-later |

快速启动 CloudCLI UI 只需一行命令：

```bash
npx @cloudcli-ai/cloudcli
```

打开 `http://localhost:3001` 即可在浏览器中管理所有 AI 编程 Agent。
