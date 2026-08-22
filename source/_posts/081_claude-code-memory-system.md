---
title: 跨会话记忆：四种类型与自动提取机制
date: 2026-04-06
tags: Memory
categories: Claude Code
---

<!-- more -->

## 问题的起点

编程助手每次对话都从零开始，用户不得不反复说明同样的背景信息：自己的角色定位、编码偏好、项目当前的决策状态。这些信息无法从代码仓库中推断出来，但如果不记住它们，AI 就无法提供真正连贯的协助。

Claude Code 的 Memory 系统通过持久化的结构化知识库解决这个问题。它不是聊天记录的归档，而是一个有明确类型定义、自动提取、智能检索的知识管理系统。

## 四种记忆类型

Memory 将知识分为四类，每类有明确的边界和用途：

| 类型 | 记录内容 | 典型示例 |
|------|----------|----------|
| User（用户画像） | 角色、目标、技能水平、偏好 | "用户是数据科学家，关注日志系统" |
| Feedback（行为反馈） | 对 Claude 工作方式的纠正或肯定 | "集成测试用真实数据库，不用 mock" |
| Project（项目动态） | 谁在做什么、为什么、截止日期 | "3/5 起合并冻结，移动团队发版" |
| Reference（外部引用） | 外部系统的指针：仪表板、工单、Slack 频道 | "Pipeline bug 在 Linear INGEST 项目" |

这个分类覆盖了编码协作中需要从人脑传递给 AI 的全部上下文类型。用户画像决定模型的交互方式，行为反馈约束技术决策，项目动态提供时间维度的背景，外部引用打通内部工具链。

### 不存什么

Memory 有一个清晰的过滤原则：只记录无法从代码仓库中推断出来的东西。

| 记住 | 不记住 |
|------|--------|
| 你是数据科学家，关注日志系统 | 代码架构、文件结构 |
| "不要 mock 数据库" | Git 历史、谁改了什么 |
| 周四后冻结非关键合并 | 已有的 CLAUDE.md 内容 |
| Bug 跟踪在 Linear 的 INGEST 项目 | 调试方案（修复已在代码里） |

代码本身能表达的信息不需要 Memory 重复记录。Git 历史、文件结构、依赖关系这些都是代码仓库自带的上下文，Memory 只填充代码无法覆盖的空白。

## 存储格式

Memory 文件存放在 `~/.claude/projects/{项目路径哈希}/memory/` 目录下，采用 YAML frontmatter + Markdown 格式：

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

这个格式要求每条记忆都包含三个要素：是什么、为什么、怎么用。"Why"和"How to apply"两个字段确保记忆不是孤立的事实记录，而是有行动指导意义的知识单元。

### MEMORY.md 索引

目录下有一个 MEMORY.md 文件充当索引，它始终加载到上下文中：

```markdown
# Memory Index

- [用户角色](user_role.md) — 数据科学家，关注可观测性/日志
- [测试策略](feedback_testing.md) — 集成测试用真实数据库，不 mock
- [合并冻结](project_freeze.md) — 2026-03-05 起冻结非关键合并
- [Bug 追踪](reference_linear.md) — 流水线 bug 在 Linear INGEST 项目
```

这个索引文件有硬限制：最多 200 行或 25KB，超出会被截断。这个设计迫使索引保持精炼，详细内容只在需要时通过智能检索加载。

## 自动提取机制

Memory 不需要用户手动维护。系统每次模型完成回复（无 tool_use）时自动检查是否需要提取新记忆。

提取流程经过四道门控：确认是主代理执行、自动记忆功能已开启、频率控制（默认每轮检查一次）、以及互斥检查（主代理自己在当前轮次已经写过记忆则跳过）。通过门控后，系统启动一个分叉代理来执行提取，这个分叉代理共享父会话的提示词缓存，最多执行 5 个 turn，工具权限被严格限制。

```typescript
function createAutoMemCanUseTool(memoryDir: string): CanUseToolFn {
  return (toolName, input) => {
    // 允许读取类工具，用于扫描现有记忆
    if (['Read', 'Grep', 'Glob'].includes(toolName)) return true

    // Bash 只允许只读命令
    if (toolName === 'Bash' && isReadOnlyCommand(input.command)) return true

    // 写入工具仅限 memory 目录内
    if (['Edit', 'Write'].includes(toolName)) {
      return isInsideMemoryDir(input.file_path, memoryDir)
    }

    // MCP、Agent、非只读 Bash 全部拒绝
    return false
  }
}
```

这个权限设计有明确的安全意图：提取代理只能读取项目文件和写入 memory 目录，不能修改项目代码、不能调用外部服务、不能启动子代理。即使提取过程出错，影响范围也被限制在 memory 目录内。

互斥机制防止重复保存。如果主代理在当前轮次已经通过 Write/Edit 操作过 memory 目录，自动提取就会跳过，避免同一条信息被重复记录。

```typescript
function hasMemoryWritesSince(messages: Message[], sinceUuid: string): boolean {
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

## 智能检索与新鲜度管理

Memory 不是全量加载到上下文的。系统用 Sonnet 模型作为选择器，每次用户查询时动态筛选最相关的记忆。

```typescript
async function findRelevantMemories(
  query: string, memoryDir: string, recentTools: string[] = [],
): Promise<RelevantMemory[]> {
  const files = await scanMemoryFiles(memoryDir)
  const candidates = await Promise.all(files.map(f => parseMemoryFile(f)))

  // 用 Sonnet 模型从候选中选择相关记忆
  const selected = await sideQuery({
    model: 'claude-sonnet-4-5',
    systemPrompt: MEMORY_SELECTOR_PROMPT,
    messages: [{ role: 'user', content: query }],
    context: { candidates, recentTools },
  })

  return selected.map(s => ({ path: s.path, mtimeMs: s.mtimeMs }))
}
```

选择器最多选 5 条记忆，不确定是否有用的就不选。这个设计控制了额外引入的 token 开销，同时避免了无关记忆对模型的干扰。

记忆是有时效性的。一条三个月前记录的"合并冻结"可能早已解除，半年前的项目决策可能已被推翻。系统对旧记忆附带新鲜度警告：

```typescript
function memoryFreshnessText(mtimeMs: number): string {
  const days = memoryAgeDays(mtimeMs)
  if (days <= 1) return ''  // 今天/昨天：无警告
  return `This memory is ${days} days old. Memories are point-in-time
observations that may become stale. Verify against current code before
asserting as fact.`
}
```

超过一天的记忆就会被标注时效提醒，要求模型在引用前验证当前代码状态。这个机制解决了记忆系统的核心矛盾：既要跨会话保留信息，又要避免过时信息误导决策。

## 团队同步

团队成员的 Memory 可以通过 API 同步共享：

```
GET  /api/claude_code/team_memory?repo={owner/repo}  ← 拉取
PUT  /api/claude_code/team_memory?repo={owner/repo}  ← 推送
```

同步采用服务器优先的语义：Pull 时服务器内容覆盖本地，Push 时只上传哈希不同的增量内容。本地删除不会删除远程记录，下次 Pull 时会被恢复。冲突通过 412 状态码触发重试，最多 2 次。

```typescript
async function pushTeamMemory(state): Promise<PushResult> {
  const localFiles = await readLocalMemoryFiles()
  const localHashes = computeHashes(localFiles)
  const delta = computeDelta(localHashes, state.serverChecksums)

  const response = await api.pushTeamMemory(delta)

  // 412 冲突：获取最新 checksums 后重试
  if (response.status === 412) {
    const latest = await api.getTeamMemoryHashes()
    const newDelta = computeDelta(localHashes, latest)
    return pushTeamMemory({ ...state, serverChecksums: latest })
  }

  return { success: true }
}
```

安全方面，单文件上限 250KB，上传体上限 200KB，并使用 gitleaks 规则扫描凭证，检测到密钥或密码则跳过该文件，防止敏感信息泄露到团队共享空间。

## AutoDream：后台记忆整合

随着对话积累，Memory 目录会逐渐膨胀。AutoDream 是一个后台任务，定期对记忆进行整合、去重和修剪。

触发条件有四道门控：距离上次整合至少 24 小时、期间至少经历了 5 次会话、没有其他进程正在执行整合、以及 10 分钟的扫描节流。

```typescript
async function shouldTriggerAutoDream(): Promise<boolean> {
  if (hoursSinceLastConsolidation < minHours) return false          // 默认 24h
  if (sessionsSinceLastConsolidation < minSessions) return false    // 默认 5 次
  if (otherProcessConsolidating) return false                       // 互斥锁
  if (timeSinceLastScan < 10 * 60 * 1000) return false              // 10 分钟节流
  return true
}
```

整合过程分四个阶段：定向（确定要审查的会话列表）、收集（从会话中提取候选记忆）、整合（合并、去重、更新记忆文件）、修剪（删除过时或重复的记忆）。这个流程类似于人类睡眠时的记忆整理过程，将碎片化的短期记忆整合为结构化的长期知识。

## 关键源文件

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

---

**系列文章导航：**
- 上一篇：[权限与安全：分层模型与人机协作](/2026/04/06/083_claude-code-permission-security/)
- 下一篇：[Channel 系统：IM 远程控制 Agent](/2026/04/06/078_claude-code-channel-system/)
