---
title: "TrendRadar: Stop Doomscrolling, See Only the News You Actually Care About"
date: 2026-05-16
tags: AI Open Source Tools
categories: [AI]
lang: en
label: 098_trendradar-hot-news-aggregator-guide
---

## Background

Every day, the routine goes: open your phone, scroll through Weibo trending, Zhihu hot list, Douyin trending, Toutiao — two hours gone, and maybe three to five items were actually useful. The rest is clickbait headlines, marketing fluff, celebrity gossip, and whatever the algorithm decided you might be interested in. Platform algorithms hijack your attention — the content you want to see is buried, and the content you don't want is inescapable.

TrendRadar solves exactly this problem: it aggregates trending topics across the entire internet, filters them by keywords you define, pushes updates to your phone on schedule, and can even have AI analyze the trends and sentiment behind the headlines. It shifts you from passively receiving algorithm recommendations to actively consuming what you care about.

<!-- more -->
---

## What Is TrendRadar

TrendRadar is an open-source hot news aggregation and analysis tool. The core idea is to pull trending lists from 50+ platforms across the internet, filter them by keywords you configure, and deliver the content that matters to you. Push channels cover Feishu (Lark), DingTalk, WeCom (Enterprise WeChat), Telegram, email, Bark (iOS), Slack, and even custom webhooks.

It has built-in AI analysis capabilities — not just aggregating trending topics, but analyzing trend trajectories, judging public sentiment (positive/negative/controversial), performing cross-platform correlation analysis, and generating insight reports. Think of it as hiring a personal news assistant who distills valuable content from the flood of information every day.

## Data Sources

TrendRadar pulls data from another open-source project called NewsNow, which aggregates trending data from 50+ platforms:

| Domestic General | Tech Platforms | Finance Platforms | International Media |
|---------|---------|---------|---------|
| Zhihu, Weibo | IT Home, 36Kr | Wall Street CN | Hacker News |
| Baidu Trending | Juejin (稀土掘金) | Cailian Press | GitHub Trending |
| Douyin, Toutiao | V2EX | Xueqiu (Snowball) | Product Hunt |
| The Paper, iFeng | CoolApk | Gelonghui | Lianhe Zaobao |
| Hupu, Tieba | SSPAI (少数派) | Grow.cn | Sputnik News |

NewsNow fetches trending data by calling official APIs or scraping pages from each platform, outputting everything in a standardized format. TrendRadar directly calls NewsNow's public API:

```
https://newsnow.busiyi.world/api/s?id=zhihu&latest
```

The returned data looks like this:

```json
{
  "status": "success",
  "items": [
    {
      "title": "How to evaluate DeepSeek's new model?",
      "url": "https://zhuanlan.zhihu.com/p/xxx",
      "extra": {
        "info": "12.34M heat",
        "hover": "Summary description..."
      }
    }
  ]
}
```

This design means TrendRadar doesn't need to handle each platform's anti-scraping mechanisms itself — data source maintenance is handled by the NewsNow project. When a platform changes its API, NewsNow updates its adapter and TrendRadar users don't need to worry about it.

## Core Features

### Keyword Filtering

This is TrendRadar's most important feature. Write your keywords of interest in `frequency_words.txt` and the system only pushes news containing those terms. The syntax is flexible — it supports group naming, regex matching, exclusion words, result count limits, and multi-word conjunction:

```txt
# Simplest: just write a keyword
Huawei

# Group multiple keywords together (separated by blank lines)
Huawei
HarmonyOS
Ren Zhengfei

# Name the group
[Tech Giants]
Huawei
Tencent
ByteDance

# Regex matching (precise English word matching to avoid false positives)
/\bAI\b/ => AI-related
artificial intelligence

# Exclude things you don't want to see
[Apple Inc]
Apple
!fruit        # Exclude fruit-related content

# Limit displayed results
Tesla
@10          # Show at most 10 items

# Require multiple words to all appear
+launch
+new         # Must contain both "launch" and "new"
```

### AI-Powered Smart Filtering

If you'd rather not write keywords manually, you can describe your interests in natural language. In `ai_interests.txt`, write something like:

```txt
Here's what I want to follow:

1. China tech and internet companies: Focus on DeepSeek, Huawei, Tencent...
2. Large models and AI products: Follow OpenAI, Claude, ChatGPT...
3. AI infrastructure and cloud compute: Follow NVIDIA, AMD...
4. Chips and semiconductor manufacturing: Focus on chips, lithography machines...
...

# Title quality requirements
- No clickbait/shock headlines
- No marketing fluff
```

The AI automatically understands your interests, scores each news item, and only pushes highly relevant content. This feature requires configuring an AI API (supports DeepSeek, OpenAI, Gemini, etc.).

### Three Push Modes

| Mode | Description | Target Users |
|-----|------|---------|
| daily (daily digest) | Push all matched news from the day at a scheduled time | Managers, general users |
| current (current list) | Push currently trending matched news each time | Content creators, social media managers |
| incremental (incremental monitoring) | Only push newly appearing items, zero duplicates | Investors, traders |

For example: you're monitoring "Tesla" with hourly execution. In incremental mode, only first-appearance news gets pushed — subsequent repeats don't bother you again. This mode suits high-frequency monitoring scenarios.

### Scheduling System

You can fine-tune what happens when. Weekday mornings at 9 AM for a quick scan, midday for trending topics, 7 PM for the daily digest. Weekends sleep in and start at 10 AM, push only when there's something new. Five preset templates: always_on (24/7), morning_evening (morning and evening digests), office_hours (business hours), night_owl (night owl schedule), and custom (fully customizable).

### AI Analysis Push

When enabled, every push includes an AI-generated insight report covering core trending dynamics, sentiment direction and controversy, anomalies and weak signals, and strategic recommendations. The AI can also analyze each news item's ranking trajectory, how long it's been trending, and cross-platform performance. For example, if a story ranks 3rd on Weibo, 5th on Zhihu, and 8th on Douyin, the AI tells you the topic's heat distribution across the internet.

### MCP-Powered Analysis

TrendRadar implements the MCP (Model Context Protocol), allowing it to connect with AI clients like Claude Desktop, Cherry Studio, and Cursor for natural-language conversations with news data:

```
"Analyze DeepSeek's heat changes over the past week"
"Compare today's trending topics on Zhihu vs Weibo"
"Generate a tech trending summary for today and push it to Feishu"
"Search Tesla-related news and analyze sentiment"
```

The AI automatically calls TrendRadar's 21 analysis tools for deep data mining. This feature is valuable for power users — casual users can get by with keyword filtering and push notifications.

## Deployment Options

### GitHub Actions (Zero Server)

For users without a server. Fork the TrendRadar repo to your GitHub account, configure GitHub Secrets (fill in your push channel webhook URLs), and GitHub Actions runs the scheduled fetching and pushing. The downside is that the environment is destroyed after each run — data can't be stored locally. You'll need cloud storage (like Cloudflare R2) for persistence.

### Docker (Recommended)

For users with a server, NAS, or a machine that runs continuously. Data is stored locally and it's more stable:

```bash
# Clone the project
git clone https://github.com/sansan0/TrendRadar.git
cd TrendRadar

# Configure
cp config/config.yaml.example config/config.yaml
# Edit config.yaml and frequency_words.txt

# Start
docker compose up -d
```

Docker deployment has another advantage: you can run two containers simultaneously — one for news push and one for MCP AI analysis service.

### Local Execution

Windows/Mac/Linux, run directly:

```bash
# Windows
setup-windows.bat

# Mac/Linux
./setup-mac.sh

# Run
python main.py
```

## Configuration Essentials

### config.yaml Main Configuration

The core configuration file structure:

```yaml
app:
  timezone: "Asia/Shanghai"        # Timezone

schedule:
  enabled: true
  preset: "morning_evening"        # Schedule template

platforms:
  enabled: true
  sources:                         # Monitored platform list
    - id: "zhihu"
      name: "Zhihu"
    - id: "weibo"
      name: "Weibo"

report:
  mode: "incremental"              # Push mode
  display_mode: "keyword"          # Display mode

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
  model: "deepseek/deepseek-chat"  # AI model
  api_key: ""                      # API Key

ai_analysis:
  enabled: true                    # Enable AI analysis
  max_news_for_analysis: 50        # Max items to analyze

ai_translation:
  enabled: true
  language: "Chinese"
```

### Keyword Configuration Tips

**Start broad, then tighten.** Begin with broad keywords, observe for a few days, then add exclusion filters:

```txt
# Version 1: Initial test
AI
ChatGPT

# Version 2: Too many ads, add filters
AI
ChatGPT
!training
!course
!ad

# Version 3: Only want tech-related, add required words
AI
ChatGPT
+technology
```

**Use regex for precise English matching.** English words cause false matches easily — `ai` matches the `ai` in `training`. Regex solves this:

```txt
# Precise standalone word matching
/\bAI\b/i => AI-related

# Match beginning or end
/^breaking/     # Only matches items starting with "breaking"
/release$/      # Only matches items ending with "release"
```

If you can't write regex, just ask an AI to generate it for you.

**Global filtering for content you never want.** Some content you don't want to see regardless of keywords — use `[GLOBAL_FILTER]`:

```txt
[GLOBAL_FILTER]
shocking
just in
unbelievable
advertisement
promotion

[WORD_GROUPS]
Your keyword configuration...
```

### Push Channel Configuration

WeCom is the simplest: enter the target group chat, tap the top-right corner, select Group Bot, add a bot, copy the Webhook URL, and paste it into the config.

Feishu requires visiting botbuilder.feishu.cn to create a new bot command, selecting Webhook trigger, copying the URL, then configuring the parameter template.

Telegram needs two settings: bot_token and chat_id. Search for @BotFather in Telegram to create a bot and get the token. After messaging the bot, call the getUpdates API to get the chat.id.

Email supports Gmail, QQ Mail, 163, Outlook, etc. QQ Mail requires an authorization code (not your password) — enable SMTP service in your mailbox settings and generate one.

## Real-World Usage Experience

I set up a configuration with keywords: AI, DeepSeek, Huawei, Tesla, chips, large models. Push mode set to incremental, schedule set to morning_evening.

At 9 AM I receive a push with 15 new relevant trending items from the previous night to that morning. The AI analysis report is appended at the end, reading something like "AI sector sentiment is leaning positive today, DeepSeek's new model release generating discussion, Huawei HarmonyOS discussion volume rising." At 8 PM I receive the daily digest with all matched news for the day (about 30 items after dedup), and the AI provides a more comprehensive trend analysis — which topics have been consistently on the list, which are new breakout points.

After two weeks of use, the most noticeable change is that I no longer scroll through apps. Previously I spent at least two hours daily scrolling Weibo, Zhihu, and Douyin. Now I spend 5 minutes reading the push notifications. Information density is much higher too — a single push covers trending from 11 platforms, cross-platform comparison at a glance. The AI analysis genuinely adds value — it's not a simple summary, it tells you trends, sentiment, and correlations. For the "Tesla price cut" topic, for example, the AI can show that Weibo discussion leans negative (complaining about existing owners getting screwed), Zhihu discussion is neutral (analyzing impact), and Douyin discussion is positive (celebrating the cheaper price).

A few pitfalls worth sharing. Don't set too many keywords — I started with 30+ and got 100+ items per push, which was information overload. After trimming to 6 core keywords, results improved noticeably. AI analysis has a cost — the default model is DeepSeek, and at the official estimate, hourly push costs about ¥0.1 per day. To save money, reduce max_news_for_analysis from 150 to 50. GitHub Actions has timing drift — scheduled task triggers aren't perfectly stable, with possible ±15 minute variance. For precise push timing, Docker deployment on your own server is the way to go.

## MCP Advanced Usage

The MCP feature is for users who want to deep-dive into news data. Using Cherry Studio as an example (it has a GUI, simple to configure), first start TrendRadar's MCP service:

```bash
# Windows
start-http.bat

# Mac/Linux
./start-http.sh
```

Then in Cherry Studio settings, add an MCP server — type: streamableHttp, URL: http://127.0.0.1:3333/mcp — and you're ready to start a conversation.

MCP-supported operations include trend analysis ("Analyze DeepSeek's heat changes over the last 7 days" — the AI calls analyze_topic_trend and returns first-appearance time, ranking curve, peak heat, and trend forecast), platform comparison ("Compare Zhihu and Weibo's AI discussions today" — the AI compares hot topic distribution and sentiment across platforms), sentiment analysis ("Analyze Tesla's recent news sentiment" — returns positive/negative/neutral distribution), and report generation with push ("Write a tech trending summary for today and push to Feishu" — the AI handles format conversion automatically).

21 tools in total, covering the full pipeline from query to analysis to push:

| Category | Tool | Function |
|-----|------|------|
| Basic | get_latest_news | Get latest news |
| | get_news_by_date | Query by date |
| | get_trending_topics | Trending statistics |
| RSS | get_latest_rss | RSS content |
| | search_rss | RSS search |
| Search | search_news | Unified search |
| | find_related_news | Similar news |
| Analysis | analyze_topic_trend | Trend analysis |
| | analyze_sentiment | Sentiment analysis |
| | aggregate_news | Cross-platform aggregation |
| | compare_periods | Period comparison |
| | generate_summary_report | Generate report |
| Notification | send_notification | Push message |
| Article | read_article | Read full text |

## Data Storage

TrendRadar stores data in SQLite databases, partitioned by date:

```
output/
├── news/
│   ├── 2025-05-16.db    # Today's trending data
│   ├── 2025-05-15.db    # Historical data
├── rss/
│   ├── 2025-05-16.db    # RSS data
└── html/
    └── daily_digest.html  # HTML report
```

The database has three core tables: news_items stores news entries (title, URL, ranking), rank_history records ranking changes (rankings from each crawl), and crawl_records tracks crawl times and counts. The advantage of this design is that it can track heat trajectories — a story ranked 5th in the morning, 3rd at noon, and dropped to 10th by evening. All these changes are recorded for AI analysis.

## Comparison

| Tool | TrendRadar | RSS Reader | Trending Sites |
|-----|-----------|-----------|---------|
| Data sources | 50+ platform trending lists | RSS subscriptions | Single or few platforms |
| Filtering | Keywords + AI | Manual subscriptions | No filtering |
| Push | Multi-channel | Requires extra tools | No push |
| AI analysis | Built-in | None | None |
| Trend tracking | Yes | None | None |
| Deployment complexity | Medium | Low | No deployment needed |

TrendRadar's positioning is clear: it's not an RSS reader replacement — it's a solution for the scenario of "want to see trending news but don't want to be controlled by algorithms." RSS readers are for subscribing to specific blogs and information sources. Trending sites are for quick browsing of the day's hot topics. But neither has keyword filtering, AI analysis, or multi-channel push. If you need precise access to hot information in specific domains, TrendRadar is currently the most complete open-source solution available.

## Project Links

- GitHub: https://github.com/sansan0/TrendRadar
- Visual config editor: https://sansan0.github.io/TrendRadar/
- NewsNow data source: https://github.com/ourongxing/newsnow

The project is actively maintained with fast version iteration (v1.0 to v6.7), thorough documentation, and responsive GitHub Issues responses.
