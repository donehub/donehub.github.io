---
title: Context 压缩的四级策略
date: 2026-04-06
tags: Context Compression
categories: Claude Code
---

<!-- more -->

## 上下文窗口是真实存在的硬约束

所有 LLM 都有上下文限制。Claude 3.5 Sonnet 标称 200k tokens，但系统提示词占约 20k，工具定义占约 15k，固定开销就吃掉 35k 左右。留给对话的空间大约 165k tokens，如果每轮对话平均 4k tokens，50 轮就会把窗口用尽。

传统的截断策略粗暴丢弃早期消息，问题很明显：用户说过的重要信息凭空消失，模型可能重复询问已经回答过的问题，或者做出与前文矛盾的判断。长对话场景下，这种信息丢失会直接导致任务失败。

Claude Code 用四级渐进式压缩应对这个问题。四级策略从轻到重依次触发，核心目标是在有限的 token 预算内尽可能保留对任务有用的信息。

## 四级策略概览

| 级别 | 名称 | 触发条件 | 压缩方式 | 信息损失程度 |
|------|------|----------|----------|------------|
| 1 | Snip | 每轮自动 | 去重 + 截断 | 极低 |
| 2 | Micro | 每轮自动 | 原地优化缓存内容 | 无 |
| 3 | Context Collapse | 上下文接近限制 | 渐进式分段摘要 | 低 |
| 4 | Auto Compact | 上下文严重不足 | 模型生成全局摘要 | 中等 |

前两级是常规操作，每轮对话都会执行，压缩幅度小但几乎无损。后两级是应急措施，在 token 压力增大时才介入，代价是不同程度的信息压缩。

## Snip 压缩：去重与截断

Snip 是最轻量的一级，每轮对话结束后自动执行。它的逻辑很直接：遍历已处理的消息，把冗余内容清理掉。

重复出现的文件内容会被替换为引用标记 `[Duplicate file content, see earlier in conversation]`，超长的工具输出只保留前 4KB 并附加截断提示，Base64 图片只保留元数据。

```typescript
function snipMessages(messages: Message[]): Message[] {
  const seen = new Set<string>()

  return messages.map(msg => {
    if (msg.type === 'user') {
      // 检测重复的文件内容，只保留首次出现的完整版本
      const content = extractFileContent(msg)
      if (seen.has(content)) {
        return { ...msg, content: `[Duplicate file content, see earlier in conversation]` }
      }
      seen.add(content)
    }

    if (msg.type === 'tool_result') {
      // 截断过长的工具输出
      if (msg.content.length > MAX_TOOL_RESULT_SIZE) {
        return {
          ...msg,
          content: msg.content.slice(0, MAX_TOOL_RESULT_SIZE) +
            `\n... [truncated, ${msg.content.length} total chars]`
        }
      }
    }

    return msg
  })
}
```

在典型的编码会话中，同一个文件可能被多次读取（修改后再读、对比不同版本等），Snip 把这些重复的文件内容去重，只保留第一次出现的完整版本。这一步的 token 回收效率相当高，实测在 30 轮以上的长对话中，Snip 单级就能回收 15-25% 的消息体积。

## Micro 压缩：不动缓存键的原地优化

Micro 压缩处理的是消息内容的文本层面。它对已缓存的消息进行二次整理，移除多余的空白字符、重复的 tool_use 说明等。

```typescript
function microCompactMessages(messages: Message[]): Message[] {
  return messages.map(msg => {
    if (msg.type === 'assistant') {
      const compressed = compressContent(msg.content)
      const deduped = deduplicateToolUses(compressed)
      return { ...msg, content: deduped }
    }
    return msg
  })
}
```

这个设计的关键约束在于：缓存键基于消息 ID 和位置计算，不基于内容。Micro 压缩改变了消息内容，但缓存键不变，下一次 API 请求仍然能命中缓存。这意味着 Micro 压缩在不破坏 prompt caching 的前提下完成了 token 节省，两者互不干扰。

## Context Collapse：渐进式摘要

当上下文逼近限制，前两级已经不够用，系统启动 Context Collapse。这个机制的核心思路是分阶段摘要历史消息，优先处理最旧的部分，保留最近消息的完整细节。

```typescript
async function contextCollapse(
  messages: Message[],
  options: CollapseOptions
): Promise<Message[]> {
  // 识别可折叠的消息段，按时间从旧到新排序
  const segments = identifyCollapsibleSegments(messages)
  const sortedSegments = segments.sort((a, b) => a.startIndex - b.startIndex)

  // 对每个段生成摘要，渐进式替换原消息
  const summaries: Message[] = []
  for (const segment of sortedSegments) {
    if (shouldCollapse(segment, options)) {
      const summary = await generateSummary(segment.messages)
      summaries.push(createSummaryMessage(summary, segment))
    }
  }

  return replaceSegmentsWithSummaries(messages, summaries)
}
```

假设模型上下文限制是 200k tokens，折叠过程分多个阈值推进：

```
原消息序列：
[Msg1] [Msg2] [Msg3] [Msg4] [Msg5] [Msg6] [Msg7] [Msg8] [Msg9] [Msg10]

第一次折叠（上下文 > 150k）：
[Summary1] [Msg6] [Msg7] [Msg8] [Msg9] [Msg10]
  ↑ 摘要 Msg1-Msg5

第二次折叠（上下文 > 180k）：
[Summary1] [Summary2] [Msg8] [Msg9] [Msg10]
            ↑ 摘要 Msg6-Msg7

第三次折叠（上下文 > 195k）：
[Summary1] [Summary2] [Summary3] [Msg10]
                           ↑ 摘要 Msg8-Msg9
```

越旧的消息被摘要得越早、压缩率越高，越近的消息保留的原始细节越多。这符合编码任务的信息衰减规律：半小时前的架构决策比十分钟前的代码细节更需要被记住。

摘要格式有固定模板，要求保留四类关键信息：已完成的任务列表、修改过的文件路径及变更内容、当前系统状态、未完成的待办事项。这个模板设计决定了压缩后的上下文能否支撑模型继续工作。

```markdown
## Summary of Previous Work

### Tasks Completed
- Implemented user authentication with JWT
- Added password reset functionality

### Files Modified
- src/auth/auth.service.ts: Added JWT token generation
- src/user/user.controller.ts: Added profile endpoints

### Current State
- Authentication system is fully functional

### Pending Items
- Need to add email verification
- Need to implement rate limiting
```

## Auto Compact：最后的全局摘要

当 token 使用率超过 90% 且距离上次 compact 已经超过最小间隔轮数，系统触发 Auto Compact。这是最后一级，用 Claude 自身生成一段完整的对话摘要，替换所有历史消息。

```typescript
async function autoCompact(
  messages: Message[],
  context: ToolUseContext
): Promise<Message[]> {
  const compactPrompt = buildCompactPrompt(messages)

  // 用专门的系统提示词调用 Claude 生成摘要
  const summary = await query({
    messages: [createUserMessage(compactPrompt)],
    systemPrompt: COMPACT_SYSTEM_PROMPT,
    toolUseContext: context,
    maxTurns: 1,
  })

  return [createSummaryMessage(summary)]
}
```

触发条件有三个：token 使用率超过 90%、尚未尝试过本轮 compact、距离上次 compact 已超过最小间隔。三个条件缺一不可，防止频繁触发导致信息过度压缩。

```typescript
function shouldTriggerAutoCompact(state: AutoCompactTracking): boolean {
  const usageRatio = state.currentTokens / state.maxTokens
  if (usageRatio < 0.9) return false
  if (state.hasAttemptedAutoCompact) return false
  if (state.turnsSinceLastCompact < MIN_TURNS_BETWEEN_COMPACT) return false
  return true
}
```

Auto Compact 使用的系统提示词要求摘要保留五类信息：对话概述、关键决策及其理由、修改的文件列表、待完成任务、继续工作所需的上下文。这些信息是模型在新上下文窗口中维持任务连续性的最低要求。

## 恢复链：四级策略的协作

四级压缩并非独立运行，而是组成一条恢复链。当 `prompt_too_long` 错误发生时，系统从轻到重依次尝试：

```
prompt_too_long 错误
  │
  ├─ 尝试 Snip 压缩 → 重试
  │   └─ 成功 → 继续对话
  │
  ├─ 尝试 Micro 压缩 → 重试
  │   └─ 成功 → 继续对话
  │
  ├─ 尝试 Context Collapse → 重试
  │   └─ 成功 → 继续对话
  │
  └─ 尝试 Auto Compact → 重试
      └─ 成功 → 继续对话
      └─ 失败 → 报错给用户
```

每一级都是下一级的前置条件。大多数情况下，Snip 和 Micro 就能回收足够的空间。只有当对话特别长、前两级回收的空间不足以放下新消息时，才会触发 Context Collapse 甚至 Auto Compact。

## Token 预算管理

每次 API 调用前，系统计算当前可用的 token 预算：

```typescript
function calculateTokenBudget(
  model: string, messages: Message[],
  systemPrompt: string, tools: Tools,
): TokenBudget {
  const contextLimit = getModelContextLimit(model)
  const fixedCost = countTokens(systemPrompt) + countToolsTokens(tools)
  const messagesTokens = countMessagesTokens(messages)
  const outputReserve = 8192

  return {
    total: contextLimit,
    fixed: fixedCost,
    messages: messagesTokens,
    available: contextLimit - fixedCost - messagesTokens - outputReserve,
  }
}
```

可用预算等于模型上下文限制减去固定开销、当前消息消耗和输出预留（默认 8192 tokens）。根据消息消耗占比，系统分三级发出警告：70% 以下为正常，85% 以上进入 warning 状态，95% 以上触发 critical。这些阈值与压缩策略的触发时机对应。

## 上下文注入

除了压缩，上下文的构成也值得了解。系统在每轮对话中注入两类上下文：系统上下文包含 Git 状态（当前分支、最近提交、文件变更）和当前日期；用户上下文包含 CLAUDE.md 合并内容、MCP 服务器指令和记忆系统内容。

系统提醒以 `<system-reminder>` 标签的形式注入到工具返回结果或用户消息中，用于传递文件安全警告、记忆时效提示、Deferred 工具可用通知等信息。这种注入方式让系统信息自然嵌入消息流，不需要额外的通信通道。

## 关键源文件

| 文件 | 职责 |
|------|------|
| `src/services/compact/autoCompact.ts` | 自动压缩触发和管理 |
| `src/services/compact/compact.ts` | 压缩实现 |
| `src/services/compact/reactiveCompact.ts` | 反应式压缩（错误触发） |
| `src/services/contextCollapse/index.ts` | 上下文折叠实现 |
| `src/services/compact/snipCompact.ts` | Snip 压缩 |
| `src/utils/tokens.ts` | Token 计数和预算管理 |
| `src/context.ts` | 系统和用户上下文 |
| `src/utils/attachments.ts` | 系统提醒附件 |

---

**系列文章导航：**
- 上一篇：[多 Agent 编排：四种代理类型与协作机制](/2026/04/06/082_claude-code-multi-agent/)
- 下一篇：[System Prompt 工程：动态组装与缓存优化](/2026/04/06/085_claude-code-system-prompt/)
