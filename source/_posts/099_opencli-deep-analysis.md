---
title: OpenCLI 深度解析：让 AI Code Agent 操控任意网站
date: 2026-05-22
tags: OpenCLI
categories: AI
---

## 背景

之前研究 Chrome DevTools MCP 的时候，解决的核心问题是让 AI 能操控浏览器。但那个方案有天然的局限性：必须配置 MCP Server、依赖 Chrome 调试端口、每个平台要单独写适配器。

OpenCLI 把这件事重新做了一遍，而且做得更彻底。它不只是让 AI 能操控浏览器，而是把任何网站变成标准化的命令行工具。GitHub 上 22K+ Stars，说明这个方向踩中了真实需求。

这篇文章讲清楚三件事：OpenCLI 是什么、架构怎么设计的、以及最核心的部分，如何在 Claude Code 等 Code Agent 里用它。

<!-- more -->
---

## OpenCLI 是什么

OpenCLI 是一个 AI 原生的 CLI 运行时框架，把任意网站、浏览器会话、Electron 应用统一变成标准化的命令行接口。通过对比能更直观地理解它的定位：

| 场景 | 传统做法 | OpenCLI 做法 |
|------|---------|-------------|
| 发一篇小红书 | 打开浏览器 → 登录 → 上传图片 → 写文案 → 发布 | `opencli xiaohongshu publish --title "xxx" --content "xxx"` |
| 看 B站播放量 | 打开 B站创作者中心 → 刷新 → 看数据 | `opencli bilibili stats` |
| 给 Claude Code 说"帮我发篇文章" | Claude Code 做不到 | Claude Code 通过 OpenCLI 直接完成 |

核心区别在于，传统做法每次都要手动操作网页，OpenCLI 把这些操作封装成确定性 CLI 命令，而且零 LLM 运行成本。

---

## 架构拆解

### 整体架构

```
┌──────────────────────────────────────────────────────┐
│                   用户 / AI Agent                     │
│              (Claude Code / Cursor 等)                │
└──────────────────────┬───────────────────────────────┘
                       │ CLI 命令
                       ▼
┌──────────────────────────────────────────────────────┐
│                   OpenCLI CLI 层                      │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │  Plugin     │  │  Adapter     │  │  Session    │  │
│  │  Loader     │  │  Resolver    │  │  Manager    │  │
│  └─────────────┘  └──────────────┘  └─────────────┘  │
└──────────────────────┬───────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
┌────────────────────┐   ┌────────────────────────┐
│  YAML Adapter 引擎  │   │  CDP 通信层             │
│  (编译期智能)       │   │  Chrome DevTools        │
│  生成确定性命令     │   │  Protocol 注入          │
└────────────────────┘   └────────────────────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │  Chrome Extension     │
                          │  (Playwright MCP      │
                          │   Bridge)             │
                          └───────────┬───────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │  已登录的 Chrome 浏览器 │
                          │  (你的真实用户会话)     │
                          └───────────────────────┘
```

架构从上到下分四层：用户和 AI Agent 通过 CLI 命令与 OpenCLI 交互，CLI 层负责插件加载、适配器解析和会话管理，中间层是 YAML Adapter 引擎和 CDP 通信，底层通过 Chrome Extension 连接到真实的浏览器实例。每一层的职责边界清晰，下面逐层拆解关键设计。

### 编译期智能 vs 运行期智能

OpenCLI 架构里最值得关注的选择，是在编译期和运行期之间划分智能的边界。

运行期智能的意思是每次执行命令时都让 LLM 实时理解页面结构、决定操作步骤。这种方式灵活，但每次都要消耗 token，而且结果不稳定。同一个命令执行两次，LLM 可能做出不同的决策。

编译期智能是 OpenCLI 的选择：Adapter 在开发阶段只解析一次页面结构，产出一个确定性的 YAML 定义。后续所有 CLI 调用都走这个 YAML，零 LLM 成本，结果可预测。这个设计让 OpenCLI 的运行成本趋近于零，同时保证了执行的一致性和可调试性。

```yaml
# 一个 Adapter 示例：获取 B站视频播放量
name: bilibili-stats
target: https://member.bilibili.com/platform/home
steps:
  - action: navigate
    url: "https://member.bilibili.com/platform/home"
  - action: extract
    selector: ".data-overview .total-views"
    output: total_views
  - action: extract
    selector: ".data-overview .total-fans"
    output: total_fans
```

这段 YAML 定义好之后，每次执行都是确定的 DOM 选择器匹配，不需要 LLM 参与。代价是网站改版后需要手动更新选择器，但对于大多数稳定平台来说，这个维护成本可以接受。

### 为什么选 CDP 而不是 Selenium/Playwright

OpenCLI 选择基于 Chrome DevTools Protocol (CDP) 而不是传统的 Selenium 或 Playwright，原因很实际。

| 维度 | Selenium/Playwright | CDP + Chrome 实例 |
|------|-------------------|-------------------|
| 登录态 | 需要单独维护 cookies | 直接复用你正在用的 Chrome |
| 安全 | 需要存储账号密码 | 零凭证存储 |
| 真实性 | 无头浏览器可能被检测 | 真实浏览器实例 |
| 开发成本 | 要写完整的自动化脚本 | YAML 声明式定义 |

关键点在于复用登录态。你在浏览器里已经登录了知乎、B站、小红书，OpenCLI 直接通过 CDP 连上这个正在运行的实例，不需要重新登录、不需要 API Key、不需要存密码。这个设计选择让 OpenCLI 的安全模型非常简洁：不存储任何凭证，所有认证都依赖浏览器自身的会话管理。

### 浏览器扩展的作用

CDP 本身只能从外部控制 Chrome，但 OpenCLI 需要双向通信，既要控制页面，也要把页面结构回传给 CLI。这个桥梁由一个 Chrome 扩展承担。

Playwright MCP Bridge 扩展负责四件事：接收 CLI 的指令（点击、输入、导航），在页面中执行对应操作，返回结构化 DOM 快照（不是截图，是带语义的 DOM 树），维护 Session 状态（bind/unbind 标签页）。这个扩展是轻量级的 micro-daemon 模式，启动 OpenCLI 时自动加载。

### Session 绑定机制

Session 是 OpenCLI 连接 CLI 命令和具体浏览器标签页的桥梁。

```bash
# 把当前浏览器某个已登录的标签页绑定到 session
opencli browser my-blog bind

# 查看已绑定的 session
opencli browser list

# 解绑
opencli browser my-blog unbind
```

绑定之后，所有针对该平台的 CLI 命令都会在这个已登录的标签页里执行。这个设计让 OpenCLI 能同时管理多个平台的会话，互不干扰。

---

## 安装与快速上手

环境要求：Node.js >= 20.0.0，Chrome / Chromium / Brave / Edge 浏览器。

```bash
# 全局安装 OpenCLI
npm install -g @jackwener/opencli

# 自动配置（检测 Chrome 实例、安装扩展）
opencli setup
```

`opencli setup` 会做四件事：检测本地 Chrome 调试端口、下载并加载 Playwright MCP Bridge 扩展、验证 CLI 与浏览器的连通性、初始化 `~/.opencli` 配置目录。

```bash
# 查看内置适配器列表
opencli list

# 运行一个平台命令（以 B站 为例）
opencli bilibili stats
```

---

## 在 Code Agent 中的使用

这部分是整篇文章的核心。OpenCLI 的真正威力不在于手动敲命令，而在于让 AI Code Agent 通过它操控任意网站。

### Code Agent 的能力边界

Claude Code、Cursor 这类 Code Agent 原生能力很强：能写代码、能读文件、能跑测试、能用 git。但它们有一个明确的边界：不能操作网页。

这个边界在实际工作中造成的摩擦比想象中大。一个典型场景是把技术博客同步到知乎、公众号、小红书三个平台。用 Claude Code 写文章很快，但发布环节只能手动操作三个平台的后台，每篇文章要重复三次登录、复制、粘贴、调整格式的操作。OpenCLI 把这个边界打通了。

### 三种集成方式

**直接作为 CLI 工具调用**是最简单的方式。Claude Code 本身就能执行 shell 命令，在对话中让它执行 `opencli` 命令即可，不需要额外配置。

**安装 OpenCLI Skill** 能获得更好的集成效果。OpenCLI 提供了适配 AI Agent 的 Skill 定义，安装后 Agent 能更准确地理解和使用 OpenCLI：

```bash
# 在 Claude Code 中安装 OpenCLI skill
npx skills add jackwener/opencli
```

安装之后，Claude Code 会在执行浏览器相关任务时自动识别 OpenCLI 的可用命令，不需要每次手动指定。

**在 .claude/commands 中自定义命令**适合高频操作。结合 Claude Code 的自定义命令系统，可以把常用的 OpenCLI 操作封装成斜杠命令：

```yaml
# .claude/commands/publish-blog.md
---
description: 发布博客到多平台
---

执行以下命令发布博客：
1. opencli zhihu publish --title "{{title}}" --content "{{content}}"
2. opencli weixin publish --title "{{title}}" --content "{{content}}"
3. opencli xiaohongshu publish --title "{{title}}" --content "{{content}}"
```

之后在 Claude Code 中只需输入 `/publish-blog` 就能一键发布。

### 实际工作流

**博客同步**是最直接的应用场景：

```
你: 把 source/_posts/opencli-deep-analysis.md 这篇文章发到知乎、小红书、B站

Claude Code 的执行流程:
1. 读取 Markdown 文件内容
2. 根据各平台特点调整格式（知乎支持 Markdown，
   小红书需要短文案+图片，B站专栏有特定结构）
3. 执行 opencli zhihu publish --title "..." --content "..."
4. 执行 opencli xiaohongshu publish --title "..." --content "..."
5. 执行 opencli bilibili publish --title "..." --content "..."
6. 返回各平台的发布结果
```

整个过程不需要打开任何一个浏览器页面。

**数据监控**也很实用：

```
你: 帮我看看各平台最近一周的数据

Claude Code:
> opencli bilibili stats --period 7d
> opencli zhihu stats --period 7d
> opencli xiaohongshu stats --period 7d

汇总输出:
| 平台   | 阅读量  | 点赞 | 评论 |
|--------|--------|------|------|
| B站    | 12,340 | 456  | 89   |
| 知乎   | 8,920  | 312  | 56   |
| 小红书 | 15,600 | 890  | 123  |
```

**社区运营自动化**能大幅减少重复劳动：

```
你: 检查一下社区后台有没有待审核的帖子

Claude Code:
> opencli nomad-community pending-reviews

返回 3 条待审核内容，逐条展示...

你: 全部通过

Claude Code:
> opencli nomad-community approve --all
```

### Agent 操作浏览器的底层流程

理解 Claude Code 通过 OpenCLI 操作浏览器的底层流程，有助于排查问题和编写自定义插件。完整的调用链路是这样的：

```
Claude Code 发起对话
  → OpenCLI CLI 解析命令
    → 查找对应 Adapter 定义（YAML/TS）
      → 通过 CDP 连接 Chrome 实例
        → 扩展在页面中执行操作
          → 返回结构化 DOM 快照
            → Adapter 解析快照提取数据
              → CLI 返回结果给 Claude Code
```

结构化 DOM 快照是理解这一切的关键。OpenCLI 不是截图给 AI 看，而是把页面转成一个带语义的结构化文本：

```
[button] "发布文章" (clickable, enabled)
[textbox] "标题" value="OpenCLI 深度解析" (editable)
[textarea] "正文内容" (editable, placeholder="输入正文...")
[link] "预览" href="/preview"
```

这种格式对 LLM 极其友好：token 消耗远低于截图，信息密度更高，而且可以直接定位到可交互元素。相比 Computer Use 的截图方案，DOM 快照方案在成本和精度上都有明显优势。

---

## 插件开发

内置适配器覆盖了主流平台，但你自己的网站或者小众平台需要写自定义插件。

### 目录结构

```
~/.opencli/plugins/
└── my-custom-plugin/
    ├── plugin.yaml        # 插件元信息
    ├── adapters/
    │   ├── list.yaml      # 列表命令
    │   ├── publish.yaml   # 发布命令
    │   └── stats.yaml     # 统计命令
    └── README.md
```

### 编写 Adapter

以"从某个网站后台提取文章列表"为例：

```yaml
# plugin.yaml
name: my-blog-admin
version: 1.0.0
description: 个人博客后台管理 CLI
base_url: https://myblog.com/admin
```

```yaml
# adapters/list.yaml
name: articles
description: 列出所有文章
target: "https://myblog.com/admin/articles"
steps:
  - action: navigate
    url: "https://myblog.com/admin/articles"
  - action: wait
    selector: ".article-table tbody tr"
  - action: extract
    selector: ".article-table tbody tr"
    fields:
      - name: title
        selector: ".article-title"
      - name: status
        selector: ".article-status"
      - name: published_at
        selector: ".published-date"
    output: articles
  - action: format
    template: "{{title}} | {{status}} | {{published_at}}"
    output: articles
```

```yaml
# adapters/publish.yaml
name: publish
description: 发布新文章
target: "https://myblog.com/admin/articles/new"
inputs:
  - name: title
    type: string
    required: true
  - name: content
    type: string
    required: true
steps:
  - action: navigate
    url: "https://myblog.com/admin/articles/new"
  - action: input
    selector: "#article-title"
    value: "{{title}}"
  - action: input
    selector: "#article-content"
    value: "{{content}}"
  - action: click
    selector: "#publish-button"
  - action: wait
    selector: ".publish-success"
  - action: extract
    selector: ".success-message"
    output: result
```

写好之后，通过 symlink 链接到 OpenCLI 插件目录：

```bash
# Linux/Mac
ln -s /path/to/my-custom-plugin ~/.opencli/plugins/my-blog-admin

# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:USERPROFILE\.opencli\plugins\my-blog-admin" -Target "D:\path\to\my-custom-plugin"
```

之后就能直接使用：

```bash
# 列出文章
opencli my-blog-admin articles

# 发布文章
opencli my-blog-admin publish --title "OpenCLI 深度解析" --content "..."
```

### 在 Claude Code 中调用自定义插件

自定义插件写好后，Claude Code 同样能调用：

```
你: 用 my-blog-admin 插件列出所有已发布的文章
Claude Code: 执行 opencli my-blog-admin articles，返回...

你: 帮我把标题为 "xxx" 的文章同步到知乎
Claude Code:
1. 执行 opencli my-blog-admin articles 获取文章内容
2. 提取目标文章内容
3. 执行 opencli zhihu publish 发布到知乎
```

---

## 方案对比

市面上让 AI 操作网页的方案不少，这里做一个结构化对比：

| 方案 | 登录态 | LLM 成本 | 开发门槛 | 稳定性 |
|------|--------|---------|---------|--------|
| OpenCLI | 复用 Chrome | 零运行成本 | YAML 声明式 | 确定性执行 |
| Chrome DevTools MCP | 复用 Chrome | 每次消耗 token | 需 MCP 配置 | LLM 实时判断 |
| Playwright 脚本 | 需要维护 cookies | 无 | 完整编程 | 最高但开发成本大 |
| Browser Use 框架 | 需要单独登录 | 每次消耗 token | Python 代码 | 依赖 LLM 判断 |

从这张表可以看出，OpenCLI 的适用场景很明确：当你需要一个确定性的、零运行成本的、能复用浏览器登录态的网站操作方案时，它是最优选择。如果你的场景需要高度灵活性（比如目标页面结构经常变化），或者需要跨浏览器兼容，那 Playwright 脚本更合适。如果是临时性的、一次性的浏览器操作，Chrome DevTools MCP 的配置成本更低。

---

## 限制与边界

OpenCLI 不是万能的，有几个场景不适合用它。

高频交易或实时性要求极高的操作不适合。CDP 通信有延迟，不如直接调 API。如果你的场景是秒级响应的交易类操作，OpenCLI 的延迟不可接受。

大规模并发爬取也不适合。OpenCLI 依赖真实 Chrome 实例，一个 Chrome 实例同一时间只能操作一个页面。如果需要同时爬取几十个页面，应该用传统的无头浏览器方案。

对稳定性要求极高的生产环境需要谨慎。网站改版后 Adapter 的选择器会失效，需要人工更新。对于内部系统或者 API 稳定的平台，这个问题不大；但对于频繁改版的第三方平台，维护成本会上升。

安全方面需要注意，OpenCLI 复用浏览器登录态，意味着它能操作你已登录的任何网站。建议只在受信任的 AI Agent（如本地 Claude Code）中使用，不要在云端或共享环境中使用，发布类操作可以先让 Agent 生成预览、人工确认后再执行。

平台反爬是另一个现实问题。部分平台会检测自动化行为，OpenCLI 走的是真实浏览器实例，比无头浏览器好一些，但如果操作频率过高仍可能触发风控。控制节奏、避免短时间大量操作是基本策略。

---

## 个人判断

OpenCLI 的价值在于它找到了一个清晰的定位：在 LLM 驱动的浏览器操作和传统自动化脚本之间，用编译期智能取代运行期智能，把成本降到接近零。这个设计选择让它特别适合 Code Agent 场景，因为 Agent 的每次工具调用都有成本，确定性执行比灵活性更重要。

它不会取代 Playwright 或 Selenium 这类传统自动化方案，因为那些方案在稳定性和灵活性上有自己的优势。OpenCLI 填补的是一个空白：让 AI Agent 能以极低成本操控网站，同时复用用户的真实登录态。

对于内容创作者和多平台运营者来说，配合 Claude Code 使用 OpenCLI 能省掉大量重复的浏览器操作。对于开发者来说，YAML 声明式的插件开发门槛远低于写完整的自动化脚本。这个工具的实际价值，取决于你有多少重复性的网页操作需要自动化。
