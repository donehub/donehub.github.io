---
title: SDD 规格驱动开发指南
date: 2025-12-24
tags: SDD
categories: AI
---

## 为什么 SDD 突然火了

2025 年下半年，GitHub 上同时冒出了两个热门项目，都主打同一个概念——SDD（Specification-Driven Development，规格驱动开发）。

| 项目 | Stars | 出品方 | 创建时间 |
|------|-------|--------|----------|
| spec-kit | 87,549 | GitHub 官方 | 2025-08 |
| OpenSpec | 39,543 | Fission AI | 2025-08 |

SDD 这个概念早在 2010 年前后就有人提过，但始终不温不火。它之所以在 2025 年爆发，根本原因是 AI 编码助手的成熟度达到了实用门槛。以前写规格是为了让人理解需求，现在写规格是为了让 AI 理解需求并生成代码。这个转变让 SDD 从锦上添花变成了必备技能。

<!-- more -->
---

## 方法论的演进脉络

软件开发方法论的演进方向是一致的：把质量保障的关口不断前移。传统开发流程是需求、编码、测试、部署，问题往往在测试甚至部署后才暴露。TDD 在 2003 年提出先写测试再写编码，确保代码可测试。BDD 在 2006 年进一步把起点推到行为描述，用自然语言定义系统应该有什么行为。SDD 则把起点推到了规格层面：先用结构化文档定义清楚要做什么，再让 AI 按规格生成代码。

| 方法论 | 起点 | 核心思路 |
|--------|------|----------|
| 传统开发 | 编码 | 边写边调试，问题在测试阶段才暴露 |
| TDD | 测试 | 先写测试用例，确保代码可验证 |
| BDD | 行为描述 | 用自然语言描述系统行为，再推导测试和代码 |
| SDD | 规格 | 先写完整规格，让 AI 按规格生成代码 |

## SDD 过去不火的原因

SDD 的核心思想是先写规格再写代码，逻辑上很合理，但过去有三个实际障碍阻碍了它的普及。

第一，人写代码比写规格快。资深程序员脑子里有现成的代码模板，直接动手比先写文档效率高得多。第二，规格容易和代码脱节。代码改了，规格忘了同步，最后规格沦为摆设。第三，缺乏工具支撑。规格只是 Markdown 文档，既无法执行也无法验证代码是否符合规格。

这三个问题在 2024-2025 年间被 AI 编码工具逐步解决了。AI 能根据规格自动生成代码，能根据规格变更自动调整实现，也能自动检验代码与规格的一致性。

## SDD 爆发的三个条件

| 条件 | 具体变化 |
|------|----------|
| AI 编码工具成熟 | Claude Code、Cursor、Copilot 能输出生产级代码 |
| 开发者角色转变 | 从代码编写者变成规格设计者加代码审查者 |
| 工具链完善 | spec-kit 和 OpenSpec 为规格提供了完整的执行框架 |

行业预测到 2026 年，80% 的开发者将常态化使用 AI 编码工具，花在规格设计和架构上的时间会超过写代码本身。

## SDD 的核心定义

SDD 的工作方式是先用结构化规格精确描述要做什么，再让 AI 照着规格生成代码，最后验证代码是否符合规格。它的几个核心能力包括：

| 能力 | 说明 |
|------|------|
| 协作澄清 | 开发者有时自己也不清楚需求，AI 协助完成问题定义和方案探索，这是 SDD 最被低估的能力 |
| 规格即契约 | 规格不是参考文档，而是人机之间的契约，AI 必须严格按规格实现 |
| 迭代友好 | 规格可以随时更新，AI 会同步调整代码，不是写完就扔 |
| 验证闭环 | 有工具能验证代码是否符合规格，偏离时自动提醒 |
| 追溯性强 | 每一行代码都能追溯到对应的规格条款 |

## 协作澄清：最被低估的能力

很多人以为 SDD 的流程是开发者先写清楚规格再让 AI 照做。但现实情况是开发者往往也不清楚自己要什么。传统模式假设开发者想清楚了再写规格再让 AI 实现，但 SDD 的澄清模式更贴近真实场景：开发者有一个模糊的想法，AI 通过提问协助澄清，双方共同定义问题，探索可能的方案，最后形成规格让 AI 去实现。

类比来说，传统模式像你拿着一份完整的菜单去餐厅让厨师照做，澄清模式像你说想吃点清淡的，然后厨师和你讨论是汤还是蒸菜、有什么忌口，最后一起确定菜单。`/speckit.clarify` 和 `/opsx:explore` 这类命令的价值就在这里：AI 不是被动执行者，而是主动的需求澄清伙伴。

澄清过程本身就是在定义问题。很多 Bug 的根因不是代码写错了，而是需求本身就没想清楚。

## 规格的文件结构

一个完整的 SDD 规格通常包含四个部分。以 OpenSpec 为例，一个变更的目录结构如下：

```
openspec/changes/add-dark-mode/
├── proposal.md          # 为什么做这个改动，影响范围是什么
├── specs/
│   ├── requirements.md  # 功能需求详情
│   └── scenarios.md     # 使用场景
├── design.md            # 技术方案：怎么实现
└── tasks.md             # 任务清单：分几步完成
```

proposal 回答为什么做和做了影响什么，specs 回答具体要什么功能和使用场景，design 回答技术实现方案，tasks 把实施拆成可追踪的步骤。

## SDD 与 TDD、BDD 的关系

SDD 不是替代 TDD 和 BDD，而是在它们之上增加了一层规格约束。SDD 在最上层定义要做什么，BDD 在中间层定义系统应该有什么行为，TDD 在底层定义怎么验证正确性，最后的代码实现受这三层约束。AI 不是自由发挥，而是在规格、行为和测试三重约束下生成代码。

| 层次 | 关注点 | 回答的问题 |
|------|--------|-----------|
| SDD | 规格 | 要做什么 |
| BDD | 行为 | 系统应该有什么行为 |
| TDD | 测试 | 怎么验证正确性 |
| 实现 | 代码 | AI 在上述三层约束下生成 |

## 有 SDD 和没有 SDD 的工作流对比

没有 SDD 时，需求和 AI 在对话中不断补充，来回修改效率很低。

```
你：帮我加个深色模式
AI：好的，我创建 ThemeContext...
你：等等，我想要的是 localStorage 持久化
AI：那我改一下...
你：还要支持系统主题自动切换
AI：再改一下...
你：切换按钮放在导航栏右侧
AI：...
```

有 SDD 时，先对齐要做什么，再一次性实现，减少了来回修改的开销。

```
你：/opsx:propose "添加深色模式"
AI：生成完整规格 → proposal + specs + design + tasks
你：审查规格，发现漏了 localStorage 持久化，补上
AI：更新规格
你：确认无误，执行 /opsx:apply
AI：按规格一次性实现
```

## 支持的 Code Agent

| Code Agent | spec-kit 支持 | OpenSpec 支持 |
|------------|--------------|---------------|
| Claude Code | `--ai claude` | `/opsx:*` 命令 |
| Cursor | slash commands | slash commands |
| GitHub Copilot CLI | 原生支持 | skills 模式 |
| Codex CLI | skills 模式 | skills 模式 |
| Windsurf | 支持 | 支持 |

## 问题澄清模式

前面讲的工作流都有一个前提：开发者知道要做什么。但实际工作中经常遇到模糊需求，比如想给博客加个评论功能但不知道怎么设计，或者用户反馈搜索太慢但不清楚具体慢在哪里。这时候澄清模式就派上用场了。

| 澄清前 | 澄清后 |
|--------|--------|
| 我想加评论功能（模糊） | 评论需要登录、支持楼中楼最多 3 层、可编辑删除、需管理员审核（清晰） |
| 搜索太慢（笼统） | 首页搜索接口响应 3s+，原因是全文检索没走索引，需优化 SQL 加缓存（具体） |
| 提升用户体验（抽象） | 页面加骨架屏、关键操作加确认弹窗、表单加实时校验提示（可落地） |

很多项目的返工和延期根因都在这里：需求理解偏差导致做出来的东西不是想要的，边界没定清楚导致范围不断膨胀，技术路线没探索充分导致方案选错。SDD 的澄清模式帮你把这些问题前置到编码之前解决。

### spec-kit 的澄清流程

使用 `/speckit.clarify` 命令，AI 通过逐步提问帮你明确需求边界：

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

### OpenSpec 的探索流程

使用 `/opsx:explore` 命令，AI 先帮你定位问题范围、排查原因、探索方案：

```
你：/opsx:explore "用户反馈搜索太慢，想优化一下"

AI：让我先帮你分析问题...

    1. 定位问题范围：
       - 是首页搜索慢？还是后台管理搜索？
       - 是所有搜索都慢？还是特定关键词？
       - 慢的标准是什么？2s？5s？

    你：首页的全站搜索，大概 3-4 秒才出结果

    2. 排查可能原因：
       - 当前实现：全文检索 LIKE '%keyword%'
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

## 安装步骤

### spec-kit 安装

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

### OpenSpec 安装

```bash
# 需要 Node.js 20.19.0+
npm install -g @fission-ai/openspec@latest

# 验证安装
openspec --version

# 初始化项目
cd your-project
openspec init
```

## 实战示例：为博客添加深色模式

### spec-kit 完整流程

步骤一，定义项目原则。在 Claude Code 中执行 `/speckit.constitution` 命令，设定代码风格、测试覆盖和文档要求，AI 会生成 `.speckit/constitution.md` 文件。

步骤二，创建功能规格。执行 `/speckit.spec add-dark-mode`，并给出需求要点：支持亮色、深色、跟随系统三种模式，偏好存储在 localStorage，切换按钮放在导航栏右侧，切换时有平滑过渡动画。AI 会生成 `.speckit/features/add-dark-mode/spec.md`。

步骤三，生成实施计划。执行 `/speckit.plan add-dark-mode`，AI 生成包含技术方案选择、文件改动清单和实施步骤的计划文件。

步骤四，分解任务。执行 `/speckit.tasks add-dark-mode`，AI 生成如下任务清单：

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

步骤五，执行实施。执行 `/speckit.implement add-dark-mode`，AI 按任务清单逐项实现代码。

步骤六，验证审查。执行 `/speckit.verify add-dark-mode`，AI 检查每个任务是否完成、代码是否符合规格、测试是否通过。

### OpenSpec 完整流程

步骤一，一键生成完整规格。执行 `/opsx:propose` 并描述需求，AI 一次性生成完整规格目录：

```
openspec/changes/add-dark-mode/
├── proposal.md          # 为什么做，影响哪些页面
├── specs/
│   ├── requirements.md  # 功能需求详情
│   └── scenarios.md     # 用户使用场景
├── design.md            # 技术方案：React Context + CSS 变量
└── tasks.md             # 实施任务清单
```

步骤二，审查并调整规格。打开 specs/requirements.md，补充一个需求：切换按钮需要显示当前模式图标（太阳、月亮、电脑）。AI 更新规格文件。

步骤三，执行实施。执行 `/opsx:apply`，AI 按任务清单逐项实现：

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

步骤四，归档。执行 `/opsx:archive`，AI 将完成的变更归档到历史目录，规格文件同步更新。

## spec-kit vs OpenSpec 怎么选

| 维度 | spec-kit | OpenSpec |
|------|----------|----------|
| 出品方 | GitHub 官方 | Fission AI（创业公司） |
| 风格 | 工程化、严谨 | 灵活、快速 |
| 安装 | Python + uv | Node.js + npm |
| 流程 | 分步执行（6 个命令） | 一键生成加一键应用 |
| 扩展性 | 40+ 官方扩展 | 配置化定制 |
| 适合场景 | 大型项目、团队协作 | 个人项目、快速迭代 |
| 学习曲线 | 较陡（概念多） | 较平（上手快） |

选择建议：大型团队或 Python 项目选 spec-kit，个人开发者或 TypeScript 项目选 OpenSpec。如果想快速体验 SDD 的流程，可以先试 OpenSpec 再系统学习 spec-kit。

---

SDD 的核心价值在于把质量关口前移到规格阶段。当 AI 能够根据规格生成代码时，规格的质量直接决定了生成代码的质量。与其在实现过程中反复返工，不如在动手之前先把需求聊清楚。

## 参考资料

- [GitHub spec-kit](https://github.com/github/spec-kit) — 87k+ Stars
- [Fission-AI OpenSpec](https://github.com/Fission-AI/OpenSpec) — 39k+ Stars
- [The Rise of SDD in the AI Era](https://dev.to/the-rise-of-specification-driven-development-in-the-ai-era)
- [SDD Complete Guide](https://devops.com/specification-driven-development-a-complete-guide/)
