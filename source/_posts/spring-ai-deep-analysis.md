---
title: Spring AI 学习有使用
date: 2026-01-05
tags: Spring AI
categories: AI
---

## 背景

2023 年 ChatGPT 火了，2024 年 Agent 热了，2025 年 AI 应用全面开花。Java 开发者的 AI 工具箱已经非常成熟——**Spring AI 1.0 GA 在 2025 年 5 月正式发布**，经过近一年的迭代，已经成为企业级 Java AI 应用的事实标准。

这篇文章站在当下时间点，从**产生背景**到**架构演进**，从**与 LangChain4J 的深度对比**到**实战代码**，让你看完就能上手做 AI 应用。不讲虚的，全是干货。

---

## 一、Spring AI 是什么，为什么需要它

### 1. Java 开发者的 AI 困境（2023-2024）

AI 大模型爆发初期，Java 开发者面临两难选择：

| 方案 | 问题 |
|------|------|
| **直接调用 API** | 每个服务商 API 不同，切换成本高；缺乏高级抽象（RAG、对话记忆、Agent 等） |
| **用 Python 框架** | LangChain、LlamaIndex 都是 Python 原生，Java 项目得跨语言集成，架构不统一 |

更关键的是：**企业级 Java 应用 80% 以上跑在 Spring 上**，需要一个原生融入 Spring 生态的 AI 框架。

### 2. Spring AI 的诞生与演进

Spring AI 的版本演进时间线：

| 时间节点 | 版本 | 里程碑意义 |
|----------|------|------------|
| **2023 年 11 月** | 0.8.0 | 项目启动，首个 Milestone |
| **2024 年全年** | 0.8.x - 0.9.x | 快速迭代，积累社区反馈 |
| **2025 年 5 月** | **1.0.0 GA** | Spring I/O 2025 正式发布，生产就绪 |
| **2025 年下半年** | 1.0.x - 1.1.x | 稳定迭代，修复问题，增加 MCP 支持 |
| **2026 年初** | 1.1.x / 1.2 | Agent 能力增强，国产模型支持完善 |

**1.0 GA 版本的核心里程碑**：

- **API 稳定**：ChatClient、Advisor、VectorStore 等核心接口不再变化
- **生产就绪**：Observability、错误处理、配置管理达到企业级标准
- **生态完善**：官方支持 20+ 模型服务商，10+ 向量数据库
- **文档成熟**：官方文档完善，示例丰富，社区活跃

### 3. 当前定位

站在今天，Spring AI 已经是：

> **Java 企业级 AI 应用的标准框架，Spring 生态的 AI 基础设施。**

一句话概括：**Spring AI 是 Java 界的 LangChain，但它比 LangChain 更懂企业级应用。**

### 4. 核心价值矩阵

| 价值点 | 说明 | 企业收益 |
|------|------|----------|
| **统一 API 抽象** | OpenAI、Azure、Anthropic、Ollama、国产模型……一个接口搞定 | 模型切换零代码改动，供应商议价能力提升 |
| **Spring 原生集成** | 自动配置、依赖注入、Observability、配置中心 | Spring 开发者零学习成本，复用现有基础设施 |
| **企业级特性** | Token 消耗监控、调用链追踪、熔断降级、安全审计 | 生产环境直接部署，运维体系一体化 |
| **高级 AI 抽象** | RAG、Agent、MCP、Function Calling、对话记忆 | 不用自己造轮子，专注业务逻辑 |
| **国产模型支持** | 阿里通义、百度文心、讯飞星火、腾讯混元 | 数据合规、成本可控、中文效果优化 |

---

## 二、架构设计：三层抽象 + MCP 协议层

Spring AI 1.0 的架构已经稳定，可以概括为四层：

```
┌─────────────────────────────────────────────────────────────┐
│                    应用层 (Application)                      │
│         ChatClient / PromptTemplate / Advisor / Agent        │
├─────────────────────────────────────────────────────────────┤
│                    MCP 协议层 (Protocol)                     │
│           MCP Client / MCP Server / Tool Registry           │
├─────────────────────────────────────────────────────────────┤
│                    核心抽象层 (Core Abstractions)            │
│    ChatModel / EmbeddingModel / ImageModel / AudioModel     │
├─────────────────────────────────────────────────────────────┤
│                    集成层 (Integrations)                     │
│   OpenAI / Azure / Anthropic / Ollama / Alibaba / VectorDB │
└─────────────────────────────────────────────────────────────┘
```

### 1. 核心抽象层：统一接口设计

Spring AI 定义了一套稳定的模型接口，不管底层用哪个服务商，API 都一样。

**ChatModel——对话模型**

```java
// 核心接口定义（1.0 GA 后已稳定）
public interface ChatModel extends Model<Prompt, ChatResponse> {
    ChatResponse call(Prompt prompt);
}

// 使用示例：服务商切换只需改配置，代码不动
@Autowired
private ChatModel chatModel;  // 配置决定具体实现（OpenAI、Azure、Ollama...）

public String chat(String userMessage) {
    Prompt prompt = new Prompt(userMessage);
    ChatResponse response = chatModel.call(prompt);
    return response.getResult().getOutput().getContent();
}
```

**EmbeddingModel——向量嵌入模型**

```java
public interface EmbeddingModel extends Model<EmbeddingRequest, EmbeddingResponse> {
    EmbeddingResponse embed(EmbeddingRequest request);
    
    // 1.0 新增：批量嵌入
    List<float[]> embed(List<String> texts);
}

// 使用示例
@Autowired
private EmbeddingModel embeddingModel;

public float[] embed(String text) {
    return embeddingModel.embed(text);
}
```

**ImageModel——图像生成模型**

```java
public interface ImageModel extends Model<ImagePrompt, ImageResponse> {
    ImageResponse call(ImagePrompt prompt);
}

// 支持 DALL-E 3、Stability AI、Midjourney API
@Autowired
private ImageModel imageModel;

public String generateImage(String promptText) {
    ImagePrompt prompt = new ImagePrompt(promptText, 
        ImageOptions.builder()
            .width(1024)
            .height(1024)
            .style("vivid")
            .build());
    return imageModel.call(prompt).getResult().getOutput().getUrl();
}
```

### 2. 应用层：高级功能封装

**ChatClient——对话客户端（1.0 推荐使用）**

`ChatClient` 是 Spring AI 1.0 推荐的高级 API，采用**流式 Builder 模式**：

```java
@Autowired
private ChatClient.Builder chatClientBuilder;

// 构建带默认配置的 ChatClient
ChatClient chatClient = chatClientBuilder
    .defaultSystem("你是一个专业的 Java 开发顾问")
    .defaultOptions(ChatOptions.builder()
        .model("gpt-4o")
        .temperature(0.7)
        .build())
    .build();

// 简单调用
String response = chatClient.prompt()
    .user("解释一下 Spring 的依赖注入")
    .call()
    .content();

// 流式响应（SSE 或 WebSocket）
chatClient.prompt()
    .user("写一个 Spring Boot 启动流程分析")
    .stream()
    .content()
    .subscribe(chunk -> System.out.print(chunk));

// 结构化输出（1.0 新增）
Person person = chatClient.prompt()
    .user("从文本中提取人物信息：张三，35岁，北京人")
    .call()
    .entity(Person.class);  // 自动转换为 POJO
```

**PromptTemplate——提示词模板**

支持 Mustache 语法，动态生成提示词：

```java
PromptTemplate template = new PromptTemplate("""
    请根据以下信息回答问题：
    
    用户姓名：{{name}}
    用户角色：{{role}}
    问题：{{question}}
    
    请以{{style}}的风格回答。
    """);

Map<String, Object> params = Map.of(
    "name", "张三",
    "role", "架构师",
    "question", "如何设计微服务架构",
    "style", "专业简洁"
);

Prompt prompt = template.create(params);
```

**Advisor——拦截器模式（1.0 正式 API）**

Advisor 是 Spring AI 1.0 的核心拦截器机制，有两种类型：

- `CallAroundAdvisor`：同步调用拦截
- `StreamAroundAdvisor`：流式调用拦截

```java
// 自定义 Advisor（1.0 正式 API）
public class LoggingAdvisor implements CallAroundAdvisor {
    
    @Override
    public String getName() {
        return "LoggingAdvisor";
    }
    
    @Override
    public int getOrder() {
        return 0;  // 执行顺序
    }
    
    @Override
    public AdvisedResponse aroundCall(AdvisedRequest request, CallAroundAdvisorChain chain) {
        // 前置处理：记录请求
        log.info("AI Request: {}", request.userText());
        
        // 执行调用
        AdvisedResponse response = chain.nextAroundCall(request);
        
        // 后置处理：记录响应
        log.info("AI Response: {}", response.response().getResult().getOutput().getContent());
        
        return response;
    }
}

// 内置 Advisor：QuestionAnswerAdvisor（RAG 自动检索）
QuestionAnswerAdvisor qaAdvisor = new QuestionAnswerAdvisor(
    vectorStore,
    SearchRequest.defaults()
);

// 内置 Advisor：对话记忆
PromptChatMemoryAdvisor memoryAdvisor = new PromptChatMemoryAdvisor(
    chatMemory,
    "conversation-123"
);

// 使用多个 Advisor（链式执行）
String response = chatClient.prompt()
    .user("什么是 Spring AI？")
    .advisors(memoryAdvisor, qaAdvisor, loggingAdvisor)
    .call()
    .content();
```

**Agent——自主任务执行（1.1+ 新增）**

Spring AI 1.1 开始引入 Agent 抽象，支持自主任务分解和执行：

```java
// Agent 基础示例
@Autowired
private Agent agent;

public String executeTask(String task) {
    return agent.execute(task)
        .plan()     // 自主规划
        .execute()  // 执行步骤
        .result();  // 返回结果
}
```

### 3. MCP 协议层：AI 的 USB-C 接口

**MCP（Model Context Protocol）** 是 Anthropic 在 2024 年推出的开放协议，2025 年成为 AI 工具连接的事实标准。Spring AI 1.0 正式支持 MCP。

```
MCP 架构：
┌─────────────────────────────────────────────────────────────┐
│                    Spring AI MCP Layer                       │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌─────────────┐      ┌──────────────┐                     │
│   │ MCP Client  │──────► MCP Servers  │                     │
│   │ (Spring AI) │      │ (Tool/DB/API)│                     │
│   └─────────────┘      └──────────────┘                     │
│         │                     │                              │
│         ▼                     ▼                              │
│   ┌─────────────┐      ┌──────────────┐                     │
│   │ ChatClient  │      │ GitHub MCP   │                     │
│   │   Agent     │      │ File MCP     │                     │
│   │             │      │ Postgres MCP │                     │
│   └─────────────┘      └──────────────┘                     │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**使用 MCP Server**：

```java
// 配置 MCP Server
spring.ai.mcp.servers.github.type=stdio
spring.ai.mcp.servers.github.command=/usr/local/bin/github-mcp-server

// 使用 MCP 工具
ChatClient client = ChatClient.builder(chatModel)
    .defaultMcpServers("github", "filesystem", "postgres")
    .build();

String response = client.prompt()
    .user("查看我最近的 GitHub PR，并总结变更内容")
    .call()
    .content();
// Agent 会自动调用 GitHub MCP Server 获取 PR 数据
```

### 4. 集成层：服务商适配现状（2026）

| 类型 | 支持的服务商 | 状态 |
|------|--------------|------|
| **对话模型** | OpenAI、Azure OpenAI、Anthropic Claude、Google Gemini、Amazon Bedrock、**阿里通义、百度文心、讯飞星火、腾讯混元**、Ollama | ✅ 生产就绪 |
| **Embedding** | OpenAI、Azure、阿里通义、本地模型 | ✅ 生产就绪 |
| **图像生成** | OpenAI DALL-E 3、Stability AI、Azure | ✅ 生产就绪 |
| **向量数据库** | Pinecone、Chroma、Weaviate、Milvus、Redis、PostgreSQL/pgvector、MongoDB、Elasticsearch | ✅ 生产就绪 |
| **MCP Server** | GitHub、Filesystem、PostgreSQL、Slack、Google Drive（官方），第三方生态丰富 | ✅ 1.0+ 支持 |

---

## 三、Spring 生态兼容方案

Spring AI 最大的优势是**原生融入 Spring 生态**，这是 LangChain4J 无法比拟的。

### 1. 自动配置（Spring Boot Starter）

```xml
<!-- OpenAI -->
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-openai-spring-boot-starter</artifactId>
    <version>1.1.0</version>
</dependency>

<!-- 阿里云通义千问 -->
<dependency>
    <groupId>com.alibaba.cloud.ai</groupId>
    <artifactId>spring-ai-alibaba-starter</artifactId>
    <version>1.0.0</version>
</dependency>

<!-- 向量数据库 -->
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-milvus-store-spring-boot-starter</artifactId>
</dependency>
```

### 2. Observability（可观测性）

Spring AI 自动集成 Spring Boot Actuator，AI 调用的可观测性**零配置开启**：

```yaml
management:
  endpoints:
    web:
      exposure:
        include: health,metrics,prometheus
  tracing:
    enabled: true
  observations:
    ai:
      enabled: true  # AI 调用自动追踪
```

**自动上报的指标**：

| 指标 | 说明 |
|------|------|
| `ai.chat.tokens.used` | Token 消耗量（Prompt + Completion） |
| `ai.chat.latency` | 调用耗时（P50、P95、P99） |
| `ai.chat.success.rate` | 成功率 |
| `ai.embedding.latency` | Embedding 耗时 |
| `ai.vectorstore.search.latency` | 向量检索耗时 |

**自动追踪的 Span**：

```
AI Chat Call
  ├── ai-chat-request (Prompt 构建)
  ├── ai-chat-model-call (LLM 调用)
  │     ├── token-count (Token 计算)
  │     └── response-parse (响应解析)
  └── ai-chat-response (结果处理)
```

### 3. Spring Cloud 集成

```java
// 配置中心：模型参数动态刷新
@RefreshScope
@Service
public class AiService {
    
    @Value("${spring.ai.openai.chat.options.model}")
    private String model;
    
    @Value("${spring.ai.openai.chat.options.temperature}")
    private Double temperature;
}

// 熔断降级：AI 调用失败保护
@Service
public class ResilientAiService {
    
    @Autowired
    private ChatClient chatClient;
    
    @CircuitBreaker(name = "aiService", fallbackMethod = "fallback")
    @Retry(name = "aiService")
    @RateLimiter(name = "aiService")
    public String chat(String message) {
        return chatClient.prompt()
            .user(message)
            .call()
            .content();
    }
    
    public String fallback(String message, Exception e) {
        return "AI 服务暂时不可用，请稍后重试";
    }
}
```

### 4. Spring Security 集成

```java
// AI API Key 安全管理
@Configuration
public class AiSecurityConfig {
    
    @Bean
    public ChatModel chatModel(KeyProvider keyProvider) {
        // Key 从 Vault 或密钥管理服务获取
        String apiKey = keyProvider.getApiKey("openai");
        
        return OpenAiChatModel.builder()
            .apiKey(apiKey)
            .build();
    }
}

// 用户级 AI 权限控制
@Service
public class SecuredAiService {
    
    @PreAuthorize("hasRole('AI_USER')")
    public String chat(String message) {
        // 只有 AI_USER 角色才能调用
        return chatClient.prompt().user(message).call().content();
    }
}
```

---

## 四、Spring AI vs LangChain4J：2026 年深度对比

LangChain4J 是另一个流行的 Java AI 框架，两者经常被拿来对比。站在 2026 年的视角，对比结果已经清晰。

### 1. 版本成熟度对比

| 框架 | 最新版本 | 发布时间 | 成熟度 |
|------|----------|----------|--------|
| **Spring AI** | 1.1.x / 1.2 | 2025.05 GA | 生产就绪，API 稳定 |
| **LangChain4J** | 1.0.x | 2025.06 GA | 生产就绪，社区活跃 |

两者都在 2025 年上半年发布了 1.0 GA 版本，生产就绪度相当。

### 2. 设计哲学对比

| 维度 | Spring AI | LangChain4J |
|------|-----------|-------------|
| **设计哲学** | Spring 原生，企业级优先 | 轻量独立，框架中立 |
| **依赖要求** | 必须有 Spring Boot 3.x | 无强制依赖，支持 Quarkus/Micronaut/Spring |
| **API 风格** | Builder 模式 + Advisor 链 | 流式 API + AI Services 注解 |
| **配置方式** | YAML 自动配置 + Actuator | 代码 Builder 配置 |
| **生态集成** | Spring 全生态无缝集成 | 需手动集成各框架 |

### 3. 核心能力对比

| 能力 | Spring AI | LangChain4J | 说明 |
|------|-----------|-------------|------|
| **Chat** | ✅ ChatClient | ✅ ChatLanguageModel | 都成熟 |
| **Embedding** | ✅ EmbeddingModel | ✅ EmbeddingModel | 都成熟 |
| **RAG** | ✅ QuestionAnswerAdvisor | ✅ ContentRetriever + Augmentor | Spring AI 更简洁 |
| **Function Calling** | ✅ @Bean + @Description | ✅ @Tool 注解 | LangChain4J 更直观 |
| **对话记忆** | ✅ PromptChatMemoryAdvisor | ✅ ChatMemoryProvider | 都成熟 |
| **结构化输出** | ✅ .entity(Class) | ✅ 返回 POJO | 都成熟 |
| **MCP 协议** | ✅ 1.0+ 原生支持 | ✅ 1.0+ 支持 | Spring AI 集成更深 |
| **Agent** | ⚠️ 1.1+ 基础支持 | ✅ 成熟的 Agent 框架 | LangChain4J 更成熟 |
| **Observability** | ✅ Actuator 自动集成 | ⚠️ 需手动配置 | Spring AI 完胜 |
| **国产模型** | ✅ 官方支持阿里/百度/讯飞 | ⚠️ 需自行适配 | Spring AI 优势 |

### 4. 代码风格对比

**对话模型**：

```java
// Spring AI：流式 Builder
@Autowired
private ChatClient chatClient;

String response = chatClient.prompt()
    .system("你是一个专业的顾问")
    .user("你好")
    .advisors(memoryAdvisor)
    .call()
    .content();

// LangChain4J：直接调用
ChatLanguageModel model = OpenAiChatModel.builder()
    .apiKey("key")
    .modelName("gpt-4o")
    .build();

String response = model.generate("你好");
```

**AI Services 注解（LangChain4J 特色）**：

```java
// LangChain4J 的声明式 AI Services
interface Assistant {
    @SystemMessage("你是一个专业的 Java 顾问，回答要简洁")
    String chat(@UserMessage String question);
    
    @UserMessage("讲一个关于 {{topic}} 的笑话")
    String tellJoke(@V("topic") String topic);
}

// 一行代码构建
Assistant assistant = AiServices.builder(Assistant.class)
    .chatLanguageModel(model)
    .chatMemoryProvider(id -> MessageWindowChatMemory.withMaxMessages(10))
    .tools(new MyTools())
    .build();

// Spring AI 需要用 ChatClient + PromptTemplate 实现
// 目前没有直接的 AI Services 对应
```

**RAG 实现**：

```java
// Spring AI：Advisor 自动处理
@Autowired
private VectorStore vectorStore;

QuestionAnswerAdvisor qaAdvisor = new QuestionAnswerAdvisor(
    vectorStore,
    SearchRequest.defaults().withTopK(5)
);

String response = chatClient.prompt()
    .user("什么是 Spring AI？")
    .advisors(qaAdvisor)
    .call()
    .content();

// LangChain4J：ContentRetriever + Augmentor
ContentRetriever retriever = EmbeddingStoreContentRetriever.builder()
    .embeddingStore(embeddingStore)
    .embeddingModel(embeddingModel)
    .maxResults(5)
    .build();

Augmentor augmentor = DefaultAugmentor.builder()
    .contentRetriever(retriever)
    .build();

Assistant assistant = AiServices.builder(Assistant.class)
    .chatLanguageModel(model)
    .augmentor(augmentor)
    .build();
```

### 5. Agent 能力对比（关键差异）

**LangChain4J 的 Agent 更成熟**：

```java
// LangChain4J：完整的 Agent 框架
Agent agent = Agent.builder()
    .chatLanguageModel(model)
    .tools(new FileTools(), new WebSearchTools(), new DatabaseTools())
    .chatMemoryProvider(id -> MessageWindowChatMemory.withMaxMessages(20))
    .systemMessage("你是一个自主解决问题的助手...")
    .build();

// Agent 自主执行复杂任务
String result = agent.run("分析这份文档，找出关键问题，并生成改进建议");
```

**Spring AI 的 Agent（1.1+）还在发展**：

```java
// Spring AI：基础 Agent 能力
AgentExecutor executor = AgentExecutor.builder()
    .chatModel(chatModel)
    .tools(toolRegistry)
    .build();

AgentResult result = executor.execute("任务描述");
```

**结论**：复杂 Agent 应用，LangChain4J 目前更成熟；企业级可观测 Agent，Spring AI 更适合。

### 6. 选型决策矩阵

```
选型决策树：
│
├─ 项目技术栈？
│   ├─ Spring Boot → Spring AI（生态融合度最高，必选）
│   ├─ Quarkus → LangChain4J（官方支持更好）
│   ├─ Micronaut → LangChain4J
│   └─ 纯 Java → LangChain4J（轻量）
│
├─ 是否需要企业级特性？
│   ├─ Observability 重要 → Spring AI（零配置集成）
│   ├─ Spring Cloud 配置中心 → Spring AI
│   ├─ Spring Security 权限 → Spring AI
│   └─ 不需要 → LangChain4J 或 Spring AI 都行
│
├─ Agent 复杂度？
│   ├─ 复杂自主 Agent → LangChain4J（Agent 框架更成熟）
│   ├─ 简单对话 + RAG → Spring AI（QuestionAnswerAdvisor 更简洁）
│   └─ 可观测 Agent → Spring AI
│
├─ 国产模型需求？
│   ├─ 阿里通义/百度文心 → Spring AI（官方支持）
│   └─ 国际模型为主 → 两者都支持
│
├─ 团队熟悉度？
│   ├─ Spring 开发者 → Spring AI（零学习成本）
│   ├─ 非 Spring 开发者 → LangChain4J
│
└─ 快速原型？
    ├─ 声明式接口 → LangChain4J AI Services（接口定义即实现）
    └─ Spring 体系 → Spring AI ChatClient
```

**一句话总结**：

| 场景 | 推荐 |
|------|------|
| **Spring Boot 企业项目** | Spring AI（必选） |
| **Quarkus/Micronaut 项目** | LangChain4J |
| **复杂自主 Agent** | LangChain4J（Agent 更成熟） |
| **RAG + 可观测性** | Spring AI（Advisor + Actuator） |
| **国产模型合规** | Spring AI（官方支持） |
| **快速原型** | LangChain4J AI Services |

---

## 五、实战：Spring AI 经典实践

### 1. 基础对话应用

**Maven 依赖（Spring Boot 3.x）**：

```xml
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-openai-spring-boot-starter</artifactId>
    <version>1.1.0</version>
</dependency>
```

**配置**：

```yaml
spring:
  ai:
    openai:
      api-key: ${OPENAI_API_KEY}
      base-url: https://api.openai.com  # 可切换代理地址
      chat:
        options:
          model: gpt-4o-mini
          temperature: 0.7
```

**Controller（推荐写法）**：

```java
@RestController
@RequestMapping("/api/chat")
public class ChatController {
    
    private final ChatClient chatClient;
    
    // 推荐：构造时注入，一次性构建
    public ChatController(ChatClient.Builder builder) {
        this.chatClient = builder
            .defaultSystem("你是一个友好的助手，用简洁的语言回答")
            .defaultOptions(ChatOptions.builder()
                .temperature(0.7)
                .build())
            .build();
    }
    
    @PostMapping
    public String chat(@RequestBody String message) {
        return chatClient.prompt()
            .user(message)
            .call()
            .content();
    }
    
    @GetMapping("/stream")
    public Flux<String> streamChat(@RequestParam String message) {
        return chatClient.prompt()
            .user(message)
            .stream()
            .content();
    }
    
    // 结构化输出
    @PostMapping("/extract")
    public Summary extract(@RequestBody String text) {
        return chatClient.prompt()
            .user("总结以下文本：\n" + text)
            .call()
            .entity(Summary.class);
    }
}

public record Summary(String title, List<String> keyPoints, String conclusion) {}
```

### 2. Function Calling（工具调用）

Spring AI 1.0 的 Function Calling 已经非常成熟：

```java
@Configuration
public class AiFunctions {
    
    // 方式一：Spring Bean 函数
    @Bean
    @Description("查询指定城市的实时天气信息")
    public Function<WeatherRequest, WeatherResponse> weatherFunction(WeatherService weatherService) {
        return request -> weatherService.getCurrentWeather(request.city());
    }
    
    // 方式二：复杂函数
    @Bean
    @Description("在数据库中搜索相关文档")
    public Function<SearchRequest, List<Document>> searchDocuments(DocumentRepository repo) {
        return request -> repo.searchByKeyword(request.keyword(), request.limit());
    }
}

public record WeatherRequest(String city) {}
public record WeatherResponse(String city, double temperature, String condition, int humidity) {}
public record SearchRequest(String keyword, int limit) {}

// Controller 使用
@RestController
public class WeatherController {
    
    private final ChatClient chatClient;
    
    public WeatherController(ChatClient.Builder builder) {
        this.chatClient = builder
            .defaultFunctions("weatherFunction", "searchDocuments")
            .build();
    }
    
    @GetMapping("/weather")
    public String askWeather(@RequestParam String question) {
        // LLM 自动识别需要调用 weatherFunction
        // 如 "北京今天天气怎么样？适合户外运动吗？"
        return chatClient.prompt()
            .user(question)
            .call()
            .content();
    }
}
```

### 3. RAG 应用实战（QuestionAnswerAdvisor）

Spring AI 1.0 的 RAG 实现已经非常简洁：

```xml
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-pdf-document-reader</artifactId>
</dependency>
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-milvus-store-spring-boot-starter</artifactId>
</dependency>
```

**文档导入服务**：

```java
@Service
public class DocumentService {
    
    private final EmbeddingModel embeddingModel;
    private final VectorStore vectorStore;
    
    public DocumentService(EmbeddingModel embeddingModel, VectorStore vectorStore) {
        this.embeddingModel = embeddingModel;
        this.vectorStore = vectorStore;
    }
    
    public void importPdf(String filePath) {
        // 1. 读取 PDF
        Resource resource = new FileSystemResource(filePath);
        TikaDocumentReader reader = new TikaDocumentReader(resource);
        List<Document> documents = reader.get();
        
        // 2. 分块
        TokenTextSplitter splitter = new TokenTextSplitter(
            500,   // 默认块大小
            100,   // 重叠大小
            5,     // 最小块大小
            10000, // 最大块大小
            true   // 保持段落完整
        );
        List<Document> chunks = splitter.split(documents);
        
        // 3. 向量化并存入 VectorStore（自动 Embedding）
        vectorStore.add(chunks);
    }
}
```

**RAG 查询服务（使用 QuestionAnswerAdvisor）**：

```java
@Service
public class RagService {
    
    private final ChatClient chatClient;
    private final VectorStore vectorStore;
    
    public RagService(ChatClient.Builder builder, VectorStore vectorStore) {
        this.vectorStore = vectorStore;
        
        // 核心：QuestionAnswerAdvisor 自动处理检索和上下文注入
        QuestionAnswerAdvisor qaAdvisor = new QuestionAnswerAdvisor(
            vectorStore,
            SearchRequest.defaults()
                .withTopK(5)
                .withSimilarityThreshold(0.7)
        );
        
        this.chatClient = builder
            .defaultSystem("""
                你是一个专业的问答助手。
                请严格基于提供的文档内容回答问题。
                如果文档中没有相关信息，请明确告知"文档中未找到相关内容"。
                回答时请标注信息来源。
                """)
            .defaultAdvisors(qaAdvisor)
            .build();
    }
    
    public String query(String question) {
        // Advisor 自动检索相关文档并注入上下文
        return chatClient.prompt()
            .user(question)
            .call()
            .content();
    }
}
```

**对比：Spring AI 的 RAG 只需要 3 行核心代码，LangChain4J 需要更多配置。**

### 4. 使用阿里云通义千问（国产模型）

国内项目首选阿里云，性价比高，中文效果好：

```xml
<dependency>
    <groupId>com.alibaba.cloud.ai</groupId>
    <artifactId>spring-ai-alibaba-starter</artifactId>
    <version>1.0.0</version>
</dependency>
```

```yaml
spring:
  ai:
    alibaba:
      api-key: ${DASHSCOPE_API_KEY}
      chat:
        options:
          model: qwen-plus  # qwen-turbo / qwen-plus / qwen-max
```

```java
@Service
public class AlibabaAiService {
    
    private final ChatClient chatClient;
    
    public AlibabaAiService(ChatClient.Builder builder) {
        this.chatClient = builder
            .defaultSystem("你是一个专业的中文顾问")
            .build();
    }
    
    public String chat(String message) {
        return chatClient.prompt()
            .user(message)
            .call()
            .content();
    }
}
```

支持的通义模型：
- **qwen-turbo**：速度快，成本低，适合简单对话
- **qwen-plus**：能力均衡，推荐日常使用
- **qwen-max**：最强推理，适合复杂任务
- **qwen-vl**：多模态，支持图像理解

### 5. MCP 工具集成

```yaml
# 配置 MCP Server
spring:
  ai:
    mcp:
      servers:
        github:
          type: stdio
          command: /usr/local/bin/github-mcp-server
          args:
            - --token=${GITHUB_TOKEN}
        filesystem:
          type: stdio
          command: /usr/local/bin/fs-mcp-server
          args:
            - --root=/data/documents
```

```java
@Service
public class McpAiService {
    
    private final ChatClient chatClient;
    
    public McpAiService(ChatClient.Builder builder) {
        this.chatClient = builder
            .defaultMcpServers("github", "filesystem")
            .build();
    }
    
    public String analyzeGithubPr(String repo, int prNumber) {
        return chatClient.prompt()
            .user("分析 " + repo + " 的 PR #" + prNumber + " 的变更内容")
            .call()
            .content();
        // 自动调用 GitHub MCP Server 获取 PR 数据
    }
}
```

---

## 六、Spring AI 在 AI 潮流中的作用与影响

### 1. 降低 Java 企业接入 AI 的门槛

经过近一年的生产验证，Spring AI 已经证明了自己的价值：

| 2024 年痛点 | 2026 年现状 |
|-------------|-------------|
| Java 开发者被迫学 Python | Spring 开发者零学习成本接入 AI |
| 跨语言架构复杂 | 单一技术栈，架构统一 |
| 缺乏企业级特性 | Observability、安全、配置管理一体化 |

**数据佐证**：Spring AI GitHub Stars 从 2024 年的几千增长到 2026 年的数万，企业采用率快速增长。

### 2. 推动 AI 应用标准化

Spring AI 带来的标准化价值：

| 标准化 | 影响 |
|--------|------|
| **API 统一** | 模型切换零成本，供应商议价能力提升 |
| **Prompt 模板化** | 版本管理、复用、测试规范化 |
| **RAG 模式** | QuestionAnswerAdvisor 成为参考模式 |
| **Observability** | AI 调用监控追踪有 Spring 标准 |
| **MCP 协议** | 工具连接有开放标准，生态繁荣 |

### 3. 企业级 AI 应用的基础设施

Spring AI 不是玩具框架，是生产级基础设施：

| 能力 | Spring AI 实现 |
|------|----------------|
| **可观测性** | Actuator 自动集成，Token 消耗、耗时、成功率自动上报 |
| **可配置** | YAML 配置 + 配置中心动态刷新 |
| **可扩展** | 新服务商扩展简单，遵循 Spring 模式 |
| **可集成** | Spring Cloud、Security、Data 一体化 |
| **可运维** | 熔断、限流、重试、降级开箱即用 |

### 4. 与 LangChain 生态的分工协作

| 生态 | 定位 | 2026 状态 |
|------|------|-----------|
| **LangChain（Python）** | AI 创新的前沿试验场 | 继续引领新模式 |
| **LangChain4J** | Java 轻量级选择，Agent 优先 | Agent 能力领先 |
| **Spring AI** | Java 企业级标准，可观测优先 | 企业采用率领先 |

三者不是竞争，是分工协作：LangChain 探路 → LangChain4J 快速跟进 → Spring AI 企业级封装。

---

## 七、避坑指南（2026 版）

### 1. 常见问题

| 问题 | 解决方案 |
|------|----------|
| **API Key 管理混乱** | 用 Spring Cloud Vault 或配置中心，禁止硬编码 |
| **Token 消耗失控** | 启用 Actuator，配置预算告警，用 `maxTokens` 限制 |
| **RAG 效果不好** | 调整 Top-K、相似度阈值、分块策略，换 Embedding 模型 |
| **响应慢** | 流式响应，用小模型处理简单请求，预热连接 |
| **幻觉问题** | RAG + 严格系统提示，设置"无法回答"的 fallback |
| **国产模型不稳定** | 多模型备份，配置 fallback chain |

### 2. 最佳实践

1. **用 ChatClient，别直接用 ChatModel**：ChatClient 封装更好，Advisor 链式处理
2. **RAG 用 QuestionAnswerAdvisor**：3 行代码搞定，别手动拼接上下文
3. **Function 定义清晰**：`@Description` 写清楚用途和参数，帮助 LLM 正确调用
4. **VectorStore 选型**：原型 Chroma，生产 Milvus/Qdrant，小数据 Redis/pgvector
5. **Observability 必开**：上线前先配好，AI 调用必须有追踪
6. **国产模型合规**：数据不出境，用阿里/百度/讯飞，成本可控

### 3. 生产部署 Checklist

- [ ] API Key 从配置中心/Vault 获取
- [ ] Observability 开启，Token 消耗监控
- [ ] 熔断降级配置（AI 调用失败 fallback）
- [ ] 流式响应（降低首字延迟）
- [ ] 日志脱敏（Prompt 可能含敏感信息）
- [ ] VectorStore 持久化配置
- [ ] 多模型备份（OpenAI 备通义，反之亦然）

---

## 总结

Spring AI 已经是 Java 企业级 AI 应用的事实标准：

| 维度 | Spring AI 优势 |
|------|----------------|
| **成熟度** | 1.0 GA 近一年，API 稳定，生产验证 |
| **生态融合** | Spring Boot/Cloud/Security/Actuator 一体化 |
| **企业级特性** | Observability、配置管理、安全审计开箱即用 |
| **国产支持** | 阿里/百度/讯飞官方支持，合规可控 |
| **RAG 简洁** | QuestionAnswerAdvisor 3 行代码搞定 |
| **MCP 支持** | 1.0+ 原生支持，工具生态繁荣 |

**一句话**：Spring 项目做 AI 应用，Spring AI 是唯一合理的选择。LangChain4J 在 Agent 方面领先，但企业级可观测性，Spring AI 完胜。

如果你是 Spring 开发者，想做 AI 应用，现在就是最好的时机——Spring AI 已经成熟，文档完善，社区活跃，生产就绪。

---

## 参考资料

- [Spring AI 官方文档](https://docs.spring.io/spring-ai/reference/)
- [Spring AI 1.0 GA 发布公告](https://spring.io/blog/2025/05/spring-ai-1-0-release)
- [Spring AI Alibaba 官方文档](https://java2ai.com/)
- [Spring AI Alibaba GitHub](https://github.com/alibaba/spring-ai-alibaba)
- [LangChain4J 官方文档](https://docs.langchain4j.dev/)
- [Anthropic MCP 官方文档](https://modelcontextprotocol.io/)
- [Spring AI MCP 集成文档](https://docs.spring.io/spring-ai/reference/api/mcp.html)