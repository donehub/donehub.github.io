---
title: 10+ 个开源 Agent 项目学习指南
date: 2025-03-13
tags: AI Agent
categories: AI
---

上一篇我们系统梳理了 Agent 编程的核心名词词典。有了概念基础，下一步就是动手看真实项目代码。

这篇文章推荐 10+ 个值得深入学习的开源 Agent 项目，涵盖单 Agent、多 Agent、Code Agent、生产级平台。每个项目都会告诉你：Star 数、学习价值、核心文件、适合什么阶段的人看。读完之后，你会有一条清晰的学习路线，知道从哪里开始、怎么深入、最终能做什么。

<!-- more -->

## 为什么必须看开源项目

很多新手的误区是：先背完所有概念、看完所有文档，再开始写代码。这条路径效率很低。更合理的做法是用 1-2 天过一遍核心概念，然后立刻切换到项目代码，边看边写，遇到不懂的概念再回头查。

不同学习方式的效果差异很大。只看文档，概念懂了但不知道怎么组合起来；只看教程，跟着抄代码但不理解设计意图；看真实项目，能看到完整系统架构、真实代码结构和实际问题的解决方案。

一个真实项目能教会你的东西包括：Agent 怎么定义（不是文档里的抽象概念，而是具体的类和函数）、工具怎么注册和调用（完整的 Function Calling 流程）、循环怎么实现（ReAct 循环的真实代码）、状态怎么管理（多轮对话、跨会话记忆）、错误怎么处理（真实场景的异常处理）、怎么部署到生产（架构设计、监控、日志）。

## 学习路线全景

整体学习路线分为五个阶段，由浅入深。入门阶段看 LangChain 官方示例、LangGraph 示例和 Anthropic Cookbook，目标是能用 LangGraph 写一个简单的 ReAct Agent。进阶阶段看 GPT-Researcher、AutoGPT 和 AgentGPT，目标是理解完整的任务规划、执行、反馈循环。Code Agent 专项看 OpenHands、SWE-agent 和 Continue，目标是理解 Agent 如何操作代码库。多 Agent 协作阶段看 CrewAI、AutoGen 和 MetaGPT，目标是能设计多 Agent 协作系统。生产级参考看 Dify 和 LangGraph Platform，目标是理解生产级架构、部署和监控。

| 阶段 | 项目 | 达标标志 |
|------|------|---------|
| 入门 | LangChain 示例、LangGraph 示例、Anthropic Cookbook | 能用 LangGraph 写 ReAct Agent |
| 进阶 | GPT-Researcher、AutoGPT、AgentGPT | 理解任务规划、执行、反馈循环 |
| Code Agent | OpenHands、SWE-agent、Continue | 理解 Agent 如何操作代码库 |
| 多 Agent | CrewAI、AutoGen、MetaGPT | 能设计多 Agent 协作系统 |
| 生产级 | Dify、LangGraph Platform | 理解生产级架构、部署、监控 |

## 入门级项目：理解基本原理

### LangChain 官方示例

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [langchain-ai/langchain](https://github.com/langchain-ai/langchain) |
| Star | 100k+ |
| 学习路径 | `/docs/docs/use_cases/` 和 `/cookbook/` |
| 学习价值 | ★★★★★ 官方最佳实践，覆盖所有核心场景 |

LangChain 虽然有"样板代码多"的缺点，但它的官方示例是最系统、最权威的入门材料。覆盖了 Agent、RAG、Tool Calling 的标准写法，每个示例 100-300 行，适合快速上手。

| 目录 | 学习重点 |
|------|---------|
| `/cookbook/` | 完整的小案例，从简单到复杂 |
| `/docs/docs/use_cases/agents/` | Agent 的各种实现模式 |
| `/docs/docs/use_cases/question_answering/` | RAG 的各种方案 |

学习方式：

```bash
# 克隆仓库
git clone https://github.com/langchain-ai/langchain.git

# 重点看这些文件
docs/docs/use_cases/agents/
├── agent_iterations.ipynb        # Agent 循环迭代
├── tools.ipynb                   # 工具定义和使用
├── custom_agent.ipynb            # 自定义 Agent
└── agent_reasoning.ipynb         # Agent 推理过程
```

入门目标：看完后能用 LangChain 写一个能调用工具的简单 Agent。

### LangGraph 示例

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [langchain-ai/langgraph](https://github.com/langchain-ai/langgraph) |
| Star | 30k+ |
| 学习路径 | `/examples/` 目录 |
| 学习价值 | ★★★★★ 学习 Agent 状态机、循环、分支的最佳资源 |

LangGraph 是 LangChain 团队推出的新一代 Agent 框架，用状态图（StateGraph）来定义 Agent 工作流。相比 LangChain 的链式调用，LangGraph 更适合复杂的循环和分支场景。它的核心概念可以用三个词概括：State（状态，在节点间传递的数据）、Node（节点，处理函数如 agent_node 和 tool_node）、Edge（边，流转条件如 should_continue）。工作流程是先定义 State 结构，再定义 Node 处理节点，然后定义 Edge 流转逻辑，最后调用 compile() 得到一个可执行的 Agent。

| 文件 | 学习重点 |
|------|---------|
| `react-agent.ipynb` | ReAct Agent 的完整实现 |
| `planner-agent.ipynb` | 有规划能力的 Agent |
| `multi-agent.ipynb` | 多 Agent 协作基础 |
| `memory.ipynb` | 记忆系统实现 |

核心代码结构：

```python
# LangGraph 的核心模式
from langgraph.graph import StateGraph, END

# 1. 定义状态
class AgentState(TypedDict):
    messages: list
    tool_calls: list

# 2. 定义节点
def agent_node(state: AgentState):
    # LLM 处理逻辑
    ...

def tool_node(state: AgentState):
    # 工具执行逻辑
    ...

# 3. 构建图
graph = StateGraph(AgentState)
graph.add_node("agent", agent_node)
graph.add_node("tools", tool_node)
graph.add_edge("agent", "tools")
graph.add_edge("tools", "agent")

# 4. 编译并运行
app = graph.compile()
result = app.invoke({"messages": ["帮我查北京天气"]})
```

入门目标：看完后能用 LangGraph 写一个 ReAct 循环 Agent。

### Anthropic Cookbook

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [anthropics/anthropic-cookbook](https://github.com/anthropics/anthropic-cookbook) |
| Star | 10k+ |
| 学习价值 | ★★★★★ Claude 官方最佳实践，代码质量极高 |

Anthropic 的 Cookbook 是代码质量最高的学习材料。每个示例都很简洁（100 行以内），注释清晰，直击核心。不像有些项目代码又长又乱，这里每个文件都是精品。

| 目录/文件 | 学习重点 |
|----------|---------|
| `tool_use/` | Function Calling 的最佳实践 |
| `prompt_caching/` | Prompt 缓存，降本 90% |
| `context_windows/` | 长上下文处理技巧 |
| `computer_use/` | Computer Use（操作电脑）能力 |

特色代码示例：

```python
# Anthropic 的 Tool Use 示例（极简风格）
import anthropic

client = anthropic.Client()

def get_weather(city: str):
    # 实际工具函数
    return f"{city}今天晴，25度"

# 定义工具
tools = [{
    "name": "get_weather",
    "description": "获取指定城市的天气",
    "input_schema": {
        "type": "object",
        "properties": {
            "city": {"type": "string"}
        },
        "required": ["city"]
    }
}]

# 调用 Claude
response = client.messages.create(
    model="claude-sonnet-4-6",
    tools=tools,
    messages=[{"role": "user", "content": "北京今天天气怎么样"}]
)

# Claude 会返回 tool_use，你再执行并返回结果
```

入门目标：理解 Function Calling 的完整流程，学会 Claude 的最佳实践。

## 进阶级项目：学习完整 Agent 系统

### GPT-Researcher

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [assafelovic/gpt-researcher](https://github.com/assafelovic/gpt-researcher) |
| Star | 15k+ |
| 学习价值 | ★★★★★ 学习 Agent 如何完成研究任务 |

这是一个完整的端到端 Agent 系统。你给它一个研究主题（如"AI Agent 的发展趋势"），它会自动完成搜索信息、分析多个来源、整合内容、生成研究报告的全流程。系统内部有多个专职 Agent 协作：Planner Agent 负责分解研究任务并生成搜索查询，Search Agent 负责并行执行多源搜索（Google、Tavily、新闻等），Scraper Agent 负责抓取网页内容并过滤无关信息，Writer Agent 负责整合所有信息并生成结构化研究报告。

| 文件路径 | 学习重点 |
|---------|---------|
| `gpt_researcher/master.py` | 主 Agent，任务编排 |
| `gpt_researcher/actions/` | 各个 Agent 的具体实现 |
| `gpt_researcher/memory/` | 记忆系统 |
| `gpt_researcher/tools/` | 搜索、抓取等工具 |

学习收获：理解 Agent 如何分解任务，理解多源信息检索和整合，理解并行执行和结果汇总，理解如何生成结构化输出。

### AutoGPT

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [Significant-Gravitas/AutoGPT](https://github.com/Significant-Gravitas/AutoGPT) |
| Star | 170k+ |
| 学习价值 | ★★★★☆ Agent 概念的开创者 |

AutoGPT 是 2023 年 Agent 概念爆发的起点。它首次展示了 LLM 可以自主规划、自主执行、自主反思。其核心创新是一个"思考-推理-计划-行动-观察"的循环：Agent 先产生一个 Thought（比如"我需要先了解一下 Python 爬虫的基础知识"），然后 Reasoning（"应该从基础教程开始"），接着生成 Plan（搜索教程、阅读教程、写代码），执行 Action（调用搜索工具），获取 Observation（搜索结果），然后进入下一轮循环。虽然现在看来架构有些老旧，但理解它能帮助你理解 Agent 的设计初衷。代码量较大（5000+ 行），建议只看核心架构部分，不必深究每个细节。

### AgentGPT

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [reworkd/AgentGPT](https://github.com/reworkd/AgentGPT) |
| Star | 32k+ |
| 学习价值 | ★★★★☆ 带前端界面的 Agent 部署平台 |

如果你想做一个完整的 Agent Web 应用，AgentGPT 是很好的参考。它包含 Next.js 前端（任务提交界面、执行进度展示、结果展示）和 FastAPI 后端（API 接口、Agent 执行引擎、数据库任务存储、SSE 实时推送）。这种前后端完整的架构对于理解 Agent 如何落地为产品很有帮助。

| 路径 | 学习重点 |
|------|---------|
| `frontend/` | Next.js + React，Agent UI 设计 |
| `backend/` | FastAPI，Agent API 设计 |
| `backend/agent/` | Agent 核心逻辑 |

## Code Agent 专项：后端工程师重点

这部分是后端工程师的重点学习内容。Code Agent 是目前最有价值的 Agent 方向之一，它让 Agent 直接操作代码库、执行命令、修复 Bug。

### OpenHands（原名 OpenDevin）

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [All-Hands-AI/OpenHands](https://github.com/All-Hands-AI/OpenHands) |
| Star | 40k+ |
| 学习价值 | ★★★★★ 最活跃的 Devin 开源实现 |

OpenHands 是目前最成熟的 Code Agent 开源项目。它能理解代码库结构、修改代码文件、执行命令行操作、运行测试、调试问题。架构上分为四层：Controller 负责任务编排和状态管理，Agent 负责 LLM 决策、规划和执行，Runtime 提供 Docker 容器执行环境（文件操作、命令执行、代码运行），Tools 层定义了文件读写、搜索、执行命令、运行测试等工具集。

| 路径 | 学习重点 |
|------|---------|
| `agenthub/` | Agent 定义，各种 Agent 类型 |
| `controller/` | 任务编排，状态管理 |
| `runtime/` | Docker 执行环境设计 |
| `tools/` | 工具集定义 |

关键技术点包括：用 Docker 容器执行代码实现环境隔离，让 Agent 安全地读写文件，让 Agent 执行 bash 命令并获取结果，暂停和恢复 Agent 任务。

```bash
# 克隆仓库
git clone https://github.com/All-Hands-AI/OpenHands.git

# 核心文件结构
openhands/
├── agenthub/
│   ├── codeact_agent/        # 核心 Agent 实现
│   │   └── codeact_agent.py  # 重点看这个
│   └── browsing_agent/       # 浏览器操作 Agent
│
├── controller/
│   └── state.py              # 状态管理
│   └── action_parser.py      # 动作解析
│
├── runtime/
│   ├── docker/               # Docker 执行环境
│   └── plugins/              # 运行时插件
│
└── tools/
    ├── execute_bash.py       # Bash 执行工具
    ├── file_ops.py           # 文件操作工具
    └── search.py             # 代码搜索工具
```

### SWE-agent

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [princeton-nlp/SWE-agent](https://github.com/princeton-nlp/SWE-agent) |
| Star | 15k+ |
| 学习价值 | ★★★★☆ 普林斯顿出品，专注代码修复 |

SWE-agent 是学术界的 Code Agent 实现，在 SWE-bench（代码修复基准测试）上表现优秀。它的核心能力是定位问题代码、理解 Bug 原因、生成修复补丁、验证修复效果。通过这个项目可以学到 Agent 如何理解代码库、问题定位的策略（搜索、分析、追踪），以及代码修复的完整流程。

### Continue

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [continuedev/continue](https://github.com/continuedev/continue) |
| Star | 20k+ |
| 学习价值 | ★★★★★ IDE 集成 Agent 的最佳参考 |

Continue 是一个开源的 IDE AI 插件，支持 VS Code 和 JetBrains。如果你想了解如何把 Agent 集成到开发工具中，这是最好的参考。架构上分为三层：IDE Extension 层提供用户界面（聊天、代码补全），Core Engine 层负责 Context 收集（当前文件、相关文件）、LLM 调用和 Code 处理，Features 层提供 Chat（对话）、Edit（代码编辑）、Autocomplete（补全）和 Commands（自定义命令）四个核心功能。

| 路径 | 学习重点 |
|------|---------|
| `extension/` | IDE 插件开发（VS Code） |
| `core/` | Agent 核心逻辑 |
| `core/context/` | 上下文收集策略 |

## 多 Agent 协作项目

### CrewAI

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [crewAIInc/crewAI](https://github.com/crewAIInc/crewAI) |
| Star | 25k+ |
| 学习价值 | ★★★★★ 多 Agent 角色扮演的最佳学习案例 |

CrewAI 是目前最简洁的多 Agent 框架。它的核心理念是把多个 Agent 定义为不同角色，让它们像团队一样协作。每个 Agent 通过 role、goal、backstory 三个属性定义身份，任务分配给具体 Agent 执行，协作模式支持 sequential（顺序执行）和 hierarchical（层级执行）。

```python
from crewai import Agent, Task, Crew

# 定义角色
researcher = Agent(
    role="研究员",
    goal="收集最新信息",
    backstory="你擅长搜索和整理资料",
)

writer = Agent(
    role="撰稿人",
    goal="撰写高质量文章",
    backstory="你擅长文字表达",
)

# 定义任务
research_task = Task(
    description="研究 AI Agent 的最新进展",
    agent=researcher,
)

write_task = Task(
    description="撰写一篇关于 AI Agent 的文章",
    agent=writer,
)

# 组建团队
crew = Crew(
    agents=[researcher, writer],
    tasks=[research_task, write_task],
    process=Process.sequential,  # 顺序执行
)

# 执行
crew.kickoff()
```

| 路径 | 学习重点 |
|------|---------|
| `crewai/agent.py` | Agent 类定义 |
| `crewai/task.py` | Task 类定义 |
| `crewai/crew.py` | Crew 类定义，协作编排 |
| `crewai/process/` | 协作流程实现 |

### AutoGen

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [microsoft/autogen](https://github.com/microsoft/autogen) |
| Star | 35k+ |
| 学习价值 | ★★★★★ 微软出品，多 Agent 对话框架 |

AutoGen 是微软的多 Agent 研究成果，特点是 Agent 间通过对话协作。不同于 CrewAI 的角色扮演，AutoGen 更侧重于 Agent 间的信息交换和讨论。它的核心模式是：User Proxy Agent 代表用户转发消息并执行代码，Assistant Agent 作为 LLM Agent 生成方案和代码建议。典型流程是用户提出需求，Assistant 给出方案，User Proxy 执行代码，遇到错误后 Assistant 修复并再次提交，循环直到成功。

| 路径 | 学习重点 |
|------|---------|
| `autogen/agent/contrib/` | 各种 Agent 类型 |
| `autogen/oai/` | LLM 调用封装 |
| `samples/` | 使用示例 |

### MetaGPT

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [geekan/MetaGPT](https://github.com/geekan/MetaGPT) |
| Star | 45k+ |
| 学习价值 | ★★★★★ 多 Agent 模拟软件开发团队 |

MetaGPT 是最有创意的多 Agent 项目之一。它把多个 Agent 定义为软件团队的各个角色：产品经理 Agent 分析需求并输出 PRD，架构师 Agent 设计系统架构并输出设计文档，项目经理 Agent 分配任务管理进度，工程师 Agent（多个）实现代码，QA Engineer Agent 编写测试验证代码。整个流程模拟了一个真实的软件开发团队从需求到交付的完整过程。

通过这个项目可以学到：如何让 Agent 输出结构化文档（PRD、设计文档），Agent 间如何传递文档和代码，如何让 Agent 执行完整的软件流程。

## 生产级平台参考

### Dify

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [langgenius/dify](https://github.com/langgenius/dify) |
| Star | 50k+ |
| 学习价值 | ★★★★★ 企业级 LLM 应用开发平台 |

Dify 是目前最完整的开源 LLM 应用平台，包含可视化工作流编辑器、Agent 编排、RAG 知识库管理、多租户多模型支持、完整的部署方案。前端用 React + Next.js 构建（工作流可视化编辑器和知识库管理界面），后端用 Python + Flask 驱动（工作流引擎、Agent 执行器、RAG 引擎、模型路由），基础设施层依赖 PostgreSQL（元数据）、Vector Store（向量存储）、Redis（缓存）和 Celery（异步任务）。

| 路径 | 学习重点 |
|------|---------|
| `api/core/workflow/` | 工作流引擎核心 |
| `api/core/agent/` | Agent 执行逻辑 |
| `api/core/rag/` | RAG 引擎 |
| `web/` | 前端工作流编辑器 |

学习收获：理解企业级架构设计、工作流引擎设计、多租户多模型支持、生产级部署方案。

### LangGraph Platform

| 项目信息 | 内容 |
|---------|------|
| 仓库 | [langchain-ai/langgraph](https://github.com/langchain-ai/langgraph) |
| 学习路径 | `/platform/` 目录 |
| 学习价值 | ★★★★★ Agent 生产部署最佳实践 |

LangGraph Platform 是 LangChain 团队推出的生产级 Agent 部署方案。它解决了 Agent 从 Demo 到生产的关键问题：持久化（任务状态保存）、恢复（暂停后继续）、监控（执行链路追踪）、API 设计（Agent 作为服务）。

| 能力 | 说明 |
|------|------|
| Persistence | Agent 状态持久化，支持暂停恢复 |
| Memory | 跨会话记忆管理 |
| Streaming | 实时推送执行进度 |
| API | REST API + WebSocket |

## 项目学习方法

看项目的正确姿势决定了学习效率。很多人从头到尾逐行看代码，效率很低。更好的方式是先看架构再看核心模块最后看细节。只看不跑也是常见问题，应该先跑起来再改代码看效果。看完就忘的话，需要记笔记、画架构图、写总结。只看一个项目就停止也不理想，多个项目对比才能找出共同模式。

推荐的学习步骤：第一步理解项目目标，读 README 和官方文档，明确项目解决什么问题；第二步跑起来，安装依赖运行最小示例，理解基本输入输出；第三步看架构，读项目目录结构，找核心入口文件，自己画架构图；第四步看核心模块，重点关注 Agent 定义文件、工具注册文件、循环实现文件、状态管理文件；第五步改代码，尝试添加新工具、修改 Agent 行为，观察变化。

不管什么项目，这几个核心模块一定要找到：

| 核心模块 | 关键文件特征 | 学习重点 |
|---------|-------------|---------|
| Agent 定义 | 通常有 `agent.py` 或 `agents/` 目录 | Agent 如何初始化、有什么属性、如何执行 |
| 工具注册 | `tools/` 或 `functions/` 目录 | 工具如何定义、如何注册给 Agent |
| 循环实现 | `main.py` 或 `run.py` 或 `execute()` | ReAct 循环怎么写、状态怎么传递 |
| 状态管理 | `state.py` 或 `memory/` 目录 | 状态如何保存、如何恢复 |
| LLM 调用 | `llm.py` 或 `model/` 目录 | 如何调用 LLM、如何处理响应 |

## Java 工程师的特别建议

作为 Java 后端工程师，你有独特的优势可以转化到 Agent 开发中。系统设计能力让你能关注架构设计而不只是代码细节，工程化经验让你能理解生产级项目（Dify、LangGraph Platform）的设计意图，调试能力让你能主动改代码、加日志、追踪执行过程。

推荐的 Java 工程师学习路径分四个阶段。第一阶段（1-2 周）进入 Python 生态入门，看 LangGraph 示例理解状态图模式，看 GPT-Researcher 理解完整流程，用 Python 写一个简单的 ReAct Agent。第二阶段（2-3 周）进入 Code Agent 专项，看 OpenHands 核心代码，理解文件操作和命令执行工具，思考如何用 Java 实现类似系统。第三阶段（2-3 周）进入 Java 生态融合，学习 LangChain4j 和 Spring AI，用 Java 重构你的 Python Agent Demo，集成到现有项目中。第四阶段（持续）进入生产级设计，研究 Dify 的架构，设计自己的 Agent 平台，考虑多租户、监控、部署、成本控制。

Java 生态框架选择：

| 框架 | 说明 | 学习优先级 |
|------|------|-----------|
| LangChain4j | LangChain 的 Java 版，成熟度高 | ★★★★★ |
| Spring AI | Spring 官方 AI 框架，生态整合好 | ★★★★★ |
| Semantic Kernel | 微软出品，支持 Java | ★★★★☆ |

## 学习路线时间规划

| 阶段 | 时间 | 目标 |
|------|------|------|
| 入门 | 1-2 周 | 理解 Agent 基本原理，能用 LangGraph 写简单 Agent |
| 进阶 | 2-3 周 | 理解完整 Agent 系统，能写出类似 GPT-Researcher 的项目 |
| Code Agent | 2-3 周 | 理解 Code Agent，能用 Java 实现文件操作、命令执行 |
| 多 Agent | 1-2 周 | 理解多 Agent 协作，能设计 Agent 团队 |
| 生产级 | 持续 | 理解生产架构，能部署和维护 Agent 服务 |

## 附录：项目速查表

| 项目 | Star | 学习价值 | 适合阶段 | 核心学习点 |
|------|------|---------|---------|-----------|
| LangChain 示例 | 100k+ | ★★★★★ | 入门 | 基础 Agent 写法 |
| LangGraph 示例 | 30k+ | ★★★★★ | 入门 | 状态图、循环、分支 |
| Anthropic Cookbook | 10k+ | ★★★★★ | 入门 | Function Calling 最佳实践 |
| GPT-Researcher | 15k+ | ★★★★★ | 进阶 | 完整 Agent 流程 |
| AutoGPT | 170k+ | ★★★★☆ | 进阶 | Agent 自主性 |
| AgentGPT | 32k+ | ★★★★☆ | 进阶 | Web 应用架构 |
| OpenHands | 40k+ | ★★★★★ | Code Agent | 代码库操作 |
| SWE-agent | 15k+ | ★★★★☆ | Code Agent | 代码修复 |
| Continue | 20k+ | ★★★★★ | Code Agent | IDE 集成 |
| CrewAI | 25k+ | ★★★★★ | 多 Agent | 角色扮演协作 |
| AutoGen | 35k+ | ★★★★★ | 多 Agent | 对话协作 |
| MetaGPT | 45k+ | ★★★★★ | 多 Agent | 模拟软件团队 |
| Dify | 50k+ | ★★★★★ | 生产级 | 企业级架构 |

> 上一篇：Agent 编程名词词典：产品视角与技术视角的双面解读
