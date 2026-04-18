---
title: Hermes Agent：一个会"记住你"的 AI 助手
date: 2026-04-17
tags: AI Agent
categories: AI
---

> 如果你最近关注 AI Agent 领域，可能会注意到一个新名字——Hermes Agent。它来自 Nous Research，在短短两个月内从一个小型内部项目成长为功能完备的 AI Agent 平台。这篇文章聊聊它到底有什么不一样，以及为什么值得你花时间了解。

---

## 一、Hermes Agent 是什么？

简单说，它是一个**可以自我进化的 AI Agent 框架**。

市面上大多数 Agent 工具，你用完一次，下次还要重新教它。你说"帮我整理今天的 Git 提交记录"，它执行了。第二天你再说同样的话，它又从头开始理解。对话结束后，一切归零。

Hermes Agent 不一样。它有个叫"技能系统"的东西。第一次你教它做某件事，完成后它会问自己：这件事我以后是不是经常要做？如果答案是肯定的，它会把整个过程打包成一个技能。下次你只需要说"整理提交"，它就能直接调用这个技能。

这不是预设好的模板，是 Agent 自己判断、自己创建、自己优化的。用久了，它会越来越懂你的工作习惯。

---

## 二、为什么突然火了？

翻一下 Hermes Agent 的版本历史，你会发现一个有意思的时间线：

| 版本 | 发布日期 | 说明 |
|------|----------|------|
| v0.1.0 | 2026年2月底 | 内部预发布版本 |
| v0.2.0 | 3月12日 | 首个公开版本，216个PR，63位贡献者 |
| v0.3.0 | 3月17日 | 流式输出、插件架构、Honcho记忆 |
| v0.4.0 | 3月23日 | 6个新消息平台、4个新推理提供商 |
| v0.9.0 | 4月13日 | Android支持、iMessage、微信接入 |
| v0.10.0 | 4月16日 | Nous工具网关，订阅用户零额外API |

从2月底到4月中旬，不到两个月，发布了10个大版本。平均每三四天一个版本。这不是营销驱动的节奏，是真实需求驱动的迭代速度。

看看 v0.2.0 的发布说明："In just over two weeks, Hermes Agent went from a small internal project to a full-featured AI agent platform — thanks to an explosion of community contributions."

这句话翻译过来：两个星期，从内部小项目变成完整平台，原因是社区贡献爆发。

为什么爆发？因为 Hermes Agent 解决了一个长期痛点——Agent 的记忆和学习能力。之前大家做 Agent，要么接受"每次对话归零"的现实，要么自己写一套复杂的持久化逻辑。Hermes Agent 把这套逻辑内置了，而且是真正意义上的"学习"，不只是"存储"。

---

## 三、核心特质

### 3.1 闭环学习，不是单次执行

这点前面说了，展开讲一下细节。

Hermes Agent 的学习机制包含几个层次：

**技能自动创建**：完成复杂任务后，Agent 会分析这个任务是否有重复价值。有，就创建技能。技能里包含了执行步骤、需要的工具、注意事项。

**技能自我改进**：你用某个技能的时候如果给了反馈，比如"这次格式不对"或"下次加上这个字段"，Agent 会把这些反馈写进技能描述里。下一次执行会自动应用。

**定期提醒**：Agent 有个机制叫"periodic nudges"，会周期性地提醒自己把重要信息持久化。不是被动等待你要求，是主动思考"这个信息值得记住吗"。

**跨会话搜索**：你问"上次我们讨论的那个方案是什么"，它会搜索历史对话，用 LLM 做摘要，然后告诉你。这不是简单的关键词搜索，是语义层面的召回。

### 3.2 Honcho 用户建模

Hermes Agent 内置了一个叫 Honcho 的用户建模系统。这个名字来自 plastic-labs 的 Honcho 项目，是一个专门做"AI 理解用户"的框架。

它的作用是：Agent 会持续观察你的偏好、习惯、工作方式，然后建立一个用户模型。你喜欢简洁回复，它记住；你讨厌某种操作方式，它记住；你对某个项目有特殊约定，它跨会话保持。

这不是简单的"记住你说过的话"，是"理解你是什么样的人"。

### 3.3 多平台统一接入

这点对实际使用很重要。

你可以在 Telegram、Discord、Slack、WhatsApp、Signal 这些平台跟 Hermes Agent 对话，也可以在终端用 CLI。同一个 Agent，不同入口，记忆和技能是共享的。

这意味着你早上在公司电脑用 CLI 让它整理日报，晚上回家用 Telegram 继续讨论，它记得你白天说了什么。

### 3.4 定时任务，原生支持

大多数 Agent 框架没有内置的定时任务系统。你想让 Agent 每天早上自动发日报，要么写外部脚本触发，要么依赖某个外部调度器。

Hermes Agent 内置了 cron 调度。你用自然语言描述："每天早上9点，汇总昨天的 Git 提交并发到 Telegram"，它会自动解析、创建任务、按时执行。

这对于"Agent 作为助手"的场景很重要。真正的助手不只是你叫它才动，是会主动做事情。

### 3.5 云端部署，不是本地绑定

这点是 Hermes Agent 相比很多同类产品的优势。

它支持六种终端后端：本地、Docker、SSH、Daytona、Singularity、Modal。其中 Modal 和 Daytona 是"无服务器"模式——你的 Agent 环境在云端，空闲时几乎不花钱，有请求时自动唤醒。

这意味着你可以把 Hermes Agent 部署到云端，然后从 Telegram 发消息触发。不在电脑前的时候，Agent 依然在工作。这对于"随时随地操作"的需求很关键。

### 3.6 多模型，随时切换

Hermes Agent 支持大量 LLM 提供商：

- Nous Portal（官方订阅服务）
- OpenRouter（200+模型）
- Anthropic（Claude 系列）
- OpenAI（GPT 系列）
- Google AI Studio（Gemini）
- 阿里云百炼（DashScope）
- 智谱 AI（GLM）
- Moonshot（Kimi）
- MiniMax
- 小米 MiMo
- NVIDIA NIM
- DeepSeek
- xAI（Grok）
- Hugging Face
- AWS Bedrock
- 还有更多...

切换模型用一个命令：`hermes model`。不需要改代码，不需要重新部署，运行时切换。

这对于实际使用很重要。不同的任务适合不同的模型，你可能写代码用 Claude，快速问答用 GPT-mini，中文内容用 Qwen。Hermes Agent 让这种切换变得零成本。

---

## 四、对 OpenClaw 用户的意义

如果你正在用 OpenClaw，听到 Hermes Agent 可能会想：又一个类似的工具，有必要换吗？

这里有个事实你可能不知道：**Hermes Agent 是 OpenClaw 的官方进化版本**。

翻 Hermes Agent 的文档，你会发现专门的迁移章节：

```
## Migrating from OpenClaw

If you're coming from OpenClaw, Hermes can automatically import your settings, memories, skills, and API keys.
```

迁移命令很简单：

```bash
hermes claw migrate --dry-run    # 先预览会迁移什么
hermes claw migrate              # 执行迁移
```

迁移内容包括：
- SOUL.md（人格设定）
- 已有技能
- 命令白名单
- 消息平台配置
- API 密钥（Telegram、OpenRouter、OpenAI、Anthropic 等）
- 工作空间说明（AGENTS.md）

这说明 Hermes Agent 的开发团队明确知道 OpenClaw 用户群体，并且专门做了兼容路径。

那为什么要从 OpenClaw 换到 Hermes Agent？几个实际理由：

| 功能 | OpenClaw | Hermes Agent |
|------|----------|--------------|
| 技能系统 | 有，但不自改进 | 有，且会自我优化 |
| 定时任务 | 无 | 内置 cron |
| 云端部署 | 本地运行 | Modal/Daytona 无服务器 |
| 用户建模 | 会话级 | Honcho 深度建模 |
| MCP 协议 | 无 | 支持 |
| 消息平台 | Telegram、飞书等 | Telegram、Discord、Slack、WhatsApp、Signal|

如果你需要定时任务、云端部署、Agent 学习能力，Hermes Agent 提供了这些 OpenClaw 没有的东西。

---

## 五、安装和使用指南

### 5.1 Mac 用户

Mac 上安装最简单，一行命令：

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
```

安装完成后：

```bash
source ~/.zshrc   # 或者 source ~/.bashrc
hermes            # 启动
```

首次运行会引导你配置。按照提示选择 LLM 提供商、设置 API Key 就可以开始使用。

### 5.2 Windows 用户

Windows 原生不支持，需要通过 WSL2。

先安装 WSL2：

```powershell
wsl --install
```

然后进入 WSL2 的 Linux 环境，运行和 Mac 一样的安装命令。

这步对不熟悉 Linux 的用户可能有点门槛，但设置好后使用体验和 Mac 一样。

### 5.3 常用命令

```bash
hermes              # 启动交互式 CLI
hermes model        # 选择模型提供商和具体模型
hermes tools        # 配置启用的工具
hermes gateway      # 启动消息平台网关（Telegram、Discord 等）
hermes setup        # 完整设置向导
hermes doctor       # 检查配置是否有问题
hermes update       # 更新到最新版本
```

在对话中使用的斜杠命令：

```
/new              # 开始新对话
/model            # 切换模型
/skills           # 浏览可用技能
/retry            # 重试上一轮
/undo             #撤销上一轮
/compress         # 压缩上下文
/usage            # 查看用量
```

### 5.4 配置阿里云百炼

如果你之前用 OpenClaw 配了阿里云百炼的 Coding Plan，在 Hermes Agent 里可以直接用：

```bash
# 设置环境变量
export DASHSCOPE_API_KEY=你的API密钥

# 如果用国内版，额外设置
export DASHSCOPE_BASE_URL=https://dashscope.aliyuncs.com/compatible-mode/v1
```

或者在 `~/.hermes/.env` 文件里写：

```
DASHSCOPE_API_KEY=sk-xxxxxxxx
```

然后用命令切换提供商：

```bash
hermes model alibaba
hermes model qwen3-coder-plus
```

---

## 六、OpenClaw 用户迁移指南

如果你已经有 OpenClaw 的配置，迁移步骤：

**1. 安装 Hermes Agent**

```bash
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
source ~/.zshrc
```

**2. 运行迁移命令**

```bash
hermes setup
```

Setup 向导会自动检测 `~/.openclaw` 目录，提示你是否迁移。

或者任何时候手动运行：

```bash
hermes claw migrate --dry-run    # 预览会迁移什么
hermes claw migrate              # 执行迁移
```

**3. 检查迁移结果**

```bash
hermes doctor    # 检查配置是否正确
```

**4. 开始使用**

```bash
hermes    # 启动 CLI
```

迁移后，你的 SOUL.md（人格设定）、已有技能、命令白名单、消息平台配置都会保留。API 密钥会自动迁移到 `~/.hermes/.env`。

**注意**：OpenClaw 支持 Telegram、飞书等平台，这些配置会直接迁移。

---

## 七、适合什么人用？

如果你的需求是：

- **写代码为主** → 继续用 Claude Code，它在代码理解上更强
- **操作电脑、整理文件** → Hermes Agent 或 OpenClaw 都能胜任
- **重复性任务多** → Hermes Agent，技能系统会帮你省时间
- **需要定时自动化** → Hermes Agent，内置 cron
- **离开电脑时也想用** → Hermes Agent，云端部署 + Telegram
- **飞书/Telegram 是核心场景** → Hermes Agent 或 OpenClaw 都能胜任

如果你已经在用 OpenClaw，不需要立即换。两个工具核心功能重叠约 70%，Hermes Agent 新增的是学习能力、定时任务和云端部署。这些对你有没有价值，看你的实际需求。

但如果你想尝试 Hermes Agent，迁移成本很低。一条命令就能把 OpenClaw 的配置全部导过去，不存在"从头设置"的问题。

---

## 八、总结

Hermes Agent 的价值不在"功能更多"，在"设计思路不同"。

大多数 Agent 工具的设计假设是：用户发起对话 → Agent 执行 → 结束。下一次对话从零开始。

Hermes Agent 的设计假设是：Agent 和用户是长期关系，Agent 应该越来越懂用户，而不是每次都从陌生人开始。

这个假设的差异，导致了功能设计的差异：技能自动创建、技能自我改进、Honcho 用户建模、跨会话搜索、定期提醒持久化。

这些功能单独看都不复杂，组合起来形成一个闭环：Agent 做事 → Agent 学习 → Agent 下次做得更好。

这个闭环是 Hermes Agent 和其他 Agent 工具的本质区别。

如果你对"Agent 可以学习和进化"这个概念感兴趣，值得花半小时安装试试。不需要完全替换你现有的工具，先体验一下它的学习机制，看看是否符合你的预期。

---

## 九、相关资源

- Hermes Agent GitHub：https://github.com/NousResearch/hermes-agent
- 官方文档：https://hermes-agent.nousresearch.com/docs/
- Skills Hub：https://agentskills.io
- Nous Research Discord：https://discord.gg/NousResearch
- HermesClaw（微信桥接）：https://github.com/AaronWong1999/hermesclaw