---
title: SSE vs WebSocket for Agent Applications: A Protocol Selection Analysis
date: 2026-01-12
tags: [Agent]
categories: AI
lang: en
label: 063_agent-sse-vs-websocket
---

## Background

Building an Agent application inevitably raises a protocol design question: which real-time communication protocol should connect your frontend and backend? Two mainstream options exist: SSE (Server-Sent Events) and WebSocket. In practice, many teams start with WebSocket, run it for a while, discover the connection management complexity and operational overhead, and end up switching back to SSE. This doesn't mean WebSocket is bad; the two protocols have distinctly different fitness levels for the Agent use case.

This article analyzes the choice from three angles: protocol mechanics, Agent communication patterns, and engineering practice.

<!-- more -->

## Agent Communication Patterns

Before picking a protocol, you need to understand how Agent applications actually communicate. Protocols serve scenarios; choosing without understanding the scenario is pointless.

### Typical Agent Interaction Flow

A typical Agent conversation works like this: the user sends a message to the server, the server forwards the request to the LLM for inference (which can take 10 to 60 seconds), content generates token by token during inference, the server pushes tokens to the frontend as they arrive to create a typewriter effect, and once generation completes, the connection closes, waiting for the user's next message.

This flow has several defining characteristics:

| Characteristic | Description |
|---------------|-------------|
| **Request-response** | User sends one message, Agent replies with a block of text, naturally turn-based |
| **Slow server, fast client** | LLM inference takes 10-60 seconds, user types a few characters |
| **Streaming output** | Content generates token by token, needs real-time push to frontend |
| **Primarily unidirectional push** | During inference, the client only receives data; no need to send mid-stream |

These characteristics point directly toward a unidirectional push protocol.

### Communication Asymmetry

In Agent interactions, communication between client and server is asymmetric. The client sends short content (one user message); the server returns long content (potentially thousands of tokens), pushed continuously one token at a time. During inference, the client has nothing to send—it just waits and renders. This "send once, receive continuously" pattern is key to understanding the protocol choice.

## How SSE Works

SSE (Server-Sent Events) is an HTTP-based server push technology. It lets the server keep an HTTP response open and continuously push data to the client instead of closing the connection immediately.

### Protocol Format

The request is a standard HTTP request. The response header uses `Content-Type: text/event-stream` to identify this as an SSE stream:

```txt
HTTP/1.1 200 OK
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

```

The response body is a continuous data stream. Each message starts with `data:` and ends with two newline characters `\n\n`:

```txt
data: {"content": "Hello"}

data: {"content": ", "}

data: {"content": "I"}

data: {"content": " am"}

data: {"content": " an"}

data: {"content": " AI"}

data: {"content": " assistant"}

data: [DONE]
```

The frontend receives these messages one by one, concatenates and renders them to create the typewriter effect.

### Frontend Usage

Browsers provide the `EventSource` API:

```javascript
const eventSource = new EventSource('/api/chat/stream?message=hello');

eventSource.onmessage = (event) => {
  if (event.data === '[DONE]') {
    eventSource.close();
    return;
  }
  const data = JSON.parse(event.data);
  appendToChat(data.content);
};

eventSource.onerror = () => {
  // Browser handles reconnection automatically
};
```

No handshake, no frame parsing, no heartbeat maintenance. Reconnection and event ID tracking are built into the browser.

### Core Features

| Feature | Description |
|---------|-------------|
| **Unidirectional** | Server-to-client push only |
| **HTTP-based** | Runs on standard HTTP, compatible with existing infrastructure |
| **Auto-reconnect** | Native browser support |
| **Lightweight** | No protocol upgrade or handshake required |
| **Text format** | UTF-8 text only, no binary support |

## How WebSocket Works

WebSocket "upgrades" an HTTP connection into a full-duplex communication channel where both client and server can send messages at any time.

### Protocol Format

WebSocket connection establishment happens in two steps. First, the HTTP upgrade handshake:

```txt
// Client initiates
GET /chat HTTP/1.1
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==

// Server confirms
HTTP/1.1 101 Switching Protocols
Upgrade: websocket
Connection: Upgrade
Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=
```

After the handshake, the HTTP connection upgrades to a WebSocket connection, and subsequent data transfers via WebSocket frames. The second step is full-duplex communication where both sides can exchange messages freely:

```txt
// Client can send anytime
→ {"type": "message", "content": "Hello"}

// Server can also send anytime
← {"type": "message", "content": "Hello, how can I help?"}

// Both sides send simultaneously, no blocking
```

### Frontend Usage

```javascript
const ws = new WebSocket('wss://example.com/chat');

ws.onopen = () => {
  ws.send(JSON.stringify({ message: 'Hello' }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  appendToChat(data.content);
};

ws.onclose = (event) => {
  // Reconnection logic must be implemented manually
  reconnect();
};

ws.onerror = (err) => {
  console.error('WebSocket error:', err);
};
```

Compared to SSE, WebSocket requires you to handle connection lifecycle management, reconnection, and heartbeat keep-alive yourself, which adds significant code and maintenance overhead.

### Core Features

| Feature | Description |
|---------|-------------|
| **Full-duplex** | Both sides can send messages simultaneously |
| **Independent protocol** | After handshake,脱离 HTTP, uses its own frame format (RFC 6455) |
| **Low overhead** | Frame header is 2-14 bytes, smaller than HTTP headers |
| **No auto-reconnect** | Must be implemented manually after disconnection |
| **Binary support** | Can transmit both text and binary data |

## SSE vs WebSocket Comparison

### Protocol Characteristics

| Dimension | SSE | WebSocket |
|-----------|-----|-----------|
| **Communication direction** | Unidirectional (server → client) | Full-duplex |
| **Protocol basis** | Standard HTTP | Independent protocol after HTTP upgrade |
| **Connection method** | Standard HTTP long connection | Requires protocol upgrade handshake |
| **Auto-reconnect** | Native browser support | Must be implemented manually |
| **Data format** | Text only (UTF-8) | Text + binary |
| **Firewall traversal** | Excellent (uses HTTP channel) | Fair (may be blocked by proxies) |
| **Load balancing** | Standard HTTP LB works | Requires sticky sessions |

### Development Complexity

Implementing the same "streaming chat" feature shows a significant difference between the two approaches.

**SSE Backend (Spring Boot):**

```java
@GetMapping(value = "/chat/stream", produces = MediaType.TEXT_EVENT_STREAM_VALUE)
public Flux<ServerSentEvent<String>> stream(@RequestParam String message) {
    return chatService.streamResponse(message)
        .map(content -> ServerSentEvent.<String>builder()
            .data(content)
            .build());
}
```

**SSE Frontend:**

```javascript
const es = new EventSource(`/api/chat/stream?message=${msg}`);
es.onmessage = (e) => appendToChat(e.data);
```

**WebSocket Backend (Spring Boot):**

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
                // Exception handling required
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

**WebSocket Frontend:**

```javascript
const ws = new WebSocket('wss://example.com/chat');
ws.onopen = () => ws.send(JSON.stringify({ message: msg }));
ws.onmessage = (e) => appendToChat(e.data);
ws.onclose = () => {
    setTimeout(() => reconnect(), 3000);
};
```

With SSE, the backend is a standard HTTP endpoint and the frontend uses the browser's built-in `EventSource`. With WebSocket, you need to manage Session lifecycles, handle connection states, and implement reconnection logic. The code volume difference is obvious.

### Operational Complexity

| Ops Dimension | SSE | WebSocket |
|--------------|-----|-----------|
| **Nginx config** | Almost no changes needed | Requires `Upgrade` header configuration |
| **Load balancing** | Standard HTTP balancing works | Requires sticky sessions |
| **CDN support** | Native support | Not supported |
| **Monitoring** | Same as HTTP endpoints | Requires dedicated monitoring setup |
| **Horizontal scaling** | Stateless, scale directly | Stateful connections, need session sync |
| **Debugging** | View directly in DevTools Network tab | Requires dedicated debugging tools |

SSE's operational cost is essentially equivalent to a standard HTTP endpoint. WebSocket requires maintaining a separate long-connection infrastructure, including connection management, heartbeat detection, and session synchronization.

## Why SSE Became the Standard for LLM Applications

Every major LLM provider—OpenAI, Anthropic, Google, Alibaba, and ByteDance—chose SSE for streaming output. This choice has clear technical reasoning behind it.

### LLM Inference Is a Unidirectional Data Flow

LLM text generation is an auto-regressive process: the input prompt goes through inference to produce the first token, that token gets appended, inference produces the second token, and the cycle continues. Each token depends on all preceding tokens; the process is unidirectional and sequential. From a communication standpoint, this is a unidirectional data flow: the server continuously produces data, the client continuously receives it. SSE's design purpose is exactly server-to-client unidirectional push.

### The Bidirectional Channel Sits Idle During Inference

WebSocket's core advantage is full-duplex communication. But during LLM inference, after the user sends a message and inference begins, the server continuously pushes tokens until inference completes. The client has nothing to send during inference and can only send the next message after inference finishes. Inference can take tens of seconds; during that time, WebSocket's bidirectional channel is mostly half-idle.

### SSE Inherits the Entire HTTP Ecosystem

| Advantage | Source |
|-----------|--------|
| Auto-reconnect | Built into `EventSource` |
| Firewall traversal | Uses HTTP channel, no extra ports needed |
| Horizontal scaling | Essentially HTTP requests, stateless |
| CDN acceleration | Standard HTTP responses |
| Monitoring and ops | Reuses existing HTTP monitoring stack |

These aren't SSE's own design advantages; they exist because SSE IS HTTP, inheriting 30 years of accumulated HTTP infrastructure.

### What the Major Providers Chose

| Provider | Streaming Protocol |
|----------|-------------------|
| OpenAI (GPT-4o) | SSE |
| Anthropic (Claude) | SSE |
| Google (Gemini) | SSE |
| Alibaba (Qwen) | SSE |
| ByteDance (Doubao) | SSE |
| Meta (Llama) | SSE |

The consistency across providers validates SSE's fitness for LLM streaming from an engineering practice standpoint.

## Layered Selection Guide

SSE is the optimal choice for LLM streaming output, but WebSocket retains irreplaceable value in other scenarios. The selection criterion is the communication pattern, not the protocol's perceived sophistication.

Real-time communication scenarios break into three layers by interaction complexity:

| Layer | Scenario Type | Recommended Protocol | Typical Applications |
|-------|--------------|---------------------|---------------------|
| Layer 1 | Streaming text output | SSE | AI chat, notification push, data streams |
| Layer 2 | Bidirectional real-time interaction | WebSocket | Multi-user collaboration, real-time games, voice assistants |
| Layer 3 | Point-to-point audio/video | WebRTC | Video calls, screen sharing |

SSE fits Layer 1 scenarios. The common thread: client sends a request, server continuously pushes data, and the client doesn't need to send data mid-processing. Representative products include ChatGPT, Claude, Qwen, and Copilot.

WebSocket fits Layer 2 scenarios. The common thread: client and server need to exchange messages simultaneously and at any time, with multi-party state requiring real-time synchronization. Take collaborative document editing: while Person A is typing, Person B is also typing, and both need to see each other's operations in real time. Both sides are continuously sending data here; WebSocket is mandatory.

WebRTC fits Layer 3 scenarios requiring ultra-low-latency point-to-point transmission involving audio/video media streams. This layer has little relevance to LLM applications.

Complex Agent applications can also mix protocols. SSE handles LLM inference result streaming (the bulk of data volume), while WebSocket handles control commands like canceling inference mid-stream, switching models, or adjusting parameters. Each protocol plays to its strengths, though architectural complexity increases.

## Implementation: SSE Streaming Chat Endpoint

### Backend: Spring Boot + WebFlux

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

Nginx configuration to ensure SSE responses aren't buffered:

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

### Frontend: fetch + ReadableStream

In real applications, `fetch` + `ReadableStream` offers more flexibility than `EventSource`, because `EventSource` only supports GET requests, and user messages can be long enough that POST is more appropriate.

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

// Usage example
const chat = new ChatStream();
chat.sendMessage('Tell me about yourself',
  (chunk) => {
    document.getElementById('chat-box').innerText += chunk;
  },
  () => {
    console.log('Generation complete');
  }
);
```

## Frequently Asked Questions

Browsers limit HTTP connections per domain; Chrome allows 6. Opening multiple SSE connections simultaneously can exhaust this quota. The fix is using HTTP/2 (multiplexed, no connection limit) or merging multiple SSE streams into one (distinguished by event type). Also, the `EventSource` API only supports GET requests; using `fetch` + `ReadableStream` to parse SSE-format data supports POST, which is what most Agent applications actually use.

`EventSource` reconnects automatically, but the `fetch` approach needs manual reconnection logic; exponential backoff works well. WebSocket frames do have lower overhead (2-14 bytes vs HTTP chunked encoding), but in the LLM streaming scenario, the bottleneck is inference speed (tens of milliseconds to seconds per token), so the network transmission overhead difference is negligible.
