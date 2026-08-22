---
title: Agent 应用中 SSE vs WebSocket 实时通信选型分析
date: 2026-01-12
tags: [Agent]
categories: AI
---

## 背景

做 Agent 应用，前后端之间的实时通信协议选择是一个绕不开的工程设计问题。目前主流的技术方案有两种：SSE（Server-Sent Events）和 WebSocket。实际项目中，不少团队一开始选了 WebSocket，运行一段时间后发现连接管理复杂、运维成本高，最终又切回了 SSE。这不是说 WebSocket 不好，而是在 Agent 这个特定场景下，两者的适配度有明显差异。

下面从协议原理、Agent 通信模式、工程实践三个层面做分析，把选型的判断依据讲清楚。

<!-- more -->

## Agent 的通信模式

讨论协议选型之前，需要先理解 Agent 应用的通信模式。协议为场景服务，脱离场景谈选型没有意义。

### 典型的 Agent 交互流程

一次典型的 Agent 对话流程如下：用户发消息到服务端，服务端将请求转发给 LLM 开始推理（可能持续 10 到 60 秒），推理过程中内容逐 token 生成，服务端一边生成一边将 token 推送给前端形成打字机效果，生成完毕后关闭连接，等待用户发下一条消息。

这个流程有几个关键特征：

| 特征 | 说明 |
|------|------|
| **一问一答** | 用户发一条消息，Agent 回一段话，天然轮次制 |
| **服务端慢、客户端快** | LLM 推理可能 10-60 秒，用户只发几个字 |
| **流式输出** | 内容逐 token 生成，需要实时推送给前端 |
| **单向推送为主** | 推理期间客户端只需接收数据，不需要中途发送 |

这些特征直接指向了单向推送的协议方向。

### 通信的不对称性

Agent 交互中，客户端和服务端的通信量是不对称的。客户端发送的内容很短（一条用户消息），服务端返回的内容很长（可能几千个 token），而且是一个一个 token 持续推送过来的。在推理进行的过程中，客户端除了等待和渲染，不需要向服务端发送任何数据。这种"发一次请求，持续接收响应"的模式，是理解后续选型的关键。

## SSE 协议原理

SSE（Server-Sent Events）是一种基于 HTTP 的服务器推送技术。它允许服务端在建立 HTTP 响应后，不立即关闭连接，而是持续向客户端推送数据。

### 协议格式

请求是普通的 HTTP 请求，响应头中通过 `Content-Type: text/event-stream` 标识这是一个 SSE 流：

```txt
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

```

响应体是一个持续的数据流，每条消息以 `data:` 开头，以两个换行符 `\n\n` 结尾：

```txt
data: {"content": "你"}

data: {"content": "好"}

data: {"content": "，"}

data: {"content": "我是"}

data: {"content": "AI"}

data: {"content": "助手"}

data: [DONE]
```

前端逐条接收这些消息，拼接渲染到界面上，形成打字机效果。

### 前端使用方式

浏览器提供了 `EventSource` API：

```javascript
const eventSource = new EventSource('/api/chat/stream?message=你好');

eventSource.onmessage = (event) => {
  if (event.data === '[DONE]') {
    eventSource.close();
    return;
  }
  const data = JSON.parse(event.data);
  appendToChat(data.content);
};

eventSource.onerror = () => {
  // 浏览器会自动尝试重连
};
```

没有握手过程，没有帧解析，没有心跳维护。断线重连和事件 ID 追踪由浏览器内置处理。

### 核心特性

| 特性 | 说明 |
|------|------|
| **单向通信** | 只能服务端向客户端推送 |
| **基于 HTTP** | 跑在标准 HTTP 上，兼容现有基础设施 |
| **自动重连** | 浏览器原生支持 |
| **轻量** | 不需要协议升级和握手 |
| **文本格式** | 只支持 UTF-8 文本，不支持二进制 |

## WebSocket 协议原理

WebSocket 通过 HTTP 握手"升级"出一条全双工通信通道，客户端和服务端可以随时互发消息。

### 协议格式

WebSocket 的连接建立分两步。第一步是 HTTP 升级握手：

```txt
// 客户端发起
GET /chat HTTP/1.1
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==

// 服务端确认
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

握手完成后，HTTP 连接升级为 WebSocket 连接，后续数据通过 WebSocket 帧传输。第二步是全双工通信，双方可以随时互发消息：

```txt
// 客户端可以随时发
→ {"type": "message", "content": "你好"}

// 服务端也可以随时发
← {"type": "message", "content": "你好，有什么可以帮你的？"}

// 双方同时发送，互不阻塞
```

### 前端使用方式

```javascript
const ws = new WebSocket('wss://example.com/chat');

ws.onopen = () => {
  ws.send(JSON.stringify({ message: '你好' }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  appendToChat(data.content);
};

ws.onclose = (event) => {
  // 需要自行实现重连逻辑
  reconnect();
};

ws.onerror = (err) => {
  console.error('WebSocket error:', err);
};
```

相比 SSE，WebSocket 需要自行处理连接生命周期管理、断线重连、心跳保活等逻辑，代码量和维护成本都高出不少。

### 核心特性

| 特性 | 说明 |
|------|------|
| **全双工通信** | 双方可以同时互发消息 |
| **独立协议** | 握手后脱离 HTTP，使用自己的帧格式（RFC 6455） |
| **低开销** | 帧头 2-14 字节，比 HTTP 头部小 |
| **无自动重连** | 断线后需要自行实现 |
| **支持二进制** | 可传输文本和二进制数据 |

## SSE 与 WebSocket 对比

### 协议特性对比

| 对比维度 | SSE | WebSocket |
|----------|-----|-----------|
| **通信方向** | 单向（服务端→客户端） | 全双工 |
| **协议基础** | 标准 HTTP | HTTP 升级后的独立协议 |
| **连接方式** | 普通 HTTP 长连接 | 需要协议升级握手 |
| **自动重连** | 浏览器原生支持 | 需要自行实现 |
| **数据格式** | 纯文本（UTF-8） | 文本 + 二进制 |
| **防火墙穿透** | 极好（走 HTTP 通道） | 一般（可能被代理拦截） |
| **负载均衡** | 普通 HTTP LB 即可 | 需要 sticky session |

### 开发复杂度对比

同一个"流式聊天"功能，两种方案的实现差异比较大。

**SSE 后端（Spring Boot）：**

```java
@GetMapping(value = "/chat/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<ServerSentEvent<String>> stream(@RequestParam String message) {
    return chatService.streamResponse(message)
        .map(content -> ServerSentEvent.<String>builder()
            .data(content)
            .build());
}
```

**SSE 前端：**

```javascript
const es = new EventSource(`/api/chat/stream?message=${msg}`);
es.onmessage = (e) => appendToChat(e.data);
```

**WebSocket 后端（Spring Boot）：**

```java
@ServerEndpoint("/chat")
@Component
public class ChatWebSocket {
    private static final Map<String, Session> sessions = new ConcurrentHashMap<>();

    @OnOpen
    public void onOpen(Session session) {
        sessions.put(session.getId(), session);
    }

    @OnMessage
    public void onMessage(String message, Session session) {
        chatService.streamResponse(message).subscribe(content -> {
            try {
                session.getBasicRemote().sendText(content);
            } catch (IOException e) {
                // 需要自行处理异常
            }
        });
    }

    @OnClose
    public void onClose(Session session) {
        sessions.remove(session.getId());
    }

    @OnError
    public void onError(Session session, Throwable error) {
        sessions.remove(session.getId());
    }
}
```

**WebSocket 前端：**

```javascript
const ws = new WebSocket('wss://example.com/chat');
ws.onopen = () => ws.send(JSON.stringify({ message: msg }));
ws.onmessage = (e) => appendToChat(e.data);
ws.onclose = () => {
    setTimeout(() => reconnect(), 3000);
};
```

SSE 方案中，后端是一个标准的 HTTP 接口，前端使用浏览器内置的 `EventSource`。WebSocket 方案需要管理 Session 生命周期、处理连接状态、实现重连逻辑。代码量差异明显。

### 运维复杂度对比

| 运维维度 | SSE | WebSocket |
|----------|-----|-----------|
| **Nginx 配置** | 几乎不用改 | 需要配置 `Upgrade` 头 |
| **负载均衡** | 普通 HTTP 均衡即可 | 需要 sticky session |
| **CDN 支持** | 原生支持 | 不支持 |
| **监控** | 与 HTTP 接口一致 | 需要专门的监控方案 |
| **水平扩展** | 无状态，直接扩展 | 有状态连接，需要 session 同步 |
| **调试** | DevTools Network 面板直接查看 | 需要专用调试工具 |

SSE 的运维成本基本等同于一个普通 HTTP 接口。WebSocket 则需要维护一套独立的长连接基础设施，包括连接管理、心跳检测、session 同步等环节。

## LLM 场景下 SSE 成为主流的原因

OpenAI、Anthropic、Google、阿里、字节等厂商的大模型 API，在流式输出上全部选择了 SSE。这个选择背后有清晰的技术逻辑。

### LLM 推理是单向数据流

LLM 生成文本是一个自回归（auto-regressive）过程：输入 prompt 经过推理生成第一个 token，拼上这个 token 再推理生成第二个 token，如此循环。每个 token 的生成依赖前面所有 token，整个过程是单向的、顺序的。从通信角度看，这就是一个单向数据流，服务端持续产生数据，客户端持续接收。SSE 的设计目标恰好是服务端向客户端的单向推送。

### 双向通道在推理期间是闲置的

WebSocket 的核心优势是全双工通信。但在 LLM 推理过程中，用户发消息后推理开始，服务端持续推送 token 直到推理结束，客户端在推理期间不需要向服务端发送任何数据，推理结束后才能发送下一条消息。推理可能持续数十秒，这段时间内 WebSocket 的双向通道大部分时间处于半闲置状态。

### SSE 继承了 HTTP 生态的全部基础设施

| 优势 | 来源 |
|------|------|
| 自动重连 | `EventSource` 内置 |
| 穿透防火墙 | 走 HTTP 通道，不需要额外端口 |
| 水平扩展 | 本质是 HTTP 请求，无状态 |
| CDN 加速 | 标准 HTTP 响应 |
| 监控运维 | 复用现有 HTTP 监控体系 |

这些不是 SSE 本身的设计优势，而是因为它就是 HTTP，天然继承了 HTTP 生态 30 年积累的基础设施。

### 主流厂商的协议选择

| 服务商 | 流式输出协议 |
|--------|------------|
| OpenAI (GPT-4o) | SSE |
| Anthropic (Claude) | SSE |
| Google (Gemini) | SSE |
| 阿里 (通义千问) | SSE |
| 字节 (豆包) | SSE |
| Meta (Llama) | SSE |

主流厂商的一致性选择，从工程实践层面验证了 SSE 在 LLM 流式输出场景下的适用性。

## 分层选型建议

SSE 在 LLM 流式输出场景下是最优选择，但 WebSocket 在其他场景中仍然有不可替代的价值。选型的依据是通信模式，不是协议的"先进程度"。

按照交互复杂度，实时通信场景可以分为三层：

| 层级 | 场景类型 | 推荐协议 | 典型应用 |
|------|---------|---------|---------|
| 第一层 | 流式文本输出 | SSE | AI 对话、通知推送、数据流 |
| 第二层 | 双向实时互动 | WebSocket | 多人协作、实时游戏、语音助手 |
| 第三层 | 点对点音视频 | WebRTC | 视频通话、屏幕共享 |

SSE 适用于第一层场景。共同特征是：客户端发请求，服务端持续推送数据，处理期间客户端不需要中途发送数据。代表产品包括 ChatGPT、Claude、通义千问、Copilot。

WebSocket 适用于第二层场景。共同特征是：客户端和服务端需要同时、随时互发消息，多方状态需要实时同步。以多人协作文档为例，A 在打字的同时 B 也在打字，双方都需要实时看到对方的操作，这种场景下双方都在持续发送数据，必须使用 WebSocket。

WebRTC 适用于第三层场景，需要极低延迟的点对点传输，涉及音视频媒体流。这一层与 LLM 应用关系不大。

在复杂的 Agent 应用中，也可以混合使用多种协议。SSE 负责 LLM 推理结果的流式推送（占大部分数据量），WebSocket 负责用户中途取消推理、切换模型、调整参数等控制指令。各取所长，但架构复杂度会上升。

## 实战：SSE 流式对话接口实现

### 后端：Spring Boot + WebFlux

```java
@RestController
@RequestMapping("/api/chat")
public class ChatController {

    @Autowired
    private ChatService chatService;

    @GetMapping(value = "/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
    public Flux<ServerSentEvent<ChatStreamResponse>> stream(
            @RequestParam String message,
            @RequestParam(required = false) String sessionId) {

        return chatService.streamChat(message, sessionId)
            .map(content -> ServerSentEvent.<ChatStreamResponse>builder()
                .event("message")
                .data(new ChatStreamResponse(content))
                .build())
            .concatWith(Flux.just(
                ServerSentEvent.<ChatStreamResponse>builder()
                    .event("done")
                    .data(new ChatStreamResponse("[DONE]"))
                    .build()
            ));
    }
}
```

Nginx 配置，确保不会缓冲 SSE 响应：

```nginx
location /api/chat/stream {
    proxy_pass http://backend;
    proxy_set_header Connection '';
    proxy_http_version 1.1;
    chunked_transfer_encoding off;
    proxy_buffering off;
    proxy_cache off;
}
```

### 前端：fetch + ReadableStream

实际业务中用 `fetch` + `ReadableStream` 比 `EventSource` 更灵活，因为 `EventSource` 只支持 GET 请求，而用户消息可能很长，POST 更合适。

```javascript
class ChatStream {
  constructor() {
    this.abortController = null;
  }

  async sendMessage(message, onChunk, onDone) {
    this.abortController = new AbortController();

    const response = await fetch(`/api/chat/stream?message=${encodeURIComponent(message)}`, {
      signal: this.abortController.signal,
    });

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop();

      for (const line of lines) {
        if (line.startsWith('data:')) {
          const data = line.slice(5).trim();
          if (data === '[DONE]') {
            onDone?.();
            return;
          }
          const parsed = JSON.parse(data);
          onChunk?.(parsed.content);
        }
      }
    }
  }

  cancel() {
    this.abortController?.abort();
  }
}

// 使用示例
const chat = new ChatStream();
chat.sendMessage('介绍一下你自己',
  (chunk) => {
    document.getElementById('chat-box').innerText += chunk;
  },
  () => {
    console.log('生成完毕');
  }
);
```

## 常见问题

浏览器对同一域名的 HTTP 连接数有限制，Chrome 是 6 个。如果同时开多个 SSE 连接，可能占满配额。解决方案是使用 HTTP/2（多路复用，无连接数限制），或合并多个 SSE 流为一个（通过事件类型区分）。另外，`EventSource` API 只支持 GET 请求，使用 `fetch` + `ReadableStream` 解析 SSE 格式数据可以支持 POST，这也是大部分 Agent 应用实际采用的方式。

`EventSource` 会自动重连，但 `fetch` 方案需要自行实现重连逻辑，使用指数退避策略即可。WebSocket 的帧开销确实更小（2-14 字节 vs HTTP chunked 编码），但在 LLM 流式场景下，瓶颈在推理速度（几十毫秒到几秒一个 token），网络传输的开销差异可以忽略。
