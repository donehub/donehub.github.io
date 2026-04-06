---
title: 如何使用 Agency-Agents 开好你的一人公司
date: 2025-12-01
tags: Multi Agent
categories: AI
---

> 如果你是一个人做项目，你不需要成为产品经理、架构师、营销专家——只需要知道何时调用哪个「虚拟专家」。Agency-Agents 这个开源项目，就是把 200 多个专业角色打包成了可以直接导入 Claude Code 的 Agent 文件。本文会介绍这个工具是什么、怎么用，以及如何用它协作开发一个完整项目。

<!-- more -->

## 一人公司的痛点

假设你是一个独立开发者，想做一个「数字游民社区」：

- **产品规划**：你不知道怎么定义用户画像、功能优先级
- **技术架构**：你不确定用什么技术栈、数据库怎么设计
- **营销推广**：你不懂小红书怎么运营、知乎怎么引流

传统解决方案：要么自己学（费时间），要么花钱找人（费钱），要么凭感觉做（可能做错）。

Agency-Agents 提供了第四种方案：**让 AI 以「专业角色」的身份帮你输出方案**。

---

## 一、Agency-Agents 是什么？

### 1.1 一句话定义

> **Agency-Agents 是一个包含 200+ 专业角色定义的开源仓库，每个角色都可以直接导入到 Claude Code、Cursor、Copilot 等工具中使用。**

它不是传统意义上的「软件框架」，而是 **精心设计的 Agent 提示词模板库**。

### 1.2 仓库结构

整个仓库有 **21 个分类目录**，**201 个 Agent 文件**：

| 分类 | Agent 数量 | 核心角色示例 |
|------|-----------|-------------|
| `engineering` | 27 | AI工程师、后端架构师、前端开发、安全工程师、DevOps |
| `marketing` | 29 | 小红书运营、抖音策略师、SEO专家、增长黑客、知乎运营 |
| `sales` | 8 | 销售教练、客户策略师、提案专家 |
| `product` | 5 | 产品经理、趋势研究员、反馈分析师 |
| `design` | 8 | UI设计师、UX架构师、品牌守护者 |
| `project-management` | 6 | 项目经理、工作室运营、实验追踪器 |
| `specialized` | 28 | 合规审计、招聘专家、区块链安全审计、供应链策略师 |

还有针对 **中国市场** 的本地化 Agent：

- 小红书运营专家 (`marketing-xiaohongshu-specialist.md`)
- 抖音短视频策略 (`marketing-douyin-strategist.md`)
- 微信公众号运营 (`marketing-wechat-official-account.md`)
- 知乎话题运营 (`marketing-zhihu-strategist.md`)
- 钉钉/飞书集成开发 (`engineering-feishu-integration-developer.md`)

### 1.3 每个 Agent 的设计结构

每个 Agent 文件都遵循统一的结构化模板：

```markdown
---
name: Product Manager
description: 产品负责人，负责完整的产品生命周期
color: blue
emoji: 🧭
vibe: 运送正确的东西，而不仅仅是下一个东西
---

# Product Manager Agent

## 🧠 身份与记忆
## 🎯 核心使命
## 🚨 关键规则
## 🛠️ 技术交付物
## 🔄 工作流程
## 💭 沟通风格
## 🎯 成功指标
```

这种设计让 Agent 具备：

- **明确的角色身份**：不是泛泛的「助手」，而是有专业背景的「专家」
- **工作方法论**：具体的流程步骤和技术栈清单
- **约束边界**：`Critical Rules` 定义了不可逾越的原则
- **可衡量的成功指标**：有明确的 KPI 期望

---

## 二、支持的工具生态

### 2.1 可导入的工具列表

Agency-Agents 的安装脚本支持 **11 种 AI 编程工具**：

| 工具 | 安装位置 | 特点 |
|------|----------|------|
| **Claude Code** | `~/.claude/agents/` | 原生支持，直接可用 |
| **GitHub Copilot** | `~/.github/agents/` | VS Code / JetBrains 集成 |
| **Cursor** | `.cursor/rules/` | 项目级规则文件 |
| **Gemini CLI** | `~/.gemini/extensions/` | 扩展形式 |
| **Windsurf** | `.windsurfrules` | Codeium 规则系统 |
| **Qwen Code** | `.qwen/agents/` | 通义千问项目级 Agent |
| **Aider** | `CONVENTIONS.md` | 终端 AI 编程助手 |
| **OpenCode** | `.opencode/agents/` | 项目级配置 |
| **OpenClaw** | `~/.openclaw/` | 工作空间模式 |
| **Kimi Code** | `~/.config/kimi/agents/` | 月之暗面 Agent |
| **Antigravity** | `~/.gemini/antigravity/` | Gemini 技能系统 |

### 2.2 安装方法

```bash
# 克隆仓库
git clone https://github.com/msitarzewski/agency-agents.git
cd agency-agents

# 先转换（生成各工具格式的文件）
./scripts/convert.sh

# 安装到指定工具
./scripts/install.sh --tool claude-code

# 或交互式选择
./scripts/install.sh --interactive
```

安装后，Agent 文件会出现在对应目录，你就可以在工具中调用了。

---

## 三、在 Claude Code 中如何使用？

### 3.1 调用方式

安装完成后，在 Claude Code 中有三种调用方式：

**方式一：直接调用特定 Agent**

```
/agent product-manager
```

然后提出你的需求：

```
我想做一个数字游民社区，帮我做产品规划
```

**方式二：自然语言描述**

```
帮我做数字游民社区的产品规划
```

Claude Code 会自动判断你需要产品经理角色，并输出专业方案。

**方式三：组合多个 Agent**

```
需要产品经理和后端架构师一起帮我规划数字游民社区
```

Claude Code 会先用产品经理角色输出产品规划，再用架构师角色输出技术方案。

### 3.2 实际输出示例

当你调用 **产品经理 Agent** 后，它会输出类似这样的内容：

```markdown
# PRD: 数字游民社区

## 1. 问题陈述

**核心痛点**：
- 数字游民缺乏归属感，在不同城市难以找到同类人群
- 缺乏可靠的工作空间信息（咖啡馆、共享办公、网络质量）

**目标用户画像**：
| 类型 | 特征 | 核心需求 |
|------|------|----------|
| 自由职业者 | 设计师、程序员 | 找客户、找工位、找圈子 |
| 远程员工 | 大厂远程岗员工 | 找办公环境、社群连接 |

## 2. MVP 功能清单

| 功能 | 用户价值 | 优先级 |
|------|----------|--------|
| 用户注册/登录 | 身份建立 | P0 |
| 城市指南 | 找办公地点 | P0 |
| 社区帖子 | 交流分享 | P0 |
| 工作机会发布 | 找远程工作 | P1 |

## 3. 成功指标

| 指标 | 目标 | 测量周期 |
|------|------|----------|
| 注册用户 | 1000人 | 上线30天 |
| DAU | 100人 | 上线30天 |
```

这不是泛泛的「建议」，而是 **结构化的专业文档**，可以直接作为项目规划使用。

---

## 四、协作开发实战：数字游民社区

下面用一个完整案例，展示 Agency-Agents + Claude Code 如何协作开发。

### 4.1 协作架构

```
┌────────────────────────────────────────────────┐
│           你（决策者）                           │
│         定义目标、审核方案、做决策               │
└──────────────────────┬─────────────────────────┘
                       │
                       ▼
┌────────────────────────────────────────────────┐
│           Claude Code（执行引擎）               │
│     读文件、写代码、跑命令、调 Agent             │
└──────────────────────┬─────────────────────────┘
                       │
       ┌───────────────┼───────────────┬─────────┐
       ▼               ▼               ▼         ▼
┌──────────┐    ┌──────────┐    ┌──────────┐ ┌──────────┐
│产品经理   │    │后端架构师│    │前端开发   │ │营销策略师│
│Agent     │    │Agent    │    │Agent    │ │Agent    │
└──────────┘    └──────────┘    └──────────┘ └──────────┘
     │               │               │           │
     ▼               ▼               ▼           ▼
  PRD文档         API设计         UI组件      营销方案
  功能规划        数据库结构       页面实现    内容策略
```

### 4.2 阶段一：产品规划（第1周）

**你的输入：**

```
/agent product-manager

我想做一个数字游民社区，帮我做产品规划
```

**Claude Code 输出（基于产品经理 Agent）：**

- 用户画像分析
- MVP 功能清单（用户认证、城市指南、社区帖子）
- 功能优先级排序
- 成功指标定义

**你的决策：**

> 「这个规划合理，先做 MVP，包含用户认证、城市指南、社区帖子三个模块。」

### 4.3 阶段二：技术架构（第2周）

**你的输入：**

```
/agent engineering-backend-architect

基于产品经理的规划，设计技术架构和数据库结构
技术栈选择 React + Node.js + PostgreSQL
```

**Claude Code 输出（基于架构师 Agent）：**

数据库设计：

```sql
-- 用户表
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    username VARCHAR(50) UNIQUE NOT NULL,
    avatar_url VARCHAR(500),
    location VARCHAR(100),  -- 当前城市
    created_at TIMESTAMP DEFAULT NOW()
);

-- 城市指南表
CREATE TABLE city_guides (
    id UUID PRIMARY KEY,
    city_name VARCHAR(100) NOT NULL,
    country VARCHAR(100) NOT NULL,
    internet_speed VARCHAR(50),
    cost_of_living VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
);

-- 社区帖子表
CREATE TABLE posts (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    title VARCHAR(200) NOT NULL,
    content TEXT NOT NULL,
    category VARCHAR(50),
    created_at TIMESTAMP DEFAULT NOW()
);
```

API 接口设计：

```
POST   /api/auth/register    - 用户注册
POST   /api/auth/login       - 用户登录
GET    /api/cities           - 获取城市列表
GET    /api/cities/:id       - 获取城市详情
GET    /api/posts            - 获取帖子列表
POST   /api/posts            - 发布帖子
```

### 4.4 阶段三：前端开发（第3-4周）

**你的输入：**

```
/agent engineering-frontend-developer

基于架构师的API设计，帮我搭建前端项目框架
实现用户登录注册页面和城市指南列表页
```

**Claude Code 实际执行：**

```bash
# 创建项目
npm create vite@latest nomad-community-web -- --template react-ts
cd nomad-community-web
npm install tailwindcss react-router-dom axios lucide-react
```

**Claude Code 创建的文件：**

```
src/
├── components/
│   ├── auth/LoginForm.tsx
│   ├── auth/RegisterForm.tsx
│   └── common/Button.tsx
├── pages/
│   ├── LoginPage.tsx
│   ├── HomePage.tsx
│   └── CityGuidePage.tsx
├── api/
│   ├── auth.ts
│   ├── cities.ts
│   └── posts.ts
└── hooks/
    └── useAuth.ts
```

### 4.5 阶段四：营销策略（第6周）

**你的输入：**

```
/agent marketing-social-media-strategist

产品即将上线，帮我制定数字游民社区的营销策略
重点关注小红书和知乎
```

**Claude Code 输出（基于营销策略 Agent）：**

```markdown
# 数字游民社区营销策略

## 1. 目标用户触达渠道

| 渠道 | 用户特征 | 内容方向 |
|------|----------|----------|
| 小红书 | 年轻女性多 | 城市探店、办公空间打卡 |
| 知乎 | 高知人群 | 数字游民攻略、城市对比 |
| 抖音 | 流量大 | 办公日常、城市vlog |

## 2. 小红书内容矩阵

- 「数字游民在XX城市」系列 - 办公咖啡馆探店
- 「远程工作神器」系列 - 工具推荐
- 「自由职业入坑指南」系列 - 转型经验分享

## 3. 种子用户获取

- 搜索关键词用户主动触达
- 加入相关微信群、知乎话题
- 预期效果：第一月 300 个活跃用户
```

---

## 五、传统方式 vs Agent 协作

### 5.1 效率对比

| 维度 | 传统方式 | Agent 协作方式 |
|------|----------|----------------|
| 产品规划 | 搜索资料+凭感觉 | PM Agent 专业输出 |
| 技术架构 | 看教程+试错 | 架构师 Agent 最佳实践 |
| 前端实现 | 边学边写 | 前端 Agent + Claude Code 自动生成 |
| 营销策略 | 猜测渠道 | 营销 Agent 专业策略 |
| **总耗时** | 估计 16-20 周 | 估计 8-12 周 |

### 5.2 核心价值

Agency-Agents 解决了三个核心问题：

**1. 人力不足 → Agent 填补专业能力**

你不需要懂营销，营销 Agent 给你专业策略；你不需要懂安全，安全 Agent 给你审计清单。

**2. 知识盲区 → Agent 提供最佳实践**

每个 Agent 的输出都是基于该领域的最佳实践，不是凭感觉。

**3. 执行效率 → Claude Code 自动化执行**

Agent 输出方案后，Claude Code 直接生成代码、创建文件、运行命令。

---

## 六、使用建议

### 6.1 按阶段调用 Agent

不要一次性调用所有 Agent，而是按开发阶段逐步调用：

```
规划阶段 → 产品经理 Agent
设计阶段 → 架构师 Agent + UI设计 Agent
开发阶段 → 前端/后端 Agent
上线阶段 → 营销 Agent + 安全审计 Agent
```

### 6.2 Agent 是顾问，不是决策者

Agent 给的是「专业建议」，不是「最终答案」：

- 你需要判断方案是否符合你的实际情况
- 你需要做最终决策
- Agent 不知道你的预算、时间、技术能力等限制

### 6.3 保持上下文一致性

告诉 Claude Code 之前的决策：

```
我们之前决定用 React + Node.js 技术栈，
现在继续基于这个方案设计前端
```

### 6.4 迭代优化

不要期望一次就完美：

```
这个数据库设计太简单了，帮我补充更多字段

这个营销策略太泛了，给我具体的小红书发布计划
```

---

## 七、总结

Agency-Agents + Claude Code 的协作本质是：

> **你拥有了一个「虚拟专业团队」，每个 Agent 代表一个专业角色。你不需要成为每个领域的专家，只需要知道何时调用哪个专家。**

对于一人公司来说，这解决了最核心的痛点：

- **人力不足**：Agent 填补专业能力
- **知识盲区**：Agent 提供最佳实践
- **执行效率**：Claude Code 自动化执行

你的角色从「一个人做所有事」变成了「一个项目经理指挥团队」。

---

## 参考资料

- [Agency-Agents GitHub Repository](https://github.com/msitarzewski/agency-agents)
- [Agency-Agents 中文贡献指南](https://github.com/msitarzewski/agency-agents/blob/main/CONTRIBUTING_zh-CN.md)