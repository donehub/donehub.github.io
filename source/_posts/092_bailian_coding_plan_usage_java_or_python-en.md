---
title: "Calling Alibaba Bailian Coding Plan from Java and Python Applications"
date: 2026-04-19
tags: Coding Plan
categories: AI
lang: en
label: 092_bailian_coding_plan_usage_java_or_python
---

Alibaba Cloud Bailian's Coding Plan is officially marketed as "programming tools only," but its endpoint is built on the OpenAI-compatible protocol, meaning Java and Python applications can call it directly. This post shows how to use LangChain4j and the OpenAI SDK to bypass that restriction and consume your Coding Plan quota from application code.

---

<!-- more -->
## 1. Background

Alibaba Cloud Bailian's Coding Plan is a service package aimed at AI coding assistants, providing dedicated model invocation quotas. Official support says this:

> "The Coding Plan's dedicated API Key (format `sk-sp-xxxxx`) is restricted to supported programming tools (like Claude Code, OpenClaw, etc.) and cannot be used for direct large model calls from Java applications. If your Java application needs to call Bailian models, use the general Bailian API Key (format `sk-xxxxx`), which supports all Bailian models including Coding models and is billed by usage."

This means if you want to use Bailian models in a Java application, you'd need to:
1. Provision a separate general Bailian API Key (format `sk-xxxxx`)
2. Pay per usage, incurring additional costs

In practice though, Coding Plan quotas work perfectly fine in Java and Python applications. This post shows exactly how.

---

## 2. Why Coding Plan Keys "Fail" in Java

### 2.1 The Wrong Approach

Many developers (myself included) initially try calling Bailian using Alibaba's official `dashscope-sdk-java`:

```java
// pom.xml
<dependency>
    <groupId>com.alibaba</groupId>
    <artifactId>dashscope-sdk-java</artifactId>
    <version>2.22.15</version>
</dependency>

// Java code
Generation gen = new Generation();
GenerationParam param = GenerationParam.builder()
    .apiKey("sk-sp-xxxxx")  // Coding Plan API Key
    .model("qwen-plus")
    .messages(messages)
    .build();
GenerationResult result = gen.call(param);
```

Result: the API returns an InvalidApiKey error, or if it somehow works, it consumes the general quota instead of the Coding Plan quota.

### 2.2 Root Cause

Coding Plan API keys use the OpenAI-compatible protocol, and the endpoint address differs from the general Bailian service:

| Service Type | API Key Format | Endpoint | Model Name |
|-------------|---------------|----------|------------|
| **General Bailian** | `sk-xxxxx` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-plus`, `qwen-max` |
| **Coding Plan** | `sk-sp-xxxxx` | `https://coding.dashscope.aliyuncs.com/v1` | `kimi-k2.5` and others |

The official `dashscope-sdk-java` only supports the general Bailian endpoint — it can't connect to the Coding Plan endpoint at all.

---

## 3. OpenAI-Compatible Mode

### 3.1 How It Works

The Coding Plan endpoint is built on the OpenAI API-compatible protocol. Any client that speaks the OpenAI API can call it:

1. **Python**: Use the `openai` SDK
2. **Java**: Use LangChain4j's `langchain4j-open-ai` module

Point the `base_url` at the Coding Plan endpoint and the API key works as expected.

---

## 4. Java Implementation

### 4.1 Add Dependencies

```xml
<!-- pom.xml -->
<properties>
    <langchain4j.version>0.35.0</langchain4j.version>
</properties>

<dependencies>
    <!-- LangChain4j OpenAI-compatible module -->
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

### 4.2 Configuration

```properties
# application.properties - Coding Plan config
langchain4j.open-ai.chat-model.base-url=https://coding.dashscope.aliyuncs.com/v1
langchain4j.open-ai.chat-model.api-key=sk-sp-xxxxx
langchain4j.open-ai.chat-model.model-name=kimi-k2.5
langchain4j.open-ai.chat-model.temperature=0.3
langchain4j.open-ai.chat-model.max-tokens=4096
```

The critical part: `base-url` must be `coding.dashscope.aliyuncs.com/v1`, not the general `dashscope.aliyuncs.com`.

### 4.3 Java Code

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
        // Build ChatModel using OpenAI-compatible mode
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
            throw new RuntimeException("Empty response from model");
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
                "You are a professional translation assistant",
                "Translate the following to English: Hello World"
        );

        System.out.println(result);
    }
}
```

### 4.4 Spring Boot Integration

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
                "You are a translation expert. Translate from %s to %s. Output the result directly.",
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

## 5. Python Implementation

### 5.1 Install Dependencies

```bash
pip install openai
```

### 5.2 Python Code

```python
from openai import OpenAI

# Use Coding Plan endpoint
client = OpenAI(
    base_url="https://coding.dashscope.aliyuncs.com/v1",
    api_key="sk-sp-xxxxx"
)

response = client.chat.completions.create(
    model="kimi-k2.5",
    messages=[
        {"role": "system", "content": "You are a professional translation assistant"},
        {"role": "user", "content": "Translate the following to English: Hello World"}
    ],
    temperature=0.3,
    max_tokens=4096
)

print(response.choices[0].message.content)
```

### 5.3 Async Example

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
            {"role": "system", "content": "You are a translation expert"},
            {"role": "user", "content": content}
        ]
    )
    return response.choices[0].message.content

# Batch translation
async def batch_translate(contents: list[str]) -> list[str]:
    tasks = [translate_async(c) for c in contents]
    return await asyncio.gather(*tasks)

# Run example
async def main():
    results = await batch_translate(["Hello World", "Artificial Intelligence"])
    print(results)

asyncio.run(main())
```

---

## 6. Practical Use Cases

### 6.1 Job Description Translation

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
            You are a professional job description translator.
            Translate the following job description from %s to %s.

            Requirements:
            1. Preserve the original paragraph structure and formatting
            2. Use industry-standard translations for technical terms
            3. Output the translation directly
            """, sourceLang, targetLang);
    }
}
```

### 6.2 Document Outline Generation

```java
public String generateDocumentOutline(String topic) {
    String prompt = """
        Generate a technical document outline for the following topic:
        Topic: %s

        Requirements:
        1. Clear structure with distinct sections
        2. Each section should have a brief description
        3. Output in Markdown format
        """.formatted(topic);

    List<ChatMessage> messages = Arrays.asList(
        SystemMessage.from("You are a technical writing expert"),
        UserMessage.from(prompt)
    );

    return chatModel.generate(messages).content().text();
}
```

### 6.3 Customer Service Bot

```java
@Service
public class CustomerServiceBot {

    private final ChatLanguageModel chatModel;

    public String handleUserMessage(String userMessage, List<String> history) {
        List<ChatMessage> messages = new ArrayList<>();

        // System prompt
        messages.add(SystemMessage.from("""
            You are a professional customer service assistant helping users with product questions.
            Requirements:
            1. Friendly and professional tone
            2. Concise and clear answers
            3. If unable to answer, guide the user to contact human support
            """));

        // Add conversation history
        for (String h : history) {
            messages.add(UserMessage.from(h));
        }

        // Current message
        messages.add(UserMessage.from(userMessage));

        return chatModel.generate(messages).content().text();
    }
}
```

---

## 7. Key Things to Watch Out For

### 7.1 Don't Mix Up Endpoints

| Key Type | Correct Endpoint | Wrong Endpoint |
|---------|-----------------|----------------|
| `sk-sp-xxxxx` (Coding Plan) | `coding.dashscope.aliyuncs.com/v1` | `dashscope.aliyuncs.com` |
| `sk-xxxxx` (General) | `dashscope.aliyuncs.com/compatible-mode/v1` | `coding.dashscope.aliyuncs.com` |

Mixing them up causes `InvalidApiKey` errors or consumes the wrong quota.

### 7.2 Model Name Differences

Models available on Coding Plan may differ from general Bailian:
- Coding Plan: `kimi-k2.5` and others
- General Bailian: `qwen-plus`, `qwen-max`, `qwen-turbo`

Choose based on what your account actually supports.

### 7.3 Token Consumption Monitoring

Even though you're using Coding Plan quota, keep an eye on:
- Per-call token count
- Remaining Coding Plan balance
- Set reasonable `max_tokens` to avoid overruns

### 7.4 Timeout Settings

Coding Plan response times may differ from the general service. Set a generous timeout:

```java
.timeout(Duration.ofSeconds(60))  // Or longer
```

---

## 8. Summary

| Official Claim | Actual Reality |
|---------------|----------------|
| Coding Plan keys are for programming tools only | Java/Python apps can use them normally |
| Need to provision a separate general key | No extra provisioning needed |
| Per-usage billing incurs extra costs | Directly consumes Coding Plan quota |
| dashscope-sdk-java doesn't work | LangChain4j/OpenAI SDK works fine |

The core principle is simple: the Coding Plan endpoint uses the OpenAI API-compatible protocol, which is an industry-standard LLM API format. Any client that speaks OpenAI protocol can call it — no programming tool restriction applies.

In practice, watch out for endpoint confusion (`coding.dashscope.aliyuncs.com` vs `dashscope.aliyuncs.com`), pick model names from the Coding Plan supported list, and set reasonable timeouts.

---

## 9. References

- [LangChain4j Documentation](https://docs.langchain4j.dev/)
- [OpenAI API Compatible Protocol](https://platform.openai.com/docs/api-reference)
- [Alibaba Bailian Coding Plan](https://bailian.console.aliyun.com/)
