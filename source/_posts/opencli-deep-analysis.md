---
title: OpenCLI 深度解析：让 AI Code Agent 操控任意网站
date: 2026-05-22
tags: OpenCLI
categories: AI
---

## 一、背景

之前研究 Chrome DevTools MCP 的时候，解决的核心问题是**让 AI 能操控浏览器**。但那个方案有天然的局限性：必须配置 MCP Server、依赖 Chrome 调试端口、每个平台要单独写适配器。

OpenCLI 把这件事重新做了一遍，而且做得更彻底——它不只是让 AI 能操控浏览器，而是把**任何网站变成标准化的命令行工具**。GitHub 上 22K+ Stars，不是偶然。

这篇文章的目标很明确：讲清楚 OpenCLI 是什么、架构怎么设计的、以及最核心的部分——**如何在 Claude Code 等 Code Agent 里用它**。

---

## 二、OpenCLI 是什么

一句话定义：OpenCLI 是一个 AI 原生的 CLI 运行时框架，把任意网站、浏览器会话、Electron 应用统一变成标准化的命令行接口。

打个比方理解它的定位：

| 场景 | 传统做法 | OpenCLI 做法 |
|------|---------|-------------|
| 发一篇小红书 | 打开浏览器 → 登录 → 上传图片 → 写文案 → 发布 | `opencli xiaohongshu publish --title "xxx" --content "xxx"` |
| 看 B站播放量 | 打开 B站创作者中心 → 刷新 → 看数据 | `opencli bilibili stats` |
| 给 Claude Code 说"帮我发篇文章" | Claude Code 做不到 | Claude Code 通过 OpenCLI 直接完成 |

核心区别在于：传统做法每次都要手动操作网页，OpenCLI 把这些操作封装成**确定性 CLI 命令**，而且**零 LLM 运行成本**。

---

## 三、架构深度拆解

### 3.1 整体架构图

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
└────────────────────┘   └────────────┬───────────┘
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

这个架构有几个关键设计点，值得拆开细说。

### 3.2 核心理念：编译期智能 vs 运行期智能

这是 OpenCLI 架构里最重要的一个设计选择。

**运行期智能**的意思是：每次执行命令时都让 LLM 实时理解页面结构、决定操作步骤。这种方式灵活，但每次都要消耗 token，而且结果不稳定。

**编译期智能**是 OpenCLI 的选择：Adapter 在生成阶段只解析一次页面结构，产出一个确定性的 YAML 定义。后续所有 CLI 调用都走这个 YAML，**零 LLM 成本，结果可预测**。

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

这段 YAML 定义好之后，每次执行都是确定的 DOM 选择器匹配，不需要 LLM 参与。只有在 Adapter 开发阶段才需要一次智能解析。

### 3.3 CDP 驱动层：为什么不走 Selenium/Playwright 路线

OpenCLI 选择基于 **Chrome DevTools Protocol (CDP)** 而不是传统的 Selenium 或 Playwright，原因很实际：

| 维度 | Selenium/Playwright | CDP + Chrome 实例 |
|------|-------------------|-------------------|
| 登录态 | 需要单独维护 cookies | 直接复用你正在用的 Chrome |
| 安全 | 需要存储账号密码 | 零凭证存储 |
| 真实性 | 无头浏览器可能被检测 | 真实浏览器实例 |
| 开发成本 | 要写完整的自动化脚本 | YAML 声明式定义 |

关键点在于**复用登录态**。你在浏览器里已经登录了知乎、B站、小红书，OpenCLI 直接通过 CDP 连上这个正在运行的实例，不需要重新登录、不需要 API Key、不需要存密码。

### 3.4 浏览器扩展：Playwright MCP Bridge

CDP 本身只能从外部控制 Chrome，但 OpenCLI 需要双向通信——既要控制页面，也要把页面结构回传给 CLI。这个桥梁由一个 Chrome 扩展承担：

**Playwright MCP Bridge 扩展**负责：
1. 接收 OpenCLI CLI 的指令（点击、输入、导航）
2. 在页面中执行对应操作
3. 返回结构化 DOM 快照（不是截图，是带语义的 DOM 树）
4. 维护 Session 状态（bind/unbind 标签页）

这个扩展是轻量级的 micro-daemon 模式，启动 OpenCLI 时自动加载。

### 3.5 Session 管理：bind 机制

Session 是 OpenCLI 连接 CLI 命令和具体浏览器标签页的桥梁：

```bash
# 把当前浏览器某个已登录的标签页绑定到 session
opencli browser my-blog bind

# 查看已绑定的 session
opencli browser list

# 解绑
opencli browser my-blog unbind
```

绑定之后，所有针对该平台的 CLI 命令都会在这个已登录的标签页里执行。

---

## 四、安装与快速上手

### 4.1 环境要求

- Node.js >= 20.0.0
- Chrome / Chromium / Brave / Edge 浏览器

### 4.2 安装步骤

```bash
# 全局安装 OpenCLI
npm install -g @jackwener/opencli

# 自动配置（检测 Chrome 实例、安装扩展）
opencli setup
```

`opencli setup` 会做这几件事：
1. 检测本地 Chrome 调试端口
2. 下载并加载 Playwright MCP Bridge 扩展
3. 验证 CLI 与浏览器的连通性
4. 初始化 `~/.opencli` 配置目录

### 4.3 运行第一个命令

```bash
# 查看内置适配器列表
opencli list

# 运行一个平台命令（以 B站 为例）
opencli bilibili stats
```

---

## 五、在 Code Agent 中的使用（重点）

这部分是整篇文章的核心。OpenCLI 的真正威力不在于手动敲命令，而在于**让 AI Code Agent 通过它操控任意网站**。

### 5.1 为什么 Code Agent 需要 OpenCLI

Claude Code、Cursor 这类 Code Agent 原生能力很强：能写代码、能读文件、能跑测试、能用 git。但有一个明确的边界——**它们不能操作网页**。

这个边界在实际工作中很要命。举个例子：

你要把一篇技术博客同步到知乎、公众号、小红书三个平台。用 Claude Code 写文章很快，但发布环节只能手动操作三个平台的后台。OpenCLI 把这个边界打通了。

### 5.2 在 Claude Code 中集成 OpenCLI

#### 方式一：直接作为 CLI 工具调用

Claude Code 本身就能执行 shell 命令，最直接的方式就是在对话中让它执行 `opencli` 命令：

```
你: 帮我查看 B站最近的视频数据
Claude Code: 执行 opencli bilibili stats，返回结果...
```

这种方式不需要额外配置，只要本机装了 OpenCLI 就行。

#### 方式二：安装 OpenCLI Skill

OpenCLI 提供了适配 AI Agent 的 Skill 定义，安装后 Agent 能更准确地理解和使用 OpenCLI：

```bash
# 在 Claude Code 中安装 OpenCLI skill
npx skills add jackwener/opencli
```

安装之后，Claude Code 会在执行浏览器相关任务时自动识别 OpenCLI 的可用命令，而不是每次都让你手动指定。

#### 方式三：在 .claude/commands 中自定义命令

结合 Claude Code 的自定义命令系统，可以把常用的 OpenCLI 操作封装成斜杠命令：

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

### 5.3 实际工作流示例

#### 场景：AI 驱动的博客同步工作流

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

整个过程不需要你打开任何一个浏览器页面。

#### 场景：数据监控面板

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

#### 场景：社区运营自动化

对于数字游民社区的运营工作，OpenCLI 能大幅减少重复劳动：

```
你: 检查一下社区后台有没有待审核的帖子

Claude Code:
> opencli nomad-community pending-reviews

返回 3 条待审核内容，逐条展示...

你: 全部通过

Claude Code:
> opencli nomad-community approve --all
```

### 5.4 Agent 操作浏览器的技术细节

理解 Claude Code 通过 OpenCLI 操作浏览器的底层流程，有助于你排查问题和编写自定义插件。

**完整的调用链路**：

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

**结构化 DOM 快照** 是理解这一切的关键。OpenCLI 不是截图给 AI 看，而是把页面转成一个带语义的结构化文本：

```
[button] "发布文章" (clickable, enabled)
[textbox] "标题" value="OpenCLI 深度解析" (editable)
[textarea] "正文内容" (editable, placeholder="输入正文...")
[link] "预览" href="/preview"
```

这种格式对 LLM 极其友好：token 消耗远低于截图，信息密度更高，而且可以直接定位到可交互元素。

---

## 六、插件开发实战

内置适配器覆盖了主流平台，但你自己的网站或者小众平台需要写自定义插件。

### 6.1 插件目录结构

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

### 6.2 编写一个完整的 Adapter

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

### 6.3 在 Claude Code 中使用自定义插件

自定义插件写好后，Claude Code 同样能调用。你可以在 Claude 的对话中直接说：

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

## 七、OpenCLI vs 其他方案对比

市面上让 AI 操作网页的方案不少，简单对比一下：

| 方案 | 登录态 | LLM 成本 | 开发门槛 | 稳定性 |
|------|--------|---------|---------|--------|
| **OpenCLI** | 复用 Chrome | 零运行成本 | YAML 声明式 | 确定性执行 |
| Chrome DevTools MCP | 复用 Chrome | 每次消耗 token | 需 MCP 配置 | LLM 实时判断 |
| Playwright 脚本 | 需要维护 cookies | 无 | 完整编程 | 最高但开发成本大 |
| Browser Use 框架 | 需要单独登录 | 每次消耗 token | Python 代码 | 依赖 LLM 判断 |

OpenCLI 的 sweet spot 很明确：**当你需要一个确定性的、零运行成本的、能复用浏览器登录态的网站操作方案时**，它是最优选择。

---

## 八、注意事项与限制

任何工具都有边界，OpenCLI 也不例外。

### 8.1 不适合的场景

- **高频交易或实时性要求极高的操作**：CDP 通信有延迟，不如直接调 API
- **需要无头浏览器批量爬取的场景**：OpenCLI 依赖真实 Chrome 实例，不适合大规模并发
- **对稳定性要求 100% 的生产环境**：网站改版后 Adapter 需要更新选择器

### 8.2 安全考量

OpenCLI 复用浏览器登录态，意味着它能操作你已登录的任何网站。建议：

- 只在受信任的 AI Agent（如本地 Claude Code）中使用
- 不要在云端或共享环境中使用
- 发布类操作可以先让 Agent 生成预览，人工确认后再执行

### 8.3 平台反爬

部分平台会检测自动化行为。OpenCLI 走的是真实浏览器实例，比无头浏览器好一些，但如果操作频率过高仍可能触发风控。控制节奏、避免短时间大量操作。

---

## 九、总结

OpenCLI 把"让 AI 操作网页"这件事从实验阶段拉到了生产可用阶段。它的核心价值可以概括为三点：

1. **统一接口**：任何网站变成 CLI，不用管底层是网页、Electron 还是本地工具
2. **零运行成本**：Adapter 编译后确定性执行，不消耗 LLM token
3. **安全复用登录态**：不存密码、不要 API Key、走真实浏览器

对于写博客、运营社区、管理多平台的创作者来说，配合 Claude Code 这样的 Code Agent，OpenCLI 能省掉大量重复的浏览器操作。对于开发者来说，YAML 声明式的插件开发门槛远低于写完整的自动化脚本。
