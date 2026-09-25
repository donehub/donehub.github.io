---
title: "opcode: A Desktop GUI for Claude Code"
date: 2025-09-11
tags: [GUI (Claude Code)]
categories: AI
lang: en
label: 054_opcode-claude-code-gui-guide
---

opcode is an open-source desktop application built by the Asterisk team, constructed with Tauri 2 + React, providing a full graphical management interface for the Claude Code CLI. It transforms the command-line tool into an intuitive desktop experience, supporting custom Agent creation, session management, cost tracking, and timeline rollback. All data stays local with no cloud dependency.

<!-- more -->

## Technical Architecture

opcode's frontend is built with React 18 + TypeScript + Vite 6. The UI layer uses Tailwind CSS v4 and shadcn/ui, with Zustand 5 for state management. The backend is a Rust-based Tauri 2 layer handling process management, checkpoints, and Tauri command processing. Pre-configured Agent definitions are stored in the cc_agents directory. Data storage uses SQLite (via rusqlite), and the package manager is Bun.

| Layer | Technology |
|-------|-----------|
| Frontend framework | React 18 + TypeScript + Vite 6 |
| UI framework | Tailwind CSS v4 + shadcn/ui + Radix UI |
| State management | Zustand 5 |
| Backend framework | Rust + Tauri 2 |
| Data storage | SQLite (rusqlite) |
| Package management | Bun |

## Project and Session Management

After launch, opcode automatically scans the `~/.claude/projects/` directory and displays all Claude Code projects visually. The project list shows project name, path, and last activity time, with smart search for quick navigation. Click any project to enter its session management view.

Session history is fully preserved under each project. The session overview shows the first message, timestamp, and model info. The metadata area displays Token usage, cost, and status. The session resume feature lets you continue any previous conversation with the full context intact.

## CC Agents: Build Your Own AI Agent

Custom Agents are opcode's core differentiator. Users can create their own AI Agents, configuring system prompts, permissions, and default tasks, packaging specific workflows into reusable Agent templates.

Agent configuration uses JSON format, including fields for name, icon, model, system prompt, and default task. Supported icon types include bot, shield, code, terminal, database, and more. Model options are opus, sonnet, or haiku.

| Parameter | Options | Description |
|-----------|---------|-------------|
| name | Custom string | Agent name |
| icon | bot, shield, code, terminal, database, globe, file-text, git-branch | Icon type |
| model | opus, sonnet, haiku | Claude model to use |
| system_prompt | Custom text | Agent behavioral instructions |
| default_task | Custom text | Default task description |

Agents support both foreground and background execution modes. Foreground execution is blocking — you can watch progress in real time. Background execution runs in a separate process without blocking the main interface. Permissions can be configured for file read/write and network access.

### Built-in Agent Examples

opcode ships with three out-of-the-box Agents covering the most common development scenarios.

Git Commit Bot automates Git commits. It analyzes Git changes, generates Conventional Commits-compliant commit messages, and pushes them. It uses the sonnet model with a default task of "Push all changes." For daily development, replacing manual commit message writing with this Agent delivers a noticeable efficiency boost.

Security Scanner handles pre-launch security audits. It runs STRIDE threat modeling and OWASP Top 10 vulnerability scanning, generating professional security reports. It uses the opus model for stronger reasoning capabilities.

Unit Tests Bot rapidly adds test coverage for new modules. It analyzes code structure and generates unit tests with a coverage target above 80%, also using the opus model.

## Usage Analytics Dashboard

The cost tracking module monitors Claude API usage in real time. Total cost accumulates per session. Model distribution breaks down costs by type. Time trends display usage charts at daily or weekly granularity. Exported data feeds directly into financial analysis or team accounting.

Token analysis provides four key metrics: Input Tokens consumed, Output Tokens consumed, Context Usage utilization, and Cache Hit Rate. Visualized through pie charts and line graphs, it helps identify which sessions have elevated Token costs.

## MCP Server Management

MCP (Model Context Protocol) servers are centrally managed in opcode. The server registry provides unified management of all MCP configurations, supports importing existing configs directly from Claude Desktop, and includes connection testing to verify server availability. Each session can selectively enable different MCP servers — no need for a global uniform configuration.

## Timeline and Checkpoints

The timeline feature gives sessions version control capabilities. You can create checkpoint snapshots at any point in a session, recording the current state. A visual timeline shows the session's evolution path, supporting code diff viewing between any two checkpoints, one-click rollback to any historical state, and spawning new session branches from checkpoints.

The practical value here: when you're about to have an Agent execute a high-risk operation (like a large-scale refactoring), create a checkpoint first. If the result isn't satisfactory, roll back with zero cost.

## CLAUDE.md Editor

A built-in Markdown editor manages project configuration files. Edit on the left, see a live preview on the right, with full syntax highlighting support. opcode automatically discovers all CLAUDE.md files, and changes apply to the current session immediately.

## Installation Guide

### System Requirements

| Item | Requirement |
|------|------------|
| OS | Windows 10/11, macOS 11+, Linux (Ubuntu 20.04+) |
| Memory | Minimum 4GB, recommended 8GB |
| Storage | At least 1GB free space |
| Claude Code | Claude Code CLI must be installed |

### Prerequisites

Install the Rust environment via rustup (macOS/Linux: `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh`; Windows: download rustup-init.exe). Verify after installation with `rustc --version` and `cargo --version`.

Install the Bun runtime on macOS/Linux via `curl -fsSL https://bun.sh/install | bash`, or on Windows via `powershell -c "irm bun.sh/install.ps1 | iex"`. Verify with `bun --version`.

Install Claude Code CLI from claude.ai/code, and make sure the `claude` command is available in your PATH.

Platform-specific dependencies: Linux (Ubuntu/Debian) needs libwebkit2gtk-4.1-dev, libgtk-3-dev, and other system libraries. macOS needs Xcode command-line tools (`xcode-select --install`). Windows needs Microsoft C++ Build Tools and WebView2.

### Build Steps

After cloning the repository, run `bun install` to install frontend dependencies. Start development mode with `bun run tauri dev` (supports hot reload). Production build uses `bun run tauri build`, with output in the `src-tauri/target/release/` directory. Different platforms produce different executable formats.

Debug builds use `bun run tauri build --debug` — faster compilation but larger binaries. On macOS, use `--target universal-apple-darwin` to build a universal binary supporting both Intel and Apple Silicon.

## Usage Flow

After launching, opcode auto-scans the `~/.claude` directory. The welcome screen lets you navigate to CC Agents or Projects.

Project management path: Projects → project list → click a project to view sessions. Each project card shows name, last activity time, and session count. Session resume path: project details → session list → click session → Resume. Context is fully preserved after resuming.

Create a custom Agent path: CC Agents → Create Agent → configure parameters → Save. Configuration takes four steps: fill in basic info (name, icon, model), write the system prompt to define behavioral instructions and output format, configure file read/write and network access permissions, then click Create to save.

| Agent Type | Recommended Model | Prompt Key Points |
|------------|-------------------|-------------------|
| Simple tasks | Haiku | Concise, clear instructions |
| General tasks | Sonnet | Structured step-by-step instructions |
| Complex reasoning | Opus | Detailed context and examples |

Importing pre-built Agents supports two methods: browse the official GitHub repository to import, or import from a local .opcode.json file.

When executing Agent tasks, foreground execution suits short tasks where you want to watch progress. Background execution suits long-running tasks where the Agent runs in a separate process. Execution history records each task's start/end time, task description, execution result, and Token usage.

Timeline features are available at Session → Timeline. After creating checkpoints, you can roll back or view diffs at any time.

MCP Server configuration is managed in Menu → MCP Manager, supporting manual JSON config entry or auto-import from Claude Desktop.

The Usage Analytics Dashboard is at Menu → Usage Dashboard, showing real-time costs, Token distribution pie chart, trend line chart, and CSV/JSON data export.

## Advanced Techniques

### Agent Prompt Templates

A code review Agent's prompt structure has three layers: role defines the reviewer expert identity, task lists review focus areas (code style, potential bugs, performance issues, security vulnerabilities), and output_format specifies table output by file, line number, and issue type with an overall score. This structured prompt approach produces stable, predictable Agent output.

A documentation generation Agent uses the same role-task-output_format three-layer structure. The task section requires analyzing function signatures, generating parameter descriptions, writing usage examples, and adding notes. Output uses Markdown format with function names, parameter tables, return value descriptions, and code examples.

### Process Isolation

opcode's Agents run in independent child processes, isolated from the main Tauri process and the React UI process. This architecture delivers three direct benefits: an Agent crash doesn't affect main interface stability, multiple Agents can run in parallel without interference, and each Agent's resource usage can be monitored and controlled independently.

### Data Storage Locations

| Data Type | Storage Path |
|-----------|-------------|
| Agent configs | ~/.opcode/agents/ |
| Checkpoint data | ~/.opcode/checkpoints/ |
| Usage records | ~/.opcode/analytics.db |
| MCP configs | ~/.claude/mcp_servers.json |

## Troubleshooting

A "cargo not found" error during build typically means Rust environment variables aren't loaded. Run `source ~/.cargo/env` or restart the terminal, then confirm `cargo --version` works.

On Linux, "webkit2gtk not found" requires installing system dependencies: `sudo apt install libwebkit2gtk-4.1-dev`.

On Windows, "MSVC not found" requires installing Visual Studio Build Tools with the C++ build tools workload selected. Restart the terminal after installation.

"claude command not found" means Claude Code CLI isn't installed or isn't in your PATH. Check installation status with `claude --version`. On Windows, you may need to manually add the install path to PATH.

If memory runs out during the build, reduce parallel compilation jobs with `cargo build -j 2`.

## Project Resources

| Resource | Link |
|----------|------|
| GitHub repo | [winfunc/opcode](https://github.com/winfunc/opcode) |
| Discord community | [Join Discord](https://discord.com/invite/KYwhHVzUsY) |
| License | AGPL-3.0 |
