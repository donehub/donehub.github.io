---
title: SDD（规格驱动开发）：AI 编码时代的必修方法论
date: 2025-12-24
tags: SDD
categories: AI
---

## 一、为什么 SDD 突然火了？

2025 年下半年，GitHub 上突然冒出两个"爆款"项目：

| 项目 | Stars | 出品方 | 创建时间 |
|------|-------|--------|----------|
| **spec-kit** | 87,549 | GitHub 官方 | 2025-08 |
| **OpenSpec** | 39,543 | Fission AI | 2025-08 |

两个项目都主打同一个概念——**SDD（Specification-Driven Development，规格驱动开发）**。

有意思的是，SDD 这个概念早在 2010 年左右就有人提过，但一直不温不火。为什么到了 2025 年突然"爆了"？

答案很简单：**AI 编码助手成熟了**。

以前写规格是为了"人理解需求"，现在写规格是为了"AI 理解需求并生成代码"。这个转变，让 SDD 从"锦上添花"变成了"必备技能"。

---

## 二、SDD 的起源与发展

### 2.1 方法论的演进脉络

软件开发方法论一直在"左移"——把质量保障的关口往前推：

```
传统开发：需求 → 编码 → 测试 → 部署
         ↑______________| 问题发现太晚

TDD（2003）：测试 → 编码 → 重构
            ↑_____| 先写测试，确保可测试

BDD（2006）：行为描述 → 测试 → 编码
            ↑__________| 用自然语言描述行为

SDD（2025）：规格 → AI生成代码 → 审查验证
            ↑______________| 先写清楚"要什么"，AI 再生成"怎么做"
```

用一个生活类比：

| 方法论 | 类比 |
|--------|------|
| 传统开发 | 厨师边做菜边尝，最后才发现盐放多了 |
| TDD | 先准备好品尝标准，做菜过程中不断对照 |
| BDD | 先写好"菜谱描述"（这道菜应该有什么味道），再让厨师做 |
| **SDD** | 先写好"完整菜单规格"（食材、步骤、口味），让 AI 厨师按规格来做 |

### 2.2 为什么以前 SDD 不火？

SDD 的核心思想是"先写规格再写代码"，听起来很合理。但以前有三大障碍：

1. **人写代码比写规格快**：资深程序员脑子里有模板，写代码比写文档快多了
2. **规格容易过时**：代码改了，规格忘了同步，最后变成"摆设"
3. **没有工具支撑**：规格只是 Markdown 文档，没法"执行"，也没法验证代码是否符合规格

### 2.3 为什么现在突然火了？

2024-2025 年，三个关键条件同时成熟：

| 条件 | 变化 |
|------|------|
| **AI 编码工具成熟** | Claude Code、Cursor、Copilot 能真正写出可用代码 |
| **开发者角色转变** | 从"代码编写者"变成"规格设计者 + 代码审查者" |
| **工具链完善** | spec-kit、OpenSpec 提供了规格的"执行框架" |

一个数据：预计到 2026 年，**80% 的开发者将常态化使用 AI 编码工具**。开发者花在规格设计和架构上的时间将超过写代码的时间。

---

## 三、SDD 的核心能力

### 3.1 一句话定义

**SDD = 先用结构化规格精确描述"要做什么"，再让 AI 照着规格生成代码，最后验证代码是否符合规格。**

### 3.2 核心能力拆解

| 能力 | 说明 |
|------|------|
| **协作澄清** | 开发者可能不清楚怎么做，AI 协助完成问题定义和方案探索——这是 SDD 最被低估的能力 |
| **规格即契约** | 规格不是"参考文档"，而是人机之间的"契约"——AI 必须按规格实现 |
| **迭代友好** | 规格可以随时更新，AI 会同步更新代码（不是"写完就扔"） |
| **验证闭环** | 有工具验证代码是否符合规格，偏离时自动提醒 |
| **追溯性强** | 每一行代码都能追溯到对应的规格条款 |

### 3.3 协作澄清：SDD 最被低估的能力

很多人以为 SDD 是"开发者先写清楚规格，再让 AI 照着做"。但现实是：**开发者往往也不清楚自己要什么**。

这时候，SDD 的"澄清模式"就派上用场了：

```
传统模式：开发者想清楚 → 写规格 → AI 实现
澄清模式：开发者有个模糊想法 → AI 协助澄清 → 共同定义问题 → 探索方案 → 写规格 → AI 实现
```

用一个类比：

| 场景 | 类比 |
|------|------|
| 传统 SDD | 你拿着完整菜单去餐厅，厨师照着做 |
| **澄清模式** | 你说"我想吃点清淡的"，厨师和你讨论：是汤？是蒸菜？有什么忌口？最后一起定菜单 |

这就是 `/speckit.clarify` 或 `/opsx:explore` 模式的价值——**AI 不是被动执行者，而是主动的"需求澄清伙伴"**。

### 3.4 规格包含什么？

一个完整的 SDD 规格通常包含四个部分：

```
openspec/changes/add-dark-mode/
├── proposal.md      # 为什么做这个改动？影响范围？
├── specs/           # 详细需求规格
│   ├── requirements.md  # 功能需求
│   └── scenarios.md     # 使用场景
├── design.md        # 技术方案：怎么实现？
└── tasks.md         # 任务清单：分几步完成？
```

### 3.5 与 TDD/BDD 的关系

SDD 不是替代 TDD/BDD，而是它们的"前置层"：

```
┌─────────────────────────────────────────────────────┐
│                    SDD                              │
│  规格 → 定义"要做什么"                               │
├─────────────────────────────────────────────────────┤
│                    BDD                              │
│  行为描述 → 定义"应该有什么行为"                      │
├─────────────────────────────────────────────────────┤
│                    TDD                              │
│  测试 → 定义"怎么验证正确性"                         │
├─────────────────────────────────────────────────────┤
│                    实现                             │
│  代码 → AI 按上述三层约束生成                        │
└─────────────────────────────────────────────────────┘
```

---

## 四、如何与 Code Agent 配合使用

### 4.1 工作流程对比

**没有 SDD 时的工作流**：

```
你：帮我加个深色模式
AI：（直接开始写代码）好的，我创建 ThemeContext...
你：等等，我想要的是 localStorage 持久化
AI：那我改一下...
你：还要支持系统主题自动切换
AI：再改一下...
你：切换按钮放在导航栏右侧
AI：...

问题：需求在"聊天中不断补充"，AI 来回改，效率低
```

**有 SDD 时的工作流**：

```
你：/opsx:propose "添加深色模式"
AI：生成完整规格 → proposal + specs + design + tasks
你：（审查规格）嗯，规格里漏了 localStorage 持久化，补一下
AI：（更新规格）
你：（确认无误）/opsx:apply
AI：按规格一次性实现，不用来回改

优势：先对齐"要做什么"，再一次性实现
```

### 4.2 支持的 Code Agent

| Code Agent | spec-kit 支持 | OpenSpec 支持 |
|------------|--------------|---------------|
| **Claude Code** | ✅ `--ai claude` | ✅ `/opsx:*` 命令 |
| **Cursor** | ✅ slash commands | ✅ slash commands |
| **GitHub Copilot CLI** | ✅ 原生支持 | ✅ skills 模式 |
| **Codex CLI** | ✅ skills 模式 | ✅ skills 模式 |
| **Windsurf** | ✅ | ✅ |

---

## 五、问题澄清模式：当你不知道怎么做时

前面讲的流程都有一个前提：开发者知道"要做什么"。但现实往往是：

> "我想给博客加个评论功能，但不知道怎么设计..."
> "用户反馈搜索太慢，但我不清楚具体慢在哪里..."
> "产品说要提升用户体验，但这个需求太模糊了..."

这时候，**澄清模式（Clarify/Explore）** 就派上用场了。

### 5.1 澄清模式的价值

| 澄清前 | 澄清后 |
|--------|--------|
| "我想加评论功能"（模糊） | "评论功能需要：登录才能评论、支持楼中楼、可编辑删除、有审核机制"（清晰） |
| "搜索太慢"（笼统） | "问题定位：首页搜索接口响应 3s+，原因是全文检索没走索引，需要优化 SQL 并加缓存"（具体） |
| "提升用户体验"（抽象） | "具体方案：页面加载加骨架屏、关键操作加确认弹窗、表单加实时校验提示"（可落地） |

**澄清过程本身就是在"定义问题"**——很多 Bug 的根因不是代码写错了，而是需求本身就没想清楚。

### 5.2 spec-kit 的澄清流程

使用 `/speckit.clarify` 命令：

```
你：/speckit.clarify "我想给博客加个评论功能"

AI：让我帮你澄清一下这个需求...
    Q1: 评论需要登录才能发吗？
    你：是的，必须登录

    Q2: 评论支持回复别人的评论吗？（楼中楼）
    你：支持，最多嵌套 3 层

    Q3: 评论发出去能编辑或删除吗？
    你：发出去 5 分钟内可以编辑，用户自己发的可以删除

    Q4: 评论需要审核吗？还是直接显示？
    你：需要审核，管理员后台审核后才显示

    AI：好的，我来整理一下澄清后的需求...

    [生成 clarification.md]
    ✓ 问题边界已明确
    ✓ 关键决策已记录
    ✓ 可以进入规格编写阶段

你：/speckit.spec blog-comment-system
```

### 5.3 OpenSpec 的探索流程

使用 `/opsx:explore` 命令：

```
你：/opsx:explore "用户反馈搜索太慢，想优化一下"

AI：让我先帮你分析问题...

    1. 定位问题范围：
       - 是首页搜索慢？还是后台管理搜索？
       - 是所有搜索都慢？还是特定关键词？
       - "慢"的标准是什么？2s？5s？

    你：首页的全站搜索，大概 3-4 秒才出结果，用户说体验很差

    2. 排查可能原因：
       - 检查当前实现：全文检索 LIKE '%keyword%'
       - 数据量：posts 表 10万+，没走索引
       - 缓存策略：无缓存，每次查库

    3. 方案探索：
       方案A：加全文索引（MySQL FULLTEXT）
       方案B：引入 Elasticsearch
       方案C：加 Redis 缓存热点关键词

       各方案对比：
       | 方案 | 成本 | 效果 | 维护难度 |
       |------|------|------|----------|
       | A | 低 | 中（大数据量仍慢） | 低 |
       | B | 高 | 高 | 高（新增组件） |
       | C | 低 | 中（命中率依赖） | 低 |

       建议组合方案：A + C，先加索引打底，再加缓存加速热点

    你：就用 A + C 组合方案

    AI：好的，我来生成探索记录...

    [生成 openspec/explorations/search-optimization/]
    ✓ exploration.md — 问题分析 + 方案对比
    ✓ decision.md — 最终选择的方案 + 原因
    ✓ 可以进入 /opsx:propose 阶段
```

### 5.4 澄清模式的核心价值

用一个公式总结：

```
需求质量 = 澄清深度 × 规格精度 × 验证闭环
```

**澄清是起点**。如果一开始需求就模糊，后面写再详细的规格、做再严格的验证，都是"在错误的方向上努力"。

很多项目的返工、延期，根因都在这里：

| 返工原因 | 根因 |
|----------|------|
| "这不是我想要的" | 澄清不够，理解偏差 |
| "需求又变了" | 边界没定清楚，后面不断加范围 |
| "实现方案不对" | 没探索充分，选错了技术路线 |

**SDD 的澄清模式，就是帮你把这些问题"前置解决"**——在写代码之前，先把问题聊清楚。

---

## 六、与 Claude Code 配合的安装步骤

### 6.1 spec-kit 安装

```bash
# 方式一：推荐安装稳定版本（v0.6.1）
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v0.6.1

# 方式二：安装最新版本
uv tool install specify-cli --from git+https://github.com/github/spec-kit.git

# 验证安装
specify check
```

初始化项目：

```bash
# 创建新项目
specify init my-project --ai claude

# 或在现有项目中初始化
specify init . --ai claude
```

### 6.2 OpenSpec 安装

```bash
# 需要 Node.js 20.19.0+
npm install -g @fission-ai/openspec@latest

# 验证安装
openspec --version

# 初始化项目
cd your-project
openspec init
```

---

## 七、实战示例：同一个需求，两种工具

需求：**为博客网站添加深色模式**

### 7.1 spec-kit 使用流程

#### 步骤 1：定义项目原则

```bash
cd my-project
claude
```

在 Claude Code 中执行：

```
> /speckit.constitution 创建项目核心原则：
  - 代码风格遵循 ESLint 规范
  - 所有 UI 组件需要单元测试
  - 新功能需要配套文档
```

AI 会生成 `.speckit/constitution.md` 文件。

#### 步骤 2：创建功能规格

```
> /speckit.spec add-dark-mode 创建深色模式功能规格

需求要点：
  - 支持亮色/深色/跟随系统三种模式
  - 用户偏好存储在 localStorage
  - 导航栏右侧放置切换按钮
  - 切换时平滑过渡动画
```

AI 会生成 `.speckit/features/add-dark-mode/spec.md`。

#### 步骤 3：生成实施计划

```
> /speckit.plan add-dark-mode
```

AI 生成 `.speckit/features/add-dark-mode/plan.md`，包含：
- 技术方案（用 React Context 还是 CSS 变量？）
- 文件改动清单
- 实施步骤

#### 步骤 4：分解任务

```
> /speckit.tasks add-dark-mode
```

生成 `.speckit/features/add-dark-mode/tasks.md`：

```markdown
## Tasks

### 1. 基础设施
- [ ] 1.1 创建 ThemeContext
- [ ] 1.2 定义 CSS 变量体系
- [ ] 1.3 创建 useTheme hook

### 2. UI 组件
- [ ] 2.1 创建 ThemeToggle 组件
- [ ] 2.2 添加过渡动画样式
- [ ] 2.3 集成到导航栏

### 3. 持久化
- [ ] 3.1 localStorage 存取逻辑
- [ ] 3.2 系统主题监听

### 4. 测试
- [ ] 4.1 ThemeContext 单元测试
- [ ] 4.2 ThemeToggle 组件测试
```

#### 步骤 5：执行实施

```
> /speckit.implement add-dark-mode
```

AI 按任务清单逐项实现代码。

#### 步骤 6：验证审查

```
> /speckit.verify add-dark-mode
```

AI 检查：
- 每个任务是否完成
- 代码是否符合规格
- 测试是否通过

---

### 7.2 OpenSpec 使用流程

#### 步骤 1：一键生成完整规格

```bash
cd my-project
claude
```

在 Claude Code 中执行：

```
> /opsx:propose "添加深色模式，支持亮色/深色/跟随系统三种模式，
  用户偏好存储在 localStorage，导航栏右侧放置切换按钮"
```

AI **一次性生成**完整规格目录：

```
openspec/changes/add-dark-mode/
├── proposal.md      # ✅ 为什么做？影响哪些页面？
├── specs/
│   ├── requirements.md  # ✅ 功能需求详情
│   └── scenarios.md     # ✅ 用户使用场景
├── design.md        # ✅ 技术方案：React Context + CSS 变量
└── tasks.md         # ✅ 实施任务清单
```

#### 步骤 2：审查并调整规格

```
> 打开 specs/requirements.md，补充一个需求：
  切换按钮需要显示当前模式图标（太阳/月亮/电脑）
```

AI 更新规格文件。

#### 步骤 3：执行实施

```
> /opsx:apply
```

输出：

```text
AI: Implementing tasks...
     ✓ 1.1 Create ThemeContext provider
     ✓ 1.2 Define CSS variable system
     ✓ 1.3 Create useTheme hook
     ✓ 2.1 Create ThemeToggle component
     ✓ 2.2 Add transition animation
     ✓ 2.3 Integrate to navbar
     ✓ 3.1 localStorage logic
     ✓ 3.2 System theme listener
     ✓ 4.1 Unit tests
     ✓ 4.2 Component tests
     All tasks complete!
```

#### 步骤 4：归档

```
> /opsx:archive
```

AI 将完成的变更归档：

```text
Archived to openspec/changes/archive/2026-04-13-add-dark-mode/
Specs updated. Ready for the next feature.
```

---

## 八、spec-kit vs OpenSpec：如何选择？

| 维度 | spec-kit | OpenSpec |
|------|----------|----------|
| **出品方** | GitHub 官方 | Fission AI（创业公司） |
| **风格** | 工程化、严谨 | 灵活、快速 |
| **安装** | Python + uv | Node.js + npm |
| **流程** | 分步执行（6 个命令） | 一键生成 + 一键应用 |
| **扩展性** | 40+ 官方扩展 | 配置化定制 |
| **适合场景** | 大型项目、团队协作 | 个人项目、快速迭代 |
| **学习曲线** | 较陡（概念多） | 较平（上手快） |

### 选择建议

```
如果你是...
├─ 大型团队，需要严格控制 → 选 spec-kit
├─ 个人开发者，追求效率 → 选 OpenSpec
├─ Python 项目 → spec-kit（工具链一致）
├─ TypeScript/JS 项目 → OpenSpec（工具链一致）
└─ 想快速体验 SDD → 先试 OpenSpec，再学 spec-kit
```

---

## 九、总结：SDD 是 AI 编码时代的"必修课"

回顾一下：

1. **SDD 不是新概念**，但 AI 编码工具让它变得至关重要
2. **核心能力**：协作澄清、规格即契约、迭代友好、验证闭环、追溯性强
3. **澄清模式**：当你不知道怎么做时，AI 协助你把需求聊清楚——这是最被低估的能力
4. **与 Code Agent 配合**：先对齐"要做什么"，再让 AI 一次性实现
5. **两个主流工具**：spec-kit（GitHub 官方）、OpenSpec（灵活高效）

一句话总结：

> **以前写代码靠"手艺"，现在写代码靠"规格"。写得越清楚，AI 生成得越精准。**
> 
> 如果你自己都不清楚要什么，先用澄清模式把需求聊明白——这才是 SDD 的起点。

---

## 参考资料

- [GitHub spec-kit](https://github.com/github/spec-kit) — 87k+ Stars
- [Fission-AI OpenSpec](https://github.com/Fission-AI/OpenSpec) — 39k+ Stars
- [The Rise of SDD in the AI Era](https://dev.to/the-rise-of-specification-driven-development-in-the-ai-era)
- [SDD Complete Guide](https://devops.com/specification-driven-development-a-complete-guide/)