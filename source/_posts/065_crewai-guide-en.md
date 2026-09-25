---
title: Getting Started with CrewAI: Building a Multi-Agent Collaboration System from Scratch
date: 2026-02-10
tags: AI Tools
categories: AI
lang: en
label: 065_crewai-guide
---

---

<!-- more -->

CrewAI is a Python framework for orchestrating autonomous AI agents. Its core selling point is making multiple Agents work together like a team. It doesn't depend on LangChain or any other framework; it's built from the ground up, and the official claim is performance 5x faster than LangGraph. The framework offers two orchestration modes: Crews handle autonomous collaboration, and Flows handle precise workflow control. For scenarios requiring multi-role collaboration (report generation, data analysis, virtual teams), CrewAI's learning curve is noticeably gentler than LangGraph's.

Compared to similar frameworks, CrewAI's strengths are simplicity and independence; its weakness is a relatively young community. LangGraph is more feature-complete but comes with more boilerplate and tight LangChain coupling. Autogen excels at conversational agents but lacks workflow concepts. ChatDev has workflow concepts but limited customization. If you need to quickly stand up a multi-role collaboration system rather than building complex stateful graphs, CrewAI is the lowest-friction option available today.

## Core Concepts

CrewAI's architecture revolves around four concepts: Agent, Task, Crew, and Tools. Understanding their relationships is essential for using the framework.

An Agent represents a role, the most basic execution unit in the system. Each Agent requires a role (identity), goal (objective), and backstory (background story). Backstory determines the Agent's personality and behavior patterns. You can also specify available tools, which LLM to use, and whether tasks can be delegated to other Agents via allow_delegation.

```python
from crewai import Agent

agent = Agent(
    role="Senior Data Analyst",
    goal="Analyze data and provide insights",
    backstory="You are a seasoned analyst skilled at discovering key trends from massive datasets...",
    verbose=True,
    allow_delegation=True,
    tools=[],
    llm=...,
)
```

A Task defines specific work an Agent must complete, including description (task description), expected_output (expected output format), agent (executor), and output_file (output file path). Tasks and Agents have a many-to-many relationship, but typically one Task binds to one specific Agent.

```python
from crewai import Task

task = Task(
    description="Analyze sales data and identify growth trends",
    expected_output="A report with 5 key findings",
    agent=agent,
    output_file="report.md",
)
```

A Crew is a collection of Agents and Tasks, defining how the entire team collaborates. CrewAI offers two process modes: sequential (tasks execute one after another) suits task chains with clear workflows; hierarchical (automatically assigns a Manager Agent to coordinate) suits scenarios requiring dynamic decision-making.

```python
from crewai import Crew, Process

crew = Crew(
    agents=[agent1, agent2, agent3],
    tasks=[task1, task2, task3],
    process=Process.sequential,
    verbose=True,
)
```

Tools extend an Agent's capability boundary, letting Agents search the web, read/write files, call external APIs, and more. The framework includes a set of built-in tools and supports custom ones.

```python
from crewai_tools import SerperDevTool, FileReadTool

search_tool = SerperDevTool()
file_tool = FileReadTool()

agent = Agent(
    role="Researcher",
    tools=[search_tool, file_tool],
    ...
)
```

The overall workflow works like this: you register a set of Agents and a set of Tasks in a Crew, and the Crew assigns Tasks to corresponding Agents based on the selected process mode. In sequential mode, Tasks flow through in definition order; in hierarchical mode, the Manager Agent receives all tasks and dynamically decomposes and distributes them. Each Agent can call its own tools for external information during task execution, passing results to the next step upon completion.

## Installation and Environment Setup

CrewAI requires Python 3.10 through 3.13, and uv is the recommended package manager. Basic installation needs only `pip install crewai`; if you want the built-in tool set (search, file operations, etc.), run `pip install 'crewai[tools]'`. With uv, the corresponding commands are `uv pip install crewai` and `uv pip install 'crewai[tools]'`.

After installation, use the CLI to create a project skeleton:

```bash
crewai create crew my_project
```

The generated project structure:

```
my_project/
├── .env                    # Environment variables
├── pyproject.toml          # Project configuration
└── src/my_project/
    ├── main.py             # Entry point
    ├── crew.py             # Crew definition
    ├── tools/              # Custom tools
    └── config/
        ├── agents.yaml     # Agent configuration
        └── tasks.yaml      # Task configuration
```

Windows users will likely hit two issues during installation. First, `ModuleNotFoundError: tiktoken`; fix it by installing embedding dependencies: `uv pip install 'crewai[embeddings]'`. Second, a Rust compilation error with tiktoken; skip compilation and install the prebuilt package directly: `uv pip install tiktoken --prefer-binary`. If neither works, you'll need to install Visual C++ Build Tools first.

## Connecting LLM Services

This is where most beginners get stuck. CrewAI defaults to connecting to `https://api.openai.com/v1`. If you're using a different LLM service (Alibaba Bailian, DeepSeek, Zhipu, etc.), you must explicitly specify base_url, or you'll get `Connection refused` or `Invalid API key` errors.

CrewAI interfaces with LLMs through LangChain's ChatModel abstraction, so you essentially need to construct a correct ChatOpenAI or ChatAnthropic instance and pass it to the Agent's llm parameter. The differences between providers come down to three fields: model name, api_key, and base_url.

OpenAI official is the simplest; no base_url needed:

```python
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="gpt-4o",
    api_key="sk-xxxxx",
)
```

Anthropic Claude uses a separate package:

```python
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="claude-sonnet-4-6",
    api_key="sk-ant-xxxxx",
)
```

Alibaba Bailian Coding Plan supports both OpenAI and Anthropic protocols simultaneously, with different base_urls. The OpenAI-compatible endpoint is `https://coding.dashscope.aliyuncs.com/v1`, and the Anthropic-compatible endpoint is `https://coding.dashscope.aliyuncs.com/apps/anthropic`. Both protocols can call the Qwen model series; your choice depends on which SDK you prefer.

```python
# OpenAI-compatible protocol
from langchain_openai import ChatOpenAI

llm = ChatOpenAI(
    model="qwen-max",
    api_key="your_dashscope_key",
    base_url="https://coding.dashscope.aliyuncs.com/v1",
)
```

```python
# Anthropic-compatible protocol
from langchain_anthropic import ChatAnthropic

llm = ChatAnthropic(
    model="qwen-max",
    api_key="your_dashscope_key",
    base_url="https://coding.dashscope.aliyuncs.com/apps/anthropic",
)
```

DeepSeek and Zhipu AI both support the OpenAI protocol; you only need to change base_url. DeepSeek's address is `https://api.deepseek.com/v1`, and Zhipu AI's address is `https://open.bigmodel.cn/api/paas/v4/`. Local model Ollama works the same way: address is `http://localhost:11434/v1`, and api_key can be any value.

| Provider | base_url | Compatible Protocol |
|----------|---------|-------------------|
| OpenAI | Default (no config needed) | Native |
| Anthropic | Default (no config needed) | Native |
| Alibaba Bailian Coding Plan | `https://coding.dashscope.aliyuncs.com/v1` | OpenAI / Anthropic |
| DeepSeek | `https://api.deepseek.com/v1` | OpenAI |
| Zhipu AI | `https://open.bigmodel.cn/api/paas/v4/` | OpenAI |
| Ollama | `http://localhost:11434/v1` | OpenAI |

In production projects, managing provider parameters through a configuration file avoids repeating values in every Agent:

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
        raise ValueError(f"Please configure the API Key for {provider}")

    return ChatOpenAI(
        model=config["model"],
        api_key=config["api_key"],
        base_url=config["base_url"],
    )
```

One-line invocation when using it; switching models is straightforward:

```python
llm = get_llm()              # Default to Alibaba Bailian
llm = get_llm("openai")      # Switch to OpenAI
```

Reference this configuration in an Agent:

```python
from crewai import Agent
from config.llm_config import get_llm

agent = Agent(
    role="Analyst",
    goal="Analyze data",
    backstory="You are a seasoned analyst",
    llm=get_llm("dashscope"),
)
```

## Project Structure Breakdown

CrewAI's CLI generates a standardized project structure. Understanding each file's responsibility helps you get up to speed faster.

`config/agents.yaml` defines all Agent role information. The file uses YAML format to describe each Agent's role, goal, and backstory, with support for placeholders like `{topic}` for dynamic runtime substitution.

```yaml
researcher:
  role: >
    {topic} Senior Researcher
  goal: >
    Deeply research the latest developments in the {topic} field
  backstory: >
    You are an experienced researcher skilled at discovering cutting-edge technology trends.
    You are known for finding the most relevant information and presenting it clearly and concisely.

analyst:
  role: >
    {topic} Data Analyst
  goal: >
    Analyze research data and generate insight reports
  backstory: >
    You are a meticulous analyst skilled at transforming complex data into actionable insights.
```

`config/tasks.yaml` defines all Task descriptions and expected outputs, also supporting placeholders and dynamic Agent binding.

```yaml
research_task:
  description: >
    Conduct comprehensive research on {topic}, finding the latest and most relevant information.
  expected_output: >
    A bullet-point list with 10 key findings
  agent: researcher

analysis_task:
  description: >
    Analyze research findings and generate a detailed analysis report.
  expected_output: >
    A complete Markdown-formatted report
  agent: analyst
  output_file: report.md
```

`crew.py` is the project core, using a decorator pattern to assemble agents.yaml and tasks.yaml configurations into an executable Crew. `@CrewBase` marks the class, `@agent` and `@task` mark methods, and `@crew` marks the final Crew assembly method. The framework automatically reads configuration files and injects contents into `self.agents_config` and `self.tasks_config`.

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

`main.py` is the entry point, passing dynamic parameters and launching Crew execution:

```python
from my_crew.crew import MyCrew

def run():
    inputs = {'topic': 'AI Agents'}
    MyCrew().crew().kickoff(inputs=inputs)

if __name__ == "__main__":
    run()
```

Two ways to run: `crewai run` (CLI) or `python src/my_crew/main.py` (direct Python execution).

## Hands-On: Building a One-Person Company Agent Team

Suppose you want to develop a "Life Planner" app, but you're the only person on the team. You can use CrewAI to build a virtual team: a CEO handles decisions and coordination, a CTO handles technical architecture, a Product Manager handles requirements analysis, an Engineer handles code implementation, and a Tester handles quality assurance.

The project splits directories by responsibility. The agents directory holds each role's definition, tasks holds task definitions, crews holds team collaboration logic, and config holds LLM configuration and project parameters.

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

The LLM configuration strategy is assigning models by role. Decision-making Agents (CEO, CTO) use models with stronger reasoning (like qwen-max); execution Agents (Engineer, Tester) use faster models (like qwen-turbo). This balances cost and quality.

```python
# config/llm_config.py
import os
from langchain_openai import ChatOpenAI

DASHSCOPE_API_KEY = os.getenv("DASHSCOPE_API_KEY")
DASHSCOPE_BASE_URL = "https://coding.dashscope.aliyuncs.com/v1"

def get_default_llm():
    """Used by decision-making Agents"""
    return ChatOpenAI(
        model="qwen-max",
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )

def get_efficient_llm():
    """Used by execution Agents"""
    return ChatOpenAI(
        model="qwen-turbo",
        api_key=DASHSCOPE_API_KEY,
        base_url=DASHSCOPE_BASE_URL,
    )
```

The CEO Agent definition needs to be detailed because its backstory directly impacts decision quality. `allow_delegation=True` lets the CEO delegate tasks to other Agents, which is key in hierarchical mode.

```python
# agents/ceo_agent.py
from crewai import Agent
from config.llm_config import get_default_llm

def create_ceo_agent():
    return Agent(
        role="CEO - Chief Executive Officer",
        goal="""
        Responsible for:
        1. Strategic decisions and goal setting
        2. Team coordination and resource allocation
        3. Resolving disagreements within the Agent team
        4. Ensuring project completion on time and to quality standards
        """,
        backstory="""
        You are an experienced technology entrepreneur.
        Decisive but a good listener, focused on business value.
        """,
        verbose=True,
        allow_delegation=True,
        llm=get_default_llm(),
    )
```

The backend engineer uses the efficient model because its tasks lean toward execution rather than decision-making:

```python
# agents/backend_engineer.py
from config.llm_config import get_efficient_llm

def create_backend_engineer_agent():
    return Agent(
        role="Backend Engineer",
        goal="Implement APIs and database logic",
        backstory="You focus on Node.js backend development",
        verbose=True,
        allow_delegation=False,
        llm=get_efficient_llm(),
    )
```

The Crew assembly uses hierarchical mode, with the CEO acting as the manager role:

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
        tasks=[],  # Added dynamically
        process=Process.hierarchical,
        manager_llm="qwen-max",
        manager_agent=ceo,
        verbose=True,
    )
```

## Pitfalls and Debugging

LLM connection failures are the most common issue, typically showing as `ConnectionError: Failed to connect to api.openai.com`. The root cause is forgetting to configure base_url. With Alibaba Bailian, you must explicitly set `base_url="https://coding.dashscope.aliyuncs.com/v1"`; just filling in api_key isn't enough.

```python
# Wrong
llm = ChatOpenAI(model="qwen-max", api_key="xxx")

# Correct
llm = ChatOpenAI(
    model="qwen-max",
    api_key="xxx",
    base_url="https://coding.dashscope.aliyuncs.com/v1",
)
```

Malformed API Keys also trigger authentication failures. Three directions to investigate: check whether the Key was fully copied (no extra spaces or truncation), confirm the environment variable name matches what the code reads, and ensure the `.env` file loads correctly. Use `python-dotenv`'s `load_dotenv()` to load explicitly, then verify with `os.getenv()` print:

```python
from dotenv import load_dotenv
load_dotenv()

import os
print(os.getenv("DASHSCOPE_API_KEY"))
```

When Agent output doesn't match expectations, the problem usually lies in the backstory definition. A vague backstory gives the Agent no sense of direction. The more specific the backstory, including tech stack preferences, working principles, and output standards, the more stable the Agent's behavior.

```python
# Vague — Agent behavior is unpredictable
backstory="You are a programmer"

# Specific — Agent behavior has clear boundaries
backstory="""
You are a backend engineer focused on Node.js development.
Skilled in RESTful API design, following Clean Code principles,
prioritizing code maintainability, using TypeScript and NestJS.
"""
```

For debugging, enabling `verbose=True` on both Agent and Crew shows the complete execution process, including the Agent's chain of thought, task assignments, and tool call details. This is invaluable for diagnosing issues.

```python
agent = Agent(role="Analyst", verbose=True)
crew = Crew(agents=[agent], verbose=True)
```

## Learning Resources

- [CrewAI Official Documentation](https://docs.crewai.com)
- [CrewAI GitHub](https://github.com/crewAIInc/crewAI)
- [CrewAI Examples Repository](https://github.com/crewAIInc/crewAI-examples)
- [LangChain Documentation](https://python.langchain.com)

---

> Author: AI Technology Explorer
> Date: 2026-03-31
>
> Written based on CrewAI v1.12+ and Alibaba Bailian Coding Plan service
