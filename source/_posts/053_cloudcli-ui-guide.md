---
title: CloudCLI UI - Claude Code 的 Web GUI 与云端方案
date: 2025-09-11
tags: GUI(Claude Code)
categories: AI
---

> CloudCLI UI（又名 Claude Code UI）是一款基于 Node.js + React 的 Web 应用，为 Claude Code、Cursor CLI、Codex 和 Gemini CLI 提供统一的图形化界面。与桌面应用不同，它可以通过浏览器访问，支持移动端使用，并提供云端托管选项。本文将详细介绍其功能特性、安装配置和使用方法。

<!-- more -->

## 一、项目简介

**CloudCLI UI** 是由 CloudCLI 团队开发的开源项目，采用 Express + WebSocket + React 构建，为多种 AI 编程 CLI 工具提供统一的 Web UI。

### 核心定位

- **多 Agent 统一界面**：同时支持 Claude Code、Cursor CLI、Codex、Gemini CLI
- **响应式 Web 设计**：桌面、平板、手机浏览器全覆盖
- **云端托管选项**：可选择本地自托管或云端服务
- **配置无缝同步**：UI 配置直接写入 `~/.claude`，与 CLI 完全一致

### 与其他工具对比

| 对比项 | CloudCLI UI | opcode | Claude Code Remote Control |
|--------|-------------|--------|---------------------------|
| 架构 | Web 应用 | 桌面应用 | CLI 扩展 |
| 多 Agent 支持 | Claude/Cursor/Codex/Gemini | 仅 Claude | 仅 Claude |
| 移动端 | 响应式 Web | 无 | Claude App |
| 部署方式 | npx/npm/Docker/云托管 | 本地安装 | 内置功能 |
| 云端运行 | 支持（CloudCLI Cloud） | 不支持 | 不支持 |
| 会话发现 | 自动发现全部会话 | 自动发现全部会话 | 仅当前会话 |
| 配置同步 | 与 CLI 完全同步 | 与 CLI 完全同步 | 独立配置 |

### 技术架构

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
│   └── SQLite 数据存储
│   └── node-pty 进程管理
├── shared/                  # 共享模块
│   └── modelConstants.js    # 支持的模型列表
├── docker/                  # Docker 部署
│   ├── claude-code/
│   ├── codex/
│   └── gemini/
└── public/                  # 静态资源
```

**技术栈明细**：

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

---

## 二、核心功能详解

### 1. 多 Agent 支持

CloudCLI UI 是目前唯一支持多种 AI Agent CLI 的统一界面：

| Agent CLI | 说明 | SDK 集成 |
|-----------|------|----------|
| Claude Code | Anthropic 官方 CLI | @anthropic-ai/claude-agent-sdk |
| Cursor CLI | Cursor 编辑器的 CLI | 独立集成 |
| Codex | OpenAI Codex CLI | @openai/codex-sdk |
| Gemini CLI | Google Gemini CLI | 独立集成 |

#### CLI 选择界面

启动时可选择要使用的 Agent：

```
启动 CloudCLI → CLI Selection → 选择 Agent → 开始会话
```

### 2. 响应式聊天界面

#### 消息渲染

支持丰富的消息格式：

- **Markdown 渲染**：标题、列表、表格、代码块
- **数学公式**：KaTeX 渲染数学表达式
- **代码高亮**：多语言语法高亮
- **工具调用展示**：可视化展示 Agent 执行的工具

#### 实时交互

通过 WebSocket 实现实时通信：

- **流式响应**：实时显示 Agent 输出
- **交互式工具**：AskUserQuestion 等交互组件
- **状态同步**：Agent 状态实时更新

#### 聊天组件架构

```
ChatInterface.tsx
    ├── ChatComposer.tsx         # 输入框 + 文件提及
    ├── ChatMessagesPane.tsx     # 消息列表（虚拟滚动）
    ├── MessageComponent.tsx     # 单条消息渲染
    ├── Markdown.tsx             # Markdown 解析
    ├── TokenUsagePie.tsx        # Token 使用饼图
    └── ThinkingModeSelector.tsx # 思考模式选择
```

### 3. 集成 Shell 终端

基于 xterm.js 的完整终端：

```
Terminal.tsx
    ├── XTerm 组件               # 终端渲染
    ├── WebGL addon              # GPU 加速渲染
    ├── Fit addon                # 自动调整大小
    ├── WebLinks addon           # 链接点击
    └── Clipboard addon          # 剪贴板支持
```

**终端功能**：

- **伪终端（PTY）**：通过 node-pty 创建真实 shell 进程
- **多 Tab 支持**：通过插件可扩展多终端
- ** ANSI 颜色**：完整支持 ANSI 转义序列
- **复制粘贴**：系统剪贴板集成

### 4. 文件浏览器

交互式文件树，支持多种视图模式：

```
FileTree.tsx
    ├── FileTreeHeader.tsx       # 搜索 + 视图切换
    ├── FileTreeBody.tsx         # 文件列表
    ├── FileTreeNode.tsx         # 单个文件/目录
    ├── FileContextMenu.tsx      # 右键菜单
    └── FileTreeDetailedColumns.tsx # 详细列视图
```

**视图模式**：

| 模式 | 说明 |
|------|------|
| Tree | 树状结构，可展开目录 |
| List | 平铺列表 |
| Detailed | 详细信息（大小、修改时间） |

**文件操作**：

- **打开编辑**：点击文件在 CodeMirror 编辑器打开
- **上传文件**：拖拽上传到目录
- **新建/删除**：右键菜单操作
- **搜索过滤**：实时搜索文件名

### 5. CodeMirror 代码编辑器

完整的代码编辑体验：

```
CodeEditor.tsx
    ├── CodeEditorSurface.tsx    # 编辑器主体
    ├── CodeEditorHeader.tsx     # 文件路径 + 操作
    ├── CodeEditorFooter.tsx     # 状态栏
    ├── EditorSidebar.tsx        # 侧边栏大纲
    └── MarkdownPreview.tsx      # Markdown 预览
```

**编辑器特性**：

| 功能 | 说明 |
|------|------|
| 语法高亮 | JavaScript、Python、CSS、HTML、JSON、Markdown 等 |
| Minimap | 代码缩略图侧边栏 |
| 主题 | One Dark 主题 |
| 自动保存 | 编辑后自动保存 |
| Diff 视图 | 显示与 Git 版本的差异 |
| Markdown 预览 | 实时预览 Markdown 文件 |

### 6. Git 浏览器

可视化 Git 操作：

```
GitExplorer.tsx
    ├── GitStatus.tsx            # 当前状态
    ├── GitChanges.tsx           # 变更列表
    ├── GitCommit.tsx            # 提交面板
    └── GitBranch.tsx            # 分支选择
```

**Git 功能**：

- **查看变更**：显示 modified、added、deleted 文件
- **暂存文件**：点击暂存或取消暂存
- **提交更改**：输入 commit message 并提交
- **分支切换**：下拉选择切换分支
- **Diff 对比**：查看文件变更详情

### 7. 会话管理

自动发现并管理所有会话：

#### 会话发现机制

```
启动 → 扫描 ~/.claude/projects/ → 加载所有项目 → 显示会话列表
```

#### 会话操作

| 操作 | 说明 |
|------|------|
| 恢复会话 | 继续之前的对话 |
| 新建会话 | 创建新的对话 |
| 删除会话 | 清理历史会话 |
| 查看历史 | 查看完整对话记录 |

### 8. MCP Server 管理

与 Claude Code 配置完全同步：

```
Settings → MCP → Add Server
```

#### 配置同步原理

CloudCLI UI 直接读写 `~/.claude/settings.json`：

- **UI 修改 → CLI 生效**：在 UI 中添加 MCP 服务器，立即在 Claude Code CLI 中可用
- **CLI 修改 → UI 生效**：在 CLI 中配置 MCP，UI 自动读取显示

#### MCP 配置格式

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

### 9. 工具权限控制

安全优先设计——所有工具默认禁用：

```
Settings → Tools Settings → 选择性启用
```

#### 工具分类

| 类别 | 工具 | 风险等级 |
|------|------|----------|
| 文件操作 | Read、Write、Edit | 中等 |
| 系统操作 | Bash、Task | 高 |
| 网络操作 | WebFetch、WebSearch | 中等 |
| 交互工具 | AskUserQuestion | 低 |

#### 推荐做法

```
首次使用 → 启用基础工具（Read、AskUserQuestion）
需要时 → 逐步启用其他工具
保存设置 → 自动持久化
```

### 10. 插件系统

可扩展的插件架构：

#### 插件结构

```
my-plugin/
├── manifest.json           # 插件配置
├── frontend/               # React 前端
│   └── TabComponent.tsx
└── backend/                # Node.js 后端（可选）
│   └ server.js
```

#### 插件 Manifest

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

#### 安装插件

```
Settings → Plugins → Install from Git → 输入仓库 URL
```

#### 可用插件

| 插件 | 功能 | 仓库 |
|------|------|------|
| Project Stats | 文件统计、代码行数 | [cloudcli-plugin-starter](https://github.com/cloudcli-ai/cloudcli-plugin-starter) |
| Web Terminal | 多 Tab 终端 | [cloudcli-plugin-terminal](https://github.com/cloudcli-ai/cloudcli-plugin-terminal) |

### 11. REST API

提供完整的 API 接口：

```
GET  /api/projects           # 获取项目列表
GET  /api/projects/:id       # 获取项目详情
POST /api/sessions           # 创建新会话
GET  /api/sessions/:id       # 获取会话详情
POST /api/sessions/:id/chat  # 发送消息
GET  /api/files              # 获取文件树
GET  /api/files/:path        # 获取文件内容
PUT  /api/files/:path        # 更新文件内容
GET  /api/git/status         # 获取 Git 状态
POST /api/git/commit         # 提交更改
```

---

## 三、安装与部署

### 快速启动（npx）

最快的方式，无需安装：

```bash
# 需要 Node.js v22+
npx @cloudcli-ai/cloudcli
```

启动后访问 `http://localhost:3001`，自动发现所有会话。

### 全局安装

适合日常使用：

```bash
npm install -g @cloudcli-ai/cloudcli

# 启动
cloudcli
```

### Docker 部署

适合服务器部署：

```bash
# 构建 Claude Code 容器
docker build -f docker/claude-code/Dockerfile -t cloudcli-claude .

# 运行
docker run -p 3001:3001 -v ~/.claude:/root/.claude cloudcli-claude
```

#### Dockerfile 结构

```
docker/
├── claude-code/Dockerfile   # Claude Code 容器
├── codex/Dockerfile         # Codex 容器
├── gemini/Dockerfile        # Gemini CLI 容器
└── shared/
    ├── install-cloudcli.sh  # 安装脚本
    └── start-cloudcli.sh    # 启动脚本
```

### PM2 生产部署

适合长期运行：

```bash
# 安装 PM2
npm install -g pm2

# 启动
pm2 start server/index.js --name cloudcli

# 查看状态
pm2 status

# 设置开机启动
pm2 startup
pm2 save
```

### 远程服务器部署

#### 1. 安装依赖

```bash
# Ubuntu/Debian
sudo apt update
sudo apt install -y nodejs npm git

# 安装 Node.js v22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

#### 2. 克隆并构建

```bash
git clone https://github.com/siteboon/claudecodeui.git
cd claudecodeui
npm install
npm run build
```

#### 3. 配置环境变量

创建 `.env` 文件：

```env
PORT=3001
HOST=0.0.0.0
AUTH_REQUIRED=true
JWT_SECRET=your-secret-key
```

#### 4. 启动服务

```bash
npm run server
```

#### 5. 配置防火墙

```bash
sudo ufw allow 3001
```

访问 `http://your-server-ip:3001`

### CloudCLI Cloud（托管服务）

无需本地部署的云端方案：

**访问地址**：[cloudcli.ai](https://cloudcli.ai)

**特点**：

| 特性 | 说明 |
|------|------|
| 无需安装 | 直接在浏览器使用 |
| 云端运行 | Agent 在云端持续运行 |
| 团队共享 | 团队成员可共享会话 |
| REST API | 提供完整 API |
| n8n 集成 | 支持 n8n 自动化节点 |
| 费用 | $7/月起 |

---

## 四、使用指南

### 初次启动

```bash
npx @cloudcli-ai/cloudcli
```

终端输出：

```
CloudCLI UI starting...
Server running on http://localhost:3001
WebSocket connected
Discovered 5 projects from ~/.claude
```

浏览器访问 `http://localhost:3001`

### 选择 Agent CLI

首次使用需选择要使用的 Agent：

```
CLI Selection → 选择 Claude Code / Cursor / Codex / Gemini → Confirm
```

### 界面布局

```
┌─────────────────────────────────────────────────────────────┐
│ Header: Logo | Project Name | Settings | User               │
├──────────┬──────────────────────────────────────────────────┤
│ Sidebar  │ Main Content                                     │
│          │                                                   │
│ • Chat   │ ┌─────────────────────────────────────────────┐  │
│ • Files  │ │ Message List                                │  │
│ • Git    │ │ (Virtual Scroll)                            │  │
│ • Term   │ │                                             │  │
│ • MCP    │ └─────────────────────────────────────────────┘  │
│          │ ┌─────────────────────────────────────────────┐  │
│          │ │ Chat Composer                               │  │
│          │ │ [Input] [Attach] [Send]                     │  │
│          │ └─────────────────────────────────────────────┘  │
├──────────┴──────────────────────────────────────────────────┤
│ Footer: Token Usage | Model | Cost                          │
└─────────────────────────────────────────────────────────────┘
```

### 聊天操作

#### 发送消息

```
Chat Composer → 输入消息 → 点击 Send 或按 Enter
```

#### 提及文件

```
Chat Composer → 输入 @ → 选择文件 → 文件内容自动附加
```

#### 上传图片

```
Chat Composer → 点击 Attach → 选择图片 → 图片预览显示
```

#### 选择思考模式

```
Thinking Mode Selector → 选择模式
  • Default: 正常模式
  • Thinking: 扩展思考模式
  • Interleaved: 交替思考模式
```

### 文件操作

#### 浏览文件树

```
Sidebar → Files → 展开/折叠目录 → 点击文件打开
```

#### 编辑文件

```
点击文件 → CodeMirror 编辑器打开 → 编辑内容 → 自动保存
```

#### 上传文件

```
Files → 目标目录 → 拖拽文件 → 上传完成
```

### Git 操作

#### 查看状态

```
Sidebar → Git → 显示当前状态
```

状态显示：

- **Modified**：已修改未暂存
- **Staged**：已暂存待提交
- **Untracked**：未跟踪文件

#### 暂存更改

```
Git → Changes → 点击文件 → Stage/Unstage
```

#### 提交更改

```
Git → 输入 commit message → Commit
```

#### 切换分支

```
Git → Branch dropdown → 选择分支 → Confirm
```

### 终端使用

```
Sidebar → Terminal → 显示 xterm.js 终端
```

**终端操作**：

- 输入命令并执行
- 查看命令输出（ANSI 颜色）
- 复制粘贴（Ctrl+Shift+C/V）
- 滚动查看历史输出

### MCP 配置

#### 添加服务器

```
Settings → MCP → Add Server → 填写配置 → Save
```

配置示例：

```json
{
  "name": "filesystem",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
}
```

#### 从 Claude Desktop 导入

```
Settings → MCP → Import from Claude Desktop
```

### 工具权限设置

```
Settings → Tools Settings → 选择性启用工具 → Apply
```

**推荐配置**：

| 工具 | 首次启用 | 高级使用 |
|------|----------|----------|
| Read | ✓ | ✓ |
| Write | - | ✓ |
| Edit | - | ✓ |
| Bash | - | ✓（谨慎） |
| WebFetch | - | ✓ |
| WebSearch | - | ✓ |

### 移动端使用

#### 本地网络访问

```bash
# 启动服务
npx @cloudcli-ai/cloudcli

# 手机浏览器访问
http://[你的电脑IP]:3001
```

#### 响应式适配

移动端界面：

```
┌─────────────────────┐
│ Header: [Menu] Logo │
├─────────────────────┤
│                     │
│ Message List        │
│ (单列显示)          │
│                     │
├─────────────────────┤
│ Chat Composer       │
├─────────────────────┤
│ Bottom Nav:         │
│ Chat Files Git Term │
└─────────────────────┘
```

---

## 五、进阶配置

### 环境变量

创建 `.env` 文件进行配置：

```env
# 服务器配置
PORT=3001
HOST=0.0.0.0

# 认证配置
AUTH_REQUIRED=true
JWT_SECRET=your-jwt-secret-key
JWT_EXPIRY=7d

# Claude 配置
CLAUDE_API_KEY=your-api-key

# Codex 配置
OPENAI_API_KEY=your-openai-key

# Gemini 配置
GOOGLE_API_KEY=your-google-key

# 插件配置
PLUGINS_DIR=./plugins

# 日志配置
LOG_LEVEL=info
```

### 认证系统

CloudCLI UI 内置认证模块：

#### 首次设置

```
访问应用 → Setup Screen → 创建管理员账号 → 登录
```

#### 认证流程

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Setup      │ →   │  Login      │ →   │  Protected  │
│  Screen     │     │  Screen     │     │  Routes     │
└─────────────┘     └─────────────┘     └─────────────┘
     首次              已有账号           正常使用
```

#### 认证组件

```
auth/
├── context/AuthContext.tsx    # 认证状态管理
├── view/LoginForm.tsx         # 登录表单
├── view/SetupForm.tsx         # 设置表单
├── view/ProtectedRoute.tsx    # 路由保护
└── utils.ts                   # 认证工具函数
```

### 国际化支持

支持多语言界面：

```
i18next + react-i18next
├── en: English
├── zh-CN: 中文
├── ja: 日本語
├── ko: 한국어
├── de: Deutsch
└── ru: Русский
```

语言自动检测：

```
i18next-browser-languagedetector
→ 浏览器语言 → localStorage → navigator.language
```

### 性能优化

#### 虚拟滚动

消息列表使用 `@tanstack/react-virtual`：

```tsx
// 仅渲染可见消息
const rowVirtualizer = useVirtualizer({
  count: messages.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 100,
});
```

#### WebSocket 优化

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

#### 终端渲染

xterm.js WebGL addon：

```js
import { WebglAddon } from '@xterm/addon-webgl';

const terminal = new Terminal();
terminal.loadAddon(new WebglAddon());
```

---

## 六、插件开发指南

### 创建插件

#### 1. Fork 模板

```bash
# Fork https://github.com/cloudcli-ai/cloudcli-plugin-starter
git clone https://github.com/your-username/my-plugin.git
cd my-plugin
```

#### 2. 插件结构

```
my-plugin/
├── manifest.json
├── frontend/
│   ├── index.tsx
│   └── TabComponent.tsx
├── backend/
│   └ server.ts
└── package.json
```

#### 3. Manifest 配置

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

#### 4. 前端组件

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

#### 5. 后端服务

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

### 安装自定义插件

```
Settings → Plugins → Install from Git → 输入仓库 URL → Install
```

---

## 七、API 接口详解

### 项目 API

```bash
# 获取项目列表
GET /api/projects
Response: [{ id, name, path, sessionsCount }]

# 获取项目详情
GET /api/projects/:id
Response: { id, name, path, sessions, config }
```

### 会话 API

```bash
# 创建会话
POST /api/sessions
Body: { projectId, model, task }
Response: { sessionId, status }

# 发送消息
POST /api/sessions/:id/chat
Body: { message, attachments }
Response: { messageId, status }

# 获取会话详情
GET /api/sessions/:id
Response: { id, messages, model, usage }
```

### 文件 API

```bash
# 获取文件树
GET /api/files?path=/project
Response: [{ name, type, path, children }]

# 获取文件内容
GET /api/files/:path
Response: { content, encoding, size }

# 更新文件
PUT /api/files/:path
Body: { content }
Response: { success, size }
```

### Git API

```bash
# 获取状态
GET /api/git/status
Response: { branch, staged, unstaged, untracked }

# 提交更改
POST /api/git/commit
Body: { message, files }
Response: { commitId, success }
```

---

## 八、常见问题

### 1. npx 启动失败

**问题**：`node-pty` 编译失败

**解决方案**：

```bash
# 安装编译工具
# Windows: npm install -g windows-build-tools
# Linux: sudo apt install build-essential

# 清除缓存重新安装
npm cache clean --force
npx @cloudcli-ai/cloudcli
```

### 2. WebSocket 连接失败

**问题**：浏览器无法连接 WebSocket

**解决方案**：

```env
# 确保 HOST 配置正确
HOST=0.0.0.0  # 远程访问
HOST=localhost  # 本地访问
```

### 3. 移动端无法访问

**问题**：手机浏览器无法打开

**解决方案**：

```bash
# 检查防火墙
sudo ufw allow 3001

# 确认 IP 地址
ip addr show

# 手机访问
http://[正确的IP]:3001
```

### 4. MCP 服务器不显示

**问题**：UI 中添加的 MCP 在 CLI 中不生效

**解决方案**：

```bash
# 检查配置文件
cat ~/.claude/settings.json

# 确保 JSON 格式正确
# 重启 CloudCLI
```

### 5. 终端无法输入

**问题**：xterm.js 终端无法输入命令

**解决方案**：

```bash
# 确保 node-pty 正常安装
npm rebuild node-pty

# 检查终端权限
# Linux/macOS: 确保 shell 有执行权限
```

---

## 九、与 Claude Code Remote Control 的区别

官方的 Claude Code Remote Control 功能有限：

| 对比项 | CloudCLI UI | Claude Code Remote Control |
|--------|-------------|---------------------------|
| 会话覆盖 | 全部会话自动发现 | 仅当前活动会话 |
| 配置同步 | 完全同步（双向） | 独立配置 |
| 多 Agent | 支持 4 种 CLI | 仅 Claude Code |
| UI 功能 | 文件树、Git、终端 | 仅聊天窗口 |
| 运行方式 | 可云端运行 | 本地终端必须开启 |
| 超时限制 | 无限制 | 断网约 10 分钟超时 |
| 移动端 | 响应式 Web | Claude App |

---

## 十、项目资源

| 资源 | 链接 |
|------|------|
| GitHub 仓库 | [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) |
| 官方文档 | [cloudcli.ai/docs](https://cloudcli.ai/docs) |
| CloudCLI Cloud | [cloudcli.ai](https://cloudcli.ai) |
| Discord 社区 | [Discord](https://discord.gg/buxwujPNRE) |
| NPM 包 | [@cloudcli-ai/cloudcli](https://www.npmjs.com/package/@cloudcli-ai/cloudcli) |
| 许可证 | AGPL-3.0-or-later |

---

## 十一、总结

CloudCLI UI 的核心优势：

| 优势 | 说明 |
|------|------|
| 多 Agent 支持 | 统一管理 Claude、Cursor、Codex、Gemini |
| 移动端友好 | 响应式设计，手机浏览器直接访问 |
| 云端可选 | CloudCLI Cloud 提供 24/7 云端运行 |
| 配置同步 | 与 CLI 完全同步，无需额外配置 |
| 插件扩展 | 自定义 Tab + 后端服务 |
| REST API | 完整 API 供外部集成 |

### 选择建议

| 场景 | 推荐方案 |
|------|----------|
| 本地开发 + Claude Code | opcode 或 CloudCLI UI 自托管 |
| 移动端使用 Agent | CloudCLI UI 自托管或 CloudCLI Cloud |
| 多种 AI Agent 统一管理 | CloudCLI UI |
| 团队协作 + 云端运行 | CloudCLI Cloud |
| 定制自动化 Agent | opcode |
| 外部系统集成（n8n 等） | CloudCLI Cloud |

一行命令启动 CloudCLI UI：

```bash
npx @cloudcli-ai/cloudcli
```

然后打开 `http://localhost:3001`，即可在浏览器中管理所有 AI 编程 Agent。