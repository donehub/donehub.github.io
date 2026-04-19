---
title: 奇技淫巧：Java / Python 应用调用阿里百炼 Coding Plan 服务
date: 2026-04-19
tags: Coding Plan
categories: AI
---

> 阿里云百炼 Coding Plan 官方宣称"仅限编程工具使用"，但实际上其 endpoint 基于 OpenAI 兼容协议，Java/Python 应用完全可以调用。本文分享如何用 LangChain4j 和 OpenAI SDK 突破这一限制，直接消耗 Coding Plan 额度。

---

## 一、背景：一个被"误解"的服务

阿里云百炼的 **Coding Plan** 是一项面向 AI 编程助手的服务套餐，提供专门的模型调用额度。官方客服的说法是：

> "Coding Plan 的专属 API Key（格式为 `sk-sp-xxxxx`）仅限在支持的编程工具（如 Claude Code、OpenClaw 等）中使用，不能用于 Java 应用直接调用大模型。若您的 Java 应用需要调用百炼大模型，请使用百炼通用 API Key（格式为 `sk-xxxxx`），该 Key 支持调用包括 Coding 模型在内的所有百炼模型，并按量计费。"

这意味着如果你想在 Java 应用中使用百炼大模型，需要：
1. 额外开通百炼通用 API Key（格式为 `sk-xxxxx`）
2. 按量付费，产生额外费用

**但实际上，Coding Plan 的额度完全可以在 Java/Python 应用中使用！** 本文将分享这个"奇技淫巧"。

---

## 二、问题发现：为什么 Coding Plan Key 在 Java 中"失效"？

### 2.1 错误的调用方式

很多开发者（包括我）最初使用阿里云官方的 `dashscope-sdk-java` 调用百炼：

```java
// pom.xml
<dependency>
    <groupId>com.alibaba</groupId>
    <artifactId>dashscope-sdk-java</artifactId>
    <version>2.22.15</version>
</dependency>

// Java 代码
Generation gen = new Generation();
GenerationParam param = GenerationParam.builder()
    .apiKey("sk-sp-xxxxx")  // Coding Plan API Key
    .model("qwen-plus")
    .messages(messages)
    .build();
GenerationResult result = gen.call(param);
```

**结果：API 返回 InvalidApiKey 错误，或者即使调通了，消耗的是通用额度而非 Coding Plan 额度！**

### 2.2 根本原因分析

Coding Plan 的 API Key 使用的是 **OpenAI 兼容协议**，endpoint 地址不同于通用百炼服务：

| 服务类型 | API Key 格式 | Endpoint | 模型名称 |
|---------|-------------|----------|---------|
| **通用百炼** | `sk-xxxxx` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus`, `qwen-max` |
| **Coding Plan** | `sk-sp-xxxxx` | `https://coding.dashscope.aliyuncs.com/v1` | `多个模型` 等 |

官方的 `dashscope-sdk-java` 只支持通用百炼 endpoint，无法连接 Coding Plan 的 endpoint！

---

## 三、解决方案：使用 OpenAI 兼容模式

### 3.1 技术原理

Coding Plan 的 endpoint 基于 **OpenAI API 兼容协议**，任何支持 OpenAI API 的客户端都可以调用：

1. **Python**: 使用 `openai` SDK
2. **Java**: 使用 LangChain4j 的 `langchain4j-open-ai` 模块

只要将 `base_url` 指向 Coding Plan 的 endpoint，API Key 就能正常工作！

---

## 四、Java 实现：LangChain4j + Coding Plan

### 4.1 添加依赖

```xml
<!-- pom.xml -->
<properties>
    <langchain4j.version>0.35.0</langchain4j.version>
</properties>

<dependencies>
    <!-- LangChain4j OpenAI 兼容模块 -->
    <dependency>
        <groupId>dev.langchain4j</groupId>
        <artifactId>langchain4j</artifactId>
        <version>${langchain4j.version}</version>
    </dependency>
    <dependency>
        <groupId>dev.langchain4j</groupId>
        <artifactId>langchain4j-open-ai</artifactId>
        <version>${langchain4j.version}</version>
    </dependency>
</dependencies>
```

### 4.2 配置文件

```properties
# application.properties - Coding Plan 配置
langchain4j.open-ai.chat-model.base-url=https://coding.dashscope.aliyuncs.com/v1
langchain4j.open-ai.chat-model.api-key=sk-sp-xxxxx
langchain4j.open-ai.chat-model.model-name=kimi-k2.5
langchain4j.open-ai.chat-model.temperature=0.3
langchain4j.open-ai.chat-model.max-tokens=4096
```

**关键点：`base-url` 必须是 `coding.dashscope.aliyuncs.com/v1`，不是通用的 `dashscope.aliyuncs.com`！**

### 4.3 Java 代码实现

```java
import dev.langchain4j.data.message.AiMessage;
import dev.langchain4j.data.message.ChatMessage;
import dev.langchain4j.data.message.SystemMessage;
import dev.langchain4j.data.message.UserMessage;
import dev.langchain4j.model.chat.ChatLanguageModel;
import dev.langchain4j.model.openai.OpenAiChatModel;
import dev.langchain4j.model.output.Response;

import java.time.Duration;
import java.util.Arrays;
import java.util.List;

public class CodingPlanExample {

    private final ChatLanguageModel chatModel;

    public CodingPlanExample(String baseUrl, String apiKey, String modelName) {
        // 使用 OpenAI 兼容模式构建 ChatModel
        this.chatModel = OpenAiChatModel.builder()
                .baseUrl(baseUrl)  // Coding Plan endpoint
                .apiKey(apiKey)    // Coding Plan API Key
                .modelName(modelName)
                .temperature(0.3)
                .maxTokens(4096)
                .timeout(Duration.ofSeconds(60))
                .build();
    }

    public String chat(String systemPrompt, String userMessage) {
        List<ChatMessage> messages = Arrays.asList(
                SystemMessage.from(systemPrompt),
                UserMessage.from(userMessage)
        );

        Response<AiMessage> response = chatModel.generate(messages);

        if (response == null || response.content() == null) {
            throw new RuntimeException("模型返回结果为空");
        }

        return response.content().text();
    }

    public static void main(String[] args) {
        CodingPlanExample example = new CodingPlanExample(
                "https://coding.dashscope.aliyuncs.com/v1",
                "sk-sp-xxxxx",
                "kimi-k2.5"
        );

        String result = example.chat(
                "你是一位专业的翻译助手",
                "将以下内容翻译为英文：你好世界"
        );

        System.out.println(result);
    }
}
```

### 4.4 Spring Boot 集成示例

```java
@Configuration
public class LangChain4jConfig {

    @Value("${langchain4j.open-ai.chat-model.base-url}")
    private String baseUrl;

    @Value("${langchain4j.open-ai.chat-model.api-key}")
    private String apiKey;

    @Value("${langchain4j.open-ai.chat-model.model-name}")
    private String modelName;

    @Bean
    public ChatLanguageModel chatLanguageModel() {
        return OpenAiChatModel.builder()
                .baseUrl(baseUrl)
                .apiKey(apiKey)
                .modelName(modelName)
                .timeout(Duration.ofSeconds(60))
                .build();
    }
}

@Service
public class TranslationService {

    private final ChatLanguageModel chatModel;

    public TranslationService(ChatLanguageModel chatModel) {
        this.chatModel = chatModel;
    }

    public String translate(String content, String sourceLang, String targetLang) {
        String systemPrompt = String.format(
                "你是翻译专家，将内容从%s翻译为%s，直接输出结果",
                sourceLang, targetLang
        );

        List<ChatMessage> messages = Arrays.asList(
                SystemMessage.from(systemPrompt),
                UserMessage.from(content)
        );

        return chatModel.generate(messages).content().text();
    }
}
```

---

## 五、Python 实现：OpenAI SDK + Coding Plan

### 5.1 安装依赖

```bash
pip install openai
```

### 5.2 Python 代码

```python
from openai import OpenAI

# 使用 Coding Plan endpoint
client = OpenAI(
    base_url="https://coding.dashscope.aliyuncs.com/v1",
    api_key="sk-sp-xxxxx"
)

response = client.chat.completions.create(
    model="kimi-k2.5",
    messages=[
        {"role": "system", "content": "你是一位专业的翻译助手"},
        {"role": "user", "content": "将以下内容翻译为英文：你好世界"}
    ],
    temperature=0.3,
    max_tokens=4096
)

print(response.choices[0].message.content)
```

### 5.3 异步调用示例

```python
from openai import AsyncOpenAI
import asyncio

async_client = AsyncOpenAI(
    base_url="https://coding.dashscope.aliyuncs.com/v1",
    api_key="sk-sp-xxxxx"
)

async def translate_async(content: str) -> str:
    response = await async_client.chat.completions.create(
        model="kimi-k2.5",
        messages=[
            {"role": "system", "content": "你是翻译专家"},
            {"role": "user", "content": content}
        ]
    )
    return response.choices[0].message.content

# 批量翻译
async def batch_translate(contents: list[str]) -> list[str]:
    tasks = [translate_async(c) for c in contents]
    return await asyncio.gather(*tasks)

# 运行示例
async def main():
    results = await batch_translate(["你好世界", "人工智能"])
    print(results)

asyncio.run(main())
```

---

## 六、实际应用场景

### 6.1 职位内容翻译

```java
@Service
public class JobTranslationService {

    private final ChatLanguageModel chatModel;

    public String translateJobDescription(String content, String sourceLang, String targetLang) {
        String systemPrompt = buildTranslationPrompt(sourceLang, targetLang);

        List<ChatMessage> messages = Arrays.asList(
                SystemMessage.from(systemPrompt),
                UserMessage.from(content)
        );

        return chatModel.generate(messages).content().text();
    }

    private String buildTranslationPrompt(String sourceLang, String targetLang) {
        return String.format("""
            你是一位专业的职位内容翻译专家。
            请将用户输入的职位描述从%s翻译为%s。

            翻译要求：
            1. 保持原文的段落结构和格式
            2. 专业术语使用行业标准翻译
            3. 直接输出翻译结果
            """, sourceLang, targetLang);
    }
}
```

### 6.2 文档内容生成

```java
public String generateDocumentOutline(String topic) {
    String prompt = """
        根据以下主题，生成一份技术文档大纲：
        主题：%s

        要求：
        1. 结构清晰，层次分明
        2. 每个章节要有简要说明
        3. 使用 Markdown 格式输出
        """.formatted(topic);

    List<ChatMessage> messages = Arrays.asList(
        SystemMessage.from("你是技术文档撰写专家"),
        UserMessage.from(prompt)
    );

    return chatModel.generate(messages).content().text();
}
```

### 6.3 智能客服对话

```java
@Service
public class CustomerServiceBot {

    private final ChatLanguageModel chatModel;

    public String handleUserMessage(String userMessage, List<String> history) {
        List<ChatMessage> messages = new ArrayList<>();

        // 系统提示词
        messages.add(SystemMessage.from("""
            你是专业的客服助手，帮助用户解答产品相关问题。
            回答要求：
            1. 语气友好专业
            2. 回答简洁明了
            3. 如果无法回答，引导用户联系人工客服
            """));

        // 添加历史对话
        for (String h : history) {
            messages.add(UserMessage.from(h));
        }

        // 当前消息
        messages.add(UserMessage.from(userMessage));

        return chatModel.generate(messages).content().text();
    }
}
```

---

## 七、关键注意事项

### 7.1 Endpoint 不要混用

| Key 类型 | 正确 Endpoint | 错误 Endpoint |
|---------|--------------|--------------|
| `sk-sp-xxxxx` (Coding Plan) | `coding.dashscope.aliyuncs.com/v1` | `dashscope.aliyuncs.com` |
| `sk-xxxxx` (通用) | `dashscope.aliyuncs.com/compatible-mode/v1` | `coding.dashscope.aliyuncs.com` |

混用会导致 `InvalidApiKey` 错误或消耗错误的额度！

### 7.2 模型名称差异

Coding Plan 支持的模型可能与通用百炼不同：
- Coding Plan: `kimi-k2.5` 等
- 通用百炼: `qwen-plus`, `qwen-max`, `qwen-turbo`

请根据实际账号支持的模型选择。

### 7.3 Token 消耗监控

虽然使用了 Coding Plan 额度，但仍需关注：
- 单次调用 Token 数量
- Coding Plan 额度剩余
- 设置合理的 `max_tokens` 防止超限

### 7.4 超时设置

Coding Plan 响应时间可能与通用服务不同，建议设置较长超时：

```java
.timeout(Duration.ofSeconds(60))  // 或更长
```

---

## 八、总结

### 8.1 官方说法 vs 实际实践

| 官方说法 | 实际实践 |
|---------|---------|
| Coding Plan Key 仅限编程工具使用 | Java/Python 应用可正常使用 |
| 需要额外开通通用 Key | 无需额外开通 |
| 按量付费产生额外费用 | 直接消耗 Coding Plan 额度 |
| dashscope-sdk-java 不支持 | LangChain4j/OpenAI SDK 完美支持 |

### 8.2 核心原理

Coding Plan 的 endpoint 基于 **OpenAI API 兼容协议**，这是业界通用的 LLM API 标准。任何支持 OpenAI 协议的客户端都可以调用，不受编程工具限制。

### 8.3 适用场景

- ✅ Java 后端服务调用 LLM
- ✅ Python 应用调用 LLM
- ✅ Spring Boot / LangChain4j 集成
- ✅ 翻译、生成、对话等各类 NLP 任务
- ❌ 直接使用 dashscope-sdk-java（不支持 Coding Plan endpoint）

---

## 九、参考资料

- [LangChain4j 官方文档](https://docs.langchain4j.dev/)
- [OpenAI API 兼容协议](https://platform.openai.com/docs/api-reference)
- [阿里百炼 Coding Plan](https://bailian.console.aliyun.com/)