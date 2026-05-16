---
title: TrendRadar：告别无效刷屏，只看真正关心的新闻
date: 2025-05-16
tags: AI 开源工具
categories: [AI]
---

## 背景

每天打开手机，十几个 APP 轮番刷一遍，微博热搜、知乎热榜、抖音热点、今日头条……刷完一圈下来，两个小时过去了，真正有用的信息可能就三五条。剩下的是什么？震惊体标题党、营销软文、明星八卦、各种算法硬塞给你的"你可能感兴趣"。

更气人的是，明明只想看看科技圈今天发生了什么，却被"某明星离婚"霸占了热搜第一。平台算法绑架了我们的注意力，想看的内容找不到，不想看的铺天盖地。

有没有一种工具，能帮你从"被动接收"变成"主动获取"？**TrendRadar** 就是这么一个开源项目——聚合全网热点，按你的关键词筛选，定时推送到你的手机。更重要的是，它还能让 AI 帮你分析这些热点背后的趋势和情绪。

## TrendRadar 是什么

一句话概括：**TrendRadar 是一个开源的热点新闻聚合分析工具**。

它的核心思路很简单——把全网 50+ 个平台的热榜抓过来，按你设定的关键词过滤，把真正关心的内容推给你。推送渠道也很丰富：飞书、钉钉、企业微信、Telegram、邮件、Bark（iOS）、Slack，甚至自定义 Webhook。

更厉害的是，它内置了 **AI 分析功能**。不仅是聚合热点，还能让 AI 帮你：
- 分析热点趋势走向
- 判断舆论情绪（正面/负面/争议）
- 跨平台关联分析
- 生成洞察报告

这就像雇了一个私人新闻助理，每天帮你从海量信息中提炼出真正有价值的干货。

## 数据是怎么来的

TrendRadar 的数据来源是另一个开源项目 **NewsNow**。这个项目聚合了全网 50+ 个平台的热榜数据，包括：

| 国内综合 | 科技平台 | 金融平台 | 国际媒体 |
|---------|---------|---------|---------|
| 知乎、微博 | IT之家、36氪 | 华尔街见闻 | Hacker News |
| 百度热搜 | 稀土掘金 | 财联社 | GitHub Trending |
| 抖音、今日头条 | V2EX | 雪球 | Product Hunt |
| 澎湃新闻、凤凰网 | 酷安 | 金十数据 | 联合早报 |
| 虎扑、贴吧 | 少数派 | 格隆汇 | 卫星通讯社 |

NewsNow 通过调用各平台的官方 API 或爬取页面来获取热榜数据，然后统一输出成标准格式。TrendRadar 直接调用 NewsNow 的公开 API：

```
https://newsnow.busiyi.world/api/s?id=zhihu&latest
```

返回的数据格式是这样的：

```json
{
  "status": "success",
  "items": [
    {
      "title": "如何评价DeepSeek新模型?",
      "url": "https://zhuanlan.zhihu.com/p/xxx",
      "extra": {
        "info": "1234万热度",
        "hover": "摘要描述..."
      }
    }
  ]
}
```

所以 TrendRadar 不需要自己去啃各平台的反爬机制，数据源维护这个苦活儿由 NewsNow 项目负责。万一某个平台接口变了，NewsNow 更一下就行，TrendRadar 用户完全不用操心。

## 核心功能一览

### 热榜聚合

默认支持 11 个主流平台：知乎、微博、百度热搜、抖音、今日头条、B站热搜、华尔街见闻、财联社、澎湃新闻、凤凰网、贴吧。想加更多平台？直接在配置文件里加就行。

### 关键词筛选

这是核心功能。你在 `frequency_words.txt` 里写上关心的关键词，系统就只推送包含这些词的新闻。语法很灵活：

```txt
# 最简单的：直接写关键词
华为

# 多个关键词归为一组（空行分隔）
华为
鸿蒙
任正非

# 给词组起个名字
[科技巨头]
华为
腾讯
字节

# 正则匹配（精确匹配英文单词，避免误匹配）
/\bAI\b/ => AI相关
人工智能

# 排除不想看的
[苹果公司]
苹果
!水果        # 排除"水果"相关的

# 限制显示条数
特斯拉
@10          # 最多显示10条

# 必须同时包含多个词
+发布会
+新品        # 必须同时出现"发布会"和"新品"
```

### AI 智能筛选（新功能）

如果你不想自己写关键词，可以用 **自然语言描述** 你关注的方向。在 `ai_interests.txt` 里写：

```txt
下面是我要关注的内容：

1. 中国科技与互联网公司：重点关注 DeepSeek、华为、腾讯...
2. 大模型与 AI 产品：关注 OpenAI、Claude、ChatGPT...
3. AI 基础设施与云算力：关注英伟达、AMD...
4. 芯片与半导体制造：关注芯片、光刻机...
...

# 标题质量要求
- 不要标题党/震惊体
- 不要营销软文
```

AI 会自动理解你的兴趣，给每条新闻打分，只推送高相关度的内容。这个功能需要配置 AI API（支持 DeepSeek、OpenAI、Gemini 等）。

### 三种推送模式

| 模式 | 说明 | 适用人群 |
|-----|------|---------|
| **daily（当日汇总）** | 每天定时推送当天所有匹配新闻 | 企业管理者、普通用户 |
| **current（当前榜单）** | 每次推送当前榜单匹配新闻 | 自媒体人、内容创作者 |
| **incremental（增量监控）** | 只推送新出现的内容，零重复 | 投资者、交易员 |

举个例子：你监控"特斯拉"，每小时执行一次。如果选择 `incremental` 模式，只有第一次出现的新闻才会推送给你，后续重复出现的就不打扰了。适合高频监控场景。

### 调度系统（时间线）

你可以精细控制"什么时间做什么事"。比如：

- 工作日：早上9点速览、中午看热点、晚上7点汇总
- 周末：睡到自然醒，10点开始推送，有新增就推

预设了 5 种模板：`always_on`（全天候）、`morning_evening`（早晚汇总）、`office_hours`（办公时间）、`night_owl`（夜猫子）、`custom`（完全自定义）。

### AI 分析推送

开启后，每次推送都会附带一份 AI 生成的洞察报告，包含：
- 核心热点态势
- 舆论风向争议
- 异动与弱信号
- 研判策略建议

AI 还能分析每条新闻的排名变化轨迹、热度持续时间、跨平台表现。比如某条新闻在微博排第3，知乎排第5，抖音排第8——AI 能告诉你这个话题的"全网热度分布"。

### AI 多语言翻译

如果你订阅了海外 RSS（如 Hacker News），AI 可以帮你把英文标题翻译成中文。反过来，如果你想用英文读国内热点，也可以翻译成英文。

### MCP 智能分析（进阶功能）

这是给深度用户准备的。TrendRadar 实现了 **MCP (Model Context Protocol)** 协议，可以接入 Claude Desktop、Cherry Studio、Cursor 等 AI 客户端。

你可以用自然语言跟新闻数据"对话"：

```
"分析过去一周 DeepSeek 的热度变化"
"对比知乎和微博今天的热点差异"
"生成一份今天的科技热点摘要，推送到飞书"
"搜索特斯拉相关新闻，分析情感倾向"
```

AI 会自动调用 TrendRadar 的 21 个分析工具，帮你做深度数据挖掘。

## 部署方式

### GitHub Actions（零服务器）

适合没有服务器的用户。流程是：

1. Fork TrendRadar 仓库到自己的 GitHub
2. 配置 GitHub Secrets（填推送渠道的 webhook URL）
3. GitHub Actions 定时运行，自动抓取并推送

缺点是每次运行完环境就销毁，数据没法本地存。需要配置云存储（如 Cloudflare R2）来持久化数据。

### Docker（推荐）

适合有服务器、NAS 或长期运行电脑的用户。数据本地存储，更稳定。

```bash
# 克隆项目
git clone https://github.com/sansan0/TrendRadar.git
cd TrendRadar

# 配置
cp config/config.yaml.example config/config.yaml
# 编辑 config.yaml 和 frequency_words.txt

# 启动
docker compose up -d
```

Docker 部署还有个好处：可以同时跑两个容器——一个做新闻推送，一个做 MCP AI 分析服务。

### 本地运行

Windows/Mac/Linux 直接跑：

```bash
# Windows
setup-windows.bat

# Mac/Linux
./setup-mac.sh

# 运行
python main.py
```

## 配置要点

### config.yaml 主配置

这是核心配置文件，结构如下：

```yaml
app:
  timezone: "Asia/Shanghai"        # 时区

schedule:
  enabled: true
  preset: "morning_evening"        # 调度模板

platforms:
  enabled: true
  sources:                         # 监控平台列表
    - id: "zhihu"
      name: "知乎"
    - id: "weibo"
      name: "微博"

report:
  mode: "incremental"              # 推送模式
  display_mode: "keyword"          # 显示方式

filter:
  method: "keyword"                # keyword | ai

notification:
  enabled: true
  channels:
    feishu:
      webhook_url: ""
    telegram:
      bot_token: ""
      chat_id: ""

ai:
  model: "deepseek/deepseek-chat"  # AI 模型
  api_key: ""                      # API Key

ai_analysis:
  enabled: true                    # 开启 AI 分析
  max_news_for_analysis: 50        # 分析数量上限

ai_translation:
  enabled: true
  language: "中文"
```

### frequency_words.txt 关键词配置

前面已经介绍过语法，这里补充几个实用技巧：

**技巧1：从宽到严，逐步调整**

刚开始可以写宽泛的关键词，观察几天后再加过滤词：

```txt
# 第一版：先测试
AI
ChatGPT

# 第二版：发现太多广告，加过滤
AI
ChatGPT
!培训
!课程
!广告

# 第三版：只想看技术相关，加必须词
AI
ChatGPT
+技术
```

**技巧2：正则表达式精确匹配英文**

英文容易误匹配，比如 `ai` 会匹配到 `training` 里的 `ai`。用正则解决：

```txt
# 精确匹配独立单词
/\bAI\b/i => AI相关

# 匹配开头或结尾
/^breaking/     # 只匹配开头是 breaking 的
/发布$/         # 只匹配结尾是"发布"的
```

不会写正则？直接问 ChatGPT："帮我写一个正则表达式，精确匹配英文单词 AI，不匹配 training 里的 ai，格式是 /正则/ => 别名"

**技巧3：全局过滤不想看的**

有些内容不管什么关键词都不想看，用 `[GLOBAL_FILTER]`：

```txt
[GLOBAL_FILTER]
震惊
刚刚
竟然
广告
推广

[WORD_GROUPS]
你的关键词配置...
```

### 推送渠道配置

**企业微信（最简单）**：

1. 打开企业微信，进入目标群聊
2. 点击右上角"..."，选择"群机器人"
3. 添加机器人，复制 Webhook URL
4. 填入配置或 GitHub Secrets

**飞书**：

1. 访问 https://botbuilder.feishu.cn/home/my-command
2. 新建机器人指令
3. 选择"Webhook 触发"，复制 URL
4. 配置参数模板：
```json
{
  "message_type": "text",
  "content": { "text": "{{内容}}" }
}
```

**Telegram**：

需要两个配置：`bot_token` 和 `chat_id`。

1. 在 Telegram 搜索 @BotFather，发送 `/newbot` 创建机器人
2. 获取 Bot Token
3. 向你的机器人发一条消息
4. 访问 `https://api.telegram.org/bot<Token>/getUpdates`
5. 从返回 JSON 找到 `chat.id`

**邮件**：

支持 Gmail、QQ邮箱、163、Outlook 等。QQ邮箱需要用授权码（不是密码），在邮箱设置里开启 SMTP 服务后生成。

## 实际使用体验

我部署了一套配置，关键词设为：AI、DeepSeek、华为、特斯拉、芯片、大模型。推送模式选 `incremental`，调度选 `morning_evening`。

效果是这样的：

**早上 9 点**：收到推送，包含昨晚到今早新出现的 15 条相关热点。AI 分析报告附在最后，告诉我"AI 领域今天舆论偏正面，DeepSeek 新模型发布引发热议，华为鸿蒙讨论度上升"。

**晚上 8 点**：收到当日汇总，包含全天所有匹配新闻（去重后约 30 条）。AI 给了一份更完整的趋势分析，包括"哪些话题持续在榜"、"哪些是新爆发点"。

**好处**：

1. **不用刷 APP 了**。之前每天刷微博知乎抖音至少两小时，现在 5 分钟看完推送就行。
2. **信息密度高**。一条推送包含 11 个平台的热点，跨平台对比一目了然。
3. **AI 分析有价值**。不是简单的汇总，而是告诉你趋势、情绪、关联。比如"特斯拉降价"这个话题，AI 能分析出"微博讨论偏负面（吐槽割韭菜），知乎讨论偏中性（分析影响），抖音讨论偏正面（喊降价真香）"。

**注意点**：

1. **关键词不要太多**。我刚开始写了 30 多个关键词，结果每次推送 100 多条，信息过载。后来精简到 6 个核心关键词，效果好多了。
2. **AI 分析有成本**。默认模型是 DeepSeek，很便宜。按官方估算，每小时推送一次，每天约 0.1 元。如果想省钱，可以把 `max_news_for_analysis` 从 150 降到 50。
3. **GitHub Actions 有延迟**。定时任务触发时间不稳定，可能有 ±15 分钟偏差。如果需要精准推送，建议用 Docker 部署到自己的服务器。

## MCP 功能进阶用法

如果你想深度挖掘新闻数据，MCP 功能很有价值。

### 配置 MCP 客户端

以 Cherry Studio 为例（推荐，有 GUI）：

1. 运行 TrendRadar 的 MCP 服务：
```bash
# Windows
start-http.bat

# Mac/Linux
./start-http.sh
```

2. 在 Cherry Studio 设置里添加 MCP 服务器：
   - 类型：`streamableHttp`
   - URL：`http://127.0.0.1:3333/mcp`

3. 开始对话。

### MCP 可以做什么

**趋势分析**：

```
"分析最近 7 天 DeepSeek 的热度变化"
```

AI 会调用 `analyze_topic_trend` 工具，返回：
- 首次出现时间、持续时间
- 排名变化曲线（第3→第1→第5）
- 热度峰值、爆火判断
- 趋势预测

**平台对比**：

```
"对比知乎和微博今天关于 AI 的讨论差异"
```

AI 会对比两个平台的热点分布、情绪倾向、讨论角度差异。

**情感分析**：

```
"分析特斯拉最近新闻的情感倾向"
```

返回正面/负面/中性分布，以及典型情感关键词。

**生成报告并推送**：

```
"写一份今天的科技热点摘要，推送到飞书"
```

AI 会调用 `generate_summary_report` 生成报告，然后调用 `send_notification` 推送。自动处理格式转换（Markdown → 飞书格式）。

### MCP 工具列表

| 分类 | 工具 | 功能 |
|-----|------|------|
| 基础 | `get_latest_news` | 获取最新新闻 |
| | `get_news_by_date` | 按日期查询 |
| | `get_trending_topics` | 热点统计 |
| RSS | `get_latest_rss` | RSS 内容 |
| | `search_rss` | RSS 搜索 |
| 搜索 | `search_news` | 统一搜索 |
| | `find_related_news` | 相似新闻 |
| 分析 | `analyze_topic_trend` | 趋势分析 |
| | `analyze_sentiment` | 情感分析 |
| | `aggregate_news` | 跨平台聚合 |
| | `compare_periods` | 时期对比 |
| | `generate_summary_report` | 生成报告 |
| 通知 | `send_notification` | 推送消息 |
| 文章 | `read_article` | 读取正文 |

总共 21 个工具，覆盖了从查询到分析到推送的全流程。

## 数据存储

TrendRadar 的数据存储在 SQLite 数据库，按日期分库：

```
output/
├── news/
│   ├── 2025-05-16.db    # 当天热榜数据
│   ├── 2025-05-15.db    # 历史数据
├── rss/
│   ├── 2025-05-16.db    # RSS 数据
└── html/
    └── 当日汇总.html     # HTML 报告
```

数据库表结构设计得很好：

- `news_items`：存储新闻条目（标题、URL、排名）
- `rank_history`：记录排名变化历史（每次抓取的排名）
- `crawl_records`：记录抓取时间和数量

这样设计的好处是可以追踪热度变化轨迹。比如某条新闻早上排第 5，中午排第 3，晚上掉到第 10——这些变化都会被记录下来，供 AI 分析。

## 与其他工具对比

| 工具 | TrendRadar | RSS 阅读器 | 热榜网站 |
|-----|-----------|-----------|---------|
| 数据源 | 50+ 平台热榜 | RSS订阅源 | 单一或少量平台 |
| 筛选方式 | 关键词+AI | 手动订阅 | 无筛选 |
| 推送 | 多渠道 | 需额外工具 | 无推送 |
| AI 分析 | 内置 | 无 | 无 |
| 趋势追踪 | 有 | 无 | 无 |
| 部署复杂度 | 中 | 低 | 无需部署 |

TrendRadar 的优势在于：**聚合 + 筛选 + 分析 + 推送** 一条龙。RSS 阅读器适合订阅特定博客，热榜网站适合快速浏览，但都没有 AI 分析和自动推送。

## 项目地址和资源

- **GitHub**：https://github.com/sansan0/TrendRadar
- **可视化配置编辑器**：https://sansan0.github.io/TrendRadar/
- **NewsNow 数据源**：https://github.com/ourongxing/newsnow

项目维护得很活跃，版本迭代快（从 v1.0 到 v6.7），文档也很详细。有问题可以去 GitHub Issues 提，作者回复很及时。

## 总结

TrendRadar 解决的问题是：**如何从信息洪流中高效获取有价值的内容**。

它不是简单的热榜聚合，而是：
- 用关键词/AI筛选过滤噪音
- 用多渠道推送直达手机
- 用AI分析提供深度洞察
- 用MCP协议支持自定义数据挖掘

如果你每天花大量时间刷 APP 看热点，却总觉得信息过载、抓不住重点——试试 TrendRadar。部署一次，配置好关键词，之后就等着推送敲门，看完推送就完事。

从"被动接收算法推荐"变成"主动获取关心内容"，这才是高效的信息消费方式。