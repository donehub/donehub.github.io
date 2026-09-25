---
title: "OpenCLI Deep Dive: Letting AI Code Agents Control Any Website"
date: 2026-05-22
tags: OpenCLI
categories: AI
lang: en
label: 099_opencli-deep-analysis
---

## Background

When I was researching Chrome DevTools MCP previously, the core problem it solved was letting AI control a browser. But that approach had inherent limitations: you had to configure an MCP Server, depend on Chrome's debug port, and write a separate adapter for each platform.

OpenCLI reimagines this from scratch, and goes further. It doesn't just let AI control a browser — it turns any website into a standardized command-line tool. With 22K+ stars on GitHub, it's clearly hitting a real need.

This article covers three things: what OpenCLI is, how its architecture is designed, and — the most important part — how to use it within Code Agents like Claude Code.

<!-- more -->
---

## What Is OpenCLI

OpenCLI is an AI-native CLI runtime framework that turns any website, browser session, or Electron application into a standardized command-line interface. A comparison makes its positioning clearer:

| Scenario | Traditional Approach | OpenCLI Approach |
|------|---------|-------------|
| Post to Xiaohongshu | Open browser → log in → upload image → write copy → publish | `opencli xiaohongshu publish --title "xxx" --content "xxx"` |
| Check Bilibili views | Open Bilibili creator center → refresh → check data | `opencli bilibili stats` |
| Tell Claude Code "publish an article for me" | Claude Code can't do it | Claude Code does it directly through OpenCLI |

The core difference: traditional approaches require manual browser interaction every time. OpenCLI wraps those operations into deterministic CLI commands with zero LLM runtime cost.

---

## Architecture Breakdown

### Overall Architecture

```
┌──────────────────────────────────────────────────────┐
│                   User / AI Agent                     │
│              (Claude Code / Cursor etc.)              │
└──────────────────────┬───────────────────────────────┘
                       │ CLI commands
                       ▼
┌──────────────────────────────────────────────────────┐
│                   OpenCLI CLI Layer                    │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────┐  │
│  │  Plugin     │  │  Adapter     │  │  Session    │  │
│  │  Loader     │  │  Resolver    │  │  Manager    │  │
│  └─────────────┘  └──────────────┘  └─────────────┘  │
└──────────────────────┬───────────────────────────────┘
                       │
          ┌────────────┴────────────┐
          ▼                         ▼
┌────────────────────┐   ┌────────────────────────┐
│  YAML Adapter      │   │  CDP Communication     │
│  Engine            │   │  Chrome DevTools        │
│  (Compile-time     │   │  Protocol injection     │
│   intelligence)    │   │                         │
│  Deterministic     │   │                         │
│  command output    │   │                         │
└────────────────────┘   └────────────────────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │  Chrome Extension      │
                          │  (Playwright MCP       │
                          │   Bridge)              │
                          └───────────┬───────────┘
                                      │
                                      ▼
                          ┌───────────────────────┐
                          │  Logged-in Chrome      │
                          │  (Your real user       │
                          │   session)             │
                          └───────────────────────┘
```

The architecture has four layers top to bottom: users and AI agents interact with OpenCLI through CLI commands; the CLI layer handles plugin loading, adapter resolution, and session management; the middle layer is the YAML Adapter engine and CDP communication; the bottom layer connects to a real browser instance through a Chrome extension. Each layer has clearly defined responsibilities — let's break down the key design decisions.

### Compile-Time Intelligence vs Runtime Intelligence

The most interesting architectural choice in OpenCLI is where it draws the line between compile-time and runtime intelligence.

Runtime intelligence means having the LLM understand page structure and decide on actions in real-time every time a command executes. This is flexible, but costs tokens on every invocation and produces inconsistent results — the same command executed twice might yield different LLM decisions.

Compile-time intelligence is OpenCLI's choice: the Adapter parses the page structure exactly once during development, producing a deterministic YAML definition. All subsequent CLI calls run against this YAML — zero LLM cost, predictable results. This design drives OpenCLI's runtime cost toward zero while ensuring execution consistency and debuggability.

```yaml
# An Adapter example: get Bilibili video play count
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

Once this YAML is defined, every execution uses deterministic DOM selector matching — no LLM involvement. The tradeoff is that when a website redesigns its UI, selectors need manual updating. But for most stable platforms, this maintenance cost is acceptable.

### Why CDP over Selenium/Playwright

OpenCLI chose Chrome DevTools Protocol (CDP) over traditional Selenium or Playwright for practical reasons.

| Dimension | Selenium/Playwright | CDP + Chrome Instance |
|------|-------------------|-------------------|
| Login state | Must maintain cookies separately | Directly reuses your active Chrome |
| Security | Must store credentials | Zero credential storage |
| Authenticity | Headless browser can be detected | Real browser instance |
| Development cost | Full automation scripts needed | YAML declarative definitions |

The key insight is reusing login state. You're already logged into Zhihu, Bilibili, and Xiaohongshu in your browser. OpenCLI connects directly to that running Chrome instance via CDP — no re-login, no API keys, no password storage. This design makes OpenCLI's security model clean: it stores no credentials at all; all authentication relies on the browser's own session management.

### The Browser Extension's Role

CDP alone can only control Chrome from the outside, but OpenCLI needs bidirectional communication — it needs to both control the page and relay page structure back to the CLI. A Chrome extension serves as this bridge.

The Playwright MCP Bridge extension handles four things: receiving CLI instructions (click, type, navigate), executing corresponding operations in the page, returning structured DOM snapshots (not screenshots — semantic DOM trees), and maintaining session state (bind/unbind tabs). This extension is lightweight, following a micro-daemon pattern that auto-loads when OpenCLI starts.

### Session Binding Mechanism

Sessions are the bridge connecting CLI commands to specific browser tabs in OpenCLI.

```bash
# Bind a logged-in browser tab to a session
opencli browser my-blog bind

# List bound sessions
opencli browser list

# Unbind
opencli browser my-blog unbind
```

Once bound, all CLI commands targeting that platform execute within that logged-in tab. This design lets OpenCLI manage sessions across multiple platforms simultaneously, without interference.

---

## Installation and Quick Start

Requirements: Node.js >= 20.0.0, Chrome / Chromium / Brave / Edge browser.

```bash
# Install OpenCLI globally
npm install -g @jackwener/opencli

# Auto-configuration (detects Chrome instances, installs extension)
opencli setup
```

`opencli setup` does four things: detects local Chrome debug ports, downloads and loads the Playwright MCP Bridge extension, verifies CLI-to-browser connectivity, and initializes the `~/.opencli` configuration directory.

```bash
# List built-in adapters
opencli list

# Run a platform command (using Bilibili as example)
opencli bilibili stats
```

---

## Using OpenCLI in Code Agents

This section is the heart of the article. OpenCLI's real power isn't in manually typing commands — it's in enabling AI Code Agents to control any website through it.

### The Capability Boundary of Code Agents

Code Agents like Claude Code and Cursor are natively powerful: they can write code, read files, run tests, use git. But they have a clear boundary: they can't operate web pages.

The friction this causes in real work is bigger than you might expect. A typical scenario is syncing a tech blog to Zhihu, WeChat Official Account, and Xiaohongshu. Claude Code can write the article quickly, but publishing requires manually operating three different platform backends — login, copy, paste, adjust formatting — repeated three times per article. OpenCLI breaks through this boundary.

### Three Integration Methods

**Direct CLI invocation** is the simplest approach. Claude Code can already execute shell commands — just tell it to run `opencli` commands in conversation, no extra configuration needed.

**Installing the OpenCLI Skill** gives better integration. OpenCLI provides a Skill definition tailored for AI agents. After installation, the agent understands and uses OpenCLI more accurately:

```bash
# Install OpenCLI skill in Claude Code
npx skills add jackwener/opencli
```

After installation, Claude Code automatically recognizes available OpenCLI commands when handling browser-related tasks — no manual specification each time.

**Custom commands in .claude/commands** suits high-frequency operations. Combined with Claude Code's custom command system, you can wrap frequently used OpenCLI operations into slash commands:

```yaml
# .claude/commands/publish-blog.md
---
description: Publish blog to multiple platforms
---

Execute the following commands to publish the blog:
1. opencli zhihu publish --title "{{title}}" --content "{{content}}"
2. opencli weixin publish --title "{{title}}" --content "{{content}}"
3. opencli xiaohongshu publish --title "{{title}}" --content "{{content}}"
```

After that, just type `/publish-blog` in Claude Code to publish everywhere in one shot.

### Real Workflows

**Blog syndication** is the most straightforward use case:

```
You: Publish source/_posts/opencli-deep-analysis.md to Zhihu, Xiaohongshu, and Bilibili

Claude Code's execution flow:
1. Read the Markdown file content
2. Adjust format per platform (Zhihu supports Markdown,
   Xiaohongshu needs short copy + images, Bilibili articles
   have a specific structure)
3. Execute opencli zhihu publish --title "..." --content "..."
4. Execute opencli xiaohongshu publish --title "..." --content "..."
5. Execute opencli bilibili publish --title "..." --content "..."
6. Return publishing results from each platform
```

No browser tab needs to be opened during the entire process.

**Data monitoring** is also practical:

```
You: Check my data across platforms for the past week

Claude Code:
> opencli bilibili stats --period 7d
> opencli zhihu stats --period 7d
> opencli xiaohongshu stats --period 7d

Summary output:
| Platform | Views   | Likes | Comments |
|----------|---------|-------|----------|
| Bilibili | 12,340  | 456   | 89       |
| Zhihu    | 8,920   | 312   | 56       |
| Xiaohongshu | 15,600 | 890 | 123      |
```

**Community moderation automation** can drastically reduce repetitive work:

```
You: Check if there are pending posts in the community admin

Claude Code:
> opencli nomad-community pending-reviews

Returns 3 pending items, displayed one by one...

You: Approve all

Claude Code:
> opencli nomad-community approve --all
```

### Under the Hood: How Agents Operate the Browser

Understanding the underlying flow of Claude Code operating the browser through OpenCLI helps with debugging and writing custom plugins. The full call chain works like this:

```
Claude Code initiates conversation
  → OpenCLI CLI parses the command
    → Finds the corresponding Adapter definition (YAML/TS)
      → Connects to Chrome instance via CDP
        → Extension executes operations in the page
          → Returns structured DOM snapshot
            → Adapter parses the snapshot to extract data
              → CLI returns results to Claude Code
```

The structured DOM snapshot is key to understanding all of this. OpenCLI doesn't take screenshots for the AI — it converts the page into semantic structured text:

```
[button] "Publish Article" (clickable, enabled)
[textbox] "Title" value="OpenCLI Deep Dive" (editable)
[textarea] "Article Body" (editable, placeholder="Enter content...")
[link] "Preview" href="/preview"
```

This format is extremely LLM-friendly: token consumption is far lower than screenshots, information density is higher, and it can directly target interactive elements. Compared to Computer Use's screenshot approach, the DOM snapshot approach has clear advantages in both cost and precision.

---

## Plugin Development

Built-in adapters cover mainstream platforms, but your own website or a niche platform needs a custom plugin.

### Directory Structure

```
~/.opencli/plugins/
└── my-custom-plugin/
    ├── plugin.yaml        # Plugin metadata
    ├── adapters/
    │   ├── list.yaml      # List command
    │   ├── publish.yaml   # Publish command
    │   └── stats.yaml     # Stats command
    └── README.md
```

### Writing an Adapter

Here's an example — extracting an article list from a website's admin panel:

```yaml
# plugin.yaml
name: my-blog-admin
version: 1.0.0
description: Personal blog admin CLI
base_url: https://myblog.com/admin
```

```yaml
# adapters/list.yaml
name: articles
description: List all articles
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
description: Publish a new article
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

After writing the plugin, symlink it to the OpenCLI plugins directory:

```bash
# Linux/Mac
ln -s /path/to/my-custom-plugin ~/.opencli/plugins/my-blog-admin

# Windows (PowerShell)
New-Item -ItemType Junction -Path "$env:USERPROFILE\.opencli\plugins\my-blog-admin" -Target "D:\path\to\my-custom-plugin"
```

Then you can use it directly:

```bash
# List articles
opencli my-blog-admin articles

# Publish an article
opencli my-blog-admin publish --title "OpenCLI Deep Dive" --content "..."
```

### Calling Custom Plugins from Claude Code

Once custom plugins are written, Claude Code can use them too:

```
You: Use the my-blog-admin plugin to list all published articles
Claude Code: Executes opencli my-blog-admin articles, returns...

You: Sync the article titled "xxx" to Zhihu
Claude Code:
1. Execute opencli my-blog-admin articles to get article content
2. Extract the target article's content
3. Execute opencli zhihu publish to publish to Zhihu
```

---

## Comparison

There are quite a few solutions for letting AI operate web pages. Here's a structured comparison:

| Solution | Login State | LLM Cost | Dev Barrier | Stability |
|------|--------|---------|---------|--------|
| OpenCLI | Reuses Chrome | Zero runtime cost | YAML declarative | Deterministic execution |
| Chrome DevTools MCP | Reuses Chrome | Token cost per invocation | Requires MCP config | LLM real-time decisions |
| Playwright scripts | Must maintain cookies | None | Full programming | Highest, but high dev cost |
| Browser Use framework | Separate login needed | Token cost per invocation | Python code | Depends on LLM judgment |

The table makes OpenCLI's sweet spot clear: when you need a deterministic, zero-runtime-cost website operation solution that reuses browser login state, it's the optimal choice. If your scenario demands high flexibility (target page structure changes frequently) or cross-browser compatibility, Playwright scripts are better. For ad-hoc, one-off browser operations, Chrome DevTools MCP has lower setup cost.

---

## Limitations and Boundaries

OpenCLI isn't universal — several scenarios aren't a good fit.

High-frequency trading or ultra-real-time operations aren't suitable. CDP communication has latency — it can't match direct API calls. If your scenario requires sub-second response for trading operations, OpenCLI's latency is unacceptable.

Large-scale concurrent scraping also isn't the right use case. OpenCLI depends on a real Chrome instance, and one Chrome instance can only operate one page at a time. If you need to scrape dozens of pages simultaneously, use traditional headless browser solutions.

Production environments requiring extreme stability need careful consideration. When a website redesigns, Adapter selectors break and need manual updating. For internal systems or platforms with stable APIs, this isn't a big deal. For third-party platforms that redesign frequently, maintenance costs climb.

On the security side, OpenCLI reusing browser login state means it can operate any website you're logged into. Use it only within trusted AI agents (like local Claude Code) — not in cloud or shared environments. For publishing operations, have the agent generate a preview first, confirm manually, then execute.

Platform anti-bot detection is another real concern. Some platforms detect automated behavior. OpenCLI runs against a real browser instance, which fares better than headless browsers, but excessively rapid operations can still trigger risk controls. Pacing operations and avoiding large bursts of activity in short windows is the basic strategy.

---

## Personal Assessment

OpenCLI's value lies in its clear positioning: between LLM-driven browser operations and traditional automation scripts, it substitutes compile-time intelligence for runtime intelligence, driving cost close to zero. This design choice makes it especially well-suited for Code Agent scenarios, where every tool call has a cost and deterministic execution matters more than flexibility.

It won't replace traditional automation solutions like Playwright or Selenium — those have their own advantages in stability and flexibility. OpenCLI fills a gap: letting AI agents manipulate websites at minimal cost while reusing the user's real login state.

For content creators and multi-platform operators, pairing Claude Code with OpenCLI eliminates mountains of repetitive browser work. For developers, the YAML declarative plugin development barrier is far lower than writing full automation scripts. The tool's actual value depends on how much repetitive web operation work you need automated.
