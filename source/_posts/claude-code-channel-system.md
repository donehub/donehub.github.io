---
title: Channel 系统：IM 远程控制 Agent
date: 2026-04-06
tags: Channel
categories: Claude Code
---

> 你在手机上打开 Telegram，给 Claude Code 发一条消息，它就开始在你的电脑上工作——这就是 Channel 系统。它打破了 AI 编程助手只能在终端中交互的限制，实现了真正的远程控制。更精妙的是，它有六层访问控制和权限中继机制，确保安全性。

<!-- more -->

## 导读：打破终端的边界

传统的 AI 编程助手只能在终端中交互。如果你想让它工作，你必须坐在电脑前。

Channel 系统改变了这一切：
- 你在手机上通过 Telegram 发消息
- Claude Code 收到消息，理解意图，执行操作
- 结果回复到你的 Telegram 聊天窗口

**这不是简单的消息转发**——这是一个完整的远程控制系统：
- 六层访问控制确保只有授权的 Channel 能推送消息
- 权限中继让你在手机上也能审批危险操作
- MCP 协议让任何 IM 平台都能集成

---

## 一、Channel 的本质

### 1.1 Channel 就是一个 MCP Server

从技术角度看，一个 Channel 就是一个特殊的 **MCP Server**：

```typescript
// Channel 的能力声明
{
  "experimental": {
    "claude/channel": {}           // 声明 Channel 能力
    "claude/channel/permission": {}  // 声明权限中继能力（可选）
  }
}
```

### 1.2 Channel 的两种形态

```typescript
type ChannelEntry =
  | { kind: 'plugin'; name: string; marketplace: string; dev?: boolean }
  | { kind: 'server'; name: string; dev?: boolean }
```

| 形态 | 说明 | 安全性 |
|------|------|--------|
| **plugin** | 来自 marketplace 的验证插件 | 需要白名单 |
| **server** | 直接指定的 MCP 服务器名称 | 需要 dev 旁路 |

---

## 二、消息流转全链路

### 2.1 入站流程（IM → Agent）

```
┌─────────────────────────────────────────────────────────────┐
│                    入站消息流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Telegram/Feishu/Discord                                    │
│       ↓                                                     │
│  Channel Plugin（MCP Server）                               │
│       ↓                                                     │
│  notifications/claude/channel { content, meta }             │
│       ↓                                                     │
│  useManageMCPConnections → registerNotificationHandler      │
│       ↓                                                     │
│  wrapChannelMessage() → <channel source="..." user="...">  │
│       ↓                                                     │
│  enqueue({ priority: 'next', isMeta: true })                │
│       ↓                                                     │
│  SleepTool 每 ~1s 轮询 hasCommandsInQueue()                │
│       ↓                                                     │
│  Model 看到 <channel> 标签，理解消息来源                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 出站流程（Agent → IM）

```
┌─────────────────────────────────────────────────────────────┐
│                    出站消息流程                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Model 决定使用哪个工具回复                                   │
│       ↓                                                     │
│  callTool() → Channel 的 MCP 工具                           │
│  （reply / react / edit_message / download_attachment）      │
│       ↓                                                     │
│  MCP 协议调用 Channel Server                                │
│       ↓                                                     │
│  Channel Server 发送消息到 IM 平台                           │
│       ↓                                                     │
│  Telegram/Feishu/Discord 用户收到回复                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.3 消息封装格式

```xml
<channel source="plugin:telegram:tg" user="alice" chat_id="123456">
帮我看看 main.ts 有什么问题
</channel>
```

模型看到这个标签后，就知道消息来自 Telegram 的用户 alice，并会使用 Telegram 的 `reply` 工具回复。

---

## 三、六层访问控制

### 3.1 Gate 函数

```typescript
// src/services/mcp/channelNotification.ts
function gateChannelServer(
  serverName: string,
  capabilities: ServerCapabilities | undefined,
  pluginSource: string | undefined,
): ChannelGateResult  // { action: 'register' } | { action: 'skip', kind, reason }
```

### 3.2 六层关卡详解

```
┌─────────────────────────────────────────────────────────────┐
│                    六层访问控制                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Gate 1: 能力声明（Capability）                             │
│    └─ MCP Server 必须声明 claude/channel 能力              │
│                                                             │
│  Gate 2: 运行时开关（Runtime Gate）                         │
│    └─ tengu_harbor Feature Flag 必须开启                   │
│                                                             │
│  Gate 3: OAuth 认证（Auth）                                 │
│    └─ 必须通过 OAuth 认证（API Key 用户被阻止）             │
│                                                             │
│  Gate 4: 组织策略（Policy）                                 │
│    └─ Teams/Enterprise 必须在托管设置中显式启用             │
│                                                             │
│  Gate 5: 会话白名单（Session）                              │
│    └─ 必须在 --channels 参数列表中                         │
│                                                             │
│  Gate 6: Marketplace 验证 + 白名单（Allowlist）             │
│    ├─ 验证插件来源标签与实际安装来源匹配                    │
│    └─ 插件必须在 GrowthBook 审批白名单中                   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 Gate 结果类型

```typescript
type ChannelGateResult =
  | { action: 'register' }           // 通过所有检查
  | { action: 'skip'; kind: string; reason: string }  // 某层拦截

// kind 枚举：capability | disabled | auth | policy | session | marketplace | allowlist
```

---

## 四、权限中继系统

### 4.1 为什么需要权限中继

当 Claude Code 需要执行敏感操作（如运行 Bash 命令），会弹出权限确认对话框。但如果用户通过 Telegram 远程控制 Agent，他看不到本地终端的对话框。

**权限中继**解决了这个问题：将权限提示转发到 IM 平台，让用户在手机上也能审批或拒绝操作。

### 4.2 出站：权限请求

```typescript
// 通知 Schema
const CHANNEL_PERMISSION_REQUEST_METHOD =
  'notifications/claude/channel/permission_request'

type ChannelPermissionRequestParams = {
  request_id: string      // 5 字母标识符（如 "tbxkq"）
  tool_name: string       // 工具名（如 "Bash"）
  description: string     // 人类可读描述
  input_preview: string   // JSON 输入预览，截断到 200 字符
}
```

### 4.3 Short Request ID 设计

5 个字母标识符的设计充满巧思：

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

**设计决策**：
- **纯字母**：手机用户不需要切换键盘模式
- **大小写不敏感**：适配手机自动更正
- **脏话过滤**：防止尴尬场景

### 4.4 入站：权限响应

用户在 IM 中回复格式：`yes tbxkq` 或 `no tbxkq`

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

### 4.5 多源竞争

权限响应来自四个来源，先到先得：

```
┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   本地终端    │   │    Bridge    │   │   Channels   │   │    Hooks     │
│  Local UI    │   │   远程控制    │   │ Telegram etc │   │  Permission  │
└──────┬───────┘   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘
       │                   │                   │                  │
       └───────────────────┴───────────────────┴──────────────────┘
                                    │
                              claim() — 先到先得
                                    │
                              ┌─────┴─────┐
                              │  resolve   │
                              │  allow/deny│
                              └───────────┘
```

---

## 五、安全设计

### 5.1 XML 注入防护

Channel 消息中的元数据会成为 XML 属性。两道防线：

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

### 5.2 Marketplace 验证

`--channels plugin:slack@anthropic` 只是用户的"意图声明"。运行时验证：

```typescript
const actual = pluginSource
  ? parsePluginIdentifier(pluginSource).marketplace
  : undefined
if (actual !== entry.marketplace) {
  return { action: 'skip', kind: 'marketplace', reason: 'Tag mismatch' }
}
```

### 5.3 权限中继的信任边界

**问题**：Claude 会自我审批吗？

**答案**：审批方是通过 Channel 的人类，不是 Claude。但信任边界不是终端——而是白名单。一个被妥协的 Channel Server 可以伪造响应，但：
- 它本来就有无限的对话注入能力
- 权限对话框减缓攻击速度，但不能完全阻止

### 5.4 skipSlashCommands

Channel 消息入队时设置 `skipSlashCommands: true`，确保 IM 用户发送的 `/help` 等文本不会被解释为 Claude Code 的斜杠命令。

---

## 六、插件 Channel 架构

### 6.1 Plugin Manifest 声明

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

### 6.2 作用域命名

插件提供的 MCP Server 会被添加作用域前缀：

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

---

## 七、命令行接口

### 7.1 启动参数

```bash
# 使用已审批的 Channel 插件
claude --channels plugin:telegram@anthropic plugin:feishu@anthropic

# 本地开发模式（旁路白名单）
claude --dangerously-load-development-channels plugin:my-channel@local

# 两者可以同时使用
claude --channels plugin:telegram@anthropic \
       --dangerously-load-development-channels plugin:dev-channel@local
```

### 7.2 特性门控

```typescript
// src/main.tsx
if (feature('KAIROS') || feature('KAIROS_CHANNELS')) {
  program.addOption(new Option('--channels <servers...>', '...').hideHelp())
  program.addOption(new Option('--dangerously-load-development-channels <servers...>', '...').hideHelp())
}
```

`hideHelp()` 表示这些选项不会出现在 `--help` 输出中——Channel 功能目前处于隐藏特性阶段。

---

## 八、关键源文件索引

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

## 九、总结

Channel 系统体现了几个核心设计原则：

1. **安全优先**：六层访问控制确保只有授权 Channel 能推送消息
2. **协议驱动**：Channel 就是 MCP Server，任何语言都可以实现
3. **松耦合**：Channel 失败不会阻断本地工作流
4. **渐进式信任**：从全局开关到白名单，信任级别逐级递增
5. **插件友好**：声明式配置，自动用户配置提示
6. **权限中继**：远程审批危险操作

这个设计让 Claude Code 真正成为一个"无处不在"的 AI 编程助手。

---

**系列文章导航：**
- 上一篇：[Memory 系统：跨会话持久化知识库](/claude-code-memory-system/)
- 下一篇：[Computer Use：桌面控制的九层安全关卡](/claude-code-computer-use/)