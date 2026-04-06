---
title: Memory 系统：跨会话持久化知识库
date: 2026-04-06
tags: Memory
categories: Claude Code
---

> 让 Claude Code 跨会话记住你是谁、你偏好什么、项目正在发生什么——这是 Memory 系统的核心目标。它不是简单的聊天记录持久化，而是一个结构化的知识管理系统，通过四种记忆类型、自动提取机制、团队同步等功能，让 AI 真正"理解"你。

<!-- more -->

## 导读：为什么需要 Memory？

假设你今天让 Claude Code 帮你重构代码，明天让它继续优化。如果没有 Memory：

- Claude 不知道你昨天做了什么
- Claude 不知道你的编码风格偏好
- Claude 不知道项目正在进行的决策

每次对话都从零开始，这是 AI 编程助手的一个根本性限制。

Claude Code 的 Memory 系统解决了这个问题：**让 AI 跨会话积累知识**。

---

## 一、四种记忆类型

### 1.1 类型定义

```
┌─────────────────────────────────────────────────────┐
│                   四种记忆类型                        │
├─────────────────────────────────────────────────────┤
│                                                     │
│  User（用户画像）                                    │
│    └─ 角色、目标、技能水平、偏好                     │
│    └─ 示例："用户是数据科学家，关注日志系统"        │
│                                                     │
│  Feedback（行为反馈）                                │
│    └─ 对 Claude 工作方式的纠正或肯定                │
│    └─ 示例："集成测试用真实数据库，不用 mock"        │
│                                                     │
│  Project（项目动态）                                 │
│    └─ 谁在做什么、为什么、截止日期                  │
│    └─ 示例："3/5 起合并冻结，移动团队发版"          │
│                                                     │
│  Reference（外部引用）                               │
│    └─ 外部系统指针：仪表板、工单系统、Slack 频道    │
│    └─ 示例："Pipeline bug 在 Linear 'INGEST' 项目"  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 1.2 不存储的内容

Memory 系统有一个核心原则：**只记住无法从代码中推断出来的东西**。

| 记住 | 不记住 |
|------|--------|
| 你是数据科学家，关注日志系统 | 代码架构、文件结构 |
| "不要 mock 数据库" | Git 历史、谁改了什么 |
| 周四后冻结非关键合并 | 已有的 CLAUDE.md 内容 |
| Bug 跟踪在 Linear 的 INGEST 项目 | 调试方案（修复已在代码里） |

---

## 二、Memory 存储格式

### 2.1 文件结构

```
~/.claude/
└── projects/
    └── {项目路径哈希}/
        └── memory/                    ← 自动记忆目录
            ├── MEMORY.md              ← 索引文件
            ├── user_role.md           ← 用户画像记忆
            ├── feedback_testing.md    ← 行为反馈记忆
            ├── project_freeze.md      ← 项目动态记忆
            ├── reference_linear.md    ← 外部引用记忆
            └── team/                  ← 团队共享记忆
                ├── MEMORY.md
                └── ...
```

### 2.2 记忆文件格式

每个记忆文件使用 YAML frontmatter + Markdown：

```markdown
---
name: testing_policy
description: 集成测试必须用真实数据库，不能用 mock
type: feedback
---

**规则：** 集成测试必须连接真实数据库，禁止使用 mock。

**Why:** 去年第四季度出现过 mock 测试通过但生产迁移失败的问题。

**How to apply:** 所有标记为 integration test 的测试文件都要使用测试数据库连接。
```

### 2.3 MEMORY.md 索引文件

MEMORY.md 是索引而不是内容，它**始终加载到上下文**中：

```markdown
# Memory Index

- [用户角色](user_role.md) — 数据科学家，关注可观测性/日志
- [测试策略](feedback_testing.md) — 集成测试用真实数据库，不 mock
- [合并冻结](project_freeze.md) — 2026-03-05 起冻结非关键合并
- [Bug 追踪](reference_linear.md) — 流水线 bug 在 Linear INGEST 项目
```

**限制**：最多 200 行或 25KB，超出会被截断。

---

## 三、Memory 提取机制

### 3.1 自动提取流程

```
触发时机：每次模型完成回复（无 tool_use）时
         ↓
守卫检查：主代理？功能门控开启？自动记忆启用？
         ↓
频率控制：turnsSinceLastExtraction++ (默认每 1 次)
         ↓
互斥检查：主代理自己写了记忆？→ 跳过
         ↓
扫描现有记忆 → 生成清单
         ↓
运行分叉代理（runForkedAgent）
  - 共享父会话提示词缓存
  - 最多 5 个 turn
  - 限制工具权限
         ↓
写入新记忆文件 + 更新 MEMORY.md
         ↓
通知用户："Memory updated in ..."
```

### 3.2 工具权限限制

```typescript
// src/services/extractMemories/extractMemories.ts
function createAutoMemCanUseTool(memoryDir: string): CanUseToolFn {
  return (toolName, input) => {
    // ✅ 允许：Read, Grep, Glob（无限制）
    if (['Read', 'Grep', 'Glob'].includes(toolName)) {
      return true
    }
    
    // ✅ 允许：Bash（只读命令：ls, find, grep, cat...）
    if (toolName === 'Bash' && isReadOnlyCommand(input.command)) {
      return true
    }
    
    // ✅ 允许：Edit/Write（仅 auto-memory 目录内）
    if (['Edit', 'Write'].includes(toolName)) {
      return isInsideMemoryDir(input.file_path, memoryDir)
    }
    
    // ❌ 拒绝：MCP, Agent, 非只读 Bash
    return false
  }
}
```

### 3.3 互斥机制

防止重复保存：

```typescript
function hasMemoryWritesSince(
  messages: Message[],
  sinceUuid: string,
): boolean {
  // 扫描 sinceUuid 之后的所有 assistant 消息
  // 如果有任何 Edit/Write 指向 auto-memory 目录 → return true
  for (const msg of messages) {
    if (msg.uuid === sinceUuid) break
    if (msg.type === 'assistant') {
      for (const block of msg.content) {
        if (block.type === 'tool_use' && 
            ['Edit', 'Write'].includes(block.name) &&
            isMemoryPath(block.input.file_path)) {
          return true
        }
      }
    }
  }
  return false
}
```

---

## 四、Memory 在 Prompt 中的使用

### 4.1 系统提示词注入

```typescript
// src/memdir/memdir.ts
async function loadMemoryPrompt(): Promise<string | null> {
  const sections = []
  
  // 1. 记忆类型说明
  sections.push(`## Types of memory`)
  sections.push(...getMemoryTypeDescriptions())
  
  // 2. 不存储的内容
  sections.push(`## What NOT to save`)
  sections.push(...getWhatNotToSaveList())
  
  // 3. 如何保存记忆
  sections.push(`## How to save memories`)
  sections.push(getSaveInstructions())
  
  // 4. 何时查阅记忆
  sections.push(`## When to access memories`)
  sections.push(getAccessGuidelines())
  
  // 5. 引用前验证
  sections.push(`## Before recommending`)
  sections.push(getValidationGuidelines())
  
  // 6. MEMORY.md 索引内容
  sections.push(`## MEMORY.md`)
  sections.push(await loadMemoryIndex())
  
  return sections.join('\n\n')
}
```

### 4.2 智能检索

每次用户查询时动态选择相关记忆：

```typescript
// src/memdir/findRelevantMemories.ts
async function findRelevantMemories(
  query: string,
  memoryDir: string,
  recentTools: string[] = [],
): Promise<RelevantMemory[]> {
  // 1. 扫描所有 .md 文件（排除 MEMORY.md）
  const files = await scanMemoryFiles(memoryDir)
  
  // 2. 解析 frontmatter（前 30 行）
  const candidates = await Promise.all(
    files.map(f => parseMemoryFile(f))
  )
  
  // 3. Sonnet 模型选择
  const selected = await sideQuery({
    model: 'claude-sonnet-4-5',
    systemPrompt: MEMORY_SELECTOR_PROMPT,
    messages: [{ role: 'user', content: query }],
    context: { candidates, recentTools },
  })
  
  // 4. 返回选中记忆
  return selected.map(s => ({ path: s.path, mtimeMs: s.mtimeMs }))
}
```

**Sonnet 选择器提示词**：

```
你是记忆选择器。从候选记忆中选择对处理用户查询有用的记忆。

规则：
- 最多选 5 个
- 不确定是否有用就不要选
- 如果提供了最近使用的工具列表，不要选这些工具的使用文档
  （但要选择关于这些工具的警告/陷阱/已知问题）

返回格式：
- memory_path: 选择原因
```

### 4.3 新鲜度警告

```typescript
function memoryFreshnessText(mtimeMs: number): string {
  const days = memoryAgeDays(mtimeMs)
  if (days <= 1) return ''  // 今天/昨天：无警告
  
  return `This memory is ${days} days old. Memories are point-in-time 
observations that may become stale. Verify against current code before 
asserting as fact.`
}
```

---

## 五、团队 Memory 同步

### 5.1 API 端点

```
GET  /api/claude_code/team_memory?repo={owner/repo}  ← 拉取
PUT  /api/claude_code/team_memory?repo={owner/repo}  ← 推送
```

### 5.2 同步语义

| 操作 | 行为 |
|------|------|
| **Pull** | 服务器内容覆盖本地文件（服务器优先） |
| **Push** | 仅上传内容哈希不同的键（delta 上传） |
| **删除** | 本地删除不会删除远程（下次 pull 会恢复） |

### 5.3 冲突解决

```typescript
async function pushTeamMemory(state): Promise<PushResult> {
  // 1. 读取本地文件 → 计算哈希
  const localFiles = await readLocalMemoryFiles()
  const localHashes = computeHashes(localFiles)
  
  // 2. 对比 serverChecksums → 生成 delta
  const delta = computeDelta(localHashes, state.serverChecksums)
  
  // 3. 上传 delta
  const response = await api.pushTeamMemory(delta)
  
  // 4. 遇到 412 冲突：
  if (response.status === 412) {
    // 探测 GET ?view=hashes 获取最新 checksums
    const latest = await api.getTeamMemoryHashes()
    // 重新计算 delta（排除队友已推送的相同内容）
    const newDelta = recomputeDelta(localHashes, latest)
    // 重试（最多 2 次）
    return pushTeamMemory({ ...state, serverChecksums: latest })
  }
  
  return { success: true }
}
```

### 5.4 安全限制

- **单文件最大**：250KB
- **上传体最大**：200KB（分批上传）
- **秘密扫描**：使用 gitleaks 规则扫描凭证，检测到则跳过该文件

---

## 六、AutoDream：后台记忆整合

### 6.1 触发条件

```typescript
// src/services/autoDream/autoDream.ts
async function shouldTriggerAutoDream(): Promise<boolean> {
  // 四重门控
  if (hoursSinceLastConsolidation < minHours) return false  // 时间门：默认 24h
  if (sessionsSinceLastConsolidation < minSessions) return false  // 会话门：默认 5 次
  if (otherProcessConsolidating) return false  // 锁门：互斥
  if (timeSinceLastScan < 10 * 60 * 1000) return false  // 扫描节流：10 分钟
  
  return true
}
```

### 6.2 四阶段流程

```
┌─────────────────────────────────────────────────────┐
│              AutoDream 四阶段流程                    │
├─────────────────────────────────────────────────────┤
│                                                     │
│  Phase 1: 定向（Orientation）                       │
│    └─ 确定要审查的会话列表                          │
│                                                     │
│  Phase 2: 收集（Collection）                        │
│    └─ 从会话中提取候选记忆                          │
│                                                     │
│  Phase 3: 整合（Consolidation）                     │
│    └─ 合并、去重、更新记忆文件                      │
│                                                     │
│  Phase 4: 修剪（Pruning）                           │
│    └─ 删除过时或重复的记忆                          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### 6.3 DreamTask 状态

```typescript
type DreamTaskState = {
  type: 'dream'
  phase: 'starting' | 'updating'  // updating = 已开始编辑文件
  sessionsReviewing: number       // 正在审查的会话数
  filesTouched: string[]          // 编辑过的文件路径
  turns: DreamTurn[]              // 对话轮次记录
}
```

---

## 七、关键源文件索引

| 文件 | 职责 |
|------|------|
| `src/memdir/paths.ts` | 路径解析，优先级链 |
| `src/memdir/memdir.ts` | 提示词构建，MEMORY.md 截断 |
| `src/memdir/memoryScan.ts` | 扫描目录、解析 frontmatter |
| `src/memdir/memoryTypes.ts` | 四种记忆类型定义 |
| `src/memdir/findRelevantMemories.ts` | Sonnet 智能检索 |
| `src/services/extractMemories/` | 自动提取服务 |
| `src/services/teamMemorySync/` | 团队记忆同步 |
| `src/services/autoDream/` | AutoDream 后台整合 |
| `src/utils/frontmatterParser.ts` | YAML frontmatter 解析 |
| `src/components/memory/` | UI 组件 |
| `src/commands/memory/` | `/memory` 命令 |

---

## 八、总结

Claude Code 的 Memory 系统体现了几个核心设计原则：

1. **结构化知识**：四种记忆类型，避免信息混淆
2. **自动提取**：后台智能分析对话，提取有价值信息
3. **智能检索**：Sonnet 模型动态选择相关记忆
4. **新鲜度管理**：旧记忆附带警告，使用前需验证
5. **团队同步**：服务器优先语义，支持协作
6. **AutoDream**：后台"做梦"整理记忆

这个设计让 AI 真正能够"记住"用户，而不是每次都从零开始。

---

**系列文章导航：**
- 上一篇：[权限与安全：分层模型与人机协作](/claude-code-permission-security/)
- 下一篇：[Channel 系统：IM 远程控制 Agent](/claude-code-channel-system/)