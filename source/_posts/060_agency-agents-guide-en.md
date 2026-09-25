---
title: Running a One-Person Company with Agency-Agents
date: 2025-12-01
lang: en
label: 060_agency-agents-guide
tags: Multi Agent
categories: AI
---

Building a product solo, the worst thing isn't the technical challenges — it's realizing you're simultaneously missing a product manager, an architect, and a marketing expert. Agency-Agents is an open-source repo that packages 200+ professional roles into Agent files you can import directly into Claude Code, letting indie developers tap into domain-specific expertise on demand. This post covers the repo structure, how to invoke agents, and how to use them to collaborate on a complete project.

<!-- more -->

## The Real Dilemma of a One-Person Company

When an indie developer kicks off a project, challenges in product planning, technical architecture, and marketing all hit at once. Take a digital nomad community, for example. You need to define user personas and feature priorities, decide on the tech stack and database design, and figure out how to run social media campaigns and drive traffic from content platforms. The traditional options are: learn it all yourself (time-consuming), pay someone (expensive), or wing it (might get it wrong). Agency-Agents offers a fourth path: let AI take on professional roles and output domain-specific plans. You make the decisions; it produces the specialized content.

## Inside the Agency-Agents Repo

Agency-Agents isn't a software framework — it's a carefully designed library of Agent prompt templates. The repo contains 21 category directories and 201 Agent files, covering the full chain from product development to marketing.

| Category | Agent Count | Example Roles |
|------|-----------|-------------|
| `engineering` | 27 | AI Engineer, Backend Architect, Frontend Dev, Security Engineer, DevOps |
| `marketing` | 29 | Xiaohongshu Operator, Douyin Strategist, SEO Specialist, Growth Hacker, Zhihu Operator |
| `sales` | 8 | Sales Coach, Client Strategist, Proposal Expert |
| `product` | 5 | Product Manager, Trend Researcher, Feedback Analyst |
| `design` | 8 | UI Designer, UX Architect, Brand Guardian |
| `project-management` | 6 | Project Manager, Studio Operator, Experiment Tracker |
| `specialized` | 28 | Compliance Auditor, Recruiting Specialist, Blockchain Security Auditor, Supply Chain Strategist |

The repo has been localized for the Chinese market, including roles like Xiaohongshu Operations Expert, Douyin Short Video Strategist, WeChat Official Account Operator, Zhihu Topic Operator, and DingTalk/Feishu Integration Developer. These roles come up frequently in the daily work of Chinese indie developers, and they work out of the box after import — no extra adaptation needed.

Every Agent file follows a unified structured template containing: identity definition, core mission, key rules, technical deliverables, workflow, communication style, and success metrics. This design gives each Agent clear professional grounding, specific methodology, non-negotiable constraint boundaries, and measurable KPI expectations.

## Supported Tool Ecosystem

Agency-Agents' install script supports 11 AI coding tools, covering the mainstream IDEs and CLI environments.

| Tool | Install Location | Notes |
|------|----------|------|
| Claude Code | `~/.claude/agents/` | Native support, works directly |
| GitHub Copilot | `~/.github/agents/` | VS Code / JetBrains integration |
| Cursor | `.cursor/rules/` | Project-level rule files |
| Gemini CLI | `~/.gemini/extensions/` | Extension format |
| Windsurf | `.windsurfrules` | Codeium rule system |
| Qwen Code | `.qwen/agents/` | Tongyi Qianwen project-level Agent |
| Aider | `CONVENTIONS.md` | Terminal AI coding assistant |
| OpenCode | `.opencode/agents/` | Project-level config |
| OpenClaw | `~/.openclaw/` | Workspace mode |
| Kimi Code | `~/.config/kimi/agents/` | Moonshot Agent |
| Antigravity | `~/.gemini/antigravity/` | Gemini skill system |

Installation is straightforward: clone the repo, run `./scripts/convert.sh` to generate files in each tool's format, then `./scripts/install.sh --tool claude-code` to install into the right directory. You can also use `--interactive` to pick your target tools interactively. After installation, the Agent files live in the corresponding tool's rules directory, ready to invoke.

## Invoking Agents in Claude Code

After installation, there are three ways to invoke agents in Claude Code. First, call a specific agent directly — type `/agent product-manager` and then state your requirement. Second, describe what you need in natural language and Claude Code will auto-detect which role you need and produce the corresponding output. Third, combine multiple agents — for example, invoke both the Product Manager and Backend Architect simultaneously to plan a project.

After invoking the Product Manager Agent, it outputs structured professional documents: problem statement, target user personas, MVP feature list, and success metrics. This isn't generic advice — it's a complete PRD you can use directly for project planning. For a digital nomad community example, the Product Manager Agent would identify two core pain points — digital nomads lacking a sense of belonging and workspace information opacity — define two target user segments (freelancers and remote employees), output an MVP list with three P0 features (user registration, city guide, community posts), and set success metrics of 1,000 registered users and 100 DAU within 30 days of launch.

## Collaboration in Practice

Let's walk through a complete case study showing how Agency-Agents and Claude Code collaborate from product planning through marketing launch. Throughout this process, you play the decision-maker — defining goals, reviewing plans, making key calls. Claude Code is the execution engine — reading Agent rules, generating code, running commands. The various Agents act as specialist consultants, producing domain-specific plans at each stage.

Product planning starts by invoking the Product Manager Agent. After entering the digital nomad community project requirements, the Agent outputs user persona analysis, MVP feature list, feature prioritization, and success metrics. You review everything and confirm the MVP scope: three modules — user authentication, city guide, and community posts. Next, hand this plan to the Backend Architect Agent, telling it to design the technical architecture based on the Product Manager's plan, with React + Node.js + PostgreSQL as the tech stack. The architect outputs a complete database design and API interface list: a users table storing basic info and current city, a city guide table recording city name, internet speed, and cost of living, a community posts table linked to users with title, content, and category. API interfaces cover registration/login, city list and detail, post list and publishing.

Moving into development, invoke the Frontend Developer Agent to build the frontend project scaffold based on the architect's API design. Claude Code actually executes `npm create vite@latest` to create the project, installs Tailwind CSS, React Router, Axios, and other dependencies, then generates the component directory structure — login/registration forms, homepage, city guide page, along with corresponding API call modules and auth hooks. As the product nears launch, invoke the Marketing Strategist Agent, focusing on Xiaohongshu and Zhihu channels. The Agent analyzes user characteristics and content directions across channels, and outputs a concrete content matrix plan — like a "Digital Nomad City Cafe Reviews" series and a "Remote Work Power Tools" series for Xiaohongshu, plus specific execution steps for seed user acquisition.

## Traditional vs Agent-Assisted Workflow

Under the traditional approach, product planning means searching for references and guessing, technical architecture means following tutorials and trial-and-error, frontend implementation means learning as you go, and marketing means guessing at channels. The full cycle typically takes 16 to 20 weeks. With Agent collaboration, each stage has a specialized Agent producing a structured plan, and Claude Code handles the automated execution. The full cycle compresses to 8 to 12 weeks.

The core problems Agency-Agents solves boil down to three areas. On the manpower gap: the marketing Agent gives you professional strategy, the security Agent gives you audit checklists — you don't need to learn every domain from scratch. On knowledge blind spots: each Agent's output is grounded in that domain's best practices, not assembled by guessing. On execution efficiency: after the Agent outputs a plan, Claude Code generates the code and files directly, eliminating the translation cost from plan to implementation.

## Usage Recommendations

Invoke Agents progressively by development stage — don't pull in every role at once. Use the Product Manager Agent during planning, the Architect and UI Designer Agents during design, frontend and backend Agents during development, and bring in marketing and security audit Agents at launch. Each stage's output becomes the next stage's input, forming a coherent workflow. Agents are advisors, not decision-makers. They give professional recommendations; you judge whether those recommendations fit your actual situation. The Agent doesn't know your budget constraints, time limits, or technical capability boundaries — you need to supply that context when reviewing plans.

Maintaining context consistency matters. Each time you invoke a new Agent, tell Claude Code about the key decisions made so far — that the tech stack is settled, that the MVP scope is defined — so the new Agent's output aligns with prior work instead of starting from scratch. Iterative optimization is the norm. The first database design might be too simple, the first marketing strategy might be too broad. Tell the Agent directly what needs more detail and what needs refining — that's far more efficient than re-describing the entire requirement.

## References

- [Agency-Agents GitHub Repository](https://github.com/msitarzewski/agency-agents)
- [Agency-Agents Chinese Contribution Guide](https://github.com/msitarzewski/agency-agents/blob/main/CONTRIBUTING_zh-CN.md)
