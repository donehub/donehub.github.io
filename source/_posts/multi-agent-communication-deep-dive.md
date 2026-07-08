---
title: Multi-Agent 通信深度解析
date: 2026-05-30
categories: AI
tags: [Multi-Agent 通信]
---

## 背景

当系统从单个 Agent 进化到多个 Agent 协作时，一个核心问题就会浮出水面：Agent 之间怎么通信？

通信设计直接决定了你的 Multi-Agent 系统是高效协作还是混乱互怼。

打个比方：单个 Agent 像一个独立工作的程序员，能力再强也有天花板。Multi-Agent 就像一个开发团队——你需要设计好团队的沟通机制：谁向谁汇报？用什么格式交流？出了问题怎么兜底？这些决策决定了团队是 1+1>2 还是 1+1<0。

这篇文章会系统性地拆解 Multi-Agent 通信的三个核心维度：拓扑（谁跟谁聊）、机制（数据怎么流）、协议（聊什么格式）**，并深入分析工程落地中的失败模式和成本控制。

---

## 一、本质问题

Multi-Agent 的通信，本质上不是"数据包交换"，而是"认知语义的传递"与"任务状态的对齐"。

传统分布式系统里，通信关心的是：HTTP 还是 gRPC？JSON 还是 Protobuf？超时时间设多少？这些当然重要，但在 Multi-Agent 系统里，它们只是基础设施层面的问题。

真正让 Multi-Agent 通信变得独特且困难的，是以下三个问题：

| 层次 | 传统分布式系统 | Multi-Agent 系统 |
|------|--------------|-----------------|
| 语义层 | 结构化数据，格式固定 | 自然语言 + 推理链，语义模糊 |
| 状态层 | 无状态或简单状态机 | 复杂的认知状态（信念、意图、置信度） |
| 容错层 | 重试 + 降级 | 语义漂移检测 + 认知纠偏 |

比如：当 Agent A 告诉 Agent B "这个 Bug 很严重"时，B 需要理解的不只是"严重"这两个字，还包括 A 判断严重的依据、影响的范围、以及 A 对修复难度的预判。这种心智模型的传递，是传统 RPC 调用里不存在的。

基于这一点，我们再来看具体的通信设计。

---

## 二、通信拓扑：谁跟谁聊？

拓扑设计是架构的第一个决策。它决定了系统的耦合度、容错性和扩展上限。

### 2.1 中心化编排（Orchestrator / Supervisor）

这是最常见的模式，也最容易理解和实现。

```
                ┌─────────────────┐
                │  Supervisor Agent│
                │  （任务调度中心）  │
                └───┬────┬────┬───┘
                    │    │    │
           ┌────────┘    │    └────────┐
           ▼             ▼             ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐
    │ Researcher │ │  Coder     │ │  Reviewer  │
    │   Agent    │ │   Agent    │ │   Agent    │
    └────────────┘ └────────────┘ └────────────┘
```

**核心逻辑**：一个 Supervisor 负责接收任务、拆解子任务、分配给 Worker Agent、收集结果并汇总。Worker 之间不直接通信，所有信息流都经过 Supervisor 中转。

**生活类比**：这就像一个项目经理带团队。需求先交给 PM，PM 拆分任务分给开发、测试、设计，最后由 PM 汇总交付。开发人员不需要直接跟测试沟通——PM 是信息枢纽。

**优势**：
- **逻辑清晰**：控制流一目了然，容易调试
- **可观测性强**：Supervisor 知道全局状态，方便监控和日志
- **易于加入 Human-in-the-loop**：人类可以在 Supervisor 层做审批

**致命缺陷**：
- **单点瓶颈**：Supervisor 挂了，整个系统瘫痪
- **性能天花板**：所有通信都经过 Supervisor，吞吐量受限
- **上下文爆炸**：Supervisor 需要维护所有 Worker 的状态，上下文窗口压力巨大

**适用场景**：任务流程明确、Agent 数量较少（3-5 个）的场景。比如"搜索 → 分析 → 生成报告"这种线性流水线。

### 2.2 去中心化协作（Peer-to-Peer / 群聊模式）

所有 Agent 地位平等，直接互相通信，没有中心节点。

```
    ┌────────────┐     ┌────────────┐
    │  Agent A   │◄───►│  Agent B   │
    └─────┬──────┘     └─────┬──────┘
          │                   │
          │    ┌────────────┐ │
          └───►│  Agent C   │◄┘
               └────────────┘
```

**核心逻辑**：每个 Agent 都能发起对话、响应请求、推荐下一个处理者。没有谁是"老板"，大家通过协商决定谁来干活。

**生活类比**：这像一个开源项目的维护者社区。每个人都能提 Issue、Review PR、Merge 代码，没有绝对的上下级关系。

**优势**：
- **扩展性强**：新增 Agent 不需要修改中心节点
- **灵活路由**：Agent 之间可以动态发现、动态协作
- **无单点故障**：某个 Agent 挂了，其他 Agent 可以继续工作

**致命缺陷**：
- **无限循环风险**：A 让 B 做，B 觉得该 C 做，C 又踢回给 A → 死循环
- **上下文爆炸**：群聊消息指数级增长，每个 Agent 都要维护所有对话历史
- **收敛性差**：没有"裁判"，很难判断任务什么时候算完成

**防循环的工程手段**：

```python
# 1. 设置最大轮次
groupchat = GroupChat(max_round=10)

# 2. 加入"终止条件"检测
def should_terminate(messages):
    last_msgs = messages[-3:]
    # 如果最近 3 条消息都在重复相同观点，终止
    return len(set(m["content"] for m in last_msgs)) == 1

# 3. 引入"主持人"角色做仲裁
moderator = AssistantAgent(
    name="Moderator",
    system_message="你是讨论主持人。当讨论陷入循环时，做出最终决策。"
)
```

**适用场景**：头脑风暴、多角色辩论、代码审查等需要**多视角碰撞**的场景。

### 2.3 层次化混合（Hierarchical）

现实中的大型系统，往往是两者的结合——分层。

```
              ┌───────────────┐
              │   CEO Agent   │
              │  （战略规划）   │
              └───┬───────┬───┘
                  │       │
        ┌─────────▼─┐   ┌─▼──────────┐
        │ VP-研发    │   │ VP-运营     │
        │ （中层管理）│   │ （中层管理） │
        └──┬────┬───┘   └──┬────┬────┘
           │    │           │    │
         ┌─▼─┐┌─▼─┐      ┌─▼─┐┌─▼─┐
         │Dev││QA │       │Mkt││CS │
         └───┘└───┘       └───┘└───┘
```

**核心逻辑**：顶层 Agent 做任务拆解和战略规划，中层 Agent 做子任务协调，底层 Agent 执行具体操作。每层只跟相邻层直接通信。

**生活类比**：这就是公司的组织架构。CEO 定方向，VP 拆目标，一线执行。你不会希望 CEO 直接管到实习生——层级是管理复杂度的利器。

**关键设计原则**：

| 原则 | 说明 |
|------|------|
| **信息压缩** | 每层向上汇报时，要压缩信息。底层报"3 个 API 报错"，中层报"接口层有 3 个异常"，顶层只需要知道"系统存在稳定性风险" |
| **上下文隔离** | 每层只维护自己需要的上下文，避免全局状态膨胀 |
| **委托边界** | 明确每层的决策权限。底层不需要请示中层就能做的小事，就不要上报 |

**适用场景**：大型企业级系统，如金融风控（合规层 → 策略层 → 执行层）、智能客服（路由层 → 业务层 → 工具层）。

### 2.4 三种拓扑对比

| 维度 | 中心化编排 | 去中心化协作 | 层次化混合 |
|------|-----------|-------------|-----------|
| **耦合度** | 高（Worker 依赖 Supervisor） | 低（Agent 独立） | 中（层级内紧耦合，层级间松耦合） |
| **容错性** | 差（单点故障） | 好（无单点） | 中（某层故障可降级） |
| **可观测性** | 好（中心节点全局可见） | 差（信息分散） | 中（分层可见） |
| **扩展性** | 差（中心节点是瓶颈） | 好（动态加入） | 好（横向+纵向扩展） |
| **实现复杂度** | 低 | 高 | 中 |
| **适用 Agent 数** | 3-5 个 | 5-10 个 | 10+ 个 |

---

## 三、通信机制：数据怎么流动？

拓扑解决的是"谁跟谁聊"，机制解决的是"数据怎么从 A 到 B"。

### 3.1 基于共享状态（State-Based）

这是 LangGraph 的核心设计哲学，也是目前最流行的方案。

**核心思想**：Agent 之间不直接发送消息，而是共同读写一个全局状态对象。前一个 Agent 更新状态，后一个 Agent 读取状态变化，间接完成通信。

```
┌──────────┐       ┌──────────────┐       ┌──────────┐
│ Agent A  │──写──►│  Global State │◄──读──│ Agent B  │
└──────────┘       │  {            │       └──────────┘
                   │   task: "...", │
┌──────────┐       │   result: "...",│      ┌──────────┐
│ Agent C  │──写──►│   status: "..."│◄──读──│ Agent D  │
└──────────┘       │  }            │       └──────────┘
                   └──────────────┘
```

**生活类比**：想象一个共享的 Google Docs。团队成员不需要开会讨论，直接打开文档看最新内容，需要修改就直接编辑。文档本身就是通信媒介。

**优势**：

| 优势 | 说明 |
|------|------|
| **天然支持断点续传** | 状态持久化到数据库，崩溃后可以从上次状态恢复 |
| **Human-in-the-loop 友好** | 人类可以查看和修改中间状态，再让 Agent 继续 |
| **可观测性强** | 每次状态变更都有记录，方便调试和审计 |
| **避免消息丢失** | 状态是幂等更新的，不存在"消息丢了"的问题 |

**注意事项**：
- **状态冲突**：如果两个 Agent 并发修改同一字段，需要冲突解决策略（如 last-write-wins、merge 函数）
- **状态膨胀**：长时间运行的任务，状态会越来越大，需要定期压缩或归档

### 3.2 基于消息队列（Message Queue / Event Bus）

当你的 Agent 系统需要跨语言、跨进程、跨机器通信时，共享状态就不够用了。这时候需要引入消息中间件。

```
┌───────────┐                    ┌───────────┐
│ Python     │                    │ Java       │
│ Research   │                    │ Recommend  │
│ Agent      │                    │ Agent      │
└─────┬──────┘                    └─────┬──────┘
      │ 发布                             │ 订阅
      ▼                                 ▼
┌───────────────────────────────────────────────┐
│              消息队列 / 事件总线                 │
│         (Kafka / RabbitMQ / Redis Streams)    │
│                                               │
│  Topic: research.results                      │
│  Topic: recommendation.requests               │
│  Topic: code.generation.tasks                 │
└───────────────────────────────────────────────┘
      ▲                                 ▲
      │ 订阅                             │ 发布
┌─────┴──────┐                    ┌─────┴──────┐
│ Python     │                    │ Python     │
│ Coder      │                    │ Summarizer │
│ Agent      │                    │ Agent      │
└────────────┘                    └────────────┘
```

**生活类比**：这像公司的邮件系统 + 公告板。你需要别的团队配合时，发邮件（发布消息）到对方的收件箱（Topic），对方在自己方便的时候查看并处理（异步消费）。不需要面对面沟通。

**与共享状态的核心区别**：

| 维度 | 共享状态 | 消息队列 |
|------|---------|---------|
| **通信模式** | 隐式（通过读写状态） | 显式（发送/接收消息） |
| **耦合方式** | 数据耦合（共享同一份状态） | 消息耦合（约定消息格式） |
| **时效性** | 最终一致 | 可精确控制（同步/异步） |
| **跨语言** | 困难（需要共享运行时） | 天然支持（消息是通用格式） |
| **失败恢复** | 状态快照恢复 | 消息重发（ACK 机制） |
| **适用场景** | 单进程、强一致性 | 多进程/多语言、异步解耦 |

### 3.3 基于共享向量记忆（Shared Memory / RAG）

这是一种隐式通信方式：Agent 之间不直接交换数据，而是通过一个共享的向量知识库来间接协作。

```
┌──────────┐                    ┌──────────┐
│ Agent A  │──向量化写入────────│ 向量数据库 │
│(信息生产者)│                   │(共享记忆)  │
└──────────┘                    └─────┬────┘
                                      │
                                语义检索 │
                                      │
                                ┌─────▼────┐
                                │ Agent B  │
                                │(信息消费者)│
                                └──────────┘
```

**核心逻辑**：Agent A 将中间推理结果、观察到的事实、学到的经验向量化后存入向量库。Agent B 在需要时，通过语义检索主动"拉取"相关信息。

**生活类比**：这像公司的知识库（Confluence / Notion）。前人在项目结束后把经验写成文档，后来的人遇到类似问题时去搜索，找到相关文档后借鉴。写文档的人和读文档的人不需要直接沟通。

**适用场景**：
- **长期记忆**：Agent 需要记住之前学到的东西
- **跨任务知识复用**：不同任务之间共享经验
- **隐式协作**：Agent 之间不需要实时交互，各自独立工作

**关键设计点**：

| 设计点 | 建议 |
|--------|------|
| **元数据过滤** | 一定要给向量加元数据（来源 Agent、时间戳、类型），否则检索结果会混入无关信息 |
| **遗忘机制** | 不能只增不减，需要定期清理过期或低相关度的记忆 |
| **冲突检测** | 不同 Agent 可能写入矛盾的信息，需要版本控制或置信度排序 |

---

## 四、通信协议：聊什么格式？

拓扑和机制解决的是"通道"问题，协议解决的是"内容"问题——Agent 之间传什么格式的消息，才能确保对方准确理解？

### 4.1 纯文本通信（最原始，也最脆弱）

```python
# Agent A 发给 Agent B 的消息
message = "帮我查一下这个 Bug，我觉得可能是数据库连接池的问题，你看看是不是 max_connections 设太小了"

# Agent B 收到的就是这段自然语言，需要自己解析意图
# 问题：B 怎么知道 A 是要"查询"还是"修复"？"我觉得"说明 A 的置信度不高？
```

**问题**：
- 意图不明确（是要查询？修复？还是只是讨论？）
- 没有结构，下游 Agent 解析困难
- 无法传递置信度、优先级等元信息

### 4.2 结构化工具调用（Structured Tool Call）

这是目前业界的主流做法。把 Agent 之间的通信标准化为函数调用格式，充分利用 LLM 原生的 Function Calling 能力。

```json
{
  "tool_call_id": "call_abc123",
  "name": "delegate_to_agent",
  "arguments": {
    "target_agent": "code_reviewer",
    "task_type": "review",
    "payload": {
      "code": "def calculate_price(...): ...",
      "review_focus": "security",
      "priority": "high"
    },
    "context": {
      "parent_task": "修复价格计算的安全漏洞",
      "requester_agent": "code_generator",
      "deadline": "5min"
    }
  }
}
```

**核心优势**：
- **意图明确**：`name` 字段直接说明要做什么
- **参数结构化**：下游 Agent 不需要"猜"参数
- **可追踪**：`tool_call_id` 让每次调用都可溯源
- **LLM 原生支持**：直接利用 Function Calling，不需要额外的解析层

### 4.3 心智模型传递（Theory-of-Mind / CoT 共享）

这是进阶玩法。不只要传递"结果"，还要传递"推理过程"和"置信度"。

```json
{
  "from": "research_agent",
  "to": "decision_agent",
  "content": "推荐使用 Redis 作为缓存层",
  "reasoning": {
    "steps": [
      "分析了数据访问模式：读多写少，比例约 100:1",
      "评估了数据一致性要求：允许秒级延迟",
      "对比了 Redis 和 Memcached：Redis 支持更丰富的数据结构",
      "考虑了团队技术栈：后端团队有 Redis 使用经验"
    ],
    "assumptions": [
      "日活用户不超过 100 万",
      "缓存数据不需要强一致性"
    ],
    "alternatives_considered": [
      {"option": "Memcached", "rejected_reason": "数据结构支持有限"},
      {"option": "本地缓存", "rejected_reason": "多实例部署，本地缓存无法共享"}
    ]
  },
  "confidence": 0.82,
  "risk_assessment": {
    "level": "low",
    "details": "Redis 单点故障风险可通过 Sentinel 解决"
  }
}
```

**为什么这很重要？**

因为下游 Agent 需要根据置信度来决定下一步行动：

```python
def decision_agent(received_message):
    confidence = received_message["confidence"]

    if confidence >= 0.8:
        # 高置信度，直接采纳
        return execute(received_message["content"])
    elif confidence >= 0.5:
        # 中等置信度，交给另一个 Agent 复核
        return delegate_to("reviewer_agent", received_message)
    else:
        # 低置信度，要求重新调研
        return delegate_to("research_agent", {
            "action": "redo_research",
            "feedback": received_message["reasoning"]
        })
```

**生活类比**：这像医生会诊。一个医生不能只说"我觉得是肺炎"，他需要说"基于 X 光片和血常规结果（推理依据），我有 80% 的把握是肺炎（置信度），但也考虑了支气管炎的可能性（备选方案），建议再做 CT 确认（下一步建议）"。

### 4.4 标准化 Agent 协议（A2A / MCP）

目前最重要的行业趋势之一：Agent 通信协议的标准化。

两个值得关注的协议：

| 协议 | 提出者 | 定位 | 核心概念 |
|------|--------|------|---------|
| **MCP**（Model Context Protocol） | Anthropic | Agent ↔ 工具/数据源 | Resource、Tool、Prompt |
| **A2A**（Agent-to-Agent） | Google | Agent ↔ Agent | Task、Artifact、Message、StatusUpdate |

**MCP 解决的是**：Agent 怎么调用外部工具和数据源。它定义了一套标准接口，让不同的 LLM 应用能以统一方式访问工具，类似于 USB-C 之于外设。

**A2A 解决的是**：不同平台、不同供应商的 Agent 之间怎么互通。它定义了 Agent Card（能力描述）、Task（任务生命周期）、Artifact（产出物）等标准对象。

```
A2A 协议核心对象：

Agent Card:
  - name: "代码审查 Agent"
  - skills: ["code_review", "security_audit"]
  - endpoint: "https://api.example.com/a2a"

Task:
  - id: "task-123"
  - status: "submitted" → "working" → "completed" / "failed"
  - messages: [输入消息列表]
  - artifacts: [输出产物列表]

Artifact:
  - type: "code_review_result"
  - content: {...}
  - metadata: {...}
```

**为什么标准化很重要？**

想象一下这个场景：你的公司用 LangChain 写了 5 个 Agent，合作伙伴用 AutoGen 写了 3 个 Agent，供应商用自研框架写了 2 个 Agent。如果没有标准协议，每两个 Agent 之间都需要写一个"翻译层"——N 个 Agent 需要 N×(N-1)/2 个适配器。有了标准协议，所有 Agent 只需要实现协议接口，N 个 Agent 只需要 N 个适配器。

---

## 五、通信的失败模式：怎么确保"聊不崩"？

这是工程落地中最关键、也最容易被忽视的部分。你的系统在 Demo 里跑得很好，一上生产就炸，大概率就是通信失败处理没做好。

### 5.1 语义漂移（Semantic Drift）

**问题**：Agent A 的意图在传递过程中被曲解，Agent B 理解的意思和 A 想表达的不一样。

```
Agent A: "优化这个函数的性能"（意图：降低时间复杂度）
    ↓ 传递
Agent B: "优化函数命名和代码风格"（理解：改善可读性）
    ↓ 结果
返回了命名更规范但性能没变的代码
```

**解决方案**：
- **意图确认机制**：Agent B 在执行前先回述自己对任务的理解，让 A 确认
- **结构化任务描述**：用 schema 定义任务的"验收标准"，而不是纯自然语言

```python
# 结构化的任务描述，避免语义漂移
task = {
    "action": "optimize",
    "target": "calculate_price",
    "objective": "reduce_time_complexity",  # 明确优化目标
    "metric": "execution_time",
    "current_value": "O(n^2)",
    "target_value": "O(n log n)",
    "constraint": "不改变函数签名和返回值"
}
```

### 5.2 上下文溢出（Context Overflow）

**问题**：多轮通信导致消息列表越来越长，超出 LLM 的上下文窗口限制。

```
Round 1: 2,000 tokens
Round 2: 4,500 tokens
Round 3: 9,000 tokens
Round 4: 18,000 tokens
Round 5: 35,000 tokens  ← 接近 GPT-4 的 32K 限制
Round 6: 💥 超出限制
```

**解决方案**：

| 策略 | 做法 | 优缺点 |
|------|------|--------|
| **滑动窗口** | 只保留最近 N 轮消息 | 简单，但会丢失早期重要信息 |
| **摘要压缩** | 定期将历史消息压缩成摘要 | 保留关键信息，但摘要本身消耗 Token |
| **分层记忆** | 短期记忆（最近消息）+ 长期记忆（向量化存储） | 效果最好，但实现复杂 |

```python
def compress_context(messages: list, max_tokens: int = 4000):
    """上下文压缩策略"""
    if count_tokens(messages) <= max_tokens:
        return messages

    # 1. 保留系统消息和最近 3 轮
    system_msgs = [m for m in messages if m["role"] == "system"]
    recent_msgs = messages[-6:]  # 最近 3 轮 = 6 条消息

    # 2. 中间的历史消息压缩成摘要
    old_msgs = messages[len(system_msgs):-6]
    summary = summarize(old_msgs)  # 用 LLM 生成摘要

    return system_msgs + [{"role": "system", "content": f"历史摘要：{summary}"}] + recent_msgs
```

### 5.3 死锁与活锁（Deadlock / Livelock）

**死锁**：Agent A 等待 Agent B 的结果，Agent B 等待 Agent C 的结果，Agent C 等待 Agent A 的结果 → 三个都卡住。

**活锁**：Agent A 和 B 互相传递任务，谁都不处理，一直踢皮球 → 系统一直在"忙"但没有进展。

```
死锁示例：
Agent A: "我需要 B 的分析结果才能给出建议"
Agent B: "我需要 C 的数据才能分析"
Agent C: "我需要 A 的建议才能确定数据范围"
→ 循环等待，无人能开始

活锁示例：
Agent A: "这个任务应该交给 B"
Agent B: "不，应该交给 A"
Agent A: "还是交给 B 吧"
Agent B: "不不不，A 更适合"
→ 无限循环，没有实际工作
```

**解决方案**：

```python
# 1. 全局超时机制
import asyncio

async def with_timeout(coro, timeout_seconds=30):
    try:
        return await asyncio.wait_for(coro, timeout=timeout_seconds)
    except asyncio.TimeoutError:
        return {"error": "timeout", "message": "任务执行超时"}

# 2. 循环检测
class LoopDetector:
    def __init__(self, max_repeats=3):
        self.history = []
        self.max_repeats = max_repeats

    def check(self, message):
        self.history.append(hash(message["content"]))
        if len(self.history) >= self.max_repeats * 2:
            # 检查最近 N 条是否重复
            recent = self.history[-self.max_repeats:]
            if len(set(recent)) == 1:
                return True  # 检测到循环！
        return False

# 3. 强制降级
def fallback_when_stuck(agents_in_loop):
    """当检测到死锁/活锁时，强制交给更高级的 Agent 处理"""
    return escalate_to_supervisor(
        task="检测到 Agent 间通信死锁，请人工介入",
        context=agents_in_loop
    )
```

### 5.4 错误传播（Error Propagation）

**问题**：一个 Agent 的输出错误，会导致下游所有 Agent 基于错误信息做出错误决策。

```
Agent A（数据收集）: 错误地认为 API 限额是 1000 次/小时（实际是 10000 次）
    ↓
Agent B（方案设计）: 基于"1000 次限额"设计了保守的缓存策略
    ↓
Agent C（代码实现）: 实现了不必要的复杂缓存逻辑
    ↓
结果: 过度设计，性能反而下降
```

**解决方案**：
- **置信度传递**：每个 Agent 标注自己输出的置信度，下游根据置信度决定采信程度
- **交叉验证**：关键决策让多个 Agent 独立给出答案，投票决定
- **溯源机制**：保留完整的推理链，出问题时可以逐级回溯

---

## 六、通信成本控制

每次 Agent 间的通信都不是免费的。架构师需要在"充分通信"和"成本控制"之间找平衡。

### 6.1 通信成本构成

| 成本项 | 说明 | 量级 |
|--------|------|------|
| **Token 消耗** | 每次通信的输入 + 输出 Token | 主要成本 |
| **API 延迟** | 每次 LLM 调用的网络延迟 | 0.5-5 秒/次 |
| **错误代价** | 一次错误通信导致的重做成本 | 可能数倍于正常成本 |

### 6.2 成本控制策略

**策略一：按需通信，不要全程直播**

```
❌ 差的做法：Agent A 的每一步都实时通知 Agent B
✅ 好的做法：Agent A 完成阶段性成果后再通知 Agent B

不是每想了一步就要同步，而是想清楚了一个完整方案再交流。
就像高效的团队协作——不需要每分钟站会，有阶段性产出时再同步。
```

**策略二：通信分级**

| 级别 | 方式 | 适用场景 | Token 消耗 |
|------|------|---------|-----------|
| **L1 轻量** | 结构化信号（状态码/枚举值） | "任务完成"、"需要帮助" | 极少 |
| **L2 标准** | 结果摘要 + 关键数据 | 阶段性汇报 | 中等 |
| **L3 完整** | 完整推理链 + 原始数据 | 关键决策、任务交接 | 高 |

不是所有通信都需要完整的推理链。简单的状态同步，一个枚举值就够了。

**策略三：缓存复用**

```python
# 缓存其他 Agent 的历史输出，避免重复请求
agent_output_cache = {}

def get_agent_output(agent_id: str, task_hash: str):
    cache_key = f"{agent_id}:{task_hash}"
    if cache_key in agent_output_cache:
        return agent_output_cache[cache_key]  # 命中缓存

    # 未命中，实际调用
    result = call_agent(agent_id, task_hash)
    agent_output_cache[cache_key] = result
    return result
```

---

## 七、实战选型指南

### 7.1 按场景选拓扑

```
你的 Agent 系统是什么场景？
│
├── 线性流水线（A → B → C）
│   └── 中心化编排（Supervisor 模式）
│
├── 多角色讨论/辩论
│   └── 去中心化协作（GroupChat 模式）
│
├── 大型复杂系统（>10 个 Agent）
│   └── 层次化混合（Hierarchical 模式）
│
└── 动态任务分配（不知道谁来做）
    └── 去中心化 + 竞争机制（Contract Net 协议）
```

### 7.2 按需求选机制

```
你的 Agent 在哪里运行？
│
├── 单进程 / 同一运行时
│   └── 共享状态（LangGraph State）
│
├── 多进程 / 跨语言
│   └── 消息队列（Redis Streams / Kafka）
│
├── 需要长期记忆
│   └── 共享向量记忆（Vector Store）
│
└── 以上都需要
    └── 混合方案（状态 + 消息队列 + 向量记忆）
```

### 7.3 按阶段选协议

```
你的项目处于什么阶段？
│
├── MVP / 原型阶段
│   └── 结构化 JSON + Tool Call（够用了，别过度设计）
│
├── 生产环境
│   └── 心智模型传递（CoT + 置信度）+ 完整的错误处理
│
└── 跨组织协作
    └── A2A / MCP 标准协议（互操作性优先）
```

---

## 八、总结

Multi-Agent 通信设计，核心就是回答三个问题：

1. **拓扑（谁跟谁聊）**：中心化、去中心化、还是层次化？
2. **机制（数据怎么流）**：共享状态、消息队列、还是向量记忆？
3. **协议（聊什么格式）**：纯文本、结构化工具调用、还是心智模型传递？

没有银弹，只有权衡。选择取决于你的**Agent 数量**、**任务复杂度**、**性能要求**和**成本预算**。

但有几个通用原则：

- **能少聊就少聊**：每次通信都有成本，不要过度同步
- **结构化优于自然语言**：能用 JSON Schema 就不要用纯文本
- **传递推理过程，不只传结果**：置信度和推理链让下游决策更准确
- **为失败而设计**：超时、循环检测、降级策略缺一不可
- **标准化是投资**：现在多花一周做协议标准化，未来能省几个月适配成本

Multi-Agent 系统还处于快速发展期，A2A 和 MCP 等标准协议正在逐步成熟。现在投入精力把通信架构设计好，未来接入更广泛的 Agent 生态时，就会觉得打地基阶段都是值得的。