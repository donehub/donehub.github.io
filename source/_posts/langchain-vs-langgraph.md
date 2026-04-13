---
title: LangChain vs LangGraph：从链式调用到图状态机的 Agent 演进之路
date: 2024-12-13
tags: AI Agent
categories: AI
---

> 这篇文章不讲废话，只讲干货：LangChain 和 LangGraph 分别是什么、为什么 LangChain 团队要造 LangGraph、两者的技术本质差异、以及你该选哪个。

---

## 一、先说结论

**LangChain 是"零件库"，LangGraph 是"组装图纸"。**

- **LangChain**：给你各种组件——LLM 连接器、工具定义、记忆系统、向量检索器。你用它来"组装"一个 LLM 应用。
- **LangGraph**：帮你定义组件之间的"组装方式"——怎么循环、怎么分支、怎么传递状态、什么时候结束。

两者不是竞争关系，而是**互补关系**。LangChain 团队自己造了 LangGraph，用来解决 LangChain 原生 Agent 能力不足的问题。

---

## 二、LangChain：起源与发展

### 2.1 创始人与背景

| 维度 | 内容 |
|------|------|
| **创始人** | Harrison Chase |
| **背景** | 曾在 Robust Intelligence（AI 安全公司）和 McKinsey 工作 |
| **创立时间** | 2022 年 10 月，作为开源项目发布在 GitHub |
| **公司成立** | 2023 年初，LangChain Inc. 成立，获得风险投资 |

### 2.2 为什么能火

2022 年 10 月，ChatGPT 还没发布（11 月才发布）。Harrison Chase 做了一件关键的事：**把 LLM 应用开发的"碎片化经验"变成"标准化组件"**。

当时开发者面临的问题：

```
每个 LLM 应用都要自己解决：
- 怎么调用不同模型的 API（OpenAI、Anthropic、 Cohere...）
- 怎么记住用户之前说了什么
- 怎么让 LLM 调用外部工具
- 怎么把长文档切成小块让 LLM 能读
- 怎么把检索结果喂给 LLM
```

LangChain 把这些问题**抽象成统一的组件**，你只需要配置参数，不用自己造轮子。

### 2.3 发展时间线

| 时间 | 事件 | 影响 |
|------|------|------|
| **2022.10** | LangChain 开源发布 | GitHub 迅速获得数千 Star |
| **2022.12** | ChatGPT 发布，LLM 应用需求爆发 | LangChain 成为首选框架 |
| **2023.01** | LangChain Inc. 成立，获风险投资 | 商业化运营 |
| **2023.03** | 推出 LCEL（LangChain Expression Language） | 链式调用更简洁 |
| **2023.06** | LangSmith 发布 | 可观测性平台 |
| **2023.10** | LangServe 发布 | 快速部署 API |
| **2024.01** | LangGraph 发布 | 解决 Agent 循环问题 |

### 2.4 核心组件一览

```
LangChain = 以下组件的集合

┌─────────────────────────────────────────────────────────────┐
│                    LangChain 组件体系                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Models    │  │   Prompts   │  │   Memory    │        │
│  │  (LLM连接)  │  │ (模板管理)  │  │ (对话记忆)  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │   Tools     │  │   Chains    │  │   Agents    │        │
│  │ (外部工具)  │  │ (调用链)    │  │ (决策执行)  │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  Retrieval  │  │   Output    │  │   Document  │        │
│  │  (RAG检索)  │  │   Parser    │  │   Loaders   │        │
│  └─────────────┘  └─────────────┘  └─────────────┘        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.5 LangChain 的技术本质

**LangChain 的核心抽象是 "Chain"（链）**——把多个步骤串起来，线性执行：

```python
# LangChain LCEL 语法（链式调用）
chain = (
    {"context": retriever, "question": RunnablePassthrough()}
    | prompt
    | llm
    | output_parser
)

result = chain.invoke("什么是 Agent？")
```

**优点**：
- 简单直观，上手快
- 组件丰富，生态完善
- 适合 RAG、简单问答、固定流程的场景

**缺点**（这也是 LangGraph 存在的原因）：
- 无法循环执行（Agent 需要 ReAct 循环）
- 无法根据中间结果动态选择路径
- 状态管理能力弱

---

## 三、LangGraph：为什么 LangChain 团队要造它

### 3.1 核心问题：LangChain 的 Agent 不够用

LangChain 有 `AgentExecutor`，理论上可以做 Agent。但实际使用中发现：

```
问题 1：AgentExecutor 无法真正循环
- LangChain 的链是线性的：A → B → C → 结束
- Agent 需要 ReAct 循环：思考 → 执行 → 观察 → 再思考 → 再执行...
- 用 LangChain 做 Agent，只能"模拟"循环，很别扭

问题 2：无法控制流程分支
- Agent 执行到某一步，可能需要：
  - 成功了 → 结束
  - 失败了 → 重试
  - 信息不够 → 再搜索
- LangChain 的链无法根据条件选择不同路径

问题 3：状态管理混乱
- Agent 需要记住"我刚才做了什么"、"我现在的进度"
- LangChain 的记忆系统是独立的，无法和执行流程绑定
```

### 3.2 LangGraph 的诞生

2024 年第一季度，LangChain 团队推出 LangGraph，**专门解决 Agent 工作流问题**。

| 维度 | 内容 |
|------|------|
| **发布时间** | 2024 年第一季度 |
| **创始人** | LangChain 团队（Harrison Chase 领导） |
| **核心目的** | 让 Agent 能真正循环执行、状态管理、流程分支 |
| **技术本质** | 状态机（State Machine） + 图结构（Graph） |

### 3.3 LangGraph 的核心创新

**LangGraph 的核心抽象是 "StateGraph"（状态图）**——用图结构定义执行流程：

```python
from langgraph.graph import StateGraph, END

# 定义状态
class AgentState(TypedDict):
    messages: list
    next_step: str

# 构建图
graph = StateGraph(AgentState)
graph.add_node("agent", agent_node)      # Agent 思考节点
graph.add_node("tool", tool_node)        # 工具执行节点
graph.add_node("check", check_node)      # 结果检查节点

# 定义边（流转关系）
graph.add_edge("agent", "tool")
graph.add_edge("tool", "check")

# 条件分支：根据检查结果决定下一步
graph.add_conditional_edges("check", 
    lambda state: state["next_step"],
    {"continue": "agent", "end": END}  # 循环回去或结束
)

# 编译执行
app = graph.compile()
```

**LangGraph 解决的三大问题**：

| 问题 | LangChain 方案 | LangGraph 方案 |
|------|---------------|---------------|
| **循环执行** | 用 AgentExecutor 模拟，很别扭 | 用图的边连接回去，原生支持循环 |
| **流程分支** | 无法根据条件选择路径 | `add_conditional_edges` 原生支持 |
| **状态管理** | Memory 独立，不绑定流程 | State 在节点间传递，自动管理 |

### 3.4 LangGraph 发展时间线

| 时间 | 事件 | 影响 |
|------|------|------|
| **2024.Q1** | LangGraph 发布 | 解决 Agent 循环问题 |
| **2024.06** | LangGraph Studio 发布 | 可视化调试工具 |
| **2024.08** | 支持多 Agent 协作 | 复杂系统必备 |
| **2025.01** | LangGraph 0.3 发布 | 流式输出、多租户、改进调试 |

---

## 四、技术对比：本质差异

### 4.1 抽象模型对比

| 维度 | LangChain | LangGraph |
|------|-----------|-----------|
| **核心抽象** | Chain（链） | StateGraph（状态图） |
| **执行模式** | 线性执行 | 循环 + 分支执行 |
| **状态管理** | 独立 Memory 组件 | State 在节点间传递 |
| **流程控制** | 固定顺序 | 条件分支、并行、循环 |
| **适用场景** | RAG、问答、固定流程 | Agent、多步骤决策 |

### 4.2 架构图对比

**LangChain：线性链**

```
Input → [Prompt] → [LLM] → [Parser] → Output

特点：
- 单向流动
- 固定顺序
- 无法回头
```

**LangGraph：状态图**

```
              ┌─────────┐
              │  Start  │
              └────┬────┘
                   │
              ┌────▼────┐
              │ Agent   │ ←─────┐
              │(思考)   │       │
              └────┬────┘       │
                   │            │ 循环
         ┌─────────┼─────────┐  │
         │                   │  │
    ┌────▼────┐         ┌────▼────┤
    │ Tool A  │         │ Tool B  │
    │(执行)   │         │(执行)   │
    └────┬────┘         └────┬────┤
         │                   │  │
         └───────┬───────────┘  │
                 │              │
            ┌────▼────┐         │
            │  Check  │─────────┘
            │(检查)   │
            └────┬────┘
                 │
         ┌───────┴───────┐
         │               │
    ┌────▼────┐     ┌────▼────┐
    │ Continue│     │   End   │
    │ (继续)  │     │  (结束) │
    └─────────┘     └─────────┘

特点：
- 可以循环（边可以指向之前的节点）
- 可以分支（条件判断选择路径）
- State 在节点间自动传递
```

### 4.3 代码对比：同一功能的不同实现

**任务：让 Agent 搜索信息，如果不够就再搜索**

**LangChain 方案（别扭）**

```python
# 只能模拟循环，用 max_iterations 限制
from langchain.agents import AgentExecutor

agent_executor = AgentExecutor(
    agent=agent,
    tools=[search_tool],
    max_iterations=5,  # 强制限制循环次数
    verbose=True
)

# 问题：无法精确控制"什么时候结束"
# 只能靠 iterations 数量硬限制
```

**LangGraph 方案（原生支持）**

```python
from langgraph.graph import StateGraph, END

def check_result(state):
    # 精确判断：信息是否足够
    if state["info_complete"]:
        return "end"
    else:
        return "continue"

graph = StateGraph(AgentState)
graph.add_node("agent", agent_node)
graph.add_node("search", search_node)
graph.add_node("check", check_node)

# 精确控制：根据 check 结果决定循环或结束
graph.add_edge("agent", "search")
graph.add_edge("search", "check")
graph.add_conditional_edges("check", check_result,
    {"continue": "agent", "end": END})

app = graph.compile()
# 优点：循环条件精确可控，不是硬限制
```

---

## 五、应用场景对比：该选哪个

### 5.1 选 LangChain 的场景

| 场景 | 原因 |
|------|------|
| **RAG 应用** | 检索 → 生成，固定流程，不需要循环 |
| **问答机器人** | 用户问 → LLM 答，简单线性 |
| **文档处理** | 读文档 → 提取 → 输出，固定步骤 |
| **快速原型** | 上手快，组件多，适合验证想法 |
| **单轮任务** | 一次调用就完成，不需要多步骤决策 |

**典型 LangChain 代码（RAG）**：

```python
from langchain_openai import ChatOpenAI
from langchain_community.vectorstores import Chroma
from langchain.chains import RetrievalQA

# 用 LangChain 做 RAG，三行搞定
llm = ChatOpenAI(model="gpt-4o")
vectorstore = Chroma.from_documents(docs, embeddings)
qa = RetrievalQA.from_chain_type(llm, retriever=vectorstore.as_retriever())

answer = qa.run("什么是 Agent？")
```

### 5.2 选 LangGraph 的场景

| 场景 | 原因 |
|------|------|
| **真正的 Agent** | 需要 ReAct 循环（思考→执行→观察→再思考） |
| **多步骤决策** | 执行到某一步后，需要判断下一步做什么 |
| **复杂工作流** | 有分支、有并行、有循环 |
| **多 Agent 协作** | 多个 Agent 互相配合 |
| **需要状态管理** | 要追踪"做了什么"、"进度如何" |

**典型 LangGraph 代码（Agent）**：

```python
from langgraph.graph import StateGraph, END
from langgraph.prebuilt import create_react_agent

# 用 LangGraph 做真正的 Agent
class AgentState(TypedDict):
    messages: list
    tools_result: dict

def should_continue(state):
    # 精确判断：任务是否完成
    if state["tools_result"]["complete"]:
        return "end"
    return "continue"

graph = StateGraph(AgentState)
graph.add_node("agent", agent_node)
graph.add_node("tools", tools_node)

graph.add_edge("agent", "tools")
graph.add_conditional_edges("tools", should_continue,
    {"continue": "agent", "end": END})

app = graph.compile()
```

### 5.3 选型决策树

```
你的需求是什么？
│
├─ 固定流程、单次调用（如 RAG、问答）
│   → 选 LangChain
│
├─ 需要循环执行（如 Agent 多轮决策）
│   → 选 LangGraph
│
├─ 需要根据结果选择不同路径
│   → 选 LangGraph
│
├─ 需要多个 Agent 协作
│   → 选 LangGraph 或 CrewAI
│
├─ 快速验证想法
│   → 先用 LangChain，复杂了再迁移到 LangGraph
│
└─ 生产级复杂系统
    → LangGraph + LangChain 组件配合使用
```

---

## 六、最佳实践：两者配合使用

LangGraph 和 LangChain 不是竞争关系，而是**配合关系**：

```
LangChain 提供"零件"：
- LLM 连接器（ChatOpenAI、ChatAnthropic）
- 工具定义（@tool 装饰器）
- 向量检索器
- 文档加载器

LangGraph 定义"组装方式"：
- 怎么让 Agent 循环执行
- 怎么根据结果选择路径
- 怎么管理状态
```

**配合使用的典型代码**：

```python
from langchain_openai import ChatOpenAI          # LangChain 组件
from langchain_community.tools import Tool       # LangChain 组件
from langgraph.graph import StateGraph, END      # LangGraph 编排

# 用 LangChain 定义零件
llm = ChatOpenAI(model="gpt-4o")
search_tool = Tool(name="search", func=search, description="搜索")

# 用 LangGraph 定义流程
graph = StateGraph(AgentState)
graph.add_node("agent", lambda s: llm.invoke(s["messages"]))
graph.add_node("tool", lambda s: search_tool.invoke(s["tool_input"]))
...
```

---

## 七、生态对比

| 生态组件 | LangChain | LangGraph |
|----------|-----------|-----------|
| **文档** | python.langchain.com/docs | langchain-ai.github.io/langgraph |
| **调试工具** | LangSmith | LangGraph Studio |
| **部署** | LangServe | LangGraph Platform |
| **社区** | GitHub 90k+ Star | GitHub 50k+ Star |
| **教程** | 官方教程丰富 | 官方教程 + LangGraph Mastery Course |

---

## 八、总结：一句话记住两者的区别

| 框架 | 一句话定义 |
|------|-----------|
| **LangChain** | 给你砖块、水泥、门窗——各种 LLM 应用组件 |
| **LangGraph** | 教你怎么画房子的结构图——定义组件的组装流程 |

**什么时候用 LangChain**：固定流程、单次调用、快速原型。

**什么时候用 LangGraph**：需要循环、需要分支、需要状态管理、真正的 Agent。

**最佳方案**：两者配合使用——LangChain 提供组件，LangGraph 定义流程。

---

## 参考资料

- [LangChain 官方文档](https://python.langchain.com/docs/)
- [LangGraph 官方文档](https://langchain-ai.github.io/langgraph/)
- [LangGraph Origins - Harrison Chase 演讲](https://www.youtube.com/watch?v=Hilp4F9dtRw)
- [LangGraph 0.3 Released](https://medium.com/@ankushksinghal/langgraph-0-3-released-7bc72a5b86a2)
- [LangGraph vs LangChain: 6 Key Differences](https://www.codecademy.com/resources/blog/langgraph-vs-langchain/)