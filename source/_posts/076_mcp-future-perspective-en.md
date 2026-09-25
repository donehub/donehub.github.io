---
title: "Is MCP Dead? A Look at the Numbers"
date: 2026-04-03
categories: MCP
tags: [AI]
lang: en
label: 076_mcp-future-perspective
---

On April 22, 2026, Anthropic published an official blog post about MCP's positioning and evolution. The context was anything but calm — over the preceding months, the community had raised serious concerns about MCP's cost, context consumption, and schema design. Perplexity's CTO even publicly stated they were moving away from MCP internally. Anthropic's response didn't rebut each criticism point by point. Instead, it offered a more complete framework for understanding how agents connect to external systems, along with two concrete technical optimizations that directly addressed the community's core concerns.

<!-- more -->
---

## The Charges: Cost, Context, and Schema

Criticism of MCP clustered around three areas, each backed by real numbers.

ScaleKit's benchmarks showed MCP costing 17x more than CLI for the same operations. That's not a marginal difference — it's an order-of-magnitude gap that immediately disqualified MCP from consideration at many teams.

Perplexity's CTO provided data from another angle: MCP tool definitions consumed up to 72% of their context window. For agents handling long conversations and complex tasks, context window is the scarcest resource. When tool definitions eat most of it, there's barely room left for actual reasoning and business logic.

GitHub's MCP schema put the third problem in concrete terms: 43 tools, each with an average description of 4,026 tokens, all sent to the model on every interaction. Just transmitting tool definitions becomes a significant fixed cost, regardless of how many tools the current task actually needs.

All three issues boil down to one thing: MCP's design causes token consumption to spiral out of control as tool scale grows.

## Three Connection Methods and Their Boundaries

Anthropic's blog categorized agent-to-external-system connections into three types, with clear guidance on when each applies.

| Method | Use Case | Advantage | Disadvantage |
|--------|----------|-----------|--------------|
| Direct API | Simple, fixed integrations | Fast, straightforward | Poor scalability — hits M×N integration problems as tools grow |
| CLI | Local dev environments | Efficient, flexible, lowest token cost | Can't run in the cloud, depends on local filesystem |
| MCP | Cloud and cross-platform | Standardized protocol, build once, reuse everywhere | Higher cost and context overhead |

Anthropic acknowledged that CLI is genuinely more efficient in local environments, with a clear cost advantage. But they pointed to a trend that's already underway: an increasing share of production-grade agents run in the cloud with no local filesystem and no ability to execute CLI commands. Claude on the web, mobile apps, enterprise agents deployed to cloud infrastructure — none of these can use CLI. MCP fills that gap with a standardized remote connection layer.

This positioning is much clearer than before. MCP isn't trying to replace CLI. It's the standardized integration layer for cloud and cross-platform scenarios that CLI can't reach.

Market data backs up developer buy-in for this direction. MCP SDK monthly downloads grew from 100 million to 300 million in just a few months.

## First Fix: Tool Search

Anthropic's first fix targets the most criticized issue: token consumption. They call it Tool Search.

The problem with the traditional approach is straightforward: every interaction sends all tool definitions into context, regardless of what the task actually needs. 43 tools? Send all 43. 2,500 API endpoints? Send all 2,500. It's like going to the library for one book and having the librarian wheel the entire shelf to your table.

Tool Search turns tool selection into a two-stage process. The model first describes what it wants to do based on user intent. The system then retrieves matching tool definitions and sends only the relevant ones. Instead of grouping tools by API, they're grouped by user intent — so retrieval matches how people actually work.

The results are direct: tool definition token consumption drops by over 85%, with no decrease in tool selection accuracy. This approach eliminates the fixed cost of sending all tool definitions, changing MCP's token cost model from "always send everything" to "load on demand."

## Second Fix: Programmatic Tool Calls

The second solution targets a different source of token consumption — the raw data returned by tools.

In the traditional flow, when a tool finishes executing, all raw data goes straight back into the model's context. A query returns 500 records? All 500 enter context, even if the model only needs a statistical summary or a filtered subset.

Programmatic calls change this flow. The model generates a small piece of processing code in a secure sandbox. The sandbox executes data filtering, computation, and aggregation, returning only the refined result to the model. Data processing happens in the sandbox; token consumption only applies to the final output.

According to Anthropic's data, this approach reduces token consumption by an additional 37% on complex tasks. Its value scales with the problem: the more tools and the larger the return data, the more dramatic the compression from programmatic calls.

## Combined Cost Impact

Stacking Tool Search and programmatic calls together, the cost gap between MCP and CLI changes like this:

| Stage | MCP Token Cost | CLI Token Cost | Gap |
|-------|---------------|---------------|-----|
| Before optimization | ~32,000 | ~1,000 | 32x |
| After both optimizations | ~10,000 | ~1,000 | ~7x |

The gap shrinks from 32x to roughly 7x. MCP still costs more than CLI, but the difference is now within an acceptable range. In cloud environments, the engineering value of MCP's standardization, security, and cross-platform capabilities more than covers the 7x cost difference. Flip the question: if you skip MCP, what does it cost to build equivalent cloud capabilities another way?

## Cloudflare's Production Design

Cloudflare is a heavy MCP user, and their design puts Anthropic's ideas into practice.

Cloudflare needed to expose roughly 2,500 API endpoints through MCP. Registering all 2,500 as individual MCP tools would make the token overhead astronomical. Their approach: expose only two tools externally — one `search`, one `execute`. The agent first uses `search` to find the target API, then uses `execute` to run the operation server-side.

This design compresses tool definition tokens to approximately 1,000, essentially matching CLI consumption. It also reflects a design principle Anthropic advocates: MCP servers should be designed like CLI tools, letting agents orchestrate and control operations through code rather than wrapping every atomic operation as an independent tool.

## Ecosystem Evolution: MCP and Skills

Anthropic's blog also clarified the relationship between MCP and Skills, formally incorporating Skills into official best practices.

MCP handles connecting to services and providing capabilities. Skills tell the agent how to use those capabilities to accomplish specific tasks. The relationship is like a toolbox paired with an operations manual. Claude's data plugin illustrates this: it consists of 10 Skills and 8 MCP servers. Users can analyze data from different databases — Skills handle analysis logic and workflow orchestration, while MCP servers handle data source connections and query execution.

Third-party providers like Canva and Notion are following this pattern, releasing MCP servers alongside companion Skills. The ecosystem is shifting from tool-vs-tool competition to bundled tool-plus-orchestration packages.

## The Emerging Division of Labor

Combining Anthropic's response with actual community feedback, the division of labor in the agent connectivity layer is taking shape:

| Environment | Recommended Approach |
|-------------|---------------------|
| Cloud production (user-facing SaaS) | MCP + Skills |
| Developer local environment | CLI + Skills |
| Simple fixed integrations | Direct API |

MCP's cost problems are real, but Anthropic's Tool Search and programmatic calls provide quantifiable solutions, compressing the gap from 32x to 7x. MCP hasn't become a universal solution, but it has found where it belongs: the standardized integration layer for cloud and cross-platform environments. No single connection method covers all scenarios. The agent era's connectivity layer is evolving toward environment-specific specialization.

---

**Key Data Sources:**

| Data Point | Source | Value |
|-----------|--------|-------|
| MCP vs CLI cost gap | ScaleKit testing | 17x |
| MCP context usage | Perplexity CTO | 72% |
| GitHub MCP tool count | Official schema | 43 |
| Tool Search token reduction | Anthropic | 85%+ |
| Programmatic call token reduction | Anthropic | 37% |
| MCP SDK monthly downloads | npm data | 300M |
| Cloudflare tool definition tokens | Production case | ~1,000 |

**References:**
- [Anthropic official blog](https://www.anthropic.com)
- [ScaleKit MCP test report](https://scalekit.com)
- [Cloudflare MCP implementation](https://blog.cloudflare.com)
