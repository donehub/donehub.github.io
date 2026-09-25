---
title: "CloudCLI UI: A Web-Based GUI and Cloud Solution for Claude Code"
date: 2025-09-11
tags: [GUI (Claude Code)]
categories: AI
lang: en
label: 053_cloudcli-ui-guide
---

CloudCLI UI (also known as Claude Code UI) is a Node.js + React web application that provides a unified graphical interface for Claude Code, Cursor CLI, Codex, and Gemini CLI. Unlike desktop apps, it runs in the browser, works on mobile devices, and offers cloud hosting options. The project is open-sourced by the CloudCLI team, built with Express + WebSocket + React, and writes configuration directly to the `~/.claude` directory, staying fully in sync with the CLI.

<!-- more -->

## Project Positioning and Comparison

CloudCLI UI's core features include a unified multi-Agent interface (supporting Claude Code, Cursor CLI, Codex, and Gemini CLI simultaneously), responsive web design (covering desktop, tablet, and mobile browsers), cloud hosting options (self-hosted locally or via CloudCLI Cloud service), and seamless configuration sync (UI settings write directly to `~/.claude`, fully consistent with the CLI).

| Comparison | CloudCLI UI | opcode | Claude Code Remote Control |
|------------|-------------|--------|---------------------------|
| Architecture | Web app | Desktop app | CLI extension |
| Multi-Agent support | Claude/Cursor/Codex/Gemini | Claude only | Claude only |
| Mobile | Responsive web | None | Claude App |
| Deployment | npx/npm/Docker/cloud | Local install | Built-in |
| Cloud execution | Supported (CloudCLI Cloud) | Not supported | Not supported |
| Session discovery | Auto-discovers all sessions | Auto-discovers all sessions | Current session only |
| Config sync | Fully synced with CLI | Fully synced with CLI | Independent config |

## Technical Architecture

The project uses a frontend-backend separation. The frontend is built on React 18 + TypeScript + Vite 7, with Tailwind CSS + Radix UI for the UI layer, CodeMirror 6 (with minimap) for code editing, xterm.js 5 + WebGL rendering for terminal emulation, and react-markdown + remark-gfm + KaTeX for Markdown rendering. The backend runs on Express 4 + WebSocket (ws), using node-pty to create pseudo-terminal processes, SQLite + better-sqlite3 for data storage, and i18next for internationalization.

Directory structure:

```
CloudCLI UI/
├── src/                     # React 18 frontend
│   ├── components/
│   │   ├── chat/            # Chat UI + tool rendering
│   │   ├── code-editor/     # CodeMirror editor
│   │   ├── file-tree/       # File tree component
│   │   ├── git-explorer/    # Git browser
│   │   ├── terminal/        # xterm.js terminal
│   │   ├── settings/        # Settings panel
│   │   └── auth/            # Authentication module
│   └── hooks/               # React Hooks
├── server/                  # Node.js backend
│   ├── index.js             # Express server
│   ├── WebSocket real-time communication
│   ├── REST API
│   ├── SQLite data storage
│   └── node-pty process management
├── shared/                  # Shared modules
│   └── modelConstants.js    # Supported model list
├── docker/                  # Docker deployment
│   ├── claude-code/
│   ├── codex/
│   └── gemini/
└── public/                  # Static assets
```

| Layer | Technology |
|-------|-----------|
| Frontend framework | React 18 + TypeScript + Vite 7 |
| UI framework | Tailwind CSS + Radix UI |
| Code editor | CodeMirror 6 + minimap |
| Terminal emulation | xterm.js 5 + WebGL rendering |
| Markdown rendering | react-markdown + remark-gfm + KaTeX |
| Backend framework | Express 4 + WebSocket (ws) |
| Process management | node-pty (pseudo-terminal) |
| Data storage | SQLite + better-sqlite3 |
| Internationalization | i18next |

## Multi-Agent Support

CloudCLI UI is currently the only unified interface supporting multiple AI Agent CLIs. It integrates Claude Code (Anthropic's official CLI, using @anthropic-ai/claude-agent-sdk), Cursor CLI (Cursor editor's CLI, independently integrated), Codex (OpenAI Codex CLI, using @openai/codex-sdk), and Gemini CLI (Google Gemini CLI, independently integrated). At startup, you select which Agent to use in the CLI Selection screen, then enter the corresponding session.

## Responsive Chat Interface

The chat interface supports multiple message formats: Markdown rendering (headings, lists, tables, code blocks), KaTeX math formulas, multi-language syntax highlighting, and visualized tool calls. Real-time interaction runs over WebSocket, including streaming responses (live Agent output), interactive tools (AskUserQuestion and similar interactive components), and state synchronization (real-time Agent status updates).

Chat component architecture:

```
ChatInterface.tsx
    ├── ChatComposer.tsx         # Input box + file mentions
    ├── ChatMessagesPane.tsx     # Message list (virtual scrolling)
    ├── MessageComponent.tsx     # Single message rendering
    ├── Markdown.tsx             # Markdown parsing
    ├── TokenUsagePie.tsx        # Token usage pie chart
    └── ThinkingModeSelector.tsx # Thinking mode selection
```

## Integrated Shell Terminal

A full terminal based on xterm.js, using node-pty to create real shell processes (pseudo-terminal PTY). Supports ANSI color escape sequences, system clipboard integration (copy/paste), and multi-tab extension via plugins. The rendering layer uses the WebGL addon for GPU acceleration, the Fit addon for automatic resizing, and the WebLinks addon for clickable links.

```
Terminal.tsx
    ├── XTerm component          # Terminal rendering
    ├── WebGL addon              # GPU-accelerated rendering
    ├── Fit addon                # Auto-resize
    ├── WebLinks addon           # Clickable links
    └── Clipboard addon          # Clipboard support
```

## File Browser and Code Editor

The interactive file tree supports three view modes: Tree (hierarchical, expandable directories), List (flat list), and Detailed (full details including size and modification time). File operations include clicking to open files in the CodeMirror editor, drag-and-drop upload to directories, right-click context menu for creating and deleting, and real-time filename filtering.

```
FileTree.tsx
    ├── FileTreeHeader.tsx       # Search + view toggle
    ├── FileTreeBody.tsx         # File list
    ├── FileTreeNode.tsx         # Single file/directory
    ├── FileContextMenu.tsx      # Right-click menu
    └── FileTreeDetailedColumns.tsx # Detailed column view
```

The CodeMirror editor provides a full code editing experience with syntax highlighting for JavaScript, Python, CSS, HTML, JSON, Markdown, and more. It includes a code minimap sidebar, One Dark theme, auto-save, diff view against Git versions, and live Markdown preview.

```
CodeEditor.tsx
    ├── CodeEditorSurface.tsx    # Editor main body
    ├── CodeEditorHeader.tsx     # File path + actions
    ├── CodeEditorFooter.tsx     # Status bar
    ├── EditorSidebar.tsx        # Sidebar outline
    └── MarkdownPreview.tsx      # Markdown preview
```

| Feature | Description |
|---------|------------|
| Syntax highlighting | JavaScript, Python, CSS, HTML, JSON, Markdown, etc. |
| Minimap | Code thumbnail sidebar |
| Theme | One Dark theme |
| Auto-save | Saves automatically after edits |
| Diff view | Shows differences from Git version |
| Markdown preview | Live preview of Markdown files |

## Git Browser

The visual Git interface includes four core components: GitStatus (current state), GitChanges (change list), GitCommit (commit panel), and GitBranch (branch selector). Functionality covers viewing changes (modified, added, deleted files), staging files (click to stage or unstage), committing changes (enter commit message and commit), switching branches (dropdown selector), and diff comparison (detailed file change view).

```
GitExplorer.tsx
    ├── GitStatus.tsx            # Current state
    ├── GitChanges.tsx           # Change list
    ├── GitCommit.tsx            # Commit panel
    └── GitBranch.tsx            # Branch selector
```

## Session Management

On startup, the app automatically scans the `~/.claude/projects/` directory, loads all projects, and displays the session list. Supported session operations include resuming sessions (continuing a previous conversation), creating new sessions, deleting sessions (cleaning up history), and viewing history (browsing the full conversation log).

## MCP Server Management

CloudCLI UI reads and writes `~/.claude/settings.json` directly, enabling bidirectional sync with Claude Code configuration. Add an MCP server in the UI and it's immediately available in Claude Code CLI. Configure MCP in the CLI and the UI picks it up automatically. The configuration entry point is Settings → MCP → Add Server.

MCP configuration example:

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

## Tool Permission Control

All tools are disabled by default and need to be selectively enabled in Settings → Tools Settings. Tools are classified into four risk levels: file operations (Read, Write, Edit — medium risk), system operations (Bash, Task — high risk), network operations (WebFetch, WebSearch — medium risk), and interactive tools (AskUserQuestion — low risk). On first use, it's recommended to enable only basic tools (Read, AskUserQuestion), then gradually enable others as needed. Settings auto-persist after saving.

| Category | Tools | Risk Level |
|----------|-------|-----------|
| File operations | Read, Write, Edit | Medium |
| System operations | Bash, Task | High |
| Network operations | WebFetch, WebSearch | Medium |
| Interactive tools | AskUserQuestion | Low |

## Plugin System

The extensible plugin architecture supports custom tabs and backend services. A plugin structure includes manifest.json (plugin configuration), a frontend directory (React frontend), and an optional backend directory (Node.js backend). Install plugins via Settings → Plugins → Install from Git, entering the repository URL.

```
my-plugin/
├── manifest.json           # Plugin configuration
├── frontend/               # React frontend
│   └── TabComponent.tsx
└── backend/                # Node.js backend (optional)
    └── server.js
```

Plugin manifest configuration example:

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

Currently available plugins include Project Stats (file statistics, line counts; repo: cloudcli-plugin-starter) and Web Terminal (multi-tab terminal; repo: cloudcli-plugin-terminal).

## Installation and Deployment

**Quick start with npx** (no installation needed, requires Node.js v22+):

```bash
npx @cloudcli-ai/cloudcli
```

After startup, visit `http://localhost:3001` to auto-discover all sessions.

**Global install** (for daily use):

```bash
npm install -g @cloudcli-ai/cloudcli
cloudcli
```

**Docker deployment** (for server environments):

```bash
docker build -f docker/claude-code/Dockerfile -t cloudcli-claude .
docker run -p 3001:3001 -v ~/.claude:/root/.claude cloudcli-claude
```

Docker deployment file structure:

```
docker/
├── claude-code/Dockerfile   # Claude Code container
├── codex/Dockerfile         # Codex container
├── gemini/Dockerfile        # Gemini CLI container
└── shared/
    ├── install-cloudcli.sh  # Install script
    └── start-cloudcli.sh    # Startup script
```

**PM2 production deployment** (for long-running instances):

```bash
npm install -g pm2
pm2 start server/index.js --name cloudcli
pm2 status
pm2 startup
pm2 save
```

**Remote server deployment** requires the following steps. First, install dependencies (Ubuntu/Debian):

```bash
sudo apt update
sudo apt install -y nodejs npm git
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt install -y nodejs
```

Then clone and build the project:

```bash
git clone https://github.com/siteboon/claudecodeui.git
cd claudecodeui
npm install
npm run build
```

Create a `.env` file for environment variables:

```env
PORT=3001
HOST=0.0.0.0
AUTH_REQUIRED=true
JWT_SECRET=your-secret-key
```

Start the service and configure the firewall:

```bash
npm run server
sudo ufw allow 3001
```

Visit `http://your-server-ip:3001` to access the app.

**CloudCLI Cloud** offers a managed cloud solution with no local deployment needed, accessible at [cloudcli.ai](https://cloudcli.ai).

| Feature | Description |
|---------|------------|
| No install | Use directly in the browser |
| Cloud execution | Agents run continuously in the cloud |
| Team sharing | Team members can share sessions |
| REST API | API interface available |
| n8n integration | Supports n8n automation nodes |
| Pricing | From $7/month |

## Usage Guide

After starting the service, the terminal shows output (Server running on http://localhost:3001, WebSocket connected, Discovered N projects from ~/.claude). Open `http://localhost:3001` in a browser. On first use, select an Agent (Claude Code / Cursor / Codex / Gemini) in the CLI Selection screen and confirm.

For the interface layout: the top Header contains the Logo, project name, settings entry, and user info. The left Sidebar provides navigation for Chat, Files, Git, Terminal, MCP, etc. The center Main Content area shows the message list (virtual scrolling) and the Chat Composer (input box + attachments + send button). The bottom Footer displays Token usage, current model, and cost statistics. On mobile, the interface automatically adjusts to single-column layout, with the bottom navigation bar retaining Chat, Files, Git, and Terminal entries.

**Chat operations**: Enter a message in the Chat Composer and click Send or press Enter. Type `@` to mention files — their content attaches automatically. Click the Attach button to upload images. Use the Thinking Mode Selector to choose between Default (normal mode), Thinking (extended thinking mode), and Interleaved (alternating thinking mode).

**File operations**: In Sidebar → Files, expand and collapse directories, click files to open. After clicking a file, the CodeMirror editor opens and edits save automatically. Drag files into the Files target directory to upload.

**Git operations**: Sidebar → Git shows current status including Modified (changed but unstaged), Staged (staged for commit), and Untracked (untracked files). In Git → Changes, click files to Stage/Unstage. Enter a commit message and click Commit. Use the Branch dropdown to switch branches.

**Terminal usage**: Sidebar → Terminal shows the xterm.js terminal. Enter commands to execute, view ANSI color output, use Ctrl+Shift+C/V for copy/paste, and scroll to browse history.

**MCP configuration**: Settings → MCP → Add Server, fill in the configuration and save. You can also import from Claude Desktop (Settings → MCP → Import from Claude Desktop).

Configuration example:

```json
{
  "name": "filesystem",
  "command": "npx",
  "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path/to/dir"]
}
```

**Tool permission settings**: Settings → Tools Settings, selectively enable tools and click Apply. Recommended configuration:

| Tool | First Use | Advanced Use |
|------|-----------|-------------|
| Read | ✓ | ✓ |
| Write | - | ✓ |
| Edit | - | ✓ |
| Bash | - | ✓ (with caution) |
| WebFetch | - | ✓ |
| WebSearch | - | ✓ |

**Mobile usage**: After starting the service, open `http://[your-computer-ip]:3001` in your phone browser. The interface automatically adapts to the mobile layout.

## Advanced Configuration

Environment variables are configured through the `.env` file, covering: server settings (PORT=3001, HOST=0.0.0.0), authentication settings (AUTH_REQUIRED=true, JWT_SECRET, JWT_EXPIRY=7d), Agent API keys (CLAUDE_API_KEY, OPENAI_API_KEY, GOOGLE_API_KEY), plugin settings (PLUGINS_DIR=./plugins), and logging settings (LOG_LEVEL=info).

For the authentication system, the first visit opens a Setup Screen to create an admin account. After that, log in through the Login Screen to access Protected Routes. Authentication components include context/AuthContext.tsx (auth state management), view/LoginForm.tsx (login form), view/SetupForm.tsx (setup form), view/ProtectedRoute.tsx (route protection), and utils.ts (auth utility functions).

Internationalization support: the interface supports six languages — English, 中文, 日本語, 한국어, Deutsch, and Русский. It auto-detects the browser language via i18next-browser-languagedetector and also supports manual switching with persistence to localStorage.

Performance optimizations: the message list uses `@tanstack/react-virtual` for virtual scrolling, rendering only visible messages. WebSocket communication uses a message queue buffer to avoid concurrent processing conflicts. Terminal rendering uses the xterm.js WebGL addon for GPU acceleration.

Virtual scrolling code example:

```tsx
// Only render visible messages
const rowVirtualizer = useVirtualizer({
  count: messages.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 100,
});
```

WebSocket message queue example:

```js
// Message queue buffer
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

Terminal rendering configuration:

```js
import { WebglAddon } from '@xterm/addon-webgl';

const terminal = new Terminal();
terminal.loadAddon(new WebglAddon());
```

## Plugin Development Guide

Start by forking the template repository at https://github.com/cloudcli-ai/cloudcli-plugin-starter, then clone it locally:

```bash
git clone https://github.com/your-username/my-plugin.git
cd my-plugin
```

Plugin directory structure:

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

The Manifest configuration needs to specify the plugin name, version, display name, description, icon, entry files, frontend entry, tab definitions, and RPC methods:

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

Frontend components access project path and RPC capabilities through `usePluginContext`:

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

Backend services register RPC methods through `createPluginServer`:

```ts
// backend/server.ts
import { createPluginServer } from '@cloudcli-ai/plugin-sdk';

const server = createPluginServer();

server.registerMethod('getData', async (params) => {
  return { data: 'Hello from backend' };
});

server.registerMethod('processData', async (params) => {
  // Process data
  return { success: true };
});

server.start();
```

Install custom plugins via Settings → Plugins → Install from Git. Enter the repository URL and click Install.

## API Reference

The project provides a complete REST API covering project management, session management, file operations, and Git operations.

**Project API**:

```bash
GET /api/projects           # List projects, returns [{ id, name, path, sessionsCount }]
GET /api/projects/:id       # Get project details, returns { id, name, path, sessions, config }
```

**Session API**:

```bash
POST /api/sessions          # Create session, Body: { projectId, model, task }, returns { sessionId, status }
POST /api/sessions/:id/chat # Send message, Body: { message, attachments }, returns { messageId, status }
GET  /api/sessions/:id      # Get session details, returns { id, messages, model, usage }
```

**File API**:

```bash
GET  /api/files?path=/project  # Get file tree, returns [{ name, type, path, children }]
GET  /api/files/:path          # Get file content, returns { content, encoding, size }
PUT  /api/files/:path          # Update file, Body: { content }, returns { success, size }
```

**Git API**:

```bash
GET  /api/git/status           # Get status, returns { branch, staged, unstaged, untracked }
POST /api/git/commit           # Commit changes, Body: { message, files }, returns { commitId, success }
```

## Comparison with Claude Code Remote Control

The official Claude Code Remote Control has relatively limited capabilities. Here's a detailed comparison:

| Comparison | CloudCLI UI | Claude Code Remote Control |
|------------|-------------|---------------------------|
| Session coverage | Auto-discovers all sessions | Current active session only |
| Config sync | Fully synced (bidirectional) | Independent config |
| Multi-Agent | Supports 4 CLI types | Claude Code only |
| UI features | File tree, Git, terminal | Chat window only |
| Execution mode | Can run in cloud | Local terminal must stay open |
| Timeout limits | No limits | ~10 minute timeout on disconnect |
| Mobile | Responsive web | Claude App |

## Troubleshooting

**npx startup failure**: If `node-pty` compilation fails, install build tools first (Windows: `npm install -g windows-build-tools`; Linux: `sudo apt install build-essential`), then clear cache and reinstall (`npm cache clean --force && npx @cloudcli-ai/cloudcli`).

**WebSocket connection failure**: When the browser can't connect to WebSocket, check the HOST configuration in `.env`. For remote access, set `HOST=0.0.0.0`; for local access, use `HOST=localhost`.

**Mobile can't connect**: If the phone browser can't open the page, first check if the firewall allows port 3001 (`sudo ufw allow 3001`), then confirm the correct IP address via `ip addr show`, and finally visit `http://[correct-ip]:3001` on your phone.

**MCP server not showing**: When an MCP server added in the UI doesn't work in the CLI, check the `~/.claude/settings.json` file contents, ensure the JSON format is correct, then restart CloudCLI.

**Terminal won't accept input**: When the xterm.js terminal can't receive commands, run `npm rebuild node-pty` to rebuild the pseudo-terminal module. On Linux/macOS, also make sure the shell has execution permissions.

## Project Resources

| Resource | Link |
|----------|------|
| GitHub repo | [siteboon/claudecodeui](https://github.com/siteboon/claudecodeui) |
| Official docs | [cloudcli.ai/docs](https://cloudcli.ai/docs) |
| CloudCLI Cloud | [cloudcli.ai](https://cloudcli.ai) |
| Discord community | [Discord](https://discord.gg/buxwujPNRE) |
| NPM package | [@cloudcli-ai/cloudcli](https://www.npmjs.com/package/@cloudcli-ai/cloudcli) |
| License | AGPL-3.0-or-later |

Getting started with CloudCLI UI takes a single command:

```bash
npx @cloudcli-ai/cloudcli
```

Open `http://localhost:3001` to manage all your AI coding agents from the browser.
