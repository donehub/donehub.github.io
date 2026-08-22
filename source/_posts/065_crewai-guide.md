---
title: CrewAI 入门实战：从零构建多 Agent 协作系统
date: 2026-02-10
tags: AI 工具
categories: AI
---

---

<!-- more -->

CrewAI 是一个用于编排自主 AI 代理的 Python 框架，核心卖点是让多个 Agent 像团队一样协同工作。它不依赖 LangChain 或其他框架，从零构建，官方宣称性能比 LangGraph 快 5 倍以上。框架提供两种编排模式：Crews 负责自主协作，Flows 负责精确控制工作流。对于需要多角色协作的场景（报告生成、数据分析、虚拟团队），CrewAI 的学习曲线比 LangGraph 平缓不少。

和同类框架横向对比，CrewAI 的优势在于简洁和独立，缺点是社区相对年轻。LangGraph 功能更全面但样板代码多且与 LangChain 强耦合，Autogen 的对话代理能力强但缺乏流程概念，ChatDev 有流程概念但定制能力有限。如果你的需求是快速搭建一个多角色协作系统，而不是构建复杂的有状态图，CrewAI 是目前上手成本最低的选择。

## 核心概念

CrewAI 的架构围绕四个概念展开：Agent、Task、Crew 和 Tools。理解它们之间的关系是使用框架的前提。

Agent 代表一个角色，是系统中最基本的执行单元。每个 Agent 需要定义 role（身份）、goal（目标）和 backstory（背景故事），其中 backstory 决定了 Agent 的性格和行为方式。此外还可以通过 tools 指定可用工具，通过 llm 指定使用哪个大模型，通过 allow_delegation 控制是否可以将任务委派给其他 Agent。

```python
from crewai import Agent

agent = Agent(
    role="高级数据分析师",
    goal="分析数据并提供洞察",
    backstory="你是一位资深分析师，擅长从海量数据中发现关键趋势...",
    verbose=True,
    allow_delegation=True,
    tools=[],
    llm=...,
)
```

Task 定义 Agent 需要完成的具体工作，包括 description（任务描述）、expected_output（预期输出格式）、agent（执行者）和 output_file（输出文件路径）。Task 和 Agent 是多对多的关系，但通常一个 Task 会绑定一个特定的 Agent。

```python
from crewai import Task

task = Task(
    description="分析销售数据，找出增长趋势",
    expected_output="包含 5 个关键发现的报告",
    agent=agent,
    output_file="report.md",
)
```

Crew 是 Agent 和 Task 的集合，定义整个团队的协作方式。CrewAI 提供两种 process 模式：sequential（顺序执行，一个任务完成后执行下一个）适合流程明确的任务链，hierarchical（层级模式，自动分配 Manager Agent 协调）适合需要动态决策的场景。

```python
from crewai import Crew, Process

crew = Crew(
    agents=[agent1, agent2, agent3],
    tasks=[task1, task2, task3],
    process=Process.sequential,
    verbose=True,
)
```

Tools 扩展 Agent 的能力边界，让 Agent 可以搜索网页、读写文件、调用外部 API 等。框架内置了一批常用工具，也支持自定义工具。

```python
from crewai_tools import SerperDevTool, FileReadTool

search_tool = SerperDevTool()
file_tool = FileReadTool()

agent = Agent(
    role="研究员",
    tools=[search_tool, file_tool],
    ...
)
```

整个工作流程可以这样理解：你在 Crew 中注册一组 Agent 和一组 Task，Crew 根据选定的 process 模式将 Task 分配给对应的 Agent 执行。顺序模式下，Task 按定义顺序依次流转；层级模式下，Manager Agent 接收所有任务后动态拆解和分发。每个 Agent 在执行任务时可以调用自己的 tools 获取外部信息，完成后将结果传递给下一个环节。

## 安装与环境配置

CrewAI 要求 Python 3.10 到 3.13，推荐使用 uv 作为包管理器。基础安装只需要 `pip install crewai`，如果需要内置工具集（搜索、文件操作等），执行 `pip install 'crewai[tools]'`。使用 uv 的话，对应命令是 `uv pip install crewai` 和 `uv pip install 'crewai[tools]'`。

安装完成后，用 CLI 创建项目骨架：

```bash
crewai create crew my_project
```

生成的项目结构如下：

```
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

Windows 用户安装时大概率会遇到两个问题。第一个是 `ModuleNotFoundError: tiktoken`，解决方法是安装嵌入依赖：`uv pip install 'crewai[embeddings]'`。第二个是 tiktoken 的 Rust 编译错误，可以跳过编译直接安装预编译包：`uv pip install tiktoken --prefer-binary`。如果这两个方案都不行，需要先安装 Visual C++ Build Tools。

## 大模型服务接入

这是大多数新手卡住的环节。CrewAI 默认连接 `https://api.openai.com/v1`，如果你用的是其他大模型服务（阿里百炼、DeepSeek、智谱等），必须显式指定 base_url，否则会遇到 `Connection refused` 或 `Invalid API key` 错误。

CrewAI 通过 LangChain 的 ChatModel 抽象来对接大模型，所以本质上你只需要构造一个正确的 ChatOpenAI 或 ChatAnthropic 实例，然后传给 Agent 的 llm 参数。不同服务商的差异只在 model 名称、api_key 和 base_url 三个字段上。

OpenAI 官方最简单，不指定 base_url 即可：

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="gpt-4o",
    api_key="sk-xxxxx",
)
```

Anthropic Claude 使用独立的包：

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="claude-sonnet-4-6",
    api_key="sk-ant-xxxxx",
)
```

阿里百炼 Coding Plan 同时兼容 OpenAI 和 Anthropic 两种协议，对应的 base_url 不同。OpenAI 兼容协议的地址是 `https://coding.dashscope.aliyuncs.com/v1`，Anthropic 兼容协议的地址是 `https://coding.dashscope.aliyuncs.com/apps/anthropic`。两种协议都可以调用通义千问系列模型，选择取决于你更习惯哪个 SDK。

```python
# OpenAI 兼容协议
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="qwen-max",
    api_key="your_dashscope_key",
    base_url="https://coding.dashscope.aliyuncs.com/v1",
)
```

```python
# Anthropic 兼容协议
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="qwen-max",
    api_key="your_dashscope_key",
    base_url="https://coding.dashscope.aliyuncs.com/apps/anthropic",
)
```

DeepSeek 和智谱 AI 都兼容 OpenAI 协议，只需要改 base_url。DeepSeek 的地址是 `https://api.deepseek.com/v1`，智谱 AI 的地址是 `https://open.bigmodel.cn/api/paas/v4/`。本地模型 Ollama 同理，地址是 `http://localhost:11434/v1`，api_key 填任意值即可。

| 服务商 | base_url | 兼容协议 |
|-------|---------|---------|
| OpenAI | 默认（无需配置） | 原生 |
| Anthropic | 默认（无需配置） | 原生 |
| 阿里百炼 Coding Plan | `https://coding.dashscope.aliyuncs.com/v1` | OpenAI / Anthropic |
| DeepSeek | `https://api.deepseek.com/v1` | OpenAI |
| 智谱 AI | `https://open.bigmodel.cn/api/paas/v4/` | OpenAI |
| Ollama | `http://localhost:11434/v1` | OpenAI |

在实际项目中，建议用配置文件统一管理不同服务商的参数，避免在每个 Agent 中重复填写：

```python
# config/llm_config.py
import os
from langchain_openai import ChatOpenAI

def get_llm(provider: str = "dashscope"):
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

使用时只需一行调用，切换模型也很方便：

```python
llm = get_llm()              # 默认使用阿里百炼
llm = get_llm("openai")      # 切换到 OpenAI
```

在 Agent 中引用这个配置：

```python
from crewai import Agent
from config.llm_config import get_llm

agent = Agent(
    role="分析师",
    goal="分析数据",
    backstory="你是一位资深分析师",
    llm=get_llm("dashscope"),
)
```

## 项目结构详解

CrewAI 的 CLI 工具会生成一套标准化的项目结构，理解每个文件的职责能让你更快地上手开发。

`config/agents.yaml` 定义所有 Agent 的角色信息。文件中使用 YAML 格式描述每个 Agent 的 role、goal 和 backstory，支持 `{topic}` 这样的占位符在运行时动态替换。

```yaml
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

`config/tasks.yaml` 定义所有 Task 的描述和预期输出，同样支持占位符和动态绑定 Agent。

```yaml
research_task:
  description: >
    对 {topic} 进行全面研究，找出最新、最相关的信息。
  expected_output: >
    包含 10 个关键发现的要点列表
  agent: researcher

analysis_task:
  description: >
    分析研究结果，生成详细的分析报告。
  expected_output: >
    一份完整的 Markdown 格式报告
  agent: analyst
  output_file: report.md
```

`crew.py` 是整个项目的核心，用装饰器模式将 agents.yaml 和 tasks.yaml 中的配置组装成可执行的 Crew。`@CrewBase` 标记类，`@agent` 和 `@task` 标记方法，`@crew` 标记最终的 Crew 组装方法。框架会自动读取配置文件并将内容注入到 `self.agents_config` 和 `self.tasks_config` 中。

```python
from crewai import Agent, Crew, Process, Task
from crewai.project import CrewBase, agent, crew, task

@CrewBase
class MyCrew():

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
        return Task(config=self.tasks_config['research_task'])

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

`main.py` 是入口文件，传入动态参数后启动 Crew 执行：

```python
from my_crew.crew import MyCrew

def run():
    inputs = {'topic': 'AI Agents'}
    MyCrew().crew().kickoff(inputs=inputs)

if __name__ == "__main__":
    run()
```

运行方式有两种：`crewai run`（CLI 方式）或 `python src/my_crew/main.py`（直接执行 Python）。

## 实战：构建一人公司 Agent 团队

假设你要开发一个「人生规划器」App，但只有你一个人。你可以用 CrewAI 搭建一个虚拟团队：CEO 负责决策和协调，CTO 负责技术架构，产品经理负责需求分析，工程师负责代码实现，测试负责质量保证。

项目按照职责拆分目录。agents 目录存放每个角色的定义，tasks 目录存放任务定义，crews 目录存放团队协作逻辑，config 目录存放 LLM 配置和项目参数。

```
life-planner-crew/
├── .env
├── main.py
├── agents/
│   ├── ceo_agent.py
│   ├── cto_agent.py
│   ├── product_manager.py
│   └── backend_engineer.py
├── tasks/
│   ├── requirement_tasks.py
│   ├── development_tasks.py
│   └── test_tasks.py
├── crews/
│   └── development_crew.py
└── config/
    ├── llm_config.py
    └── project_config.py
```

LLM 配置的策略是按角色分配模型。决策类 Agent（CEO、CTO）使用推理能力更强的模型（如 qwen-max），执行类 Agent（工程师、测试）使用速度更快的模型（如 qwen-turbo），这样可以在成本和质量之间取得平衡。

```python
# config/llm_config.py
import os
from langchain_openai import ChatOpenAI

DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY")
DASHSCOPE_BASE_URL = "https://coding.dashscope.aliyuncs.com/v1"

def get_default_llm():
    """决策类 Agent 使用"""
    return ChatOpenAI(
        model="qwen-max",
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )

def get_efficient_llm():
    """执行类 Agent 使用"""
    return ChatOpenAI(
        model="qwen-turbo",
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )
```

CEO Agent 的定义需要足够详细，因为它的 backstory 直接影响决策质量。`allow_delegation=True` 允许 CEO 将任务委派给其他 Agent，这是层级模式的关键。

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
        allow_delegation=True,
        llm=get_default_llm(),
    )
```

后端工程师则使用高效模型，因为它的任务更多是执行而非决策：

```python
# agents/backend_engineer.py
from config.llm_config import get_efficient_llm

def create_backend_engineer_agent():
    return Agent(
        role="后端工程师",
        goal="实现 API 和数据库逻辑",
        backstory="你专注于 Node.js 后端开发",
        verbose=True,
        allow_delegation=False,
        llm=get_efficient_llm(),
    )
```

Crew 的组装使用 hierarchical 模式，由 CEO 充当管理者角色：

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
    ceo = create_ceo_agent()
    cto = create_cto_agent()
    pm = create_product_manager()
    backend = create_backend_engineer()

    return Crew(
        agents=[ceo, cto, pm, backend],
        tasks=[],  # 动态添加
        process=Process.hierarchical,
        manager_llm="qwen-max",
        manager_agent=ceo,
        verbose=True,
    )
```

## 踩坑与调试

连接大模型失败是最常见的问题，错误信息通常是 `ConnectionError: Failed to connect to api.openai.com`。根因是忘记配置 base_url。用阿里百炼时必须显式指定 `base_url="https://coding.dashscope.aliyuncs.com/v1"`，只填 api_key 是不够的。

```python
# 错误写法
llm = ChatOpenAI(model="qwen-max", api_key="xxx")

# 正确写法
llm = ChatOpenAI(
    model="qwen-max",
    api_key="xxx",
    base_url="https://coding.dashscope.aliyuncs.com/v1",
)
```

API Key 格式错误也会引发认证失败。排查方向有三个：检查 Key 是否完整复制（没有多余空格或截断），确认环境变量名和代码中读取的变量名一致，以及确保 `.env` 文件被正确加载。可以用 `python-dotenv` 的 `load_dotenv()` 显式加载，再用 `os.getenv()` 打印验证。

```python
from dotenv import load_dotenv
load_dotenv()

import os
print(os.getenv("DASHSCOPE_API_KEY"))
```

Agent 输出不符合预期时，问题通常出在 backstory 的定义上。一个模糊的 backstory 会让 Agent 的行为缺乏方向感。把 backstory 写得越具体，包含技术栈偏好、工作原则和输出标准，Agent 的表现就越稳定。

```python
# 模糊 — Agent 行为不可预测
backstory="你是一个程序员"

# 具体 — Agent 行为有明确边界
backstory="""
你是一位专注 Node.js 后端开发的工程师。
擅长 RESTful API 设计，遵循 Clean Code 原则，
注重代码可维护性，使用 TypeScript 和 NestJS。
"""
```

调试方面，在 Agent 和 Crew 上都开启 `verbose=True` 可以看到完整的执行过程，包括 Agent 的思考链、任务分配和工具调用细节，这对定位问题非常有帮助。

```python
agent = Agent(role="分析师", verbose=True)
crew = Crew(agents=[agent], verbose=True)
```

## 学习资源

- [CrewAI 官方文档](https://docs.crewai.com)
- [CrewAI GitHub](https://github.com/crewAIInc/crewAI)
- [CrewAI 示例仓库](https://github.com/crewAIInc/crewAI-examples)
- [LangChain 文档](https://python.langchain.com)

---

> 作者：AI 技术探索者
> 日期：2026-03-31
>
> 本文基于 CrewAI v1.12+ 和阿里百炼 Coding Plan 服务编写
