---
title: 条件激活与动态发现的 Skills 系统
date: 2026-04-06
tags: Skills
categories: Claude Code
---

<!-- more -->

## 不只是命令别名

Skills 的表面形态是斜杠命令（`/code-review`、`/commit`），但本质是一个完整的 AI 行为定义系统。一个 Skill 文件可以同时约束工具池、指定模型、注入 Hook、选择执行上下文（inline 或 fork），这些能力组合起来让 Skill 成为一个可复用的行为模板，而不是简单的 prompt 快捷方式。

```markdown
---
name: code-review
description: Expert code review with best practices
allowed-tools: ['Read', 'Grep', 'WebSearch']
model: sonnet
context: fork
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "echo 'Review mode: read-only'"
---

You are a code reviewer. Analyze the code for:
- Security vulnerabilities
- Performance issues
- Code style and best practices
```

这个 Skill 定义了只读工具池（Read、Grep、WebSearch），使用 Sonnet 模型，在 Fork 上下文中执行（独立子代理），并通过 Hook 阻止 Bash 调用。四重约束确保 Skill 的行为边界清晰。

## 系统架构与模块职责

Skills 系统分为五个模块，各司其职：

| 模块 | 核心文件 | 职责 |
|------|---------|------|
| Discovery | `loadSkillsDir.ts` | 从 6 种来源发现和加载 Skills |
| Prompt | `prompt.ts` + `attachments.ts` | 将 Skill 列表注入 system-reminder |
| SkillTool | `SkillTool.ts` | 验证、权限检查、执行 Skill |
| Activation | `loadSkillsDir.ts` | 条件激活和动态发现 |
| Context | `forkedAgent.ts` | 上下文准备和修改 |

Discovery 模块负责从六个来源加载 Skills：内置 Skills（`src/skills/bundled/*.md`）、内置插件 Skills（`src/plugins/bundled/*/skills/*.md`）、管理 Skills（`${MANAGED_PATH}/.claude/skills/`）、用户全局 Skills（`~/.claude/skills/`）、项目级 Skills（`.claude/skills/`）和插件 Skills（`~/.claude/plugins/*/skills/`）。加载时按优先级排序，内置 Skills 优先级最高，插件 Skills 最低。

去重机制通过文件身份标识（`realpath()` 解析符号链接）实现。如果同一个文件被多个来源引用（例如符号链接），只加载一次，以首次发现的来源为准。

```typescript
const seenFileIds = new Map<string, SettingSource>()
for (const entry of allSkillsWithPaths) {
  const fileId = await getFileIdentity(entry.filePath)
  const existingSource = seenFileIds.get(fileId)
  if (existingSource !== undefined) continue
  seenFileIds.set(fileId, entry.skill.source)
  deduplicatedSkills.push(entry.skill)
}
```

## Frontmatter 字段与解析

Skill 的行为由 Frontmatter YAML 定义，支持以下字段：

```typescript
type FrontmatterData = {
  'allowed-tools'?: string | string[] | null   // 允许的工具
  description?: string | null                  // 描述
  'argument-hint'?: string | null              // 参数提示
  when_to_use?: string | null                  // 使用场景说明
  model?: string | null                        // haiku, sonnet, opus, inherit
  'user-invocable'?: string | null             // 用户可调用
  'disable-model-invocation'?: string | null   // 禁止模型调用
  hooks?: HooksSettings | null                 // Hook 配置
  effort?: string | null                       // low, medium, high, max
  context?: 'inline' | 'fork' | null           // 执行上下文
  agent?: string | null                        // Agent 类型
  paths?: string | string[] | null             // 条件激活路径
  shell?: string | null                        // bash, powershell
}
```

解析流程分两步：首先 `parseFrontmatter()` 分离 YAML 和 Markdown 内容，处理特殊字符；然后 `parseSkillFrontmatterFields()` 提取各字段，包括模型别名解析、力度级别解析、Hook 配置验证和工具列表解析，最终生成 Command 对象。

## 条件激活：按需发现

条件激活是 Skills 系统最有特色的设计。带 `paths` frontmatter 的 Skills 不会在启动时暴露给模型，只有当用户操作匹配路径的文件时才会被动态发现。

```markdown
---
name: react-component-test
description: Generate tests for React components
paths:
  - "src/components/**/*.tsx"
  - "src/components/**/*.jsx"
allowed-tools: ['Read', 'Write', 'Bash']
model: sonnet
---

Generate comprehensive tests for this React component...
```

这个 Skill 只有在你操作 `src/components/` 下的 `.tsx` 或 `.jsx` 文件时才会出现在可用列表中。启动时，系统将所有带 `paths` 的 Skills 放入 `conditionalSkills` Map。运行时，每次文件操作都会触发 `activateConditionalSkillsForPaths()`，用 ignore 库匹配文件路径。匹配成功后，Skill 从 `conditionalSkills` 移入 `dynamicSkills`，一旦激活，会话内持续有效。

这个设计解决了两个问题。一是上下文效率：一个项目可能有几十个 Skills，全部加载会占用大量 token，条件激活确保只有相关的 Skills 被注入上下文。二是认知负担：模型看到的 Skill 列表越短，选择越精准，无关 Skill 不会干扰决策。

动态发现还包含目录遍历逻辑。当操作深层目录文件时，系统从文件所在目录向上遍历到 cwd，检查每一级的 `.claude/skills/` 目录，自动发现新的 Skills。发现的目录按深度排序（最深优先），确保局部 Skills 优先级高于全局 Skills。

```typescript
async function discoverSkillDirsForPaths(filePaths: string[], cwd: string): Promise<string[]> {
  for (const filePath of filePaths) {
    let currentDir = dirname(filePath)
    while (currentDir.startsWith(resolvedCwd + pathSep)) {
      const skillDir = join(currentDir, '.claude', 'skills')
      if (!dynamicSkillDirs.has(skillDir)) {
        dynamicSkillDirs.add(skillDir)
        if (await exists(skillDir) && !await isGitignored(currentDir)) {
          newDirs.push(skillDir)
        }
      }
      currentDir = dirname(currentDir)
    }
  }
  return newDirs.sort((a, b) => b.split(pathSep).length - a.split(pathSep).length)
}
```

## 上下文注入与预算控制

Skills 通过 `system-reminder` 消息注入到对话中。系统对 Skill 列表的 token 占用有严格预算控制：上下文窗口的 1%，兜底 8000 字符，每条描述上限 250 字符。

```typescript
const SKILL_BUDGET_CONTEXT_PERCENT = 0.01
const DEFAULT_CHAR_BUDGET = 8_000
const MAX_LISTING_DESC_CHARS = 250
```

截断策略优先保护内置 Skills。Bundled Skills 始终保留完整描述，其余 Skills 平分剩余预算。如果总字符超出预算，描述会被截断到 `maxDescLen` 字符。这个设计确保核心 Skills 的可发现性不会被自定义 Skills 挤压。

## 执行引擎：Inline 与 Fork

SkillTool 的执行流程分为六步：标准化输入（去除前导 `/`）、远程 Skill 检查（实验性）、查找 Command 对象、记录使用频率、判断执行路径、应用 contextModifier。

执行路径根据 `command.context` 分为两种模式。Inline 模式将 Skill 的 prompt 注入当前对话，修改上下文（工具池、模型、effort），模型在当前会话中执行。Fork 模式启动独立子代理，Skill 在隔离的上下文中执行，结果通过 `tool_result` 返回。

| 特性 | Inline 模式 | Fork 模式 |
|------|-----------|----------|
| 上下文 | 注入当前对话 | 独立子代理 |
| 工具池修改 | 修改当前会话 | 子代理独立工具池 |
| 结果传递 | 新消息注入对话 | 嵌入 tool_result |
| 适用场景 | 需要对话连续性 | 独立任务，无需上下文 |

Inline 模式适合需要对话连续性的场景（如 `/commit` 需要与用户交互确认提交信息），Fork 模式适合独立任务（如 `/verify` 运行测试后返回结果）。

## Hook 集成

Skills 可以通过 Frontmatter 声明 Hook，调用时自动注册为会话级 Hook。`once: true` 的 Hook 执行一次后自动移除。

```markdown
---
name: test-runner
hooks:
  PostToolUse:
    - matcher: "Edit"
      hooks:
        - type: command
          command: "npm test"
          once: true
---
```

```typescript
function registerSkillHooks(setAppState, sessionId, hooks, skillName, skillRoot): void {
  for (const eventName of HOOK_EVENTS) {
    for (const matcher of hooks[eventName] || []) {
      for (const hook of matcher.hooks) {
        const onHookSuccess = hook.once
          ? () => removeSessionHook(setAppState, sessionId, eventName, hook)
          : undefined

        addSessionHook(
          setAppState, sessionId, eventName,
          matcher.matcher || '',
          hook, onHookSuccess, skillRoot,
        )
      }
    }
  }
}
```

Hook 注册机制让 Skill 的行为可以扩展到工具生命周期。例如，一个 `test-runner` Skill 可以在每次文件编辑后自动运行测试，确保修改不会破坏现有功能。

## 权限控制

Skill 调用的权限检查按优先级执行五步：Deny 规则检查（精确匹配或前缀匹配，如 `review:*` 匹配所有 review 开头的命令）、远程 Skill 自动允许、Allow 规则检查、安全属性自动允许（无 hooks、无 allowedTools、无 fork 的 Skill 自动放行）、默认询问用户。

安全属性白名单包含 Skill 的基础元数据（type、name、description、source 等）。如果 Skill 只包含这些属性，不涉及工具池修改、Hook 注入或 Fork 执行，系统认为它是安全的，自动允许。

## 关键源文件

| 文件 | 职责 |
|------|------|
| `src/tools/SkillTool/SkillTool.ts` | SkillTool 定义、验证、权限、执行 |
| `src/tools/SkillTool/prompt.ts` | 工具提示词、Skill 列表格式化 |
| `src/skills/loadSkillsDir.ts` | 目录 Skill 发现、加载、去重、条件激活 |
| `src/skills/bundledSkills.ts` | 内置 Skill 注册系统 |
| `src/skills/bundled/index.ts` | 内置 Skills 初始化入口 |
| `src/commands.ts` | 命令聚合、排序、过滤 |
| `src/utils/forkedAgent.ts` | Fork 上下文准备、结果提取 |
| `src/utils/hooks/registerSkillHooks.ts` | Skill Hook 注册 |

---

**系列文章导航：**
- 上一篇：[System Prompt 工程：动态组装与缓存优化](/2026/04/06/085_claude-code-system-prompt/)
- 下一篇：[权限决策的五层防线](/2026/04/06/083_claude-code-permission-security/)
