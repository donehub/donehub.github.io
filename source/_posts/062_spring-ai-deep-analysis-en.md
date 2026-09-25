---
title: Spring AI Deep Analysis
date: 2026-01-05
tags: Spring AI
categories: AI
lang: en
label: 062_spring-ai-deep-analysis
---

## Background

ChatGPT broke through in 2023, the Agent concept landed in 2024, and AI applications went mainstream in 2025. The AI toolkit for Java developers matured rapidly during this period. Spring AI 1.0 GA shipped in May 2025, and after nearly a year of iteration, it's become the de facto standard for enterprise Java AI applications. This article covers Spring AI comprehensively: why it exists, how the architecture evolved, how it compares to LangChain4J, and how to use it in practice.

<!-- more -->
---

## What Is Spring AI and Why You Need It

### The AI Dilemma for Java Developers

When large language models first took off, Java developers faced an uncomfortable choice. Calling provider APIs directly meant dealing with different interfaces per platform, high switching costs, and no abstractions for RAG, conversational memory, or Agents. Switching to Python frameworks like LangChain or LlamaIndex meant cross-language integration and inconsistent architecture. Over 80% of enterprise Java applications run on Spring, and the market needed an AI framework that fits natively into the Spring ecosystem.

### Origin and Evolution

Spring AI's version timeline:

| Date | Version | Milestone |
|------|---------|-----------|
| Nov 2023 | 0.8.0 | Project launched, first Milestone |
| Throughout 2024 | 0.8.x - 0.9.x | Rapid iteration, community feedback |
| May 2025 | 1.0.0 GA | Released at Spring I/O 2025, production-ready |
| H2 2025 | 1.0.x - 1.1.x | Stable iteration, bug fixes, MCP support added |
| Early 2026 | 1.1.x / 1.2 | Agent capabilities enhanced, Chinese model support matured |

The 1.0 GA release delivered several key milestones: core interfaces like ChatClient, Advisor, and VectorStore stabilized (API frozen); observability, error handling, and configuration management reached enterprise standards (production-ready); official support for 20+ model providers and 10+ vector databases (mature ecosystem); comprehensive documentation and examples with an active community.

### Core Value

| Value | Description | Enterprise Benefit |
|-------|-------------|-------------------|
| Unified API abstraction | OpenAI, Azure, Anthropic, Ollama, Chinese models, all behind one interface | Zero code changes when switching models, better vendor negotiation leverage |
| Spring-native integration | Auto-configuration, dependency injection, observability, config center | Zero learning curve for Spring developers, reuse existing infrastructure |
| Enterprise features | Token consumption monitoring, call chain tracing, circuit breaking, security audit | Deploy directly to production, unified operations pipeline |
| Advanced AI abstractions | RAG, Agent, MCP, Function Calling, conversational memory | No need to reinvent the wheel, focus on business logic |
| Chinese model support | Alibaba Qwen, Baidu Wenxin, iFlytek Spark, Tencent Hunyuan | Data compliance, cost control, optimized Chinese-language performance |

Spring AI is essentially the LangChain of the Java world, but it understands enterprise applications better than LangChain does.

---

## Architecture Design

Spring AI 1.0's architecture has stabilized into four layers: the Application Layer (ChatClient / PromptTemplate / Advisor / Agent), the MCP Protocol Layer (MCP Client / MCP Server / Tool Registry), the Core Abstraction Layer (ChatModel / EmbeddingModel / ImageModel / AudioModel), and the Integration Layer (adapters for OpenAI / Azure / Anthropic / Ollama / Alibaba / VectorDB and other providers).

### Core Abstraction Layer: Unified Interface Design

Spring AI defines a stable set of model interfaces. Regardless of which provider sits underneath, the API stays the same.

ChatModel is the core interface for conversational models:

```java
// Core interface definition (stabilized after 1.0 GA)
public interface ChatModel extends Model<Prompt, ChatResponse> {
    ChatResponse call(Prompt prompt);
}

// Usage example: switching providers requires only config changes, no code changes
@Autowired
private ChatModel chatModel;  // Config determines the implementation (OpenAI, Azure, Ollama...)

public String chat(String userMessage) {
    Prompt prompt = new Prompt(userMessage);
    ChatResponse response = chatModel.call(prompt);
    return response.getResult().getOutput().getContent();
}
```

EmbeddingModel handles vector embeddings. Version 1.0 added batch embedding capability:

```java
public interface EmbeddingModel extends Model<EmbeddingRequest, EmbeddingResponse> {
    EmbeddingResponse embed(EmbeddingRequest request);

    // New in 1.0: batch embedding
    List<float[]> embed(List<String> texts);
}

// Usage example
@Autowired
private EmbeddingModel embeddingModel;

public float[] embed(String text) {
    return embeddingModel.embed(text);
}
```

ImageModel handles image generation, supporting DALL-E 3, Stability AI, and Midjourney API:

```java
public interface ImageModel extends Model<ImagePrompt, ImageResponse> {
    ImageResponse call(ImagePrompt prompt);
}

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

### Application Layer: High-Level Feature Wrapping

ChatClient is Spring AI 1.0's recommended high-level API, using a fluent Builder pattern. It wraps conversational configuration, streaming responses, and structured output:

```java
@Autowired
private ChatClient.Builder chatClientBuilder;

// Build a ChatClient with default configuration
ChatClient chatClient = chatClientBuilder
    .defaultSystem("You are a professional Java consultant")
    .defaultOptions(ChatOptions.builder()
        .model("gpt-4o")
        .temperature(0.7)
        .build())
    .build();

// Simple call
String response = chatClient.prompt()
    .user("Explain Spring's dependency injection")
    .call()
    .content();

// Streaming response (SSE or WebSocket)
chatClient.prompt()
    .user("Write a Spring Boot startup analysis")
    .stream()
    .content()
    .subscribe(chunk -> System.out.print(chunk));

// Structured output (new in 1.0)
Person person = chatClient.prompt()
    .user("Extract person info from text: Zhang San, 35, from Beijing")
    .call()
    .entity(Person.class);  // Auto-converts to POJO
```

PromptTemplate supports Mustache syntax for dynamic prompt generation:

```java
PromptTemplate template = new PromptTemplate("""
    Please answer the following question based on this information:

    User name: {{name}}
    User role: {{role}}
    Question: {{question}}

    Answer in a {{style}} style.
    """);

Map<String, Object> params = Map.of(
    "name", "Zhang San",
    "role", "Architect",
    "question", "How to design a microservices architecture",
    "style", "professional and concise"
);

Prompt prompt = template.create(params);
```

Advisor is Spring AI 1.0's core interceptor mechanism, coming in two types: CallAroundAdvisor (synchronous call interception) and StreamAroundAdvisor (streaming call interception). It inserts custom logic before and after AI calls, enabling chained composition of logging, conversational memory, RAG retrieval, and other features:

```java
// Custom Advisor (official 1.0 API)
public class LoggingAdvisor implements CallAroundAdvisor {

    @Override
    public String getName() {
        return "LoggingAdvisor";
    }

    @Override
    public int getOrder() {
        return 0;  // Execution order
    }

    @Override
    public AdvisedResponse aroundCall(AdvisedRequest request, CallAroundAdvisorChain chain) {
        // Pre-processing: log the request
        log.info("AI Request: {}", request.userText());

        // Execute the call
        AdvisedResponse response = chain.nextAroundCall(request);

        // Post-processing: log the response
        log.info("AI Response: {}", response.response().getResult().getOutput().getContent());

        return response;
    }
}

// Built-in Advisor: QuestionAnswerAdvisor (RAG auto-retrieval)
QuestionAnswerAdvisor qaAdvisor = new QuestionAnswerAdvisor(
    vectorStore,
    SearchRequest.defaults()
);

// Built-in Advisor: conversational memory
PromptChatMemoryAdvisor memoryAdvisor = new PromptChatMemoryAdvisor(
    chatMemory,
    "conversation-123"
);

// Using multiple Advisors (chained execution)
String response = chatClient.prompt()
    .user("What is Spring AI?")
    .advisors(memoryAdvisor, qaAdvisor, loggingAdvisor)
    .call()
    .content();
```

The Agent abstraction was introduced starting from version 1.1, supporting autonomous task decomposition and execution:

```java
@Autowired
private Agent agent;

public String executeTask(String task) {
    return agent.execute(task)
        .plan()     // Autonomous planning
        .execute()  // Execute steps
        .result();  // Return result
}
```

### MCP Protocol Layer

MCP (Model Context Protocol) is an open protocol launched by Anthropic in 2024 that became the de facto standard for AI tool connectivity in 2025. Spring AI 1.0 officially supports MCP. Its architecture: an MCP Client (running inside Spring AI) connects to multiple MCP Servers (GitHub, filesystem, PostgreSQL, etc.), and the ChatClient Agent orchestrates these external tools through the MCP Client.

```java
// Configure MCP Server
spring.ai.mcp.servers.github.type=stdio
spring.ai.mcp.servers.github.command=/usr/local/bin/github-mcp-server

// Use MCP tools
ChatClient client = ChatClient.builder(chatModel)
    .defaultMcpServers("github", "filesystem", "postgres")
    .build();

String response = client.prompt()
    .user("Check my recent GitHub PRs and summarize the changes")
    .call()
    .content();
// The Agent automatically calls the GitHub MCP Server to fetch PR data
```

### Integration Layer: Provider Support Status (2026)

| Type | Supported Providers | Status |
|------|-------------------|--------|
| Chat models | OpenAI, Azure OpenAI, Anthropic Claude, Google Gemini, Amazon Bedrock, Alibaba Qwen, Baidu Wenxin, iFlytek Spark, Tencent Hunyuan, Ollama | Production-ready |
| Embedding | OpenAI, Azure, Alibaba Qwen, local models | Production-ready |
| Image generation | OpenAI DALL-E 3, Stability AI, Azure | Production-ready |
| Vector databases | Pinecone, Chroma, Weaviate, Milvus, Redis, PostgreSQL/pgvector, MongoDB, Elasticsearch | Production-ready |
| MCP Server | GitHub, Filesystem, PostgreSQL, Slack, Google Drive (official), rich third-party ecosystem | 1.0+ support |

---

## Spring Ecosystem Integration

Spring AI's biggest advantage is its native fit within the Spring ecosystem, something LangChain4J cannot match.

### Auto-Configuration (Spring Boot Starter)

Adding a Starter dependency handles basic configuration. Here's OpenAI and Alibaba Cloud Qwen as examples:

```xml
<!-- OpenAI -->
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-openai-spring-boot-starter</artifactId>
    <version>1.1.0</version>
</dependency>

<!-- Alibaba Cloud Qwen -->
<dependency>
    <groupId>com.alibaba.cloud.ai</groupId>
    <artifactId>spring-ai-alibaba-starter</artifactId>
    <version>1.0.0</version>
</dependency>

<!-- Vector database -->
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-milvus-store-spring-boot-starter</artifactId>
</dependency>
```

### Observability

Spring AI automatically integrates with Spring Boot Actuator, giving you zero-config observability for AI calls. Enable tracing and AI observations in configuration, and Actuator automatically reports token consumption (Prompt + Completion), call latency (P50, P95, P99), success rates, embedding latency, and vector search latency.

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
      enabled: true  # AI call auto-tracing
```

Auto-traced Spans cover the full call chain: from Prompt construction (ai-chat-request), through LLM invocation (ai-chat-model-call, including token-count and response-parse), to result processing (ai-chat-response).

### Spring Cloud Integration

Dynamic model parameter refresh from config center, combined with circuit breaking to protect AI calls:

```java
// Config center: dynamic model parameter refresh
@RefreshScope
@Service
public class AiService {

    @Value("${spring.ai.openai.chat.options.model}")
    private String model;

    @Value("${spring.ai.openai.chat.options.temperature}")
    private Double temperature;
}

// Circuit breaking: AI call failure protection
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
        return "AI service temporarily unavailable, please retry later";
    }
}
```

### Spring Security Integration

API Keys fetched from Vault or a secrets management service, user-level permissions controlled through Spring Security:

```java
// Secure AI API Key management
@Configuration
public class AiSecurityConfig {

    @Bean
    public ChatModel chatModel(KeyProvider keyProvider) {
        // Key fetched from Vault or secrets management service
        String apiKey = keyProvider.getApiKey("openai");

        return OpenAiChatModel.builder()
            .apiKey(apiKey)
            .build();
    }
}

// User-level AI permission control
@Service
public class SecuredAiService {

    @PreAuthorize("hasRole('AI_USER')")
    public String chat(String message) {
        // Only AI_USER role can call this
        return chatClient.prompt().user(message).call().content();
    }
}
```

---

## Spring AI vs LangChain4J: In-Depth Comparison

LangChain4J is another popular Java AI framework, and the two get compared frequently. From the vantage point of 2026, the comparison results are clear.

### Version Maturity

| Framework | Latest Version | Release Date | Maturity |
|-----------|---------------|--------------|----------|
| Spring AI | 1.1.x / 1.2 | 2025.05 GA | Production-ready, API stable |
| LangChain4J | 1.0.x | 2025.06 GA | Production-ready, active community |

Both released 1.0 GA in H1 2025 and are roughly equal in production readiness.

### Design Philosophy

| Dimension | Spring AI | LangChain4J |
|-----------|-----------|-------------|
| Design philosophy | Spring-native, enterprise-first | Lightweight, independent, framework-neutral |
| Dependency requirements | Requires Spring Boot 3.x | No mandatory dependencies, supports Quarkus/Micronaut/Spring |
| API style | Builder pattern + Advisor chain | Fluent API + AI Services annotations |
| Configuration | YAML auto-config + Actuator | Code-based Builder configuration |
| Ecosystem integration | Seamless full Spring ecosystem | Manual integration with each framework |

### Core Capability Comparison

| Capability | Spring AI | LangChain4J | Notes |
|------------|-----------|-------------|-------|
| Chat | ChatClient | ChatLanguageModel | Both mature |
| Embedding | EmbeddingModel | EmbeddingModel | Both mature |
| RAG | QuestionAnswerAdvisor | ContentRetriever + Augmentor | Spring AI is simpler |
| Function Calling | @Bean + @Description | @Tool annotation | LangChain4J is more intuitive |
| Conversational memory | PromptChatMemoryAdvisor | ChatMemoryProvider | Both mature |
| Structured output | .entity(Class) | Returns POJO | Both mature |
| MCP protocol | Native support in 1.0+ | Supported in 1.0+ | Spring AI integrates more deeply |
| Agent | Basic support from 1.1+ | Mature Agent framework | LangChain4J is more mature |
| Observability | Actuator auto-integrated | Requires manual setup | Clear Spring AI advantage |
| Chinese models | Official Alibaba/Baidu/iFlytek support | Requires custom adaptation | Spring AI advantage |

### Code Style Comparison

The usage patterns for chat models differ noticeably. Spring AI takes the fluent Builder route; LangChain4J goes with direct construction:

```java
// Spring AI: Fluent Builder
@Autowired
private ChatClient chatClient;

String response = chatClient.prompt()
    .system("You are a professional consultant")
    .user("Hello")
    .advisors(memoryAdvisor)
    .call()
    .content();

// LangChain4J: Direct call
ChatLanguageModel model = OpenAiChatModel.builder()
    .apiKey("key")
    .modelName("gpt-4o")
    .build();

String response = model.generate("Hello");
```

LangChain4J's AI Services annotations are its most distinctive design. You define an interface with annotations and get a complete AI service built, including system prompts, user templates, conversational memory, and tool binding:

```java
// LangChain4J's declarative AI Services
interface Assistant {
    @SystemMessage("You are a professional Java consultant, keep answers concise")
    String chat(@UserMessage String question);

    @UserMessage("Tell a joke about {{topic}}")
    String tellJoke(@V("topic") String topic);
}

// Built in one line
Assistant assistant = AiServices.builder(Assistant.class)
    .chatLanguageModel(model)
    .chatMemoryProvider(id -> MessageWindowChatMemory.withMaxMessages(10))
    .tools(new MyTools())
    .build();

// Spring AI needs ChatClient + PromptTemplate for equivalent functionality
// No direct AI Services counterpart currently
```

For RAG implementation, Spring AI handles retrieval and context injection automatically through Advisors, while LangChain4J requires manual assembly of ContentRetriever and Augmentor:

```java
// Spring AI: Advisor handles everything automatically
@Autowired
private VectorStore vectorStore;

QuestionAnswerAdvisor qaAdvisor = new QuestionAnswerAdvisor(
    vectorStore,
    SearchRequest.defaults().withTopK(5)
);

String response = chatClient.prompt()
    .user("What is Spring AI?")
    .advisors(qaAdvisor)
    .call()
    .content();

// LangChain4J: ContentRetriever + Augmentor
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

### Agent Capabilities (Key Difference)

LangChain4J's Agent framework is more mature, supporting tool binding, conversational memory, and autonomous task execution:

```java
// LangChain4J: Complete Agent framework
Agent agent = Agent.builder()
    .chatLanguageModel(model)
    .tools(new FileTools(), new WebSearchTools(), new DatabaseTools())
    .chatMemoryProvider(id -> MessageWindowChatMemory.withMaxMessages(20))
    .systemMessage("You are an autonomous problem-solving assistant...")
    .build();

// Agent autonomously executes complex tasks
String result = agent.run("Analyze this document, identify key issues, and generate improvement suggestions");
```

Spring AI's Agent was introduced in version 1.1 and remains at a basic stage:

```java
// Spring AI: Basic Agent capability
AgentExecutor executor = AgentExecutor.builder()
    .chatModel(chatModel)
    .tools(toolRegistry)
    .build();

AgentResult result = executor.execute("Task description");
```

For complex autonomous Agent applications, LangChain4J is currently more mature. For enterprise-grade observable Agents, Spring AI is the better fit.

### Selection Guide

The core decision criterion is your project's tech stack and specific requirements:

| Scenario | Recommendation | Reason |
|----------|---------------|--------|
| Spring Boot enterprise project | Spring AI | Best ecosystem fit, default choice |
| Quarkus/Micronaut project | LangChain4J | Better official support |
| Complex autonomous Agent | LangChain4J | More mature Agent framework |
| RAG + observability | Spring AI | Advisor + Actuator combo is cleaner |
| Chinese model compliance | Spring AI | Official Alibaba/Baidu/iFlytek support |
| Rapid prototyping | LangChain4J AI Services | Interface definition is implementation |

---

## Hands-On: Spring AI in Practice

### Basic Chat Application

Maven dependency and configuration:

```xml
<dependency>
    <groupId>org.springframework.ai</groupId>
    <artifactId>spring-ai-openai-spring-boot-starter</artifactId>
    <version>1.1.0</version>
</dependency>
```

```yaml
spring:
  ai:
    openai:
      api-key: ${OPENAI_API_KEY}
      base-url: https://api.openai.com  # Switchable proxy address
      chat:
        options:
          model: gpt-4o-mini
          temperature: 0.7
```

The Controller should inject ChatClient.Builder at construction time and build once, avoiding repeated configuration per request. The example below demonstrates regular calls, streaming responses, and structured output:

```java
@RestController
@RequestMapping("/api/chat")
public class ChatController {

    private final ChatClient chatClient;

    // Recommended: inject at construction, build once
    public ChatController(ChatClient.Builder builder) {
        this.chatClient = builder
            .defaultSystem("You are a friendly assistant, answer concisely")
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

    // Structured output
    @PostMapping("/extract")
    public Summary extract(@RequestBody String text) {
        return chatClient.prompt()
            .user("Summarize the following text:\n" + text)
            .call()
            .entity(Summary.class);
    }
}

public record Summary(String title, List<String> keyPoints, String conclusion) {}
```

### Function Calling (Tool Invocation)

Spring AI 1.0's Function Calling supports two approaches: registering Spring Bean functions with @Bean + @Description, or writing complex functions directly. The LLM decides when to call based on the function description:

```java
@Configuration
public class AiFunctions {

    // Approach 1: Spring Bean function
    @Bean
    @Description("Query real-time weather for a specified city")
    public Function<WeatherRequest, WeatherResponse> weatherFunction(WeatherService weatherService) {
        return request -> weatherService.getCurrentWeather(request.city());
    }

    // Approach 2: Complex function
    @Bean
    @Description("Search for relevant documents in the database")
    public Function<SearchRequest, List<Document>> searchDocuments(DocumentRepository repo) {
        return request -> repo.searchByKeyword(request.keyword(), request.limit());
    }
}

public record WeatherRequest(String city) {}
public record WeatherResponse(String city, double temperature, String condition, int humidity) {}
public record SearchRequest(String keyword, int limit) {}

// Controller usage
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
        // LLM automatically identifies it needs to call weatherFunction
        // e.g., "How's the weather in Beijing today? Good for outdoor activities?"
        return chatClient.prompt()
            .user(question)
            .call()
            .content();
    }
}
```

### RAG in Practice

Spring AI 1.0's RAG implementation relies on two components: DocumentService handles document ingestion (reading, chunking, vectorizing), and QuestionAnswerAdvisor handles auto-retrieval and context injection during queries.

Document ingestion service requires PDF reader and vector database Starters:

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
        // 1. Read PDF
        Resource resource = new FileSystemResource(filePath);
        TikaDocumentReader reader = new TikaDocumentReader(resource);
        List<Document> documents = reader.get();

        // 2. Chunk
        TokenTextSplitter splitter = new TokenTextSplitter(
            500,   // default chunk size
            100,   // overlap size
            5,     // minimum chunk size
            10000, // maximum chunk size
            true   // preserve paragraph integrity
        );
        List<Document> chunks = splitter.split(documents);

        // 3. Vectorize and store in VectorStore (auto-embedding)
        vectorStore.add(chunks);
    }
}
```

The core of the RAG query service is QuestionAnswerAdvisor, which handles retrieval and context injection automatically. Bind VectorStore and search parameters at construction time, and the Advisor handles document retrieval on every subsequent call:

```java
@Service
public class RagService {

    private final ChatClient chatClient;
    private final VectorStore vectorStore;

    public RagService(ChatClient.Builder builder, VectorStore vectorStore) {
        this.vectorStore = vectorStore;

        // Core: QuestionAnswerAdvisor handles retrieval and context injection automatically
        QuestionAnswerAdvisor qaAdvisor = new QuestionAnswerAdvisor(
            vectorStore,
            SearchRequest.defaults()
                .withTopK(5)
                .withSimilarityThreshold(0.7)
        );

        this.chatClient = builder
            .defaultSystem("""
                You are a professional Q&A assistant.
                Answer questions strictly based on the provided document content.
                If no relevant information is found in the documents, state "No relevant content found in documents."
                Cite information sources in your answers.
                """)
            .defaultAdvisors(qaAdvisor)
            .build();
    }

    public String query(String question) {
        // Advisor automatically retrieves relevant documents and injects context
        return chatClient.prompt()
            .user(question)
            .call()
            .content();
    }
}
```

For comparison, Spring AI's RAG core code takes just 3 lines (create Advisor, bind to ChatClient, make the call). LangChain4J requires more configuration steps.

### Using Alibaba Cloud Qwen

For domestic projects, Alibaba Cloud is the top choice: good price-performance ratio and strong Chinese-language results. After adding the spring-ai-alibaba-starter dependency, configure the api-key and model name:

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
            .defaultSystem("You are a professional Chinese-language consultant")
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

Qwen model series selection guide: qwen-turbo is fast and cheap, suitable for simple conversations; qwen-plus is balanced, recommended for daily use; qwen-max has the strongest reasoning, suitable for complex tasks; qwen-vl is multimodal, supporting image understanding.

### MCP Tool Integration

After configuring MCP Servers, ChatClient can automatically orchestrate external tools. This example configures GitHub and filesystem MCP Servers:

```yaml
# Configure MCP Servers
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
            .user("Analyze the changes in " + repo + " PR #" + prNumber)
            .call()
            .content();
        // Automatically calls GitHub MCP Server to fetch PR data
    }
}
```

---

## Pitfall Guide

### Common Issues

| Problem | Solution |
|---------|----------|
| API Key management chaos | Use Spring Cloud Vault or config center; never hardcode |
| Token consumption out of control | Enable Actuator, configure budget alerts, use maxTokens limits |
| Poor RAG quality | Adjust Top-K, similarity threshold, chunking strategy; try different embedding models |
| Slow responses | Use streaming responses, use smaller models for simple requests, warm up connections |
| Hallucination | RAG + strict system prompts, set "unable to answer" fallback |
| Chinese model instability | Multi-model backup, configure fallback chains |

### Best Practices

1. Use ChatClient, not ChatModel directly: ChatClient has better wrapping and Advisor chain processing
2. Use QuestionAnswerAdvisor for RAG: 3 lines of code, don't manually assemble context
3. Keep Function definitions clear: write @Description with purpose and parameters to help LLM invoke correctly
4. VectorStore selection: Chroma for prototyping, Milvus/Qdrant for production, Redis/pgvector for small datasets
5. Always enable Observability: configure before going live, AI calls must have tracing
6. Chinese model compliance: data stays domestic with Alibaba/Baidu/iFlytek, costs remain controllable

### Production Deployment Checklist

- [ ] API Keys from config center/Vault
- [ ] Observability enabled, token consumption monitoring
- [ ] Circuit breaker configuration (AI call failure fallback)
- [ ] Streaming response (reduces time-to-first-token)
- [ ] Log sanitization (Prompts may contain sensitive info)
- [ ] VectorStore persistence configured
- [ ] Multi-model backup (OpenAI backed by Qwen, and vice versa)

---

## References

- [Spring AI Official Documentation](https://docs.spring.io/spring-ai/reference/)
- [Spring AI 1.0 GA Release Announcement](https://spring.io/blog/2025/05/spring-ai-1-0-release)
- [Spring AI Alibaba Official Documentation](https://java2ai.com/)
- [Spring AI Alibaba GitHub](https://github.com/alibaba/spring-ai-alibaba)
- [LangChain4J Official Documentation](https://docs.langchain4j.dev/)
- [Anthropic MCP Official Documentation](https://modelcontextprotocol.io/)
- [Spring AI MCP Integration Documentation](https://docs.spring.io/spring-ai/reference/api/mcp.html)
