---
title: Skills 系统：条件激活与动态发现
date: 2026-04-06
tags: Skills
categories: Claude Code
---

> Skills 是 Claude Code 最强大的扩展机制之一。它不是简单的"命令别名"，而是完整的 AI 行为定义：可以限制工具池、覆盖模型、注入 Hook、选择执行上下文（inline 或 fork）。更令人惊叹的是，Skills 支持条件激活——只有当你操作特定文件时才被发现。

<!-- more -->

## 导读：Skills 不只是命令

很多人第一次看到 Skills 时，会认为它就是"斜杠命令"的别名。但实际上，Skills 是一个**完整的 AI 行为定义系统**：

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
- Documentation completeness

Provide actionable feedback with specific line references.
```

这个 Skill 定义了：
- **工具限制**：只读工具（Read、Grep、WebSearch）
- **模型选择**：使用 Sonnet
- **执行上下文**：Fork 模式（独立子代理）
- **Hook 注入**：阻止 Bash 调用

---

## 一、Skills 系统架构

### 1.1 整体架构

```
┌─────────────────────────────────────────────────────┐
│                   Skills 系统                        │
│                                                     │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │  Discovery   │  │   Prompt     │  │  SkillTool │ │
│  │  发现 & 加载  │→│  注入 & 呈现  │→│  执行引擎   │ │
│  └─────────────┘  └──────────────┘  └────────────┘ │
│         ↑                                    ↓      │
│  ┌─────────────┐                     ┌────────────┐ │
│  │  Activation  │                     │  Context   │ │
│  │  条件激活    │←────────────────────│  上下文修改 │ │
│  └─────────────┘                     └────────────┘ │
└─────────────────────────────────────────────────────┘
```

### 1.2 核心模块职责

| 模块 | 核心文件 | 职责 |
|------|---------|------|
| Discovery | `loadSkillsDir.ts` | 从 6 种来源发现和加载 Skills |
| Prompt | `prompt.ts` + `attachments.ts` | 将 Skill 列表注入 system-reminder |
| SkillTool | `SkillTool.ts` | 验证、权限检查、执行 Skill |
| Activation | `loadSkillsDir.ts` | 条件激活和动态发现 |
| Context | `forkedAgent.ts` | 上下文准备和修改 |

---

## 二、Skill 发现与加载

### 2.1 六种来源

```
┌─────────────────────────────────────────────────────┐
│                   Skills 来源                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  1. Bundled Skills（内置）                          │
│     └─ src/skills/bundled/*.md                     │
│                                                     │
│  2. Built-in Plugin Skills（内置插件）              │
│     └─ src/plugins/bundled/*/skills/*.md           │
│                                                     │
│  3. Managed Skills（管理）                          │
│     └─ ${MANAGED_PATH}/.claude/skills/             │
│                                                     │
│  4. User Skills（用户全局）                         │
│     └─ ~/.claude/skills/                           │
│                                                     │
│  5. Project Skills（项目级）                        │
│     └─ .claude/skills/                             │
│                                                     │
│  6. Plugin Skills（插件）                           │
│     └─ ~/.claude/plugins/*/skills/                 │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 2.2 加载优先级

```typescript
// src/commands.ts
const loadAllCommands = memoize(async (cwd: string): Promise<Command[]> => {
  return [
    ...bundledSkills,        // 1. 内置 Skills（最高优先级）
    ...builtinPluginSkills,  // 2. 内置插件 Skills
    ...skillDirCommands,     // 3. 目录 Skills（managed → user → project）
    ...workflowCommands,     // 4. Workflow 命令
    ...pluginCommands,       // 5. 插件命令
    ...pluginSkills,         // 6. 插件 Skills
    ...COMMANDS(),           // 7. 内建命令（最低优先级）
  ]
})
```

### 2.3 去重机制

```typescript
// src/skills/loadSkillsDir.ts
const seenFileIds = new Map<string, SettingSource>()
for (const entry of allSkillsWithPaths) {
  const fileId = await getFileIdentity(entry.filePath)  // realpath() 解析符号链接
  const existingSource = seenFileIds.get(fileId)
  if (existingSource !== undefined) continue  // 跳过重复
  seenFileIds.set(fileId, entry.skill.source)
  deduplicatedSkills.push(entry.skill)
}
```

---

## 三、Frontmatter 解析

### 3.1 Frontmatter 字段

```typescript
// src/utils/frontmatterParser.ts
type FrontmatterData = {
  'allowed-tools'?: string | string[] | null
  description?: string | null
  'argument-hint'?: string | null
  when_to_use?: string | null
  version?: string | null
  model?: string | null          // haiku, sonnet, opus, inherit
  'user-invocable'?: string | null
  'disable-model-invocation'?: string | null
  hooks?: HooksSettings | null
  effort?: string | null         // low, medium, high, max
  context?: 'inline' | 'fork' | null
  agent?: string | null
  paths?: string | string[] | null  // 条件激活路径
  shell?: string | null          // bash, powershell
}
```

### 3.2 解析流程

```
SKILL.md 文件
    ↓
parseFrontmatter()              ← frontmatterParser.ts
    ├─ 分离 YAML frontmatter 和 Markdown 内容
    ├─ quoteProblematicValues()  ← 处理特殊字符
    └─ parseYaml()               ← 解析 YAML
    ↓
parseSkillFrontmatterFields()   ← loadSkillsDir.ts
    ├─ description 提取（frontmatter 或第一个 # 标题）
    ├─ parseUserSpecifiedModel() ← 模型别名解析
    ├─ parseEffortValue()        ← 力度级别解析
    ├─ parseHooksFromFrontmatter() ← Hook 配置验证
    └─ parseSlashCommandToolsFromFrontmatter() ← 工具列表解析
    ↓
createSkillCommand()            ← 生成 Command 对象
```

---

## 四、条件激活机制

### 4.1 工作原理

带 `paths` frontmatter 的 Skills 不会立即暴露给模型：

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

这个 Skill 只有在你操作 `src/components/` 下的文件时才会被发现。

### 4.2 激活流程

```
启动时
├─ 加载所有 Skills
├─ 有 paths 的 → conditionalSkills Map
└─ 无 paths 的 → 立即可用

运行时（文件操作触发）
├─ activateConditionalSkillsForPaths(filePaths, cwd)
│  ├─ 遍历 conditionalSkills Map
│  ├─ 用 ignore 库匹配 paths 模式
│  │  └─ filePath 转为 cwd 相对路径后匹配
│  ├─ 匹配成功:
│  │  ├─ 移入 dynamicSkills Map
│  │  ├─ 从 conditionalSkills 删除
│  │  └─ 记录遥测 tengu_dynamic_skills_changed
│  └─ 一旦激活，会话内持续有效
└─ 通知缓存失效 → skillsLoaded.emit()
```

### 4.3 动态发现

当操作深层目录文件时，系统自动发现新的 Skills：

```typescript
// src/skills/loadSkillsDir.ts
async function discoverSkillDirsForPaths(
  filePaths: string[],
  cwd: string,
): Promise<string[]> {
  for (const filePath of filePaths) {
    let currentDir = dirname(filePath)
    // 从文件所在目录向上遍历到 cwd
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
  // 按深度排序（最深优先）
  return newDirs.sort((a, b) => b.split(pathSep).length - a.split(pathSep).length)
}
```

---

## 五、Skill 注入到对话

### 5.1 注入流程

Skills 通过 `system-reminder` 消息注入到对话中：

```typescript
// src/utils/attachments.ts
async function getSkillListingAttachments(): Promise<AttachmentMessage[]> {
  const commands = await getSkillToolCommands(cwd)
  
  // 预算控制
  const budget = contextWindowTokens * 4 * 0.01  // 1% 上下文
  
  // 格式化
  const formatted = formatCommandsWithinBudget(commands, budget)
  
  return [{
    type: 'skill_listing',
    content: formatted,
    skillCount: commands.length,
  }]
}
```

### 5.2 预算控制

```typescript
// src/tools/SkillTool/prompt.ts
export const SKILL_BUDGET_CONTEXT_PERCENT = 0.01  // 上下文窗口的 1%
export const DEFAULT_CHAR_BUDGET = 8_000           // 兜底预算
export const MAX_LISTING_DESC_CHARS = 250          // 每条描述上限
```

**截断策略**：

```
formatCommandsWithinBudget(commands, budget)
├─ 计算总预算
├─ 尝试全量描述
│  └─ 总字符 ≤ 预算 → 全部输出
│
├─ 分区: Bundled（不截断） + 其余
│  ├─ Bundled Skills 始终保留完整描述
│  └─ 其余 Skills 平分剩余预算
│
└─ 截断描述 → maxDescLen 字符
```

---

## 六、SkillTool 执行引擎

### 6.1 执行流程

```
SkillTool.call({ skill, args })
    │
    ├─ 1. 标准化输入（去除前导 /）
    ├─ 2. 远程 Skill 检查（实验性）
    ├─ 3. 查找 Command 对象
    ├─ 4. 记录使用频率
    │
    ├─ 5. 判断执行路径
    │   ├─ command.context === 'fork'
    │   │  └─ → executeForkedSkill()
    │   │
    │   └─ 默认 inline
    │      ├─ processPromptSlashCommand()
    │      │  ├─ getPromptForCommand(args, context)
    │      │  ├─ registerSkillHooks()
    │      │  ├─ addInvokedSkill()
    │      │  └─ 提取附件 → 创建消息
    │      │
    │      ├─ 提取 metadata: allowedTools, model, effort
    │      ├─ tagMessagesWithToolUseID()
    │      └─ 返回 { newMessages, contextModifier }
    │
    └─ 6. contextModifier() 闭包
       ├─ 更新 allowedTools
       ├─ 更新 model
       └─ 更新 effort
```

### 6.2 Inline vs Fork 扔回

**Inline 返回**:
```typescript
{
  data: {
    success: true,
    commandName: 'commit',
    allowedTools: ['Bash', 'Read'],
    model: 'sonnet',
    status: 'inline',
  },
  newMessages: [...],        // 注入到对话
  contextModifier: (ctx) => { ... },  // 修改上下文
}
```

**Fork 返回**:
```typescript
{
  data: {
    success: true,
    commandName: 'verify',
    status: 'forked',
    agentId: 'agent_abc123',
    result: '验证通过，所有测试已运行...',
  },
  // 无 newMessages — 结果嵌入 tool_result block
}
```

---

## 七、Hook 集成

### 7.1 Hook 注册

Skills 可以通过 frontmatter 声明 Hook：

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

调用时自动注册为会话级 Hook：

```typescript
// src/utils/hooks/registerSkillHooks.ts
function registerSkillHooks(
  setAppState, sessionId, hooks, skillName, skillRoot
): void {
  for (const eventName of HOOK_EVENTS) {
    for (const matcher of hooks[eventName] || []) {
      for (const hook of matcher.hooks) {
        // once: true → 执行一次后自动移除
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

---

## 八、权限系统

### 8.1 检查流程

```
checkPermissions({ skill, args }, context)
    │
    ├─ 1. Deny 规则检查（最高优先级）
    │   └─ getRuleByContentsForTool(context, SkillTool, 'deny')
    │       ├─ 精确匹配: "commit" === commandName
    │       └─ 前缀匹配: "review:*" → commandName.startsWith("review")
    │
    ├─ 2. 远程 Skill 自动允许
    │
    ├─ 3. Allow 规则检查
    │
    ├─ 4. 安全属性自动允许
    │   └─ skillHasOnlySafeProperties(command)
    │       └─ 无 hooks、无 allowedTools、无 fork
    │
    └─ 5. 默认: 询问用户
```

### 8.2 安全属性白名单

如果 Skill 只包含以下属性，自动允许：

```
SAFE_SKILL_PROPERTIES = {
  type, name, description, contentLength, source,
  loadedFrom, progressMessage, userInvocable,
  disableModelInvocation, hasUserSpecifiedDescription,
  getPromptForCommand, userFacingName, ...
}
```

---

## 九、关键源文件索引

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

## 十、总结

Claude Code 的 Skills 系统体现了几个核心设计原则：

1. **声明式定义**：通过 Frontmatter 定义 AI 行为
2. **条件激活**：基于文件路径的动态发现
3. **双模式执行**：Inline（注入对话）和 Fork（独立子代理）
4. **上下文修改**：动态调整工具池、模型、effort
5. **Hook 集成**：将 Skill 行为扩展到工具生命周期
6. **权限控制**：安全属性白名单自动允许

这个设计使得用户可以轻松定义新的 AI 行为，而不需要修改代码。

---

**系列文章导航：**
- 上一篇：[System Prompt 工程：动态组装与缓存优化](/claude-code-system-prompt/)
- 下一篇：[权限与安全：分层模型与人机协作](/claude-code-permission-security/)