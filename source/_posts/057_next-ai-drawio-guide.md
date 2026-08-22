---
title: Next Draw.IO：用自然语言画出专业图表
date: 2025-10-23
tags: MCP
categories: AI
---

写技术文档时需要一张系统架构图，传统做法是打开 draw.io，找图标、拖拽、连线、对齐，整套流程走下来至少 10 分钟。Next AI Draw.io 把这个过程压缩到一句话：用自然语言描述需求，AI 直接在浏览器里生成 draw.io 格式的专业图表。它支持 MCP 协议，可以在 Claude Code 中直接调用，写代码时顺手把图也画了。

<!-- more -->

## 工具定位

Next AI Draw.io 是一个开源项目，技术栈基于 Next.js 16 + React 19 + Vercel AI SDK + draw.io。它的核心能力可以分四个维度来看：自然语言画图，即描述需求后 AI 生成 draw.io 格式图表；云架构图标自动匹配，覆盖 AWS、GCP、Azure、阿里云四大云厂商；对话式编辑，生成后可以通过自然语言继续修改；MCP 集成，支持在 Claude Code、Cursor 等 AI 工具中直接调用。

项目开源在 GitHub（https://github.com/DayuanJiang/next-ai-draw-io），在线 Demo 地址是 https://next-ai-drawio.jiang.jp/。

## 四种使用方式

这个工具提供了从轻量到重度的四种接入方式。在线 Demo 适合临时用一下，打开浏览器就能画图，不需要安装任何东西。桌面应用适合日常高频画图，提供 Windows、macOS、Linux 三个平台的客户端。本地部署面向企业内网场景，Docker 一键启动即可。MCP 集成则是开发者最常用的方式，在 Claude Code 中直接通过自然语言调用画图能力，也是本文重点介绍的部分。

## Claude Code 中接入 MCP

在写代码的过程中让 AI 直接帮你画图，这是 Next AI Draw.io 最有价值的用法。安装过程只需要一条命令：

```bash
claude mcp add drawio -- npx @next-ai-drawio/mcp-server@latest
```

执行完毕后重启 Claude Code 即可生效。之后你可以直接用自然语言描述图表需求，比如"帮我画一个用户认证流程图，包含登录、MFA 验证、Session 管理"。Claude 会自动调用 drawio MCP 服务器，浏览器随之打开 draw.io 界面，图表实时生成，你能看到 AI 逐步构建图表的过程。生成完成后还能继续通过对话修改细节。

## 工作原理

整个调用链路分三层。Claude Code 通过 MCP 协议与 drawio MCP Server 通信，MCP Server 在本地启动一个 HTTP 服务（默认端口 6002），浏览器打开 draw.io 界面后，AI 生成的 XML 通过该 HTTP 服务推送到浏览器进行渲染。三层之间的数据流向是单向的：Claude Code 发指令给 MCP Server，MCP Server 把图表数据推给浏览器，浏览器负责最终的渲染呈现。

如果默认端口 6002 被占用，可以手动编辑 MCP 配置文件来指定其他端口：

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

MCP 服务器内置了五个工具：`start_session` 打开浏览器预览窗口，`create_new_diagram` 创建新图表，`edit_diagram` 编辑已有图表，`get_diagram` 获取当前图表的 XML，`export_diagram` 导出为 .drawio 文件。日常使用中不需要手动调用这些工具，Claude 会根据你的描述自动选择合适的工具来完成任务。

## 支持的图表类型

这个工具覆盖了技术文档中最常用的几类图表。流程图适合描述业务逻辑和处理步骤，架构图适合展示系统模块间关系，云架构图可以自动匹配各云厂商的官方图标，时序图用于描述交互流程，网络拓扑图用于展示基础设施布局，UML 类图用于面向对象设计。

云服务商图标支持方面，Claude 系列模型在 draw.io 图表上做过专项训练，对 AWS、GCP、Azure、阿里云的图标识别和生成效果尤其好。提示词中加上"用 AWS 图标画一个..."就能触发对应图标集的自动匹配。

## 模型选择

如果自己部署或使用在线 Demo，可以选择不同的 AI 模型来驱动图表生成。Claude Sonnet 的画图效果最好，因为它在 draw.io 图表上做过专项训练，推荐作为首选。GPT-4o 和 Gemini Pro 的效果也不错，属于第二梯队。DeepSeek V3 在国内可直接访问，性价比高，适合对图表复杂度要求不高的场景。

## 实际使用场景

在写技术文档时，可以让 AI 根据当前项目的请求处理链路生成流程图：从 HTTP 请求经过中间件层、Controller、Service、Repository 到数据库的完整路径，生成后直接插入文档。代码评审场景中，让 AI 读取代码后自动生成数据流向图，比手动梳理调用链效率高很多。系统设计阶段，描述清楚需求约束后让 AI 先出一版架构图草稿，比如"设计一个秒杀系统，要考虑高并发和库存扣减"，AI 会给出架构方案和对应的图表。需求沟通时，产品经理用自然语言描述业务流程，AI 直接出图，用图说话比用文字对齐效率高得多。

## 与传统方式对比

| 维度 | 传统 draw.io | Next AI Draw.io + MCP |
|------|-------------|----------------------|
| 学习成本 | 需要熟悉界面和操作 | 自然语言，零学习成本 |
| 作图速度 | 分钟级 | 秒级 |
| 修改成本 | 手动拖拽调整 | 对话式修改 |
| 专业图标 | 需要手动查找 | AI 自动匹配云厂商图标 |
| 与编程结合 | 需要切换工具 | Claude Code 中直接调用 |
| 导出格式 | 手动操作导出 | 自动生成 .drawio 文件 |

## 企业内网部署

企业内网环境无法访问外部服务时，可以先部署一个私有 draw.io 实例，再通过环境变量让 MCP Server 指向它。部署命令是 `docker run -d -p 8080:8080 jgraph/drawio`，然后在 MCP 配置中添加 `DRAWIO_BASE_URL` 环境变量指向内网地址：

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

## 常见问题排查

浏览器没有自动打开时，先检查端口 6002 是否被其他进程占用，也可以手动在浏览器访问 `http://localhost:6002` 来确认服务是否正常运行。图表生成不完整通常是模型能力问题，换用 Claude Sonnet 或 GPT-4 这类更强的模型会有明显改善。导出图表可以在 draw.io 界面直接操作，也可以在 Claude Code 中说"把当前图表导出为 architecture.drawio 文件"来完成。

## 参考资料

- [GitHub 仓库](https://github.com/DayuanJiang/next-ai-draw-io)
- [在线 Demo](https://next-ai-drawio.jiang.jp/)
- [MCP Server 文档](https://github.com/DayuanJiang/next-ai-draw-io/tree/main/packages/mcp-server)
- [中文文档](https://github.com/DayuanJiang/next-ai-draw-io/blob/main/docs/cn/README_CN.md)
