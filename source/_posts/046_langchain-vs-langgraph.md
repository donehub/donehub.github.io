---
title: LangChain 与 LangGraph 的 Agent 架构演进
date: 2024-12-13
updated: 2026-02-18
tags: AI Agent
categories: AI
---

LangChain 和 LangGraph 是目前 LLM 应用开发领域使用最广泛的两个框架。很多开发者对两者的定位和适用场景感到困惑：什么时候用 LangChain，什么时候用 LangGraph，能不能一起用？这篇文章从技术本质、设计动机和实际应用三个角度做一次系统对比。

<!-- more -->

## 先说结论

LangChain 是零件库，LangGraph 是组装图纸。

- **LangChain**：提供 LLM 连接器、工具定义、记忆系统、向量检索器等基础组件，用于组装一个 LLM 应用。
- **LangGraph**：定义组件之间的组装方式，包括循环、分支、状态传递和终止条件。

两者不是竞争关系，而是互补关系。LangChain 团队自己造了 LangGraph，专门解决 LangChain 原生 Agent 能力不足的问题。

## LangChain 的起源与发展

Harrison Chase 曾在 Robust Intelligence（AI 安全公司）和 McKinsey 工作，2022 年 10 月将 LangChain 作为开源项目发布到 GitHub。2023 年初 LangChain Inc. 正式成立并获得风险投资，从社区项目走向商业化运营。

LangChain 能快速崛起，核心原因是它在 ChatGPT 发布前就抓住了一个关键痛点：LLM 应用开发的碎片化。当时每个开发者都要自己解决模型 API 调用（OpenAI、Anthropic、Cohere 各家接口不同）、对话记忆管理、外部工具集成、文档切分与检索等问题。LangChain 把这些经验抽象成统一的标准化组件，开发者只需配置参数，不用重复造轮子。

| 时间 | 事件 | 影响 |
|------|------|------|
| **2022.10** | LangChain 开源发布 | GitHub 迅速获得数千 Star |
| **2022.12** | ChatGPT 发布，LLM 应用需求爆发 | LangChain 成为首选框架 |
| **2023.01** | LangChain Inc. 成立，获风险投资 | 商业化运营 |
| **2023.03** | 推出 LCEL（LangChain Expression Language） | 链式调用更简洁 |
| **2023.06** | LangSmith 发布 | 可观测性平台 |
| **2023.10** | LangServe 发布 | 快速部署 API |
| **2024.01** | LangGraph 发布 | 解决 Agent 循环问题 |

LangChain 的组件体系覆盖了 LLM 应用开发的各个环节。Models 负责连接各类大模型，Prompts 管理提示词模板，Memory 提供对话记忆能力，Tools 封装外部工具调用，Chains 将多个步骤串联成调用链，Agents 基于 LLM 决策调用工具，Retrieval 支撑 RAG 场景的文档检索，Output Parser 处理模型输出格式化，Document Loaders 对接各类数据源。

## Chain 模型的能力边界

LangChain 的核心抽象是 Chain（链），把多个步骤串起来线性执行：

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

这种设计简单直观，上手快，组件生态完善，非常适合 RAG、简单问答和固定流程的场景。但它有一个根本性的限制：无法循环执行。Agent 需要 ReAct 循环（思考 → 执行 → 观察 → 再思考），而 LangChain 的链只能单向流动。加上无法根据中间结果动态选择路径、状态管理与执行流程脱节这两个问题，LangChain 在做复杂 Agent 时显得力不从心。

## LangGraph 解决什么问题

LangChain 提供了 `AgentExecutor` 来支持 Agent 场景，实际使用中暴露出三个核心问题。

第一个问题是无法真正循环。LangChain 的链是线性的，从 A 到 B 到 C 然后结束。Agent 需要的是 ReAct 循环：思考 → 执行 → 观察 → 再思考 → 再执行，直到任务完成。用 AgentExecutor 只能靠 `max_iterations` 硬限制循环次数，本质上是模拟而非原生支持。第二个问题是无法控制流程分支。Agent 执行到某一步后，可能需要根据结果走不同的路径：成功了就结束，失败了就重试，信息不够就再去搜索。LangChain 的链做不到这一点。第三个问题是状态管理混乱。Agent 需要追踪"我刚才做了什么"和"当前进度如何"，但 LangChain 的 Memory 组件是独立的，无法与执行流程绑定。

2024 年第一季度，LangChain 团队推出 LangGraph，核心思路是用状态机加图结构来替代线性链。LangGraph 的核心抽象是 StateGraph，用节点表示计算步骤，用边定义节点之间的流转关系，条件边则根据当前状态动态决定下一步走向。

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

LangGraph 针对上述三个问题分别给出了原生解决方案。循环执行方面，图的边可以指回之前的节点，天然支持 ReAct 循环。流程分支方面，`add_conditional_edges` 根据状态值选择不同路径，精确可控。状态管理方面，State 在节点间自动传递，与执行流程深度绑定。

| 时间 | 事件 | 影响 |
|------|------|------|
| **2024.Q1** | LangGraph 发布 | 解决 Agent 循环问题 |
| **2024.06** | LangGraph Studio 发布 | 可视化调试工具 |
| **2024.08** | 支持多 Agent 协作 | 复杂系统必备 |
| **2025.01** | LangGraph 0.3 发布 | 流式输出、多租户、改进调试 |

## 技术本质差异

| 维度 | LangChain | LangGraph |
|------|-----------|-----------|
| **核心抽象** | Chain（链） | StateGraph（状态图） |
| **执行模式** | 线性执行，单向流动 | 循环 + 分支执行，可回环 |
| **状态管理** | 独立 Memory 组件 | State 在节点间自动传递 |
| **流程控制** | 固定顺序，无法回头 | 条件分支、并行、循环 |
| **适用场景** | RAG、问答、固定流程 | Agent、多步骤决策 |

LangChain 的执行模型是单向链式流动：输入 → Prompt → LLM → Parser → 输出，每一步执行一次，无法回头。LangGraph 的执行模型是图结构：Start → Agent 思考 → 选择 Tool A 或 Tool B 执行 → Check 检查结果 → 根据条件决定继续循环回到 Agent 或终止。State 在整个图中自动传递，每个节点都能读取和修改当前状态。

## 代码层面的对比

以"让 Agent 搜索信息，如果信息不够就再搜索"为例，两种实现方式的差异很直观。

LangChain 方案用 `AgentExecutor` 模拟循环，只能靠 `max_iterations` 硬限制，无法精确控制什么时候结束：

```python
# 只能模拟循环，用 max_iterations 限制
from langchain.agents import AgentExecutor

agent_executor = AgentExecutor(
    agent=agent,
    tools=[search_tool],
    max_iterations=5,  # 强制限制循环次数
    verbose=True
)
```

LangGraph 方案通过条件边精确控制循环条件，根据实际搜索结果决定是继续搜索还是结束：

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
```

前者是暴力限制，后者是精确控制，这是两种架构在设计理念上的根本差异。

## 场景选型

| 场景 | 推荐 | 原因 |
|------|------|------|
| **RAG 应用** | LangChain | 检索 → 生成，固定流程，不需要循环 |
| **问答机器人** | LangChain | 用户问 → LLM 答，简单线性 |
| **文档处理** | LangChain | 读文档 → 提取 → 输出，固定步骤 |
| **快速原型** | LangChain | 上手快，组件多，适合验证想法 |
| **真正的 Agent** | LangGraph | 需要 ReAct 循环（思考 → 执行 → 观察 → 再思考） |
| **多步骤决策** | LangGraph | 执行到某一步后需要判断下一步做什么 |
| **复杂工作流** | LangGraph | 有分支、有并行、有循环 |
| **多 Agent 协作** | LangGraph | 多个 Agent 互相配合 |
| **生产级复杂系统** | 两者配合 | LangGraph 编排流程，LangChain 提供组件 |

选型的核心判断标准很简单：如果执行流程是固定的、一次调用就能完成，用 LangChain；如果需要循环、分支或状态追踪，用 LangGraph。快速验证阶段可以先用 LangChain 跑通逻辑，等流程复杂了再迁移到 LangGraph，迁移成本不高，因为 LangGraph 直接复用 LangChain 的组件。

## 两者配合使用

实际项目中，LangChain 和 LangGraph 通常是搭配使用。LangChain 提供 LLM 连接器（ChatOpenAI、ChatAnthropic）、工具定义（`@tool` 装饰器）、向量检索器和文档加载器等基础组件，LangGraph 负责编排这些组件的执行流程，定义 Agent 的思考循环、条件分支和状态管理。

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

这种分工很清晰：LangChain 解决"用什么组件"，LangGraph 解决"怎么组装和流转"。

## 生态对比

| 生态组件 | LangChain | LangGraph |
|----------|-----------|-----------|
| **文档** | python.langchain.com/docs | langchain-ai.github.io/langgraph |
| **调试工具** | LangSmith | LangGraph Studio |
| **部署** | LangServe | LangGraph Platform |
| **社区** | GitHub 90k+ Star | GitHub 50k+ Star |
| **教程** | 官方教程丰富 | 官方教程 + LangGraph Mastery Course |

## LangGraph 1.0 的发布与现状

2026 年 2 月 18 日，LangChain 团队正式宣布 LangGraph 1.0 发布。这个版本距 LangGraph 首次发布已经过去了整整两年，标志着它从一个实验性项目走向了生产级稳定版本。LangGraph 1.0 并不是推倒重来，而是在过去两年积累的基础上做了一次系统性的收敛和固化。

LangGraph 1.0 的核心变化集中在三个方面。第一是正式弃用了 0.2 版本中引入的 Node 类，原因是开发者在实际使用中普遍觉得它增加了心智负担，收益不明显，团队决定回归更简洁的函数式 API 设计。第二是正式弃用了 langchain 集成包，LangGraph 从一开始就设计为可以与任何 LLM 或框架配合使用，不再需要依赖 langchain 包，团队建议用户迁移到 langchain-openai、langchain-anthropic 等模型提供商包，或者直接使用 LangGraph 的 BaseLanguageChatModel 接口。第三是正式弃用了 langgraph.prebuilt 中的 ToolMessage，统一使用 langchain_core.messages.ToolMessage。

在平台侧，LangGraph 1.0 的配套工具也做了大规模调整。LangGraph Platform 移除了所有 LangGraph 0.2 时期引入的已弃用 API，LangGraph Server 的 API 版本从 2024-10-18 切换到 2025-03-19。LangGraph Studio（现更名为 LangGraph Workbench）移除了对 LangGraph Server 0.2 和 0.3 的支持。LangGraph SDK 移除了所有已弃用的 API 和旧的 2024 年 API 版本，同时修复了 Python SDK 中 `astream_events` 和 `stream_events` 的返回值类型错误。

另一个值得关注的变化是 langchain-openai 包的重大版本更新。0.3.x 版本被正式弃用，推荐使用 0.4.x 版本。0.4.x 是原生的 Pydantic 2 版本，不再依赖 Pydantic 1.x 的兼容层，同时移除了 `langchain_core` 的依赖，用户需要单独安装。这些变更反映了 LangChain 生态正在逐步摆脱 Pydantic 1.x 的历史包袱。

从社区反响来看，LangGraph 1.0 的评价呈现两极化。正面评价集中在 API 的稳定性和生产可靠性上，认为经过两年打磨后 LangGraph 终于成为一个可以安心用于生产环境的框架。负面评价则主要围绕迁移成本和抽象复杂度，部分开发者认为频繁的 Breaking Change 增加了维护负担，而 LangGraph 的学习曲线相比更轻量的替代方案（如 PydanticAI、Smolagents）显得陡峭。也有观点指出 LangGraph 的"状态图"抽象对于中等复杂度的 Agent 场景来说有些过度设计。

对于正在使用 LangGraph 0.3 的团队，LangGraph 1.0 的迁移路径比较清晰。Node 类的迁移只需将类方法改为普通函数，签名不变。langchain 集成包的迁移需要切换到模型提供商专用包或直接使用 BaseLanguageChatModel 接口。ToolMessage 的迁移是简单的类名替换。这些变更的破坏性不算大，但需要逐一排查代码中的引用点。

| 时间 | 版本 | 关键变化 |
|------|------|----------|
| **2024.01** | LangGraph 0.1 发布 | 引入 StateGraph，解决 Agent 循环问题 |
| **2024.06** | LangGraph Studio 发布 | 可视化调试工具 |
| **2024.08** | 支持多 Agent 协作 | 复杂系统必备 |
| **2025.01** | LangGraph 0.3 发布 | 流式输出、多租户、改进调试 |
| **2026.02** | LangGraph 1.0 发布 | API 稳定化，弃用 Node 类和 langchain 集成包 |

LangGraph 1.0 的发布意味着 LangChain 团队在 Agent 框架这条路线上做出了明确的选择：用状态图作为核心抽象，用 Pydantic 2 作为数据层基础，用模型提供商包替代大一统的集成层。这套技术栈在未来一两年内预计会保持稳定，对于已经在用 LangGraph 的团队来说是一个好消息，不用再担心频繁的 Breaking Change。对于还在观望的团队，现在是一个比较好的入场时机，API 已经收敛，文档也趋于完善。

## 参考资料

- [LangChain 官方文档](https://python.langchain.com/docs/)
- [LangGraph 官方文档](https://langchain-ai.github.io/langgraph/)
- [LangGraph Origins - Harrison Chase 演讲](https://www.youtube.com/watch?v=Hilp4F9dtRw)
- [LangGraph 0.3 Released](https://medium.com/@ankushksinghal/langgraph-0-3-released-7bc72a5b86a2)
- [LangGraph vs LangChain: 6 Key Differences](https://www.codecademy.com/resources/blog/langgraph-vs-langchain/)
