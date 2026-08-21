---
title: System Prompt 工程：动态组装与缓存优化
date: 2026-04-06
tags: System Prompt
categories: Claude Code
---

> Claude Code 的系统提示词不是一个静态字符串，而是一个动态组装的管道。通过分层构建、缓存边界、Section 类型等设计，实现了跨会话的缓存复用，大幅降低了延迟和成本。这是 Prompt 工程的教科书级案例。

<!-- more -->

## 导读：系统提示词的挑战

系统提示词是 Agent 的"操作系统"——它定义了 Agent 的角色、规则、能力和约束。但系统提示词面临几个挑战：

**挑战一：长度**
Claude Code 的系统提示词约 20k tokens，每次 API 调用都要发送。

**挑战二：动态性**
系统提示词需要包含：
- 当前日期
- 项目结构
- Git 状态
- MCP 服务器指令
- 用户自定义指令（CLAUDE.md）

这些内容会变化，无法静态缓存。

**挑战三：优先级**
多个来源的指令需要按优先级合并：
- 用户全局指令
- 项目级指令
- 本地私有指令

Claude Code 的解决方案：**分层管道 + 缓存边界 + Section 类型**。

---

## 一、分层构建架构

### 1.1 提示词管道

系统提示词通过分层管道动态组装：

```
┌─────────────────────────────────────────────────────────────┐
│                    静态可缓存区域                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ 角色定义  │  系统规则  │  任务指导  │  工具说明  │  风格  │  │
│  └───────────────────────────────────────────────────────┘  │
├─────────────────────── 缓存边界 ────────────────────────────┤
│                    动态可变区域                                │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ 会话指引 │ 记忆系统 │ 环境信息 │ MCP 指令 │ Token 预算 │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 缓存边界

```typescript
// src/constants/prompts.ts:114-116
export const SYSTEM_PROMPT_DYNAMIC_BOUNDARY =
  '__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__'
```

**缓存边界的作用**：
- **边界之上**：跨用户、跨组织通用的内容，使用 `scope: 'global'` 缓存
- **边界之下**：用户/会话特定的内容，使用 `scope: 'ephemeral'` 缓存

这意味着 Claude Code 的系统提示词**不需要每次都重新处理**——静态部分在全球范围内共享缓存，大幅降低延迟和成本。

---

## 二、两种 Section 类型

### 2.1 缓存 Section

计算一次，整个会话复用：

```typescript
// src/constants/systemPromptSections.ts
systemPromptSection('memory', async () => {
  return buildMemoryLines()  // 读取 CLAUDE.md、记忆文件等
}, { scope: 'ephemeral' })  // 会话级缓存
```

### 2.2 缓存破坏 Section

每轮重新计算：

```typescript
// src/constants/systemPromptSections.ts
DANGEROUS_uncachedSystemPromptSection('mcp_instructions', async () => {
  return getMcpInstructions()  // MCP 服务器可能中途连接/断开
}, 'MCP servers can connect/disconnect mid-session')
```

**何时使用缓存破坏 Section**：
- MCP 指令：服务器可能动态连接/断开
- 当前日期：每轮都不同
- Git 状态：可能快速变化
- Token 预算：每轮重新计算

---

## 三、优先级解析链

### 3.1 系统提示词优先级

最终的系统提示词通过 `buildEffectiveSystemPrompt()` 按优先级决定：

```
Override System Prompt     ← 最高优先级，完全替换
  ↓
Coordinator System Prompt  ← 协调者模式专用
  ↓
Agent System Prompt        ← agentDefinition.getSystemPrompt()
  ↓                          - proactive 模式：追加到默认
  ↓                          - 其他：替换默认
Custom System Prompt       ← --system-prompt 参数
  ↓
Default System Prompt      ← Claude Code 标准提示词
  ↓
Append System Prompt       ← 始终追加到末尾
```

### 3.2 代码实现

```typescript
// src/utils/systemPrompt.ts:41-123
export async function buildEffectiveSystemPrompt(
  options: BuildSystemPromptOptions,
): Promise<SystemPrompt> {
  const sections: SystemPromptSection[] = []
  
  // 1. 检查 Override
  if (options.overrideSystemPrompt) {
    return asSystemPrompt(options.overrideSystemPrompt)
  }
  
  // 2. 检查 Coordinator
  if (isCoordinatorMode() && options.coordinatorSystemPrompt) {
    return asSystemPrompt(options.coordinatorSystemPrompt)
  }
  
  // 3. 构建 Section 序列
  const defaultSections = await buildDefaultSections()
  sections.push(...defaultSections)
  
  // 4. 处理 Agent 提示词
  if (options.agentDefinition?.getSystemPrompt) {
    const agentPrompt = await options.agentDefinition.getSystemPrompt(options)
    if (options.agentDefinition.promptMode === 'proactive') {
      // 追加到默认提示词后
      sections.push({ type: 'text', text: agentPrompt })
    } else {
      // 替换默认提示词
      return asSystemPrompt(agentPrompt)
    }
  }
  
  // 5. 追加 Custom 和 Append
  if (options.customSystemPrompt) {
    sections.push({ type: 'text', text: options.customSystemPrompt })
  }
  if (options.appendSystemPrompt) {
    sections.push({ type: 'text', text: options.appendSystemPrompt })
  }
  
  return resolveSystemPromptSections(sections)
}
```

---

## 四、CLAUDE.md 加载机制

### 4.1 加载优先级

CLAUDE.md 是用户自定义指令系统，按优先级从低到高加载：

```
/etc/claude-code/CLAUDE.md          ← 全局管理配置（最低优先级）
  ↓
~/.claude/CLAUDE.md                 ← 用户全局指令
  ↓
项目根目录/CLAUDE.md                 ← 项目级指令
项目根目录/.claude/CLAUDE.md
项目根目录/.claude/rules/*.md
  ↓
项目根目录/CLAUDE.local.md           ← 本地私有指令（最高优先级）
```

### 4.2 递归引用

支持 `@path` 语法递归引用其他文件：

```markdown
# 项目配置

## 编码规范
@./docs/coding-standards.md

## API 文档
@./docs/api-spec.md
```

### 4.3 循环引用检测

```typescript
// src/utils/claudemd.ts
async function loadClaudeMdFile(
  path: string,
  visited: Set<string> = new Set(),
): Promise<string> {
  // 检测循环引用
  if (visited.has(path)) {
    console.warn(`Circular reference detected: ${path}`)
    return ''
  }
  visited.add(path)
  
  let content = await readFile(path, 'utf-8')
  
  // 处理 @path 引用
  const references = extractReferences(content)
  for (const ref of references) {
    const refPath = resolveReference(path, ref)
    const refContent = await loadClaudeMdFile(refPath, visited)
    content = content.replace(`@${ref}`, refContent)
  }
  
  return content
}
```

---

## 五、Agent 特有的提示词增强

### 5.1 环境详情注入

子代理会额外注入环境详情：

```typescript
// src/tools/AgentTool/runAgent.ts
function getAgentSystemPrompt(agentDef, toolUseContext) {
  let prompt = agentDef.getSystemPrompt({ toolUseContext })
  prompt = enhanceSystemPromptWithEnvDetails(prompt)
  // 添加：工作目录、启用工具列表、模型信息、环境变量
  return prompt
}
```

### 5.2 Fork 约束注入

Fork Agent 会注入行为约束：

```typescript
const FORK_BOILERPLATE_TAG = `
You are a forked worker process. Your job is to execute tasks efficiently.

CRITICAL RULES:
1. You are NOT the main agent. Do not engage in conversation or ask follow-up questions.
2. Use tools directly (Bash, Read, Write, etc.) to complete your assigned task.
3. If you modify files, commit your changes before reporting.
4. Do NOT output text between tool calls - just use tools.
5. Stay strictly within the scope of your directive.
6. Keep your final report under 500 words.
7. Your response MUST start with "Scope:" followed by what you accomplished.
`
```

---

## 六、缓存策略详解

### 6.1 三级缓存

```
Global Cache（跨组织）    ← 静态系统提示词
  ↓  scope: 'global'
Ephemeral Cache（会话级） ← 动态系统提示词
  ↓  scope: 'ephemeral'
Section Cache（轮级）     ← systemPromptSection 记忆化
     每个 Section 独立缓存
```

### 6.2 缓存失效

```typescript
// 触发缓存的场景
const cacheTriggers = {
  // Global Cache
  'static_system_prompt': 'never',  // 永不失效
  
  // Ephemeral Cache
  'memory_content': 'on_claudemd_change',  // CLAUDE.md 变化时
  'mcp_instructions': 'on_mcp_connection',  // MCP 连接/断开时
  
  // Section Cache
  'user_context': 'per_turn',  // 每轮重新计算（但有 memoize）
}
```

### 6.3 缓存命中优化

```typescript
// src/services/api/claude.ts:3213-3237
function buildSystemPromptBlocks(
  systemPrompt: SystemPrompt,
): ContentBlockParam[] {
  const blocks: ContentBlockParam[] = []
  
  // 在缓存边界处分割
  const [staticPart, dynamicPart] = splitAtBoundary(systemPrompt)
  
  // 静态部分使用 global 缓存
  if (staticPart) {
    blocks.push({
      type: 'text',
      text: staticPart,
      cache_control: { type: 'ephemeral' },  // API 会自动识别为 global
    })
  }
  
  // 动态部分使用 ephemeral 缓存
  if (dynamicPart) {
    blocks.push({
      type: 'text',
      text: dynamicPart,
      cache_control: { type: 'ephemeral' },
    })
  }
  
  return blocks
}
```

---

## 七、提示词结构示例

### 7.1 完整系统提示词结构

```markdown
# Claude Code System Prompt

## Role
You are an interactive agent that helps users with software engineering tasks.

## System Rules
- All text you output is displayed to the user
- Tools are executed in a permission mode
- The conversation has unlimited context through automatic summarization

## Doing Tasks
- Use tools available to you to assist the user
- When creating new code, follow the conventions of the existing codebase
- After completing a task, do not summarize what you did

## Tools
You have access to the following tools:
- Read: Read a file from the filesystem
- Edit: Make edits to a file
- Write: Write a new file
- Bash: Execute a bash command
- Grep: Search for patterns in files
- ...

--- SYSTEM_PROMPT_DYNAMIC_BOUNDARY ---

## Current Date
Today's date is 2026-04-06.

## Project Context
Working directory: /Users/dev/my-project
Git branch: main
Git status: 2 modified files

## User Instructions
(CLADE.md content here)

## MCP Instructions
- Filesystem MCP: provides file operations
- GitHub MCP: provides issue and PR operations

## Token Budget
You have approximately 150,000 tokens available for this turn.
```

---

## 八、关键源文件索引

| 文件 | 职责 |
|------|------|
| `src/constants/prompts.ts` | 系统提示词组装 |
| `src/constants/systemPromptSections.ts` | Section 定义和缓存 |
| `src/utils/systemPrompt.ts` | 优先级解析 |
| `src/utils/claudemd.ts` | CLAUDE.md 加载 |
| `src/context.ts` | 系统和用户上下文 |
| `src/utils/api.ts` | 缓存边界分割 |
| `src/services/api/claude.ts` | API 缓存块构建 |

---

## 九、总结

Claude Code 的 System Prompt 工程体现了几个核心设计原则：

1. **分层构建**：静态和动态分离，最大化缓存利用
2. **优先级解析**：多来源指令按优先级合并
3. **缓存边界**：明确的缓存策略，降低延迟和成本
4. **Section 类型**：缓存和缓存破坏两种类型，适应不同需求
5. **递归引用**：支持 @path 语法，模块化指令组织

这个设计是 Prompt 工程的教科书级案例——既满足了动态性需求，又最大化了缓存效率。

---

**系列文章导航：**
- 上一篇：[Context 管理：四级压缩与无限对话的秘密](/claude-code-context-compression/)
- 下一篇：[Skills 系统：条件激活与动态发现](/claude-code-skills-system/)