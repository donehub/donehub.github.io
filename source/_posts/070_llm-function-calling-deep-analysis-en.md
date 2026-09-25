---
title: LLM Function Calling — Under the Hood
date: 2026-03-21
categories: Function Calling
tags: [AI]
lang: en
label: 070_llm-function-calling-deep-analysis
---

When describing how Function Calling works, many people say the model "reads" the user's intent, "determines" it needs to call a tool, then "decides" to generate a call instruction. This explanation is popular, but words like "reads," "determines," and "decides" are misleading — they imply the model possesses some understanding ability, as if it's actually thinking. An LLM's nature has never changed: it's Next Token Prediction. Function Calling doesn't introduce any mysterious reasoning mechanism. It just teaches the model to switch output formats under specific conditions — from natural language to structured JSON text.

<!-- more -->
---

## Core Mechanism

Whether Function Calling is enabled or not, the model's computation is identical: input goes through Transformer computation, generates a probability distribution across the entire vocabulary, samples the next Token. The only difference with Function Calling enabled is that the model's vocabulary includes a few special Tokens, and the training data includes tool-calling-related samples. The model itself hasn't gained any new reasoning capability.

A fitting analogy is training a parrot to talk. In normal mode, you teach it "hello," "thank you," "goodbye" — it learns to say these in appropriate contexts. In Function Calling mode, you additionally teach it a set of signals: when it hears "what time is it," output `[CALL:get_time]`. The parrot doesn't know what "what time is it" means, nor does `get_time` actually fetch the time — it just learned that hearing X means saying Y. The model is exactly the same: it learned to output a specific format of text under specific contexts, and that text happens to be a JSON-formatted tool call instruction.

## Two-Phase Training

The model learns Function Calling through two training phases. The first is SFT (Supervised Fine-Tuning), teaching the model three things through extensive labeled samples: when to switch output mode, how to write the call instruction, how to handle tool return results.

| What to Learn | Training Sample Example |
|---------|-------------|
| When to switch output mode | User asks "How's the weather today?" → Model outputs `[tool_call]` start tag |
| How to write the call instruction | `[tool_call]{"name": "get_weather", "args": {"city": "Beijing"}}[tool_call_end]` |
| How to handle tool return results | Tool returns `{"temp": 25, "condition": "sunny"}` → Model outputs "It's sunny in Beijing today, 25 degrees" |

The training data structure looks roughly like this:

```json
{
  "messages": [
    {"role": "user", "content": "How's the weather in Beijing today?"},
    {"role": "assistant", "content": "[tool_call]{\"name\": \"get_weather\", \"args\": {\"city\": \"Beijing\"}}[/tool_call]"},
    {"role": "tool", "content": "{\"temp\": 25, \"condition\": \"sunny\"}"},
    {"role": "assistant", "content": "It's sunny in Beijing today, 25 degrees."}
  ]
}
```

Through numerous samples like this, the model learns a pattern-matching rule: when the user's question involves a callable tool, output the `[tool_call]` tag and JSON-formatted call instruction.

SFT teaches the model the basic operation, but many edge cases need fine-tuning — like not calling when it should, calling when it shouldn't, filling parameters wrong, calling the wrong tool. These problems are addressed in the second phase, RL (Reinforcement Learning): correct calling behavior gets reward reinforcement, incorrect behavior gets suppressed, and parameter generation and tool selection accuracy are both improved in this phase. RL's core value is teaching the model a sense of proportion — knowing when to call and when not to.

## Special Token Design

A key Function Calling design choice is adding special Tokens to the vocabulary: `[tool_call]` for tool call start, `[/tool_call]` for end, `[tool_result]` for tool return results. These aren't regular text — they're signals specifically designed for external system recognition.

| Without Special Tokens | With Special Tokens |
|---------------|---------------|
| Model outputs `get_weather(Beijing)` | Model outputs `[tool_call]{"name":"get_weather"}[/tool_call]` |
| External system must parse natural language | External system just detects `[tool_call]` tag |
| Parsing is error-prone and ambiguous | Parsing is simple and deterministic |

The essential purpose of special Tokens is giving external systems a deterministic signal. When the model outputs `[tool_call]`, the external system knows the following text needs to be intercepted, parsed, and executed. Different vendors use different tag formats, but the core logic is identical.

| Vendor | Start Tag | End Tag |
|-----|---------|---------|
| OpenAI | `<function_call>` | `</function_call>` |
| Claude | `<tool_use>` | `</tool_use>` |
| Some domestic models | `[TOOL_CALL]` | `[/TOOL_CALL]` |

## How Probability Determines Output

When generating each Token, the model computes a probability distribution across the entire vocabulary. Say the vocabulary has 50,000 Tokens — the model computes each Token's probability given the current context. Take the user asking "How's the weather in Beijing today?" — if the system prompt includes a `get_weather` tool description, the `[tool_call]` Token's probability might be pushed to around 0.45, far above other candidates, so the model outputs it.

Context's influence on probability distribution is strong. The same weather question: with `get_weather` in the tool list, `[tool_call]` probability spikes; with an empty tool list, natural language Tokens like "today" have higher probability; when the user says "hello," `[tool_call]` probability stays low. This is where tool descriptions matter: they get injected into the context, which is essentially adjusting the probability distribution, making the model more likely to output a tool call under specific conditions. Keywords in tool descriptions about applicable scenarios, when matched with trigger words in the user's question, push the corresponding `[tool_call]` Token's probability higher.

The model isn't actively deciding to call a tool. The probability computation just happens to result in `[tool_call]`, that's all.

## External Execution Mechanism

The model itself doesn't execute functions — it only generates text. This is the most commonly misunderstood aspect of Function Calling. The complete execution flow: user asks a question, model outputs JSON text containing the `[tool_call]` marker; external system detects this marker, intercepts and parses the JSON, executes the corresponding function call; function return results (like `{"temp": 25, "condition": "sunny"}`) get injected back into the context; model sees the tool result and generates the final natural language answer.

| Internal Execution | External Execution |
|-------------|---------|
| Model needs to know all tool implementation details | Model only needs tool descriptions and parameter formats |
| Adding tools requires retraining the model | Adding tools just needs updating descriptions, no retraining |
| High security risk, model might execute dangerous operations | External system can do permission control and auditing |
| Can't handle real-time data | External system can query latest data |

External execution keeps the responsibility boundary very clear: the model is only responsible for saying, the external system is responsible for doing.

## Four Failure Modes

The model will make mistakes. There are four common failure patterns. First is calling the wrong tool — user asks for tomorrow's stock market forecast, model calls `get_weather`; usually the tool description isn't clear enough or the model's understanding of the tool's purpose is off. Second is wrong parameters — like mixing up departure and destination when booking a flight; parameter filling is based on contextual semantic understanding, not precise logical reasoning. Third is not calling when it should — user asks what time it is, tool list has `get_current_time`, but the model makes up an answer; often because the tool description isn't prominent enough, or the model is overconfident it knows the answer. Fourth is calling when it shouldn't — user wants to hear a story about time, model sees "time" and triggers a tool call.

| Failure Mode | Typical Cause | Mitigation |
|---------|---------|---------|
| Wrong tool called | Unclear tool description | Optimize tool descriptions, add examples |
| Wrong parameters | Semantic understanding drift | Parameter validation, add constraints |
| Should call but didn't | Model overconfidence | Prompt guidance, RL optimization |
| Called when shouldn't | Overly eager triggering | Add applicable scenario notes to tool descriptions |

## Vendor Implementation Differences

Function Calling's core mechanism is the same across vendors; differences are mainly in implementation details.

Special Token design: OpenAI and Claude both use XML-style tags, readable and easy to parse; Claude also supports parallel multi-tool calls. Some domestic models use bracket-style tags, more consistent with system prompt formatting.

Tool description injection methods also differ. Placing them in the System Prompt is flexible and easy to debug but consumes context window; a dedicated `tools` field in the API has clear structure and is easy to manage but requires additional parsing; hybrid approaches cover both but can have conflicts. Tool description quality and placement directly affect the model's tool call probability judgment — it's the highest-ROI area for engineering optimization.

Parallel call capability: OpenAI supports returning multiple tool call results in one response; some models only support serial, requiring one tool call result before deciding whether to call the next. Additionally, the `tool_choice` parameter provides call control granularity: `auto` lets the model decide, `required` forces a call, `none` prohibits calls, specifying a function name forces that specific tool.

Understanding Function Calling's underlying mechanics has a major practical payoff: it shifts your debugging approach. When tool calls fail, analyzing from a probability perspective is more effective than analyzing from an understanding perspective. Is the tool description influential enough to shift the probability distribution? Is there interfering information in the context lowering `[tool_call]`'s probability? The answers to these questions point directly to optimization directions — much more useful than vaguely saying "the model's understanding is off."

---

**References**:
- [OpenAI Function Calling Guide](https://platform.openai.com/docs/guides/function-calling)
- [Anthropic Tool Use Documentation](https://docs.anthropic.com/claude/docs/tool-use)
- [How Does Function Calling Work? - Deep Dive](https://www.anthropic.com/research/function-calling)
