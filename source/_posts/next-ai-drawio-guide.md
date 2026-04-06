---
title: Next Draw.IO：用自然语言画出专业图表
date: 2025-10-23
tags: MCP
categories: AI
---

> 画架构图、流程图、时序图，传统方式是打开 draw.io 手动拖拽。Next AI Draw.io 提供了另一种方式：你用自然语言描述，AI 帮你画。更棒的是，它支持 MCP 协议，可以在 Claude Code 中直接调用——写代码时让 AI 顺手把图也画了。

<!-- more -->

## 为什么要用这个工具？

假设你在写技术文档，需要一张系统架构图：

**传统方式**：
1. 打开 draw.io 或 ProcessOn
2. 找到合适的图标
3. 拖拽、连线、对齐
4. 反复调整样式
5. 导出、插入文档

整个过程至少 10 分钟。

**AI 方式**：
```
帮我画一个微服务架构图：用户通过 API 网关访问订单服务和用户服务，
两个服务都连接到 Redis 缓存和 MySQL 数据库
```

几秒钟后，一张专业的架构图就出现在你眼前。

---

## 这是什么工具？

**Next AI Draw.io** 是一个开源的 AI 画图工具，核心能力：

| 能力 | 说明 |
|------|------|
| **自然语言画图** | 描述需求，AI 生成 draw.io 格式的图表 |
| **云架构图标** | 自动匹配 AWS、GCP、Azure、阿里云图标 |
| **图表编辑** | 对话式修改已生成的图表 |
| **MCP 集成** | 在 Claude Code、Cursor 等 AI 工具中直接调用 |

**技术栈**：Next.js 16 + React 19 + Vercel AI SDK + draw.io

**开源地址**：https://github.com/DayuanJiang/next-ai-draw-io

---

## 几种使用方式

| 方式 | 适合人群 | 特点 |
|------|----------|------|
| **在线 Demo** | 临时用一下 | 无需安装，浏览器直接访问 |
| **桌面应用** | 日常画图 | Windows/macOS/Linux 客户端 |
| **本地部署** | 企业内网 | Docker 一键启动 |
| **Claude Code MCP** | 开发者 | 编程时直接画图，**重点介绍** |

在线地址：https://next-ai-drawio.jiang.jp/

下面重点介绍 Claude Code MCP 的使用方式。

---

## 在 Claude Code 中使用 MCP

这是这个工具最强大的用法：**在写代码时，让 AI 直接帮你画图**。

### 安装 MCP 服务器

在 Claude Code 中执行一条命令：

```bash
claude mcp add drawio -- npx @next-ai-drawio/mcp-server@latest
```

安装完成后，重启 Claude Code。

### 使用方式

安装后，你可以直接用自然语言让 Claude 画图：

```
帮我画一个用户认证流程图，包含登录、MFA验证、Session管理
```

Claude 会自动调用 drawio MCP 服务器，然后：

1. **浏览器自动打开** draw.io 界面
2. **图表实时生成**，你可以看到 AI 正在"画"的过程
3. **生成完成后**，可以继续对话修改

### 工作原理

```
┌─────────────────┐     MCP协议      ┌─────────────────┐
│   Claude Code   │ <─────────────> │   MCP Server    │
│    (AI 助手)    │                 │  (drawio包)      │
└─────────────────┘                 └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │  本地 HTTP 服务  │
                                    │   (端口 6002)    │
                                    └────────┬────────┘
                                             │
                                    ┌────────▼────────┐
                                    │   你的浏览器     │
                                    │  (draw.io 界面) │
                                    └─────────────────┘
```

**流程说明**：

1. Claude Code 通过 MCP 协议调用 drawio 服务器
2. drawio 服务器启动本地 HTTP 服务（默认端口 6002）
3. 浏览器打开 draw.io 界面，实时显示图表
4. AI 生成的 XML 通过 HTTP 服务推送到浏览器渲染

### 实际演示

**场景一：画系统架构图**

```
画一个电商系统架构图：
用户 → CDN → 负载均衡 → API网关
         ↓
    订单服务 ←→ 库存服务
         ↓           ↓
      MySQL       Redis
```

Claude 会生成一张带有专业图标的架构图，可以直接导出使用。

**场景二：画流程图**

```
画一个订单处理流程图：
用户下单 → 库存检查 → 支付处理 → 订单创建 → 通知用户
如果库存不足，返回错误
如果支付失败，回滚库存
```

**场景三：修改已有图表**

```
把刚才的架构图加上消息队列，订单服务和库存服务之间用 RabbitMQ 通信
```

### 可用的 MCP 工具

MCP 服务器提供了以下工具：

| 工具 | 功能 |
|------|------|
| `start_session` | 打开浏览器预览窗口 |
| `create_new_diagram` | 创建新图表 |
| `edit_diagram` | 编辑已有图表 |
| `get_diagram` | 获取当前图表的 XML |
| `export_diagram` | 导出为 .drawio 文件 |

日常使用中，你不需要手动调用这些工具，Claude 会自动选择合适的工具。

### 配置选项

如果默认端口 6002 被占用，可以指定其他端口：

```bash
claude mcp add drawio -- npx @next-ai-drawio/mcp-server@latest
```

或者手动编辑 MCP 配置：

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

### 企业内网部署

如果需要在企业内网使用，可以：

1. **部署私有 draw.io 实例**：

```bash
docker run -d -p 8080:8080 jgraph/drawio
```

2. **配置 MCP 使用私有地址**：

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

---

## 支持的图表类型

| 类型 | 示例提示词 |
|------|-----------|
| **流程图** | "画一个用户注册流程图" |
| **架构图** | "画一个微服务架构图，包含 API 网关、服务注册中心" |
| **云架构图** | "用 AWS 图标画一个高可用架构图" |
| **时序图** | "画一个 OAuth2.0 授权流程时序图" |
| **网络拓扑** | "画一个企业网络拓扑图" |
| **UML 类图** | "画一个用户管理模块的类图" |

### 云服务商图标支持

Claude 系列模型在 draw.io 图表上训练过，特别擅长画云架构图：

| 云服务商 | 提示词示例 |
|----------|-----------|
| AWS | "用 **AWS 图标**画一个..." |
| GCP | "用 **GCP 图标**画一个..." |
| Azure | "用 **Azure 图标**画一个..." |
| 阿里云 | "用 **阿里云图标**画一个..." |

---

## 支持的 AI 模型

如果你自己部署，可以选择不同的 AI 模型：

| 模型 | 画图效果 | 说明 |
|------|----------|------|
| **Claude Sonnet** | ⭐⭐⭐⭐⭐ | 推荐，对 draw.io 训练最好 |
| GPT-4o | ⭐⭐⭐⭐ | 效果不错 |
| Gemini Pro | ⭐⭐⭐⭐ | 效果不错 |
| DeepSeek V3 | ⭐⭐⭐ | 国内可用，性价比高 |

**推荐使用 Claude 系列模型**，因为它在 draw.io 图表上做过专项训练，生成效果最好。

---

## 实际使用场景

### 写技术文档

```
帮我画一个当前项目的请求处理流程图：
HTTP请求 → 中间件层 → Controller → Service → Repository → 数据库
```

生成后直接插入文档，省去手动画图的时间。

### 代码评审

```
分析这段代码，画一个数据流向图
```

Claude 会读取代码，自动生成数据流程图。

### 系统设计

```
我要设计一个秒杀系统，帮我画出架构图，要考虑高并发和库存扣减
```

AI 会给出专业的架构方案，并生成对应的架构图。

### 需求沟通

产品经理描述需求时，直接让 AI 画图：

```
画一个用户下单的业务流程图，包含正常流程和异常处理
```

用图说话，减少理解偏差。

---

## 对比传统方式

| 维度 | 传统 draw.io | Next AI Draw.io + MCP |
|------|-------------|----------------------|
| 学习成本 | 需要熟悉操作 | 自然语言，零学习 |
| 作图速度 | 分钟级 | 秒级 |
| 修改成本 | 手动调整 | 对话修改 |
| 专业图标 | 需要手动找 | AI 自动匹配 |
| 与编程结合 | 需要切换工具 | Claude Code 中直接用 |
| 导出格式 | 手动导出 | 自动生成 .drawio 文件 |

---

## 常见问题

### 浏览器没有自动打开？

检查端口是否被占用，或者手动打开 `http://localhost:6002`。

### 图表生成不完整？

可能是模型能力问题，建议使用 Claude Sonnet 或 GPT-4 等强模型。

### 如何导出图表？

生成后可以在 draw.io 界面直接导出，或者在 Claude Code 中说：

```
把当前图表导出为 architecture.drawio 文件
```

---

## 总结

**Next AI Draw.io 解决的核心问题**：

> **把"画图"从技术活变成"说话"的事。**

**对开发者的价值**：

1. **写代码时顺手画图**：在 Claude Code 中直接调用，不用切换工具
2. **快速迭代设计**：对话式修改，比手动拖拽快 10 倍
3. **专业图标自动匹配**：不用到处找 AWS/GCP 图标
4. **代码与图同步**：让 AI 根据代码生成图，保持一致性
---

## 参考资料

- [GitHub 仓库](https://github.com/DayuanJiang/next-ai-draw-io)
- [在线 Demo](https://next-ai-drawio.jiang.jp/)
- [MCP Server 文档](https://github.com/DayuanJiang/next-ai-draw-io/tree/main/packages/mcp-server)
- [中文文档](https://github.com/DayuanJiang/next-ai-draw-io/blob/main/docs/cn/README_CN.md)