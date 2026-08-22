---
title: Channel 系统：IM 远程控制 Agent
date: 2026-04-06
tags: Channel
categories: Claude Code
---

你在手机上打开 Telegram，给 Claude Code 发一条消息，它就开始在电脑上工作。Channel 系统的本质是打破了 AI 编程助手只能在终端中交互的限制，让任何 IM 平台都能成为远程控制入口。它通过六层访问控制和权限中继机制来保障安全性，同时基于 MCP 协议实现了对多种 IM 平台的兼容。

<!-- more -->

## Channel 的本质是 MCP Server

一个 Channel 在技术上就是一个特殊的 MCP Server，它通过能力声明告诉 Claude Code 自己支持 Channel 功能。

```typescript
// Channel 的能力声明
{
  "experimental": {
    "claude/channel": {}           // 声明 Channel 能力
    "claude/channel/permission": {}  // 声明权限中继能力（可选）
  }
}
```

Channel 有两种形态：一种是来自 marketplace 的验证插件（plugin），需要白名单审批；另一种是直接指定的 MCP 服务器名称（server），需要 dev 模式旁路。

```typescript
type ChannelEntry =
  | { kind: 'plugin'; name: string; marketplace: string; dev?: boolean }
  | { kind: 'server'; name: string; dev?: boolean }
```

| 形态 | 说明 | 安全性 |
|------|------|--------|
| plugin | 来自 marketplace 的验证插件 | 需要白名单 |
| server | 直接指定的 MCP 服务器名称 | 需要 dev 旁路 |

## 消息流转全链路

消息在 Channel 系统中的流转分为入站和出站两个方向。入站流程负责将 IM 平台的消息传递给 Agent，出站流程负责将 Agent 的回复发送回 IM 平台。

### 入站流程

消息从 Telegram、飞书或 Discord 等 IM 平台进入 Channel Plugin（MCP Server），经过 `notifications/claude/channel` 通知机制传递到 `useManageMCPConnections` 注册的通知处理器。消息经过 `wrapChannelMessage()` 封装后，以 `<channel source="..." user="...">` 标签的格式进入消息队列。SleepTool 每秒轮询一次消息队列，模型最终看到带来源信息的 `<channel>` 标签并理解消息内容。

### 出站流程

模型决定使用哪个工具回复后，通过 `callTool()` 调用 Channel 的 MCP 工具（reply、react、edit_message、download_attachment），经由 MCP 协议调用 Channel Server，最终将消息发送回 IM 平台。

### 消息封装格式

```xml
<channel source="plugin:telegram:tg" user="alice" chat_id="123456">
帮我看看 main.ts 有什么问题
</channel>
```

模型看到这个标签后，知道消息来自 Telegram 的用户 alice，会使用 Telegram 的 reply 工具进行回复。

## 六层访问控制

Channel 系统通过一个 Gate 函数来控制哪些 MCP Server 能够注册为 Channel。这个函数检查六个层级，任何一个层级不通过都会返回 skip 结果。

```typescript
// src/services/mcp/channelNotification.ts
function gateChannelServer(
  serverName: string,
  capabilities: ServerCapabilities | undefined,
  pluginSource: string | undefined,
): ChannelGateResult  // { action: 'register' } | { action: 'skip', kind, reason }
```

六个检查层级按顺序执行，每层拦截不同类型的问题：

| 层级 | 检查内容 | 拦截原因 |
|------|----------|----------|
| Gate 1 | 能力声明（Capability） | MCP Server 未声明 claude/channel 能力 |
| Gate 2 | 运行时开关（Runtime Gate） | tengu_harbor Feature Flag 未开启 |
| Gate 3 | OAuth 认证（Auth） | API Key 用户被阻止，必须通过 OAuth |
| Gate 4 | 组织策略（Policy） | Teams/Enterprise 未在托管设置中启用 |
| Gate 5 | 会话白名单（Session） | 不在 --channels 参数列表中 |
| Gate 6 | Marketplace 验证 + 白名单（Allowlist） | 插件来源标签不匹配或未在 GrowthBook 白名单中 |

Gate 结果类型定义如下：

```typescript
type ChannelGateResult =
  | { action: 'register' }           // 通过所有检查
  | { action: 'skip'; kind: string; reason: string }  // 某层拦截

// kind 枚举：capability | disabled | auth | policy | session | marketplace | allowlist
```

这种分层设计的核心思路是渐进式信任：从全局开关到组织策略，再到会话级白名单，信任级别逐级递增。

## 权限中继系统

当 Claude Code 需要执行敏感操作（如运行 Bash 命令），会弹出权限确认对话框。如果用户通过 Telegram 远程控制 Agent，他看不到本地终端的对话框。权限中继将权限提示转发到 IM 平台，让用户在手机上也能审批或拒绝操作。

### 出站：权限请求

权限请求通过 `notifications/claude/channel/permission_request` 通知发送，包含 5 字母的 request_id、工具名、人类可读描述和输入预览（截断到 200 字符）。

```typescript
const CHANNEL_PERMISSION_REQUEST_METHOD =
  'notifications/claude/channel/permission_request'

type ChannelPermissionRequestParams = {
  request_id: string      // 5 字母标识符（如 "tbxkq"）
  tool_name: string       // 工具名（如 "Bash"）
  description: string     // 人类可读描述
  input_preview: string   // JSON 输入预览，截断到 200 字符
}
```

### Short Request ID 设计

5 个字母标识符的设计有几个值得关注的细节。字母表使用 a-z 去掉了 l（避免与 1/I 混淆），纯字母设计让手机用户不需要切换键盘模式，大小写不敏感适配手机自动更正，并且内置了脏话过滤机制。

```typescript
// src/services/mcp/channelPermissions.ts
function shortRequestId(toolUseID: string): string {
  // 25 字母表：a-z 去掉 l（与 1/I 混淆）
  const alphabet = 'abcdefghijkmnopqrstuvwxyz'
  const id = hashToId(toolUseID, alphabet)
  
  // 脏话过滤
  for (const bad of ID_AVOID_SUBSTRINGS) {
    if (id.includes(bad)) {
      return shortRequestId(`${toolUseID}:retry`)  // 重试
    }
  }
  
  return id
}
```

### 入站：权限响应

用户在 IM 中回复格式为 `yes tbxkq` 或 `no tbxkq`，服务端使用正则解析。

```typescript
// 服务端解析正则
const PERMISSION_REPLY_RE = /^\s*(y|yes|n|no)\s+([a-km-z]{5})\s*$/i

// 结构化通知
const ChannelPermissionNotificationSchema = z.object({
  method: z.literal('notifications/claude/channel/permission'),
  params: z.object({
    request_id: z.string(),
    behavior: z.enum(['allow', 'deny']),
  }),
})
```

### 多源竞争

权限响应来自四个来源，通过 claim() 机制先到先得：

| 来源 | 说明 |
|------|------|
| 本地终端（Local UI） | 直接在终端界面审批 |
| Bridge 远程控制 | 通过远程桌面等工具审批 |
| Channels（Telegram 等） | 通过 IM 平台审批 |
| Hooks Permission | 通过外部 Hook 审批 |

四个来源中任何一个先响应，就会锁定该权限请求的结果。

## 安全设计

### XML 注入防护

Channel 消息中的元数据会成为 XML 属性，需要防止注入攻击。防护分两道防线：键名只允许纯标识符格式（正则 `^[a-zA-Z_][a-zA-Z0-9_]*$`），值进行 XML 转义（`&` → `&amp;`，`"` → `&quot;`，`<` → `&lt;`，`>` → `&gt;`）。

```typescript
// 键名过滤：只允许纯标识符格式
const SAFE_META_KEY = /^[a-zA-Z_][a-zA-Z0-9_]*$/

// 值转义
function escapeXmlAttr(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}
```

### Marketplace 验证

`--channels plugin:slack@anthropic` 只是用户的意图声明。运行时验证插件来源标签与实际安装来源是否匹配，不匹配则拦截。

```typescript
const actual = pluginSource
  ? parsePluginIdentifier(pluginSource).marketplace
  : undefined
if (actual !== entry.marketplace) {
  return { action: 'skip', kind: 'marketplace', reason: 'Tag mismatch' }
}
```

### 权限中继的信任边界

审批方是通过 Channel 的人类，不是 Claude 自己。信任边界不在终端，而在白名单。一个被妥协的 Channel Server 可以伪造响应，但它本来就有无限的对话注入能力，权限对话框减缓攻击速度，但不能完全阻止。

### skipSlashCommands

Channel 消息入队时设置 `skipSlashCommands: true`，确保 IM 用户发送的 `/help` 等文本不会被解释为 Claude Code 的斜杠命令。

## 插件 Channel 架构

### Plugin Manifest 声明

插件通过 manifest 文件声明 Channel 能力，包括 MCP 服务器配置和用户配置项。

```json
{
  "name": "telegram",
  "version": "1.0.0",
  "mcpServers": {
    "tg": {
      "command": "node",
      "args": ["./server.js"],
      "env": {
        "BOT_TOKEN": "${user_config.bot_token}",
        "OWNER_ID": "${user_config.owner_id}"
      }
    }
  },
  "channels": [
    {
      "server": "tg",
      "displayName": "Telegram",
      "userConfig": {
        "bot_token": {
          "type": "string",
          "description": "Telegram Bot API Token",
          "required": true,
          "secret": true
        },
        "owner_id": {
          "type": "string",
          "description": "Your Telegram User ID",
          "required": true
        }
      }
    }
  ]
}
```

### 作用域命名

插件提供的 MCP Server 会被添加作用域前缀，避免不同插件之间的命名冲突。

```typescript
// 输入：{ "tg": { ... } } from telegram@anthropic
// 输出：{ "plugin:telegram:tg": { ... } }

function addPluginScopeToServers(servers, pluginName, pluginSource) {
  const scopedServers = {}
  for (const [name, config] of Object.entries(servers)) {
    const scopedName = `plugin:${pluginName}:${name}`
    scopedServers[scopedName] = {
      ...config,
      scope: 'dynamic',
      pluginSource,
    }
  }
  return scopedServers
}
```

## 命令行接口

### 启动参数

```bash
# 使用已审批的 Channel 插件
claude --channels plugin:telegram@anthropic plugin:feishu@anthropic

# 本地开发模式（旁路白名单）
claude --dangerously-load-development-channels plugin:my-channel@local

# 两者可以同时使用
claude --channels plugin:telegram@anthropic \
       --dangerously-load-development-channels plugin:dev-channel@local
```

### 特性门控

Channel 功能目前处于隐藏特性阶段，需要特定 Feature Flag 才能启用。

```typescript
// src/main.tsx
if (feature('KAIROS') || feature('KAIROS_CHANNELS')) {
  program.addOption(new Option('--channels <servers...>', '...').hideHelp())
  program.addOption(new Option('--dangerously-load-development-channels <servers...>', '...').hideHelp())
}
```

`hideHelp()` 使这些选项不会出现在 `--help` 输出中。

## 关键源文件索引

| 文件 | 行数 | 职责 |
|------|------|------|
| `src/services/mcp/channelNotification.ts` | ~320 | 门控、消息封装、白名单集成 |
| `src/services/mcp/channelPermissions.ts` | ~240 | 权限中继、请求 ID 生成 |
| `src/services/mcp/channelAllowlist.ts` | ~80 | GrowthBook 白名单查询 |
| `src/services/mcp/useManageMCPConnections.ts` | - | 连接管理、通知处理器注册 |
| `src/components/messages/UserChannelMessage.tsx` | ~140 | 终端渲染 Channel 消息 |
| `src/components/DevChannelsDialog.tsx` | ~105 | 开发模式确认对话框 |
| `src/utils/plugins/mcpPluginIntegration.ts` | - | 插件 MCP 集成、作用域命名 |
| `src/bootstrap/state.ts` | - | 全局 Channel 白名单状态 |

---

**系列文章导航：**
- 上一篇：[Memory 系统：跨会话持久化知识库](/2026/04/06/081_claude-code-memory-system/)
- 下一篇：[Computer Use：桌面控制的九层安全关卡](/2026/04/06/079_claude-code-computer-use/)
