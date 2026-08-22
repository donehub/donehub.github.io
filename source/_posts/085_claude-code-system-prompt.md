---
title: 系统提示词的动态组装与三级缓存
date: 2026-04-06
tags: System Prompt
categories: Claude Code
---

<!-- more -->

## 20k tokens 的缓存难题

Claude Code 的系统提示词约 20k tokens，每次 API 调用都要发送。这个数字本身不夸张，但叠加两个约束就变成了工程问题。第一个约束是动态性：系统提示词需要包含当前日期、项目结构、Git 状态、MCP 服务器指令、CLAUDE.md 用户指令，这些内容每轮对话都可能变化。第二个约束是成本：20k tokens 的提示词如果不做缓存优化，每个会话的延迟和 API 费用会成倍增加。

解决方案是将系统提示词拆分为静态可缓存区域和动态可变区域，通过缓存边界标记分隔。静态部分（角色定义、系统规则、任务指导、工具说明、风格约束）在全球范围内共享缓存，动态部分（会话指引、记忆系统、环境信息、MCP 指令、Token 预算）按会话级缓存。这样每次 API 调用时，静态部分可以直接复用缓存，只有动态部分需要重新计算。

## 缓存边界与 Section 类型

系统提示词的组装依赖一个显式的缓存边界标记：

```typescript
export const SYSTEM_PROMPT_DYNAMIC_BOUNDARY = '__SYSTEM_PROMPT_DYNAMIC_BOUNDARY__'
```

边界之上的内容是跨用户、跨组织通用的，使用 `scope: 'global'` 缓存。边界之下是用户或会话特定的内容，使用 `scope: 'ephemeral'` 缓存。API 层在构建请求时，沿着这个边界将提示词分割为两个 block，分别标记 `cache_control`，让服务端可以独立缓存这两部分。

提示词的每个组成部分被封装为一个 Section，分为两种类型。缓存 Section 计算一次后整个会话复用：

```typescript
systemPromptSection('memory', async () => {
  return buildMemoryLines()
}, { scope: 'ephemeral' })
```

缓存破坏 Section 每轮重新计算。适用于 MCP 指令（服务器可能中途连接或断开）、当前日期（每轮都不同）、Git 状态（可能快速变化）、Token 预算（每轮重新计算）等场景：

```typescript
DANGEROUS_uncachedSystemPromptSection('mcp_instructions', async () => {
  return getMcpInstructions()
}, 'MCP servers can connect/disconnect mid-session')
```

两种类型的区分是缓存效率的关键。如果把动态内容放在静态区域，会导致整个静态缓存频繁失效；如果把静态内容标记为动态，则白白放弃缓存机会。缓存边界的显式标记让这个问题有了清晰的工程解法。

## 三级缓存体系

系统提示词的缓存分为三级，覆盖不同的时间尺度。

Global Cache 跨组织共享，存储静态系统提示词（角色定义、规则、工具说明等），永不失效。这部分内容在所有用户、所有会话中完全相同，缓存命中率接近 100%。

Ephemeral Cache 会话级缓存，存储动态系统提示词（记忆内容、环境信息等）。CLAUDE.md 文件变化时失效重建，MCP 连接状态变化时也会触发重建。

Section Cache 轮级缓存，每个 Section 独立记忆化。即使某个 Section 被标记为缓存破坏，其内部仍然有 memoize 优化，同一轮内多次访问不会重复计算。

```typescript
function buildSystemPromptBlocks(systemPrompt: SystemPrompt): ContentBlockParam[] {
  const blocks: ContentBlockParam[] = []
  const [staticPart, dynamicPart] = splitAtBoundary(systemPrompt)

  if (staticPart) {
    blocks.push({
      type: 'text', text: staticPart,
      cache_control: { type: 'ephemeral' },
    })
  }

  if (dynamicPart) {
    blocks.push({
      type: 'text', text: dynamicPart,
      cache_control: { type: 'ephemeral' },
    })
  }

  return blocks
}
```

这个三级设计的实际效果是：一个典型会话中，静态部分（约 12k tokens）的缓存命中率接近 100%，动态部分（约 8k tokens）在 CLAUDE.md 不变的情况下也能保持高命中率。只有在 MCP 连接变化或 Git 状态频繁更新的场景下，动态缓存才会频繁重建。

## 优先级解析链

系统提示词有多个来源，最终内容通过 `buildEffectiveSystemPrompt()` 按优先级决定：

```
Override System Prompt     ← 最高优先级，完全替换
  ↓
Coordinator System Prompt  ← 协调者模式专用
  ↓
Agent System Prompt        ← agentDefinition.getSystemPrompt()
  ↓                          proactive 模式：追加到默认
  ↓                          其他模式：替换默认
Custom System Prompt       ← --system-prompt 参数
  ↓
Default System Prompt      ← Claude Code 标准提示词
  ↓
Append System Prompt       ← 始终追加到末尾
```

Override 和 Coordinator 是独占模式，直接替换整个提示词。Agent 提示词有两种行为：proactive 模式追加到默认提示词后（保留默认规则），其他模式完全替换默认提示词。Custom 和 Append 的区别在于：Custom 插入在默认提示词之后，Append 始终在最末尾。

```typescript
export async function buildEffectiveSystemPrompt(options): Promise<SystemPrompt> {
  if (options.overrideSystemPrompt) return asSystemPrompt(options.overrideSystemPrompt)
  if (isCoordinatorMode() && options.coordinatorSystemPrompt) return asSystemPrompt(options.coordinatorSystemPrompt)

  const sections: SystemPromptSection[] = await buildDefaultSections()

  if (options.agentDefinition?.getSystemPrompt) {
    const agentPrompt = await options.agentDefinition.getSystemPrompt(options)
    if (options.agentDefinition.promptMode === 'proactive') {
      sections.push({ type: 'text', text: agentPrompt })
    } else {
      return asSystemPrompt(agentPrompt)
    }
  }

  if (options.customSystemPrompt) sections.push({ type: 'text', text: options.customSystemPrompt })
  if (options.appendSystemPrompt) sections.push({ type: 'text', text: options.appendSystemPrompt })

  return resolveSystemPromptSections(sections)
}
```

这个优先级链覆盖了从测试覆盖（Override）到多 Agent 编排（Agent Prompt）到用户定制（Custom/Append）的所有场景。

## CLAUDE.md 加载与递归引用

CLAUDE.md 是用户自定义指令系统，按路径层级从低到高加载：

| 路径 | 作用域 | 优先级 |
|------|--------|--------|
| `/etc/claude-code/CLAUDE.md` | 全局管理配置 | 最低 |
| `~/.claude/CLAUDE.md` | 用户全局指令 | 低 |
| `项目根目录/CLAUDE.md` | 项目级指令 | 中 |
| `项目根目录/.claude/CLAUDE.md` | 项目级指令 | 中 |
| `项目根目录/.claude/rules/*.md` | 项目规则文件 | 中 |
| `项目根目录/CLAUDE.local.md` | 本地私有指令 | 最高 |

本地私有指令（`.local.md`）通常加入 `.gitignore`，用于存放个人偏好（如"用中文回复"），不会被提交到仓库。项目级指令则可以提交到仓库，作为团队共享的编码规范。

CLAUDE.md 支持 `@path` 语法递归引用其他文件，实现指令的模块化组织：

```markdown
# 项目配置

## 编码规范
@./docs/coding-standards.md

## API 文档
@./docs/api-spec.md
```

递归引用有循环检测机制。系统维护一个 visited Set，每次加载前检查路径是否已访问过。如果检测到循环引用，打印警告并返回空字符串，防止无限递归。

```typescript
async function loadClaudeMdFile(path: string, visited: Set<string> = new Set()): Promise<string> {
  if (visited.has(path)) {
    console.warn(`Circular reference detected: ${path}`)
    return ''
  }
  visited.add(path)

  let content = await readFile(path, 'utf-8')
  const references = extractReferences(content)
  for (const ref of references) {
    const refPath = resolveReference(path, ref)
    const refContent = await loadClaudeMdFile(refPath, visited)
    content = content.replace(`@${ref}`, refContent)
  }

  return content
}
```

## Agent 提示词增强

子代理的系统提示词在基础定义之上还有两层增强。第一层是环境详情注入，包括工作目录、启用工具列表、模型信息和环境变量。第二层是行为约束注入，Fork Agent 会收到额外的行为规则：不对话、不提问、工具调用之间不输出文本、响应必须以 "Scope:" 开头、报告控制在 500 词以内。

这些约束确保 Fork Agent 是一个高效的工作进程，不会在 Fork 上下文中产生不必要的对话开销。

## 提示词结构概览

最终的系统提示词由静态和动态两部分组成，以缓存边界分隔。静态部分包含角色定义（"You are an interactive agent..."）、系统规则（工具执行方式、权限模式）、任务指导（使用工具、遵循代码规范、不总结已完成任务）、工具说明（各工具的功能描述）和风格约束。动态部分包含当前日期、项目上下文（工作目录、Git 分支、Git 状态）、CLAUDE.md 用户指令、MCP 服务器指令和 Token 预算信息。

这个结构的关键设计决策是缓存边界的位置。工具说明放在静态区域（因为工具定义很少变化），而 Token 预算放在动态区域（因为每轮都需要重新计算）。这个分割点的选择直接决定了缓存效率。

## 关键源文件

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

**系列文章导航：**
- 上一篇：[Context 压缩的四级策略](/2026/04/06/080_claude-code-context-compression/)
- 下一篇：[条件激活与动态发现的 Skills 系统](/2026/04/06/084_claude-code-skills-system/)
