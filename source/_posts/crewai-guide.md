---
title: CrewAI 入门实战：从零构建多 Agent 协作系统
date: 2026-02-10
tags: AI 工具
categories: AI
---

---

## 一、CrewAI 是什么？

### 官方定义

CrewAI 是一个**精简、快速的 Python 框架**，用于编排自主 AI 代理（Agent）。它让多个 AI Agent 可以协同工作，像一个团队一样完成复杂任务。

### 核心特点

| 特点 | 说明 |
|-----|------|
| **独立框架** | 不依赖 LangChain 或其他框架，从零构建 |
| **高性能** | 比 LangGraph 快 5 倍以上 |
| **灵活定制** | 从高层工作流到底层提示词都可定制 |
| **两种模式** | Crews（自主协作）+ Flows（精确控制） |

### 与其他框架对比

| 框架 | 优点 | 缺点 |
|-----|------|------|
| **CrewAI** | 简洁、快速、独立 | 社区相对较新 |
| **LangGraph** | 功能强大 | 样板代码多、与 LangChain 强耦合 |
| **Autogen** | 对话代理能力强 | 缺乏流程概念 |
| **ChatDev** | 有流程概念 | 定制能力有限 |

### 适用场景

- 自动化工作流（报告生成、数据分析）
- 多角色协作系统（一人公司、虚拟团队）
- 复杂任务分解与执行
- AI 驱动的应用开发

---

## 二、核心概念

### 2.1 Agent（代理）

Agent 是 CrewAI 的核心单元，代表一个"角色"。

```python
from crewai import Agent

agent = Agent(
    role="高级数据分析师",           # 角色
    goal="分析数据并提供洞察",        # 目标
    backstory="你是一位资深分析师...", # 背景故事
    verbose=True,                    # 详细输出
    allow_delegation=True,           # 是否可以委派任务
    tools=[],                        # 可用工具
    llm=...,                        # 使用的大模型
)
```

**关键参数**：
- `role`：角色名称，定义 Agent 的身份
- `goal`：目标，定义 Agent 想要达成什么
- `backstory`：背景故事，决定 Agent 的性格和行为方式
- `tools`：Agent 可以使用的工具列表
- `llm`：Agent 使用的大模型

### 2.2 Task（任务）

Task 定义 Agent 需要完成的具体工作。

```python
from crewai import Task

task = Task(
    description="分析销售数据，找出增长趋势",
    expected_output="包含 5 个关键发现的报告",
    agent=agent,              # 执行任务的 Agent
    output_file="report.md",  # 输出文件
)
```

### 2.3 Crew（团队）

Crew 是 Agent 的集合，定义它们如何协作。

```python
from crewai import Crew, Process

crew = Crew(
    agents=[agent1, agent2, agent3],
    tasks=[task1, task2, task3],
    process=Process.sequential,  # 或 Process.hierarchical
    verbose=True,
)
```

**协作模式**：

| 模式 | 说明 | 适用场景 |
|-----|------|---------|
| `Process.sequential` | 顺序执行，一个任务完成后执行下一个 | 流程明确的任务 |
| `Process.hierarchical` | 层级模式，自动分配 Manager Agent 协调 | 需要动态决策的任务 |

### 2.4 Tools（工具）

Tools 扩展 Agent 的能力，让它可以搜索、读写文件、调用 API 等。

```python
from crewai_tools import SerperDevTool, FileReadTool

search_tool = SerperDevTool()      # 搜索工具
file_tool = FileReadTool()         # 文件读取工具

agent = Agent(
    role="研究员",
    tools=[search_tool, file_tool],
    ...
)
```

### 2.5 整体工作流程

```
┌─────────────────────────────────────────────────────────────┐
│                         Crew                                │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                    │
│  │ Agent 1 │  │ Agent 2 │  │ Agent 3 │                    │
│  │ (分析师) │  │ (研究员) │  │ (撰稿人) │                    │
│  └────┬────┘  └────┬────┘  └────┬────┘                    │
│       │            │            │                          │
│       ▼            ▼            ▼                          │
│  ┌─────────┐  ┌─────────┐  ┌─────────┐                    │
│  │  Task 1 │  │  Task 2 │  │  Task 3 │                    │
│  │ 分析数据 │→│ 研究背景 │→│ 撰写报告 │                    │
│  └─────────┘  └─────────┘  └─────────┘                    │
└─────────────────────────────────────────────────────────────┘
```

---

## 三、安装与环境配置

### 3.1 环境要求

- Python 3.10 - 3.13
- 推荐使用 `uv` 作为包管理器

### 3.2 安装 CrewAI

**方式一：使用 pip**

```bash
# 基础安装
pip install crewai

# 安装额外工具
pip install 'crewai[tools]'
```

**方式二：使用 uv（推荐）**

```bash
# 安装 uv
pip install uv

# 安装 CrewAI
uv pip install crewai
uv pip install 'crewai[tools]'
```

### 3.3 创建项目

```bash
# 创建新项目
crewai create crew my_project

# 项目结构
my_project/
├── .env                    # 环境变量
├── pyproject.toml          # 项目配置
└── src/my_project/
    ├── main.py             # 入口文件
    ├── crew.py             # Crew 定义
    ├── tools/              # 自定义工具
    └── config/
        ├── agents.yaml     # Agent 配置
        └── tasks.yaml      # Task 配置
```

### 3.4 常见安装问题

**问题 1：ModuleNotFoundError: tiktoken**

```bash
uv pip install 'crewai[embeddings]'
```

**问题 2：Windows 上 Rust 编译错误**

```bash
# 安装 Visual C++ Build Tools
# 或使用预编译包
uv pip install tiktoken --prefer-binary
```

---

## 四、大模型服务接入（重点）

这是大多数新手卡住的地方。**CrewAI 默认使用 OpenAI，但你必须配置正确的 base_url 才能连接到你的大模型服务。**

### 4.1 核心概念

**为什么需要 base_url？**

```
┌─────────────┐         ┌─────────────────────┐
│  CrewAI     │  ────→  │  LLM 服务端点        │
│  (你的代码)  │   HTTP  │  (base_url)         │
└─────────────┘         └─────────────────────┘
```

- 默认情况下，CrewAI 会连接 `https://api.openai.com/v1`
- 如果你用的是其他服务（阿里百炼、DeepSeek 等），**必须指定 base_url**
- 否则会报错：`Connection refused` 或 `Invalid API key`

### 4.2 OpenAI 官方

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="gpt-4o",
    api_key="sk-xxxxx",
    # base_url 默认是 https://api.openai.com/v1，可以不填
)
```

**环境变量方式**：

```env
OPENAI_API_KEY=sk-xxxxx
```

### 4.3 Anthropic Claude

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="claude-sonnet-4-6",
    api_key="sk-ant-xxxxx",
)
```

**环境变量方式**：

```env
ANTHROPIC_API_KEY=sk-ant-xxxxx
```

### 4.4 阿里百炼 Coding Plan（推荐）

阿里百炼 Coding Plan 提供两种兼容协议：

| 协议 | Base URL | 说明 |
|-----|---------|------|
| **OpenAI 兼容** | `https://coding.dashscope.aliyuncs.com/v1` | 使用 langchain-openai |
| **Anthropic 兼容** | `https://coding.dashscope.aliyuncs.com/apps/anthropic` | 使用 langchain-anthropic |

**使用 OpenAI 兼容协议**：

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="qwen-max",           # 通义千问模型
    api_key="your_dashscope_key",
    base_url="https://coding.dashscope.aliyuncs.com/v1",  # 关键！
)
```

**使用 Anthropic 兼容协议**：

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="qwen-max",
    api_key="your_dashscope_key",
    base_url="https://coding.dashscope.aliyuncs.com/apps/anthropic",  # 关键！
)
```

**环境变量方式**：

```env
DASHSCOPE_API_KEY=your_dashscope_key
DASHSCOPE_BASE_URL=https://coding.dashscope.aliyuncs.com/v1
```

### 4.5 DeepSeek

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="deepseek-chat",
    api_key="your_deepseek_key",
    base_url="https://api.deepseek.com/v1",  # 关键！
)
```

### 4.6 智谱 AI (GLM)

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="glm-4",
    api_key="your_zhipu_key",
    base_url="https://open.bigmodel.cn/api/paas/v4/",  # 关键！
)
```

### 4.7 本地模型 (Ollama)

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="llama3",
    api_key="ollama",  # 任意值
    base_url="http://localhost:11434/v1",  # Ollama 默认端口
)
```

### 4.8 统一配置方案

在实际项目中，推荐使用配置文件统一管理：

```python
# config/llm_config.py

import os
from langchain_openai import ChatOpenAI

def get_llm(provider: str = "dashscope"):
    """统一获取 LLM"""

    configs = {
        "openai": {
            "model": "gpt-4o",
            "api_key": os.getenv("OPENAI_API_KEY"),
            "base_url": None,
        },
        "dashscope": {
            "model": "qwen-max",
            "api_key": os.getenv("DASHSCOPE_API_KEY"),
            "base_url": "https://coding.dashscope.aliyuncs.com/v1",
        },
        "deepseek": {
            "model": "deepseek-chat",
            "api_key": os.getenv("DEEPSEEK_API_KEY"),
            "base_url": "https://api.deepseek.com/v1",
        },
    }

    config = configs.get(provider)
    if not config or not config["api_key"]:
        raise ValueError(f"请配置 {provider} 的 API Key")

    return ChatOpenAI(
        model=config["model"],
        api_key=config["api_key"],
        base_url=config["base_url"],
    )
```

**使用**：

```python
# 默认使用阿里百炼
llm = get_llm()

# 切换到 OpenAI
llm = get_llm("openai")
```

### 4.9 Agent 中使用 LLM

```python
from crewai import Agent
from config.llm_config import get_llm

agent = Agent(
    role="分析师",
    goal="分析数据",
    backstory="你是一位资深分析师",
    llm=get_llm("dashscope"),  # 指定 LLM
)
```

---

## 五、项目结构详解

### 5.1 使用 CLI 创建项目

```bash
crewai create crew my_crew
cd my_crew
```

### 5.2 目录结构说明

```
my_crew/
├── .env                    # 环境变量（API Key 等）
├── pyproject.toml          # Python 项目配置
├── README.md
└── src/my_crew/
    ├── __init__.py
    ├── main.py             # 入口文件，运行 crew
    ├── crew.py             # 定义 Crew、Agent、Task
    ├── tools/              # 自定义工具
    │   ├── __init__.py
    │   └── custom_tool.py
    └── config/
        ├── agents.yaml     # Agent 配置（角色、目标、背景）
        └── tasks.yaml      # Task 配置（描述、预期输出）
```

### 5.3 agents.yaml 配置

```yaml
# config/agents.yaml

researcher:
  role: >
    {topic} 高级研究员
  goal: >
    深入研究 {topic} 领域的最新发展
  backstory: >
    你是一位经验丰富的研究员，擅长发现最前沿的技术趋势。
    你以能够找到最相关信息并以清晰简洁的方式呈现而闻名。

analyst:
  role: >
    {topic} 数据分析师
  goal: >
    分析研究数据并生成洞察报告
  backstory: >
    你是一位严谨的分析师，擅长将复杂数据转化为可执行的洞察。
```

**占位符说明**：
- `{topic}` 会在运行时被替换为实际值

### 5.4 tasks.yaml 配置

```yaml
# config/tasks.yaml

research_task:
  description: >
    对 {topic} 进行全面研究，找出最新、最相关的信息。
  expected_output: >
    包含 10 个关键发现的要点列表
  agent: researcher  # 执行此任务的 Agent

analysis_task:
  description: >
    分析研究结果，生成详细的分析报告。
  expected_output: >
    一份完整的 Markdown 格式报告
  agent: analyst
  output_file: report.md  # 输出文件
```

### 5.5 crew.py 定义

```python
# crew.py

from crewai import Agent, Crew, Process, Task
from crewai.project import CrewBase, agent, crew, task

@CrewBase
class MyCrew():
    """我的 Crew"""

    @agent
    def researcher(self) -> Agent:
        return Agent(
            config=self.agents_config['researcher'],
            verbose=True,
        )

    @agent
    def analyst(self) -> Agent:
        return Agent(
            config=self.agents_config['analyst'],
            verbose=True,
        )

    @task
    def research_task(self) -> Task:
        return Task(
            config=self.tasks_config['research_task'],
        )

    @task
    def analysis_task(self) -> Task:
        return Task(
            config=self.tasks_config['analysis_task'],
            output_file='report.md',
        )

    @crew
    def crew(self) -> Crew:
        return Crew(
            agents=self.agents,
            tasks=self.tasks,
            process=Process.sequential,
            verbose=True,
        )
```

### 5.6 main.py 入口

```python
# main.py

from my_crew.crew import MyCrew

def run():
    """运行 Crew"""
    inputs = {
        'topic': 'AI Agents'
    }
    MyCrew().crew().kickoff(inputs=inputs)

if __name__ == "__main__":
    run()
```

### 5.7 运行项目

```bash
# 方式一：使用 CLI
crewai run

# 方式二：直接运行 Python
python src/my_crew/main.py
```

---

## 六、实战：构建一人公司 Agent 团队

### 6.1 场景描述

假设你要开发一个「人生规划器」App，但你只有一个人。你可以创建一个 Agent 团队来帮你：
- CEO Agent：负责决策和协调
- CTO Agent：负责技术架构
- 产品经理 Agent：负责需求分析
- 工程师 Agent：负责代码实现
- 测试 Agent：负责质量保证

### 6.2 项目结构

```
life-planner-crew/
├── .env
├── requirements.txt
├── main.py
├── agents/
│   ├── ceo_agent.py
│   ├── cto_agent.py
│   ├── product_manager.py
│   ├── backend_engineer.py
│   ├── frontend_engineer.py
│   └── qa_agent.py
├── tasks/
│   ├── requirement_tasks.py
│   ├── development_tasks.py
│   └── test_tasks.py
├── crews/
│   └── development_crew.py
├── tools/
│   └── file_tools.py
└── config/
    ├── project_config.py
    └── llm_config.py
```

### 6.3 LLM 配置

```python
# config/llm_config.py

import os
from langchain_openai import ChatOpenAI

DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY")
DASHSCOPE_BASE_URL = "https://coding.dashscope.aliyuncs.com/v1"

def get_default_llm():
    """默认模型（用于决策类 Agent）"""
    return ChatOpenAI(
        model="qwen-max",
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )

def get_efficient_llm():
    """高效模型（用于执行类 Agent）"""
    return ChatOpenAI(
        model="qwen-turbo",
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )
```

### 6.4 Agent 定义

```python
# agents/ceo_agent.py

from crewai import Agent
from config.llm_config import get_default_llm

def create_ceo_agent():
    return Agent(
        role="CEO - 公司首席执行官",
        goal="""
        负责：
        1. 战略决策和目标设定
        2. 团队协调和资源分配
        3. 处理 Agent 团队分歧
        4. 确保项目按时保质完成
        """,
        backstory="""
        你是一位经验丰富的技术创业者。
        决策果断但善于倾听，关注商业价值。
        """,
        verbose=True,
        allow_delegation=True,  # 可以委派任务
        llm=get_default_llm(),
    )

# agents/backend_engineer.py

def create_backend_engineer_agent():
    return Agent(
        role="后端工程师",
        goal="实现 API 和数据库逻辑",
        backstory="你专注于 Node.js 后端开发",
        verbose=True,
        allow_delegation=False,
        llm=get_efficient_llm(),  # 使用高效模型
    )
```

### 6.5 Crew 配置

```python
# crews/development_crew.py

from crewai import Crew, Process
from agents import (
    create_ceo_agent,
    create_cto_agent,
    create_product_manager,
    create_backend_engineer,
)

def create_development_crew():
    # 创建 Agent
    ceo = create_ceo_agent()
    cto = create_cto_agent()
    pm = create_product_manager()
    backend = create_backend_engineer()

    return Crew(
        agents=[ceo, cto, pm, backend],
        tasks=[],  # 动态添加
        process=Process.hierarchical,  # 层级模式
        manager_llm="qwen-max",
        manager_agent=ceo,  # CEO 作为管理者
        verbose=True,
    )
```

### 6.6 运行效果

```bash
python main.py

# 输出
╔═══════════════════════════════════════════════════════════════╗
║           🎭 Life Planner Crew - 一人公司 Agent 团队 🎭        ║
╚═══════════════════════════════════════════════════════════════╝

📋 检查环境配置...
  ✓ DASHSCOPE_API_KEY 已配置
  ✓ 项目目录存在

🎯 请选择操作模式：
  [1] 初始化项目
  [2] 功能开发模式
  [3] 决策讨论模式
```

---

## 七、常见问题与解决方案

### Q1: 连接大模型失败

**错误信息**：
```
ConnectionError: Failed to connect to api.openai.com
```

**原因**：没有配置正确的 `base_url`

**解决**：
```python
# 错误 ❌
llm = ChatOpenAI(model="qwen-max", api_key="xxx")

# 正确 ✅
llm = ChatOpenAI(
    model="qwen-max",
    api_key="xxx",
    base_url="https://coding.dashscope.aliyuncs.com/v1",
)
```

### Q2: API Key 格式错误

**错误信息**：
```
AuthenticationError: Invalid API key
```

**检查项**：
1. API Key 是否正确复制（没有多余空格）
2. 是否填对了环境变量名
3. `.env` 文件是否被正确加载

**解决**：
```python
# 确保加载 .env
from dotenv import load_dotenv
load_dotenv()

# 验证 API Key
import os
print(os.getenv("DASHSCOPE_API_KEY"))
```

### Q3: Agent 输出不符合预期

**原因**：角色定义不够清晰

**解决**：优化 `backstory`

```python
# 不好 ❌
backstory="你是一个程序员"

# 更好 ✅
backstory="""
你是一位专注 Node.js 后端开发的工程师。
- 擅长 RESTful API 设计
- 遵循 Clean Code 原则
- 注重代码可维护性
- 使用 TypeScript 和 NestJS
"""
```

### Q4: 依赖安装失败

**Windows 上常见问题**：

```bash
# 安装 Visual C++ Build Tools
# 或使用预编译包
pip install tiktoken --prefer-binary
pip install 'crewai[embeddings]'
```

### Q5: 如何调试 Agent

**开启 verbose 模式**：

```python
agent = Agent(
    role="分析师",
    verbose=True,  # 输出详细过程
)

crew = Crew(
    agents=[agent],
    verbose=True,  # 输出团队协作过程
)
```

---

## 八、总结

### 核心要点

1. **CrewAI 是什么**：多 Agent 协作框架，让多个 AI 角色协同完成任务
2. **核心概念**：Agent（角色）、Task（任务）、Crew（团队）、Tools（工具）
3. **关键配置**：LLM 接入必须配置 `base_url`，这是大多数人踩坑的地方

### 大模型接入速查表

| 服务商 | base_url | 备注 |
|-------|---------|------|
| OpenAI | 默认 | 无需配置 |
| 阿里百炼 Coding Plan | `https://coding.dashscope.aliyuncs.com/v1` | OpenAI 兼容 |
| DeepSeek | `https://api.deepseek.com/v1` | OpenAI 兼容 |
| 智谱 AI | `https://open.bigmodel.cn/api/paas/v4/` | OpenAI 兼容 |
| Ollama | `http://localhost:11434/v1` | 本地模型 |

### 学习资源

- [CrewAI 官方文档](https://docs.crewai.com)
- [CrewAI GitHub](https://github.com/crewAIInc/crewAI)
- [CrewAI 示例](https://github.com/crewAIInc/crewAI-examples)
- [LangChain 文档](https://python.langchain.com)

### 下一步

1. 尝试创建你的第一个 Crew
2. 接入你喜欢的大模型服务
3. 设计适合你场景的 Agent 角色
4. 组合 Crews 和 Flows 构建复杂工作流

---

> 作者：AI 技术探索者
> 日期：2026-03-31
>
> 本文基于 CrewAI v1.12+ 和阿里百炼 Coding Plan 服务编写