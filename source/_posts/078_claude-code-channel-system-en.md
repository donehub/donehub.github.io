---
title: "The Channel System — Controlling Your Agent from Any IM App"
date: 2026-04-06
tags: Channel
categories: Claude Code
lang: en
label: 078_claude-code-channel-system
---

Open Telegram on your phone, send Claude Code a message, and it starts working on your computer. The Channel system breaks the terminal-only constraint on AI coding assistants. Any IM platform can now control your agent remotely. Security comes from six layers of access control plus a permission relay system, and the MCP protocol handles multi-platform support.

<!-- more -->

## A Channel Is an MCP Server

Technically, a Channel is a specialized MCP Server that declares Channel capability through its capability manifest.

```typescript
// Channel capability declaration
{
  "experimental": {
    "claude/channel": {}           // Declares Channel capability
    "claude/channel/permission": {}  // Declares permission relay capability (optional)
  }
}
```

Channels come in two forms: verified plugins from the marketplace (requiring allowlist approval), or directly specified MCP server names (requiring dev mode bypass).

```typescript
type ChannelEntry =
  | { kind: 'plugin'; name: string; marketplace: string; dev?: boolean }
  | { kind: 'server'; name: string; dev?: boolean }
```

| Form | Description | Security |
|------|-------------|----------|
| plugin | Verified plugin from marketplace | Requires allowlist |
| server | Directly specified MCP server name | Requires dev bypass |

## The Full Message Flow

Messages flow through the Channel system in two directions. Inbound flow carries messages from IM platforms to the agent. Outbound flow sends agent responses back to the IM platform.

### Inbound Flow

A message arrives from Telegram, Feishu, Discord, or another IM platform into the Channel Plugin (an MCP Server). It flows through the `notifications/claude/channel` mechanism to the handler registered by `useManageMCPConnections`. After wrapping via `wrapChannelMessage()`, the message enters the queue as a `<channel source="..." user="...">` tag. SleepTool polls the message queue once per second. The model ultimately sees the `<channel>` tag with source information and understands the message content.

### Outbound Flow

To reply, the model picks a Channel MCP tool (reply, react, edit_message, download_attachment) and calls it via `callTool()`. These calls go through the MCP protocol to the Channel Server, which delivers the message back to the IM platform.

### Message Envelope Format

```xml
<channel source="plugin:telegram:tg" user="alice" chat_id="123456">
Can you check what's wrong with main.ts
</channel>
```

When the model sees this tag, it knows the message came from Telegram user alice and uses Telegram's reply tool to respond.

## Six Layers of Access Control

The Channel system uses a Gate function to control which MCP Servers can register as Channels. This function checks six layers — failure at any layer returns a skip result.

```typescript
// src/services/mcp/channelNotification.ts
function gateChannelServer(
  serverName: string,
  capabilities: ServerCapabilities | undefined,
  pluginSource: string | undefined,
): ChannelGateResult  // { action: 'register' } | { action: 'skip', kind, reason }
```

The six check layers execute in order, each intercepting a different category of issues:

| Layer | Check | Block Reason |
|-------|-------|--------------|
| Gate 1 | Capability declaration | MCP Server hasn't declared claude/channel capability |
| Gate 2 | Runtime switch | tengu_harbor Feature Flag not enabled |
| Gate 3 | OAuth authentication | API Key users blocked — must use OAuth |
| Gate 4 | Organization policy | Teams/Enterprise not enabled in managed settings |
| Gate 5 | Session allowlist | Not in --channels parameter list |
| Gate 6 | Marketplace verification + allowlist | Plugin source tag mismatch or not in GrowthBook allowlist |

The Gate result type is defined as:

```typescript
type ChannelGateResult =
  | { action: 'register' }           // Passed all checks
  | { action: 'skip'; kind: string; reason: string }  // Blocked at some layer

// kind enum: capability | disabled | auth | policy | session | marketplace | allowlist
```

The core idea behind this layered design is progressive trust: from global switches to org policies to session-level allowlists, trust level increases at each step.

## Permission Relay System

When Claude Code needs to execute a sensitive operation (like running a Bash command), it pops up a permission confirmation dialog. If the user is remotely controlling the agent through Telegram, they can't see the local terminal dialog. The permission relay forwards permission prompts to the IM platform, letting users approve or reject operations from their phone.

### Outbound: Permission Requests

Permission requests are sent via `notifications/claude/channel/permission_request` notification, including a 5-letter request_id, tool name, human-readable description, and input preview (truncated to 200 characters).

```typescript
const CHANNEL_PERMISSION_REQUEST_METHOD =
  'notifications/claude/channel/permission_request'

type ChannelPermissionRequestParams = {
  request_id: string      // 5-letter identifier (e.g., "tbxkq")
  tool_name: string       // Tool name (e.g., "Bash")
  description: string     // Human-readable description
  input_preview: string   // JSON input preview, truncated to 200 chars
}
```

### Short Request ID Design

The 5-letter identifier design has several notable details. The alphabet is a–z minus 'l' (to avoid confusion with 1/I). The all-letter design means mobile users don't need to switch keyboard modes. Case insensitivity works with phone auto-correct. And there's a built-in profanity filter.

```typescript
// src/services/mcp/channelPermissions.ts
function shortRequestId(toolUseID: string): string {
  // 25-letter alphabet: a-z minus l (confusable with 1/I)
  const alphabet = 'abcdefghijkmnopqrstuvwxyz'
  const id = hashToId(toolUseID, alphabet)
  
  // Profanity filter
  for (const bad of ID_AVOID_SUBSTRINGS) {
    if (id.includes(bad)) {
      return shortRequestId(`${toolUseID}:retry`)  // Retry
    }
  }
  
  return id
}
```

### Inbound: Permission Responses

Users respond in the IM with `yes tbxkq` or `no tbxkq`, parsed server-side with regex.

```typescript
// Server-side parsing regex
const PERMISSION_REPLY_RE = /^\s*(y|yes|n|no)\s+([a-km-z]{5})\s*$/i

// Structured notification
const ChannelPermissionNotificationSchema = z.object({
  method: z.literal('notifications/claude/channel/permission'),
  params: z.object({
    request_id: z.string(),
    behavior: z.enum(['allow', 'deny']),
  }),
})
```

### Multi-Source Race Condition

Permission responses come from four sources, using a claim() mechanism — first to respond wins:

| Source | Description |
|--------|-------------|
| Local terminal (Local UI) | Direct approval in terminal interface |
| Bridge remote control | Approval via remote desktop tools |
| Channels (Telegram, etc.) | Approval via IM platform |
| Hooks Permission | Approval via external hooks |

Whichever source responds first locks in the result for that permission request.

## Security Design

### XML Injection Prevention

Channel message metadata becomes XML attributes, so injection attacks must be prevented. Defense operates on two fronts: key names only allow pure identifier format (regex `^[a-zA-Z_][a-zA-Z0-9_]*$`), and values get XML-escaped (`&` → `&amp;`, `"` → `&quot;`, `<` → `&lt;`, `>` → `&gt;`).

```typescript
// Key name filter: only allow pure identifier format
const SAFE_META_KEY = /^[a-zA-Z_][a-zA-Z0-9_]*$/

// Value escaping
function escapeXmlAttr(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
}
```

### Marketplace Verification

`--channels plugin:slack@anthropic` is just a user intent declaration. At runtime, the system verifies the plugin source tag matches the actual install source. Mismatch results in blocking.

```typescript
const actual = pluginSource
  ? parsePluginIdentifier(pluginSource).marketplace
  : undefined
if (actual !== entry.marketplace) {
  return { action: 'skip', kind: 'marketplace', reason: 'Tag mismatch' }
}
```

### Permission Relay Trust Boundaries

The approving party is the human on the Channel, not Claude itself. The trust boundary isn't at the terminal — it's at the allowlist. A compromised Channel Server could forge responses, but it already has unlimited dialog injection capability. The permission dialog slows attacks but can't completely prevent them.

### skipSlashCommands

Channel messages are enqueued with `skipSlashCommands: true`, ensuring that text like `/help` sent by IM users won't be interpreted as Claude Code slash commands.

## Plugin Channel Architecture

### Plugin Manifest Declaration

Plugins declare Channel capability through manifest files, including MCP server configuration and user config items.

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

### Scoped Naming

MCP Servers provided by plugins get a scope prefix to avoid naming conflicts between different plugins.

```typescript
// Input: { "tg": { ... } } from telegram@anthropic
// Output: { "plugin:telegram:tg": { ... } }

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

## Command-Line Interface

### Startup Parameters

```bash
# Use approved Channel plugins
claude --channels plugin:telegram@anthropic plugin:feishu@anthropic

# Local development mode (bypass allowlist)
claude --dangerously-load-development-channels plugin:my-channel@local

# Both can be used together
claude --channels plugin:telegram@anthropic \
       --dangerously-load-development-channels plugin:dev-channel@local
```

### Feature Gating

Channel functionality is currently in hidden feature stage, requiring specific Feature Flags to enable.

```typescript
// src/main.tsx
if (feature('KAIROS') || feature('KAIROS_CHANNELS')) {
  program.addOption(new Option('--channels <servers...>', '...').hideHelp())
  program.addOption(new Option('--dangerously-load-development-channels <servers...>', '...').hideHelp())
}
```

`hideHelp()` keeps these options out of `--help` output.

## Key Source File Index

| File | Lines | Responsibility |
|------|-------|----------------|
| `src/services/mcp/channelNotification.ts` | ~320 | Gating, message wrapping, allowlist integration |
| `src/services/mcp/channelPermissions.ts` | ~240 | Permission relay, request ID generation |
| `src/services/mcp/channelAllowlist.ts` | ~80 | GrowthBook allowlist queries |
| `src/services/mcp/useManageMCPConnections.ts` | - | Connection management, notification handler registration |
| `src/components/messages/UserChannelMessage.tsx` | ~140 | Terminal rendering of Channel messages |
| `src/components/DevChannelsDialog.tsx` | ~105 | Dev mode confirmation dialog |
| `src/utils/plugins/mcpPluginIntegration.ts` | - | Plugin MCP integration, scoped naming |
| `src/bootstrap/state.ts` | - | Global Channel allowlist state |

---

**Series Navigation:**
- Previous: [Memory System: Cross-Session Persistent Knowledge Base](/2026/04/06/081_claude-code-memory-system/)
- Next: [Computer Use: Nine Security Gates for Desktop Control](/2026/04/06/079_claude-code-computer-use/)
