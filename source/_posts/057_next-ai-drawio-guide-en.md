---
title: Next Draw.IO — Professional Diagrams from Plain English
date: 2025-10-23
lang: en
label: 057_next-ai-drawio-guide
tags: MCP
categories: AI
---

Writing technical docs and need a system architecture diagram? The traditional route is opening draw.io, hunting for icons, dragging shapes, drawing connectors, aligning everything — the whole process takes at least 10 minutes. Next AI Draw.io compresses that to a single sentence: describe what you need in plain English, and the AI generates a professional draw.io-format diagram right in your browser. It supports the MCP protocol, so you can call it directly from Claude Code — sketch the diagram while you're writing the code.

<!-- more -->

## What It Is

Next AI Draw.io is an open-source project built on Next.js 16 + React 19 + Vercel AI SDK + draw.io. Its core capabilities break down into four dimensions: natural language diagramming, where you describe a requirement and the AI generates a draw.io-format diagram; automatic cloud architecture icon matching, covering AWS, GCP, Azure, and Alibaba Cloud; conversational editing, where you can keep modifying the diagram through natural language after generation; and MCP integration, allowing direct invocation from AI tools like Claude Code and Cursor.

The project is open-sourced on GitHub (https://github.com/DayuanJiang/next-ai-draw-io), and the live demo is at https://next-ai-drawio.jiang.jp/.

## Four Ways to Use It

The tool offers four integration points ranging from lightweight to heavy. The online demo is for quick one-off use — open the browser and start drawing, no install needed. The desktop app is for frequent daily diagramming, with clients for Windows, macOS, and Linux. Local deployment targets enterprise intranet scenarios — one Docker command to spin it up. MCP integration is the most popular option for developers: call the diagramming capability directly through natural language inside Claude Code, which is the focus of this post.

## Setting Up MCP in Claude Code

Having the AI draw diagrams for you while you're coding is the most valuable use case for Next AI Draw.io. Installation is a single command:

```bash
claude mcp add drawio -- npx @next-ai-drawio/mcp-server@latest
```

Restart Claude Code after running that and you're good to go. From there, describe the diagram you need in plain language — something like "Draw me a user authentication flow with login, MFA verification, and session management." Claude will call the drawio MCP server automatically, the browser opens the draw.io interface, and the diagram generates in real time. You can watch the AI build the diagram step by step. Once it's done, you can keep refining details through conversation.

## How It Works

The call chain has three layers. Claude Code communicates with the drawio MCP Server over the MCP protocol. The MCP Server starts a local HTTP service (default port 6002). When the browser opens the draw.io interface, the AI-generated XML gets pushed to the browser through that HTTP service for rendering. Data flows in one direction across the three layers: Claude Code sends instructions to the MCP Server, the MCP Server pushes diagram data to the browser, and the browser handles the final rendering.

If the default port 6002 is occupied, you can manually edit the MCP config file to specify a different port:

```json
{
  "mcpServers": {
    "drawio": {
      "command": "npx",
      "args": ["@next-ai-drawio/mcp-server@latest"],
      "env": {
        "PORT": "6003"
      }
    }
  }
}
```

The MCP server comes with five built-in tools: `start_session` opens the browser preview window, `create_new_diagram` creates a new diagram, `edit_diagram` edits an existing one, `get_diagram` fetches the current diagram's XML, and `export_diagram` exports to a .drawio file. In normal use you don't need to call these manually — Claude picks the right tool for the job based on your description.

## Supported Diagram Types

The tool covers the diagram types that come up most often in technical documentation. Flowcharts for describing business logic and processing steps. Architecture diagrams for showing system module relationships. Cloud architecture diagrams with automatic matching of official vendor icons. Sequence diagrams for interaction flows. Network topology diagrams for infrastructure layouts. UML class diagrams for object-oriented design.

On cloud service icon support, Claude-family models have been specifically trained on draw.io diagrams, so AWS, GCP, Azure, and Alibaba Cloud icon recognition and generation are particularly good. Adding "use AWS icons to draw a..." to your prompt triggers the matching icon set automatically.

## Model Selection

If you're self-hosting or using the online demo, you can choose different AI models to drive diagram generation. Claude Sonnet produces the best diagrams since it's been specifically trained on draw.io format — recommended as the first choice. GPT-4o and Gemini Pro also produce decent results and form the second tier. DeepSeek V3 is directly accessible from within China and offers good value, suitable for scenarios where diagram complexity isn't demanding.

## Practical Use Cases

When writing technical docs, you can have the AI generate a flowchart based on the current project's request handling chain — the full path from HTTP request through middleware, Controller, Service, Repository, to the database — and drop it straight into the document. During code review, have the AI read the code and auto-generate a data flow diagram, which is much faster than manually tracing call chains. In the system design phase, describe your requirements and constraints and let the AI produce a first draft of the architecture — something like "design a flash-sale system that handles high concurrency and inventory deduction" will get you both an architecture plan and the corresponding diagram. For requirements communication, a product manager describes the business flow in plain language and the AI produces the diagram immediately — aligning with diagrams is far more efficient than aligning with text.

## Comparison with the Traditional Approach

| Dimension | Traditional draw.io | Next AI Draw.io + MCP |
|------|-------------|----------------------|
| Learning curve | Need to learn the interface and operations | Natural language, zero learning curve |
| Diagramming speed | Minutes | Seconds |
| Modification cost | Manual drag-and-drop | Conversational editing |
| Professional icons | Manual search required | AI auto-matches cloud vendor icons |
| Integration with coding | Context-switching between tools | Direct invocation inside Claude Code |
| Export format | Manual export steps | Auto-generates .drawio files |

## Enterprise Intranet Deployment

When the enterprise intranet can't reach external services, deploy a private draw.io instance first, then point the MCP Server at it via environment variable. The deploy command is `docker run -d -p 8080:8080 jgraph/drawio`. Then add the `DRAWIO_BASE_URL` environment variable in your MCP config to point to the internal address:

```json
{
  "mcpServers": {
    "drawio": {
      "command": "npx",
      "args": ["@next-ai-drawio/mcp-server@latest"],
      "env": {
        "DRAWIO_BASE_URL": "http://your-internal-drawio:8080"
      }
    }
  }
}
```

## Troubleshooting

If the browser doesn't open automatically, check whether port 6002 is occupied by another process. You can also manually visit `http://localhost:6002` in the browser to confirm the service is running. Incomplete diagram generation is usually a model capability issue — switching to a stronger model like Claude Sonnet or GPT-4 will noticeably improve results. You can export diagrams directly in the draw.io interface, or tell Claude Code "export the current diagram as architecture.drawio" to do it through conversation.

## References

- [GitHub Repository](https://github.com/DayuanJiang/next-ai-draw-io)
- [Live Demo](https://next-ai-drawio.jiang.jp/)
- [MCP Server Docs](https://github.com/DayuanJiang/next-ai-draw-io/tree/main/packages/mcp-server)
- [Chinese Documentation](https://github.com/DayuanJiang/next-ai-draw-io/blob/main/docs/cn/README_CN.md)
