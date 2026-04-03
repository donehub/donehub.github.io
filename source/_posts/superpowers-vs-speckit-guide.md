---
title: Superpowers 介绍与使用
date: 2026-02-15
tags: AI 工具
categories: AI
---

## 一、写在前面：为什么需要 Superpowers？

你有没有遇到过这样的场景：

- 让 AI 帮你写代码，它一上来就开始"输出"，完全不考虑你的真实需求
- AI 写的代码看似没问题，但测试一跑就崩，因为它根本没写测试
- AI "自主工作"了半小时，结果偏离了原需求十万八千里
- 多个功能并行开发，AI 把代码混在一起，最后连回滚都困难

**Superpowers** 就是解决这些问题的"流程管家"。它不是让 AI 更聪明，而是让 AI **更靠谱**——先规划、再测试、再实现、再审查，像真正工程师一样工作。

---

## 二、Superpowers 是什么？

### 2.1 一句话定义

**Superpowers** 是由 Jesse Vincent（Perl 专家、Markdown 发明者之一）开发的软件开发工作流系统，通过一系列"技能(Skills)"让 AI 编码助手遵循严格的工程流程。

### 2.2 核心理念

打个比方：

| 没有 Superpowers | 有 Superpowers |
|-----------------|----------------|
| AI 像是个"热情但冲动的新手"——拿到任务就写代码，写完就交 | AI 像是个"老练的资深工程师"——先问清楚需求，写测试，再实现，最后审查 |
| 容易偏离需求 | 强制按计划执行 |
| 测试是"事后补的" | 测试是"先写的"（TDD） |
| 一个分支干所有事 | Git Worktree 隔离开发 |

### 2.3 支持的 AI 工具

| 工具 | 安装方式 |
|------|----------|
| **Claude Code** | `/plugin install superpowers@claude-plugins-official` |
| **Cursor** | `/add-plugin superpowers` |
| **GitHub Copilot CLI** | `copilot plugin install superpowers` |
| **Gemini CLI** | `gemini extensions install` |
| **Codex CLI** | 手动配置（见后文） |
| **OpenCode** | 手动配置 |

---

## 三、核心工作流程详解

### 3.1 七步流程

Superpowers 强制 AI 遵循以下流程：

```
┌──────────────────────────────────────────────────────────────────────┐
│                     Superpowers 工作流程                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  1. brainstorming (头脑风暴)                                         │
│     └─► AI 不直接写代码，先问你"到底想做什么"                          │
│     └─► 通过苏格拉底式提问，提炼出清晰的设计文档                       │
│                                                                      │
│  2. using-git-worktrees (创建隔离工作空间)                           │
│     └─► 自动创建新分支 + Git Worktree                                │
│     └─► 确保开发环境干净、可回滚                                      │
│                                                                      │
│  3. writing-plans (编写计划)                                         │
│     └─► 将设计拆成 2-5 分钟的小任务                                   │
│     └─► 每个任务包含：文件路径、代码、验证步骤                        │
│                                                                      │
│  4. subagent-driven-development (子代理执行)                         │
│     └─► 每个任务派发一个新的子代理                                    │
│     └─► 主代理审查子代理的工作                                        │
│     └─► 可连续自主工作数小时                                          │
│                                                                      │
│  5. test-driven-development (强制 TDD)                               │
│     └─► RED: 先写失败的测试                                           │
│     └─► GREEN: 写最少代码让测试通过                                   │
│     └─► REFACTOR: 优化代码                                           │
│     └─► 如果代码先于测试写了，会被删除！                              │
│                                                                      │
│  6. requesting-code-review (代码审查)                                │
│     └─► 每个任务完成后自动审查                                        │
│     └─► 两阶段审查：规格合规 + 代码质量                               │
│     └─► 关键问题会阻塞进度                                            │
│                                                                      │
│  7. finishing-a-development-branch (完成分支)                        │
│     └─► 验证所有测试通过                                              │
│     └─► 提供：合并 / PR / 保留 / 丢弃选项                            │
│     └─► 清理 Worktree                                                │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### 3.2 为什么这套流程有效？

**问题 1：AI 容易"跑偏"**

传统 AI 编码：
```
用户：帮我加个登录功能
AI：好的，开始写代码...
（30分钟后）
AI：登录功能写好了，还顺便加了注册、找回密码、OAuth...
用户：？？我只想要个简单的登录啊
```

有 Superpowers：
```
用户：帮我加个登录功能
AI (brainstorming)：让我先理解一下：
  - 登录方式是什么？账号密码？OAuth？
  - 需要记住登录状态吗？多久？
  - 安全要求是什么？
用户：账号密码登录，记住 7 天，简单安全就行
AI：好的，我来写设计文档，你确认后再动手
（用户确认后）
AI：现在开始实现，每个任务都会按计划执行
```

**问题 2：AI 不写测试**

传统 AI 编码：
```
AI：功能写完了！
用户：测试呢？
AI：呃...我补一下
（补的测试可能根本测不到关键逻辑）
```

有 Superpowers（强制 TDD）：
```
AI：现在要实现登录验证
AI：先写测试（RED）→ 测试失败 ✓
AI：再写代码（GREEN）→ 测试通过 ✓
AI：重构优化（REFACTOR）→ 测试仍通过 ✓
AI：继续下一个任务
```

**问题 3：多功能开发混乱**

传统方式：
```
main 分支上同时开发 3 个功能
功能 A 改了文件 X
功能 B 也改了文件 X
功能 C 又改了文件 X
→ 冲突灾难
```

有 Superpowers（Git Worktree）：
```
功能 A → worktree/feature-a/ (独立目录)
功能 B → worktree/feature-b/ (独立目录)
功能 C → worktree/feature-c/ (独立目录)
→ 完全隔离，互不影响
```

---

## 四、安装配置实战

### 4.1 Claude Code 安装（推荐）

**方式一：官方插件市场（最简单）**

```bash
# 在 Claude Code 中执行
/plugin install superpowers@claude-plugins-official
```

**方式二：第三方市场**

```bash
# 先注册市场
/plugin marketplace add obra/superpowers-marketplace

# 再安装插件
/plugin install superpowers@superpowers-marketplace
```

**验证安装：**

```bash
# 查看已安装插件
/plugin list

# 应该看到 superpowers
```

### 4.2 Cursor 安装

在 Cursor Agent 聊天中：

```
/add-plugin superpowers
```

或者在插件市场搜索 "superpowers"。

### 4.3 GitHub Copilot CLI 安装

```bash
# 注册市场
copilot plugin marketplace add obra/superpowers-marketplace

# 安装插件
copilot plugin install superpowers@superpowers-marketplace
```

### 4.4 Codex CLI 手动安装

Codex 目前没有插件市场，需要手动配置：

**步骤 1：获取技能文件**

```bash
# 克隆仓库
git clone https://github.com/obra/superpowers.git

# 复制技能到 Codex 目录
mkdir -p ~/.codex/skills
cp -r superpowers/skills/* ~/.codex/skills/
```

**步骤 2：配置 Codex**

创建或编辑 `~/.codex/config.json`：

```json
{
  "skillsDirectory": "~/.codex/skills"
}
```

**步骤 3：验证**

启动 Codex 后，技能会自动加载。

### 4.5 Gemini CLI 安装

```bash
# 安装扩展
gemini extensions install https://github.com/obra/superpowers

# 更新
gemini extensions update superpowers
```

### 4.6 更新插件

```bash
# Claude Code
/plugin update superpowers

# Copilot CLI
copilot plugin update superpowers

# Gemini CLI
gemini extensions update superpowers
```

---

## 五、使用实战：从零开始

### 5.1 触发技能

Superpowers 的技能会**自动触发**。你不需要特殊命令，只需要用自然语言描述需求。

**示例：启动一个新功能**

```
我想给博客系统加一个评论功能，支持用户登录后评论
```

AI 会自动调用 `brainstorming` 技能：

```
AI：让我先理解你的需求...

问题 1：评论需要审核吗？还是直接发布？
问题 2：评论可以回复吗？支持嵌套？
问题 3：评论内容有什么限制？字数、格式？
问题 4：需要通知博主吗？邮件？站内？

请逐一回答，我会根据你的回答设计功能。
```

### 5.2 头脑风暴阶段

**你的回答：**

```
评论不需要审核，直接发布
支持回复，但不嵌套（最多一层）
评论最多 500 字，不能发链接
不需要通知
```

**AI 会生成设计文档：**

```markdown
## 评论功能设计文档

### 核心需求
- 用户登录后可评论
- 评论直接发布，无需审核
- 支持回复评论（一层）

### 技术方案
- 数据表：comments (id, user_id, post_id, content, parent_id, created_at)
- API：POST /comments, GET /comments/:post_id
- 前端：评论框 + 评论列表 + 回复按钮

### 验收标准
- 登录用户可发表评论
- 可回复他人评论
- 评论字数限制 500 字
- 不允许发送链接
```

**你确认后，AI 进入下一阶段。**

### 5.3 Git Worktree 阶段

AI 会自动：

```bash
# 创建新分支
git checkout -b feature/comments

# 创建 Worktree（独立工作目录）
git worktree add .claude/worktrees/feature-comments feature/comments

# 在 Worktree 中初始化环境
cd .claude/worktrees/feature-comments
npm install  # 或其他项目初始化命令

# 验证测试基线
npm test     # 确保当前测试都通过
```

**Worktree 的好处：**

```
你的主项目目录:     /projects/my-blog/
评论功能 Worktree:  /projects/my-blog/.claude/worktrees/feature-comments/

两个目录完全独立！
你可以在主目录继续其他工作
AI 在 Worktree 专心开发评论功能
```

### 5.4 编写计划阶段

AI 会把设计拆成小任务：

```markdown
## 实现计划

### 任务 1：创建评论数据模型 (预计 3 分钟)
- 文件：`src/models/comment.js`
- 代码：定义 Comment schema
- 验证：模型可正确创建实例

### 任务 2：添加评论 API (预计 5 分钟)
- 文件：`src/routes/comments.js`
- 代码：POST /comments, GET /comments/:post_id
- 验证：API 测试通过

### 任务 3：评论前端组件 (预计 10 分钟)
- 文件：`src/components/CommentBox.jsx`, `src/components/CommentList.jsx`
- 代码：评论输入框、评论列表、回复按钮
- 验证：组件渲染正确，可交互

### 任务 4：字数限制和链接过滤 (预计 3 分钟)
- 文件：`src/utils/commentValidator.js`
- 代码：验证函数
- 验证：超过 500 字拒绝，包含链接拒绝

### 任务 5：集成测试 (预计 5 分钟)
- 文件：`tests/comment.test.js`
- 代码：完整流程测试
- 验证：测试通过
```

**任务粒度原则：**

- 每个任务 **2-5 分钟**
- 有**明确的文件路径**
- 有**验证步骤**

### 5.5 子代理执行阶段

这是 Superpowers 的核心亮点：

```
┌─────────────────────────────────────────────────────────────┐
│                    子代理驱动开发                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  主代理 (你对话的 AI)                                        │
│      │                                                      │
│      ├──► 派发子代理 1 → 执行任务 1 (创建模型)               │
│      │        │                                             │
│      │        └──► 完成后返回结果                            │
│      │                                                      │
│      ├──► 主代理审查：符合设计？代码质量？                    │
│      │                                                      │
│      ├──► 派发子代理 2 → 执行任务 2 (添加 API)               │
│      │        │                                             │
│      │        └──► 完成后返回结果                            │
│      │                                                      │
│      ├──► 主代理审查...                                     │
│      │                                                      │
│      └──► 继续执行...                                       │
│                                                             │
│  优势：                                                      │
│  - 每个任务用"新鲜"的子代理，无上下文污染                    │
│  - 主代理审查，确保质量                                      │
│  - 可连续自主工作数小时                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**你的体验：**

```
AI：开始执行任务 1...
AI：任务 1 完成，审查中...
AI：审查通过 ✓，继续任务 2...
AI：任务 2 完成，审查中...
AI：发现一个小问题，已修复 ✓
AI：继续任务 3...
（你可以去喝咖啡了）
AI：所有任务完成！
```

### 5.6 TDD 阶段（强制）

**Superpowers 的 TDD 是真正的 RED-GREEN-REFACTOR：**

```javascript
// 步骤 1：RED - 先写失败的测试
describe('CommentValidator', () => {
  it('should reject comment longer than 500 chars', () => {
    const longComment = 'a'.repeat(501);
    expect(validateComment(longComment)).toBe(false);
  });
});

// 运行测试 → 失败 ✓ (因为 validateComment 还不存在)

// 步骤 2：GREEN - 写最少代码让测试通过
function validateComment(content) {
  if (content.length > 500) return false;
  return true;
}

// 运行测试 → 通过 ✓

// 步骤 3：REFACTOR - 优化代码
function validateComment(content) {
  const MAX_LENGTH = 500;
  const LINK_PATTERN = /https?:\/\/\S+/;

  if (content.length > MAX_LENGTH) return false;
  if (LINK_PATTERN.test(content)) return false;
  return true;
}

// 运行测试 → 仍通过 ✓
```

**如果 AI 先写了代码再写测试？**

```
AI 会删除代码，重新从测试开始写！
这是强制的，不是建议。
```

### 5.7 代码审查阶段

每个任务完成后，主代理会审查：

**审查维度：**

| 维度 | 检查内容 |
|------|----------|
| **规格合规** | 是否符合设计文档？ |
| **代码质量** | 可读性、命名、结构 |
| **测试覆盖** | 测试是否充分？ |
| **安全性** | 有无安全漏洞？ |

**审查结果：**

```
审查报告：

✓ 规格合规：符合设计文档
⚠ 代码质量：变量命名可优化（comment → userComment）
✓ 测试覆盖：覆盖了主要场景
✓ 安全性：无明显问题

建议：优化变量命名后继续
```

**关键问题会阻塞进度：**

```
❌ 发现关键问题：API 缺少权限验证
   → 必须修复后才能继续
```

### 5.8 完成分支阶段

所有任务完成后：

```
AI：所有任务完成！验证测试...
AI：所有测试通过 ✓

请选择下一步：
[1] 合并到主分支
[2] 创建 Pull Request
[3] 保留分支（暂不合并）
[4] 丢弃所有更改

你的选择？
```

**选择后，AI 会：**

```bash
# 如果选择合并
git checkout main
git merge feature/comments
git worktree remove .claude/worktrees/feature-comments

# 如果选择创建 PR
gh pr create --title "Add comment feature" --body "..."
```

---

## 六、与 GitHub SpecKit 的对比

### 6.1 两者是什么关系？

**Superpowers** 和 **GitHub SpecKit** 都是"规范驱动开发"的工具，但理念和实现方式不同。

| 特性 | Superpowers | GitHub SpecKit |
|------|-------------|----------------|
| **开发者** | Jesse Vincent（独立开发者） | **GitHub 官方** |
| **形态** | Skills 插件系统 | CLI + Skills + Extensions 生态 |
| **核心理念** | **流程至上** - 强制 TDD、强制审查 | **规范至上** - spec 成为可执行文档 |
| **安装方式** | `/plugin install` | `uv tool install specify-cli` |
| **项目宪法** | 无 | `/speckit.constitution` 创建 |
| **产出文件** | 动态生成 | 固定：spec.md, plan.md, tasks.md |
| **TDD** | **强制** RED-GREEN-REFACTOR | 推荐但不强制 |
| **Git Worktree** | 自动创建 | 无内置 |
| **子代理执行** | **内置** subagent-driven | 通过扩展实现 |
| **可视化 UI** | 无 | VS Code 扩展支持 |
| **外部集成** | 有限 | Jira、Azure DevOps、Linear 等 40+ 扩展 |

### 6.2 核心哲学差异

**Superpowers：流程至上**

```
核心理念："让 AI 不犯错误"

方式：强制工程流程
- 不写测试就不能写代码
- 不审查就不能继续
- 不隔离就不能开发

适合：个人开发者、追求代码质量
```

**SpecKit：规范至上**

```
核心理念："让规范成为第一性原理"

方式：规范可执行
- spec.md 直接生成代码
- 规范是"活的"，不是文档
- 专注于"做什么"，而非"怎么做"

适合：团队协作、需要外部集成
```

### 6.3 工作流对比

**Superpowers 流程：**

```
需求 → 头脑风暴 → Worktree → 计划 → 子代理执行 → TDD → 审查 → 完成分支
       ↑          ↑          ↑           ↑         ↑      ↑
     问清楚     隔离环境   拆任务      自动执行    强制   质量保证
```

**SpecKit 流程：**

```
宪法 → Specify → Plan → Tasks → Implement
 ↑      ↑        ↑       ↑        ↑
原则   需求     技术    任务     执行
```

### 6.4 SpecKit 的独特优势

**1. 项目宪法**

```bash
# 定义项目原则
/speckit.constitution Create principles focused on:
- Code quality: clean code, no duplication
- Testing: unit tests required for all logic
- Performance: response time < 200ms
```

这会生成一个"宪法文件"，指导所有后续开发。

**2. 丰富的扩展生态**

| 扩展 | 功能 |
|------|------|
| `spec-kit-jira` | 同步到 Jira |
| `spec-kit-review` | 代码审查 |
| `spec-kit-qa` | QA 测试 |
| `spec-kit-ship` | 自动发布 |
| `superpowers-bridge` | **将 Superpowers 集成到 SpecKit！** |

**3. 预设系统**

可以自定义术语和模板：

```json
{
  "name": "pirate-speak",
  "templates": {
    "spec.md": "Voyage Manifest",
    "plan.md": "Battle Plan",
    "tasks.md": "Crew Assignments"
  }
}
```

### 6.5 Superpowers 的独特优势

**1. 强制 TDD**

```
这是最大的区别。
SpecKit 推荐 TDD，但 Superpowers 强制 TDD。
如果你先写代码再写测试，代码会被删除。
```

**2. Git Worktree 隔离**

```
每个功能在独立目录开发：
- 不影响主项目
- 可以并行开发多个功能
- 回滚简单（删除 worktree 即可）
```

**3. 子代理驱动**

```
每个任务派发新的子代理：
- 无上下文污染
- 主代理审查质量
- 可连续自主工作数小时
```

### 6.6 可以一起用吗？

**可以！** 社区已经创建了 `superpowers-bridge` 扩展：

```bash
# 在 SpecKit 项目中安装
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

# 安装 superpowers-bridge 扩展
# (详见扩展文档)
```

这样你可以：

- 用 SpecKit 管理规范和外部集成
- 用 Superpowers 的 TDD、Worktree、子代理执行

---

## 七、最佳实践与适用场景

### 7.1 适用场景建议

| 场景 | 推荐 |
|------|------|
| **个人开发者，追求代码质量** | Superpowers |
| **企业团队，需要外部集成** | SpecKit |
| **已有完善规范流程** | SpecKit（可定制扩展） |
| **需要长时间自主运行** | Superpowers（子代理可工作数小时） |
| **多功能并行开发** | Superpowers（Git Worktree） |
| **两者都需要** | SpecKit + superpowers-bridge |

### 7.2 使用 Superpowers 的建议

**建议 1：让 AI 问清楚再开始**

```
不要急着说"开始写代码"
等 AI 完成头脑风暴
仔细阅读设计文档
确认后再说"开始实现"
```

**建议 2：任务粒度要小**

```
好的任务：2-5 分钟，一个文件
不好的任务："实现整个评论功能"

小任务的好处：
- 更容易审查
- 更容易回滚
- 更容易并行
```

**建议 3：关注审查报告**

```
不要忽略审查报告中的警告
即使是"建议优化"
让 AI 修复后再继续
```

**建议 4：并行开发时用 Worktree**

```
如果你要同时开发 3 个功能：
功能 A → 让 AI 创建 worktree/feature-a
功能 B → 让 AI 创建 worktree/feature-b
功能 C → 让 AI 创建 worktree/feature-c

完全隔离，不会冲突
```

### 7.3 使用 SpecKit 的建议

**建议 1：先写宪法**

```bash
/speckit.constitution Define project principles first
```

宪法会指导所有后续开发，相当于"项目宪法"。

**建议 2：选择合适的扩展**

```
需要 Jira 集成？→ spec-kit-jira
需要代码审查？→ spec-kit-review
需要自动发布？→ spec-kit-ship
```

**建议 3：利用社区预设**

```
不想自己配置？
用社区预设：
- Agent Teams Lite（多代理）
- Pirate Speak（有趣模板）
```

---

## 八、常见问题

### Q1: Superpowers 和 SpecKit 可以同时用吗？

**可以。** 安装 `superpowers-bridge` 扩展即可。

### Q2: Superpowers 会让我写代码变慢吗？

**短期内可能变慢（因为要先规划、先写测试），但长期会更快（因为减少返工）。**

### Q3: 子代理执行安全吗？

**安全。** 子代理在隔离环境中执行，主代理审查结果。

### Q4: Git Worktree 会占用很多磁盘空间吗？

**会占用一些，但完成后会自动清理。** 你也可以手动清理：

```bash
git worktree list
git worktree remove <path>
```

### Q5: SpecKit 的扩展稳定吗？

**社区扩展由独立开发者维护，GitHub 官方不审核。** 使用前建议查看源代码。

---

## 九、总结

### 核心要点

1. **Superpowers 是流程管家**：让 AI 遵循严格的工程流程
2. **核心流程**：头脑风暴 → Worktree → 计划 → 子代理 → TDD → 审查 → 完成
3. **强制 TDD**：不写测试就不能写代码
4. **Git Worktree**：每个功能在独立目录开发
5. **子代理执行**：每个任务派发新的子代理，主代理审查

### 与 SpecKit 的核心区别

| 方面 | Superpowers | SpecKit |
|------|-------------|---------|
| **理念** | 流程至上 | 规范至上 |
| **TDD** | 强制 | 推荐 |
| **Worktree** | 自动 | 无内置 |
| **子代理** | 内置 | 通过扩展 |
| **生态** | 单一技能库 | 40+ 扩展 |

### 选择建议

```
追求代码质量、个人开发 → Superpowers
团队协作、外部集成     → SpecKit
两者都需要             → SpecKit + superpowers-bridge
```

### 学习路径

```
第 1 天：安装 Superpowers，体验头脑风暴
第 2 天：完整走一遍流程，感受 TDD
第 3 天：尝试并行开发（Worktree）
第 4 天：对比 SpecKit，选择适合你的
第 5 天：深入使用，定制你的工作流
```

---

## 参考资料

- [GitHub - obra/superpowers](https://github.com/obra/superpowers)
- [GitHub - github/spec-kit](https://github.com/github/spec-kit)
- [Superpowers 博客介绍](https://blog.fsck.com/2025/10/09/superpowers/)
- [Spec Kit 文档](https://github.github.io/spec-kit/)
- [superpowers-bridge 扩展](https://github.com/RbBtSn0w/spec-kit-extensions/tree/main/superpowers-bridge)
- [Discord 社区](https://discord.gg/Jd8Vphy9jq)

---