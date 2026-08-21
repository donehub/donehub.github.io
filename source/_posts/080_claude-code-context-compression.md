---
title: Context 管理：四级压缩与无限对话的秘密
date: 2026-04-06
tags: Context Compression
categories: Claude Code
---

> "对话没有上下文限制"——这是 Claude Code 的一个核心承诺。但它真的能做到吗？答案是：通过四级压缩系统，实现"伪无限对话"。这背后的设计非常精妙：不是简单截断，而是智能地压缩和保留关键信息。

<!-- more -->

## 导读：上下文限制的困境

所有 LLM 都有上下文限制。Claude 3.5 Sonnet 是 200k tokens，但实际可用空间更小，因为：
- 系统提示词占用 ~20k tokens
- 工具定义占用 ~15k tokens
- 每轮对话累积消息

假设你进行了 50 轮对话，每轮平均 4k tokens，那就是 200k tokens —— 已经触及限制。

**传统解决方案**：简单截断历史消息。但问题很明显：
- 用户之前的重要信息被丢弃
- Agent 可能重复问同样的问题
- 长期任务上下文丢失

**Claude Code 的方案**：四级渐进式压缩。

---

## 一、四级压缩策略概览

```
┌─────────────────────────────────────────────────────────────┐
│                    四级压缩策略                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  第 1 级：Snip 压缩                                          │
│    对已处理的消息进行智能裁剪                                │
│    ├─ 移除重复的文件内容                                    │
│    ├─ 截断过长的工具输出                                    │
│    └─ 触发时机：每轮自动                                    │
│                                                             │
│  第 2 级：Micro 压缩                                         │
│    修改已缓存消息的内容                                     │
│    ├─ 不改变缓存键                                          │
│    └─ 触发时机：每轮自动                                    │
│                                                             │
│  第 3 级：上下文折叠（Context Collapse）                     │
│    分阶段摘要历史消息                                       │
│    ├─ 先摘要最旧的消息                                      │
│    ├─ 保留最近的细节                                        │
│    └─ 触发时机：上下文接近限制                              │
│                                                             │
│  第 4 级：Auto Compact                                       │
│    通过 Claude 生成完整摘要                                 │
│    ├─ 替换所有历史消息                                      │
│    └─ 触发时机：上下文严重不足                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 二、第一级：Snip 压缩

### 2.1 工作原理

Snip 压缩对已处理的消息进行智能裁剪——移除重复的文件内容、过长的工具输出等。

```typescript
// src/services/compact/snipCompact.ts
function snipMessages(messages: Message[]): Message[] {
  const seen = new Set<string>()
  
  return messages.map(msg => {
    if (msg.type === 'user') {
      // 检测重复的文件内容
      const content = extractFileContent(msg)
      if (seen.has(content)) {
        // 重复内容，替换为引用
        return {
          ...msg,
          content: `[Duplicate file content, see earlier in conversation]`
        }
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

### 2.2 智能裁剪规则

| 内容类型 | 裁剪策略 |
|----------|----------|
| 重复文件内容 | 替换为引用标记 |
| 大型工具输出 | 保留前 4KB + 截断标记 |
| Base64 图片 | 保留元数据，替换内容 |
| 长对话引用 | 摘要化 |

---

## 三、第二级：Micro 压缩

### 3.1 工作原理

Micro 压缩修改已缓存消息的内容，而不改变缓存键。这是一种"原地优化"策略。

```typescript
// src/services/compact/microCompact.ts
function microCompactMessages(messages: Message[]): Message[] {
  return messages.map(msg => {
    if (msg.type === 'assistant') {
      // 移除多余的空白和格式
      const compressed = compressContent(msg.content)
      
      // 移除重复的 tool_use 说明
      const deduped = deduplicateToolUses(compressed)
      
      return { ...msg, content: deduped }
    }
    return msg
  })
}
```

### 3.2 关键特性

- **不影响缓存**：缓存键基于消息 ID 和位置，不基于内容
- **无损压缩**：保留所有语义信息
- **增量应用**：每次处理一点点，避免大变动

---

## 四、第三级：上下文折叠（Context Collapse）

### 4.1 工作原理

当上下文接近限制时，系统启动 Context Collapse —— 将历史消息分阶段摘要。

```typescript
// src/services/contextCollapse/index.ts
async function contextCollapse(
  messages: Message[],
  options: CollapseOptions
): Promise<Message[]> {
  // 1. 识别可折叠的消息段
  const segments = identifyCollapsibleSegments(messages)
  
  // 2. 按优先级排序（最旧的优先）
  const sortedSegments = segments.sort((a, b) => 
    a.startIndex - b.startIndex
  )
  
  // 3. 对每个段生成摘要
  const summaries: Message[] = []
  for (const segment of sortedSegments) {
    if (shouldCollapse(segment, options)) {
      const summary = await generateSummary(segment.messages)
      summaries.push(createSummaryMessage(summary, segment))
    }
  }
  
  // 4. 替换原消息段
  return replaceSegmentsWithSummaries(messages, summaries)
}
```

### 4.2 折叠策略

**渐进式折叠**：不是一次性摘要全部，而是**渐进式折叠**——先摘要最旧的消息，保留最近的细节。

```
原消息序列：
[Msg1] [Msg2] [Msg3] [Msg4] [Msg5] [Msg6] [Msg7] [Msg8] [Msg9] [Msg10]
  ↑                                                           ↑
  最旧                                                        最新

第一次折叠（上下文 > 150k）：
[Summary1] [Msg6] [Msg7] [Msg8] [Msg9] [Msg10]
  ↑ 摘要了 Msg1-Msg5

第二次折叠（上下文 > 180k）：
[Summary1] [Summary2] [Msg8] [Msg9] [Msg10]
                        ↑ 摘要了 Msg6-Msg7

第三次折叠（上下文 > 195k）：
[Summary1] [Summary2] [Summary3] [Msg10]
                                  ↑ 摘要了 Msg8-Msg9
```

### 4.3 摘要格式

```markdown
## Summary of Previous Work

### Tasks Completed
- Implemented user authentication with JWT
- Added password reset functionality
- Created user profile page

### Files Modified
- src/auth/auth.service.ts: Added JWT token generation
- src/user/user.controller.ts: Added profile endpoints
- src/user/user.service.ts: Added password reset logic

### Current State
- Authentication system is fully functional
- Password reset emails are being sent
- Profile page is accessible at /profile

### Pending Items
- Need to add email verification
- Need to implement rate limiting
```

---

## 五、第四级：Auto Compact

### 5.1 工作原理

当所有局部优化都不够时，通过 Claude 自身生成一个完整的对话摘要，替换所有历史消息。

```typescript
// src/services/compact/autoCompact.ts
async function autoCompact(
  messages: Message[],
  context: ToolUseContext
): Promise<Message[]> {
  // 1. 构建 compact 请求
  const compactPrompt = buildCompactPrompt(messages)
  
  // 2. 调用 Claude 生成摘要
  const summary = await query({
    messages: [createUserMessage(compactPrompt)],
    systemPrompt: COMPACT_SYSTEM_PROMPT,
    toolUseContext: context,
    maxTurns: 1,
  })
  
  // 3. 创建新的消息序列
  const summaryMessage = createSummaryMessage(summary)
  
  // 4. 替换历史消息
  return [summaryMessage]
}
```

### 5.2 触发条件

```typescript
// src/services/compact/autoCompact.ts
function shouldTriggerAutoCompact(state: AutoCompactTracking): boolean {
  // 1. 检查 token 使用率
  const usageRatio = state.currentTokens / state.maxTokens
  if (usageRatio < 0.9) return false  // 低于 90% 不触发
  
  // 2. 检查是否已经尝试过
  if (state.hasAttemptedAutoCompact) return false
  
  // 3. 检查距离上次 compact 的轮数
  if (state.turnsSinceLastCompact < MIN_TURNS_BETWEEN_COMPACT) return false
  
  return true
}
```

### 5.3 Compact 系统提示词

```typescript
const COMPACT_SYSTEM_PROMPT = `
You are a summarization assistant. Your job is to create a concise but 
complete summary of a conversation.

Your summary should:
1. Capture all important decisions and their reasoning
2. List all files that were created or modified
3. Note any pending tasks or open questions
4. Preserve the context needed to continue the work

Format your summary as:
## Summary
[Brief overview of the conversation]

## Decisions Made
- [Decision 1]: [Reasoning]
- [Decision 2]: [Reasoning]

## Files Modified
- [File path]: [What was changed]

## Pending Tasks
- [Task 1]
- [Task 2]

## Context for Continuation
[Any other relevant context]
`
```

---

## 六、上下文注入

### 6.1 系统上下文

每次 API 调用前，自动注入系统上下文：

```typescript
// src/context.ts
function getSystemContext(): SystemContext {
  return {
    gitStatus: getGitStatus(),          // 当前分支、最近提交、文件状态
    currentDate: new Date().toISOString(),
    cacheBreakerInjection: getSystemInjection(),
  }
}
```

### 6.2 用户上下文

```typescript
// src/context.ts
function getUserContext(): UserContext {
  return {
    claudeMdContent: loadClaudeMdFiles(),  // 所有 CLAUDE.md 合并内容
    mcpInstructions: getMcpInstructions(),  // MCP 服务器指令
    memoryContent: loadMemoryPrompt(),      // 记忆系统内容
  }
}
```

### 6.3 系统提醒

系统提醒是一种特殊的**附件消息**，注入到工具结果或用户消息中：

```xml
<system-reminder>
  这里是系统级的上下文信息，与具体的工具结果无关。
</system-reminder>
```

用途包括：
- 文件读取时的安全警告
- 记忆系统的时效提醒
- 用户侧问的附带信息
- Deferred 工具的可用通知

---

## 七、Token 预算管理

### 7.1 预算计算

```typescript
// src/query/tokenBudget.ts
function calculateTokenBudget(
  model: string,
  messages: Message[],
  systemPrompt: string,
  tools: Tools,
): TokenBudget {
  // 1. 获取模型上下文限制
  const contextLimit = getModelContextLimit(model)  // 如 200k
  
  // 2. 计算固定消耗
  const systemPromptTokens = countTokens(systemPrompt)
  const toolsTokens = countToolsTokens(tools)
  const fixedCost = systemPromptTokens + toolsTokens
  
  // 3. 计算消息消耗
  const messagesTokens = countMessagesTokens(messages)
  
  // 4. 计算可用预算
  const availableBudget = contextLimit - fixedCost - messagesTokens
  
  // 5. 预留输出空间
  const outputReserve = 8192  // 默认输出限制
  const finalBudget = availableBudget - outputReserve
  
  return {
    total: contextLimit,
    fixed: fixedCost,
    messages: messagesTokens,
    available: finalBudget,
  }
}
```

### 7.2 预算警告

```typescript
// src/utils/tokens.ts
function calculateTokenWarningState(budget: TokenBudget): TokenWarningState {
  const usageRatio = budget.messages / budget.available
  
  if (usageRatio > 0.95) {
    return { level: 'critical', message: 'Context nearly exhausted' }
  }
  if (usageRatio > 0.85) {
    return { level: 'warning', message: 'Context running low' }
  }
  if (usageRatio > 0.70) {
    return { level: 'info', message: 'Context usage moderate' }
  }
  return { level: 'ok', message: '' }
}
```

---

## 八、恢复与压缩的关系

### 8.1 压缩触发的恢复

当压缩策略执行后，会记录状态：

```typescript
state = {
  ...state,
  autoCompactTracking: {
    hasAttemptedAutoCompact: true,
    turnsSinceLastCompact: 0,
    compressedTokens: savedTokens,
  },
  transition: { reason: 'reactive_compact_retry' }
}
```

### 8.2 恢复链

```
prompt_too_long 错误
  │
  ├─ 尝试 Snip 压缩 → 重试
  │   └─ 成功 → 继续
  │
  ├─ 尝试 Micro 压缩 → 重试
  │   └─ 成功 → 继续
  │
  ├─ 尝试 Context Collapse → 重试
  │   └─ 成功 → 继续
  │
  └─ 尝试 Auto Compact → 重试
      └─ 成功 → 继续
      └─ 失败 → 报错给用户
```

---

## 九、关键源文件索引

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

## 十、总结

Claude Code 的四级压缩系统是其"无限对话"承诺的技术基础：

1. **Snip 压缩**：智能移除重复内容，每轮自动
2. **Micro 压缩**：原地优化缓存消息，不影响缓存
3. **Context Collapse**：渐进式摘要，保留最近细节
4. **Auto Compact**：Claude 生成的完整摘要

这个设计的关键洞察是：**不是简单截断，而是智能压缩**。通过保留关键信息（决策、文件修改、待办事项），Agent 能够在压缩后继续有效工作。

---

**系列文章导航：**
- 上一篇：[多 Agent 编排：四种代理类型与协作机制](/claude-code-multi-agent/)
- 下一篇：[System Prompt 工程：动态组装与缓存优化](/claude-code-system-prompt/)