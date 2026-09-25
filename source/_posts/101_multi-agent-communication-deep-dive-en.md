---
title: "Multi-Agent Communication: A Deep Dive"
date: 2026-05-30
categories: AI
tags: [Multi-Agent Communication]
lang: en
label: 101_multi-agent-communication-deep-dive
---

## Background

When a system evolves from a single Agent to multi-Agent collaboration, communication design becomes the deciding factor between success and failure. Once the system is running, the biggest challenge is no longer individual Agent capability — it's how efficiently and accurately information flows between Agents. A typical review task passes through an average of 4 Agents in sequence, and any misunderstanding at one stage gets amplified downstream.

Communication design determines whether a Multi-Agent system collaborates efficiently or works at cross purposes. A single Agent is like a programmer working alone — no matter how skilled, there's a ceiling. A team of Agents needs a communication protocol: who reports to whom, what format they use, and how failures are handled.

This article breaks down Multi-Agent communication across three dimensions: topology (who talks to whom), mechanism (how data flows), and protocol (what format they use). Then it analyzes failure modes and cost control strategies from real engineering experience.

<!-- more -->
---

## 1. It's Not Just Data Packet Exchange

Traditional distributed systems discuss communication in terms of HTTP vs gRPC, JSON vs Protobuf, timeout settings. These concerns still exist in Multi-Agent systems, but they're infrastructure-level. What makes Multi-Agent communication unique is semantic transfer and cognitive state alignment.

When Agent A tells Agent B "this bug is critical," B needs to understand not just the word "critical," but also A's reasoning for that judgment, the blast radius, and the estimated fix difficulty. This kind of mental model transfer simply doesn't exist in traditional RPC calls.

| Layer | Traditional Distributed Systems | Multi-Agent Systems |
|-------|-------------------------------|---------------------|
| Semantic | Structured data, fixed format | Natural language + reasoning chains, ambiguous semantics |
| State | Stateless or simple state machine | Complex cognitive state (beliefs, intents, confidence levels) |
| Fault Tolerance | Retry + degradation | Semantic drift detection + cognitive correction |

Understanding this difference makes the concrete communication design choices much clearer.

---

## 2. Communication Topology

Topology design is the first architectural decision — it determines coupling, fault tolerance, and the upper bound of scalability.

### 2.1 Centralized Orchestration

A Supervisor receives tasks, decomposes them into subtasks, assigns them to Worker Agents, collects results, and produces a summary. Workers don't communicate directly — all information flows through the Supervisor. This is like a project manager leading a team: requirements go to the PM, the PM breaks them into tasks for dev, QA, and design, then the PM consolidates and delivers. Developers don't need to talk to QA directly.

```
                ┌─────────────────┐
                │  Supervisor Agent│
                │  (Task Scheduler)│
                └───┬────┬────┬───┘
                    │    │    │
           ┌────────┘    │    └────────┐
           ▼             ▼             ▼
    ┌────────────┐ ┌────────────┐ ┌────────────┐
    │ Researcher │ │  Coder     │ │  Reviewer  │
    │   Agent    │ │   Agent    │ │   Agent    │
    └────────────┘ └────────────┘ └────────────┘
```

The advantages are clear logic and strong observability — humans can add approval gates at the Supervisor layer. But the single-point bottleneck is severe. If the Supervisor goes down, the entire system stops. All communication routes through it, limiting throughput. And the Supervisor must maintain state for every Worker, putting enormous pressure on its context window. In practice, we've observed that when Worker count exceeds 5, the Supervisor's context consumption reaches over 60% of its total window.

Best for: Tasks with a clear flow and 3-5 Agents, like search → analysis → report generation — a linear pipeline.

### 2.2 Decentralized Collaboration

All Agents are peers, communicating directly with no central node. Any Agent can initiate a conversation, respond to requests, or recommend the next handler. They negotiate who does what. This resembles an open-source maintainer community: everyone can file Issues, review PRs, and merge code, with no rigid hierarchy.

```
    ┌────────────┐     ┌────────────┐
    │  Agent A   │◄───►│  Agent B   │
    └─────┬──────┘     └─────┬──────┘
          │                   │
          │    ┌────────────┐ │
          └───►│  Agent C   │◄┘
               └────────────┘
```

Strong scalability, flexible routing, no single point of failure — these are the natural advantages of decentralization. But it has three fatal problems. First, infinite loop risk: A delegates to B, B thinks C should handle it, C kicks it back to A — deadlock. Second, context explosion: group chat messages grow exponentially, and every Agent must maintain the full conversation history. Third, poor convergence: there's no referee to decide when a task is done.

In testing, a 5-Agent decentralized group chat without effective anti-loop mechanisms averaged 1 infinite loop every 8 rounds of conversation. Anti-loop engineering typically works on three levels:

```python
# 1. Hard cap on max rounds
groupchat = GroupChat(max_round=10)

# 2. Termination condition detection
def should_terminate(messages):
    last_msgs = messages[-3:]
    # If the last 3 messages repeat the same point, terminate
    return len(set(m["content"] for m in last_msgs)) == 1

# 3. Introduce a moderator role for arbitration
moderator = AssistantAgent(
    name="Moderator",
    system_message="You are the discussion moderator. When the discussion goes in circles, make a final decision."
)
```

Best for: Brainstorming, multi-role debate, code review — scenarios that benefit from multiple perspectives colliding.

### 2.3 Hierarchical Hybrid

Real-world large systems typically combine the two approaches above. Top-level Agents handle task decomposition and strategic planning, mid-level Agents coordinate subtasks, and bottom-level Agents execute specific operations. Each layer communicates only with adjacent layers. This mirrors a corporate org chart: the CEO sets direction, VPs break down goals, frontline staff executes. You don't want the CEO managing interns directly — hierarchy is a tool for managing complexity.

```
              ┌───────────────┐
              │   CEO Agent   │
              │(Strategic Plan)│
              └───┬───────┬───┘
                  │       │
        ┌─────────▼─┐   ┌─▼──────────┐
        │ VP-Eng    │   │ VP-Ops     │
        │(Mid-level)│   │(Mid-level) │
        └──┬────┬───┘   └──┬────┬────┘
           │    │           │    │
         ┌─▼─┐┌─▼─┐      ┌─▼─┐┌─▼─┐
         │Dev││QA │       │Mkt││CS │
         └───┘└───┘       └───┘└───┘
```

Hierarchical design follows three key principles.

Information compression: Each layer compresses information granularity when reporting upward. The bottom layer reports "3 API errors," the mid layer reports "3 exceptions at the interface layer," and the top layer only needs to know "the system has stability risks."

Context isolation: Each layer maintains only the context it needs, avoiding global state bloat. The CEO doesn't need specific API error messages — only the overall system health status.

Delegation boundaries: Each layer's decision authority must be explicit. Small decisions that the bottom layer can make without mid-level approval should not be escalated. Over-escalation slows the entire system's response time.

| Principle | Description |
|-----------|-------------|
| Information Compression | Each layer compresses information granularity when reporting upward; the top layer only needs conclusion-level information |
| Context Isolation | Each layer maintains only its own context, preventing global state bloat |
| Delegation Boundaries | Decision authority is clear at each layer; small decisions don't get escalated |

Best for: Large enterprise systems like financial risk control (compliance layer → strategy layer → execution layer) or intelligent customer service (routing layer → business layer → tool layer).

### 2.4 Topology Comparison

| Dimension | Centralized Orchestration | Decentralized Collaboration | Hierarchical Hybrid |
|-----------|--------------------------|----------------------------|---------------------|
| Coupling | High (Workers depend on Supervisor) | Low (Agents are independent) | Medium (tight within layer, loose between layers) |
| Fault Tolerance | Poor (single point of failure) | Good (no single point) | Medium (layer failure can degrade gracefully) |
| Observability | Good (central node has global view) | Poor (information scattered) | Medium (visible per layer) |
| Scalability | Poor (central node is the bottleneck) | Good (dynamic join) | Good (horizontal + vertical scaling) |
| Implementation Complexity | Low | High | Medium |
| Suitable Agent Count | 3-5 | 5-10 | 10+ |

In systems with 10+ Agents, hierarchy is almost the only viable option. Centralization is simplest and most efficient at 3-5 Agents. Decentralization works well for multi-perspective scenarios where Agent count stays manageable.

---

## 3. Communication Mechanisms

Topology solves "who talks to whom." Mechanisms solve "how data gets from A to B."

### 3.1 Shared State

This is LangGraph's core design and the most widely used approach today. Agents don't send messages directly — they collectively read and write a global state object. One Agent updates the state, the next reads the changes, completing communication indirectly.

```
┌──────────┐       ┌──────────────┐       ┌──────────┐
│ Agent A  │──write►│  Global State │◄──read│ Agent B  │
└──────────┘       │  {            │       └──────────┘
                   │   task: "...", │
┌──────────┐       │   result: "...",│      ┌──────────┐
│ Agent C  │──write►│   status: "..."│◄──read│ Agent D  │
└──────────┘       │  }            │       └──────────┘
                   └──────────────┘
```

Think of it as a shared Google Doc. Team members don't need meetings — they open the doc, see the latest content, and edit directly. The document itself is the communication medium.

Shared state has clear advantages. It naturally supports checkpoint-and-resume: persist state to a database and recover from the last checkpoint after a crash. It's human-in-the-loop friendly: humans can inspect and modify intermediate state before letting Agents continue. It has strong observability: every state change is recorded, making debugging and auditing straightforward. State updates are idempotent, so there's no message loss problem.

Two caveats. If two Agents concurrently modify the same field, you need a conflict resolution strategy (last-write-wins or a custom merge function). Long-running tasks cause state to grow continuously, requiring periodic compression or archival.

### 3.2 Message Queues

When Agent systems need cross-language, cross-process, or cross-machine communication, shared state's runtime binding becomes a bottleneck. That's when you introduce message middleware.

```
┌───────────┐                    ┌───────────┐
│ Python     │                    │ Java       │
│ Research   │                    │ Recommend  │
│ Agent      │                    │ Agent      │
└─────┬──────┘                    └─────┬──────┘
      │ publish                         │ subscribe
      ▼                                 ▼
┌───────────────────────────────────────────────┐
│         Message Queue / Event Bus              │
│    (Kafka / RabbitMQ / Redis Streams)         │
│                                               │
│  Topic: research.results                      │
│  Topic: recommendation.requests               │
│  Topic: code.generation.tasks                 │
└───────────────────────────────────────────────┘
      ▲                                 ▲
      │ subscribe                       │ publish
┌─────┴──────┐                    ┌─────┴──────┐
│ Python     │                    │ Python     │
│ Coder      │                    │ Summarizer │
│ Agent      │                    │ Agent      │
└────────────┘                    └────────────┘
```

Think of it as the company's email system plus bulletin boards. When you need another team's help, you send an email to their Topic, and they process it asynchronously at their convenience — no face-to-face meeting required.

The core differences between the two mechanisms:

| Dimension | Shared State | Message Queue |
|-----------|-------------|---------------|
| Communication Pattern | Implicit (via reading/writing state) | Explicit (send/receive messages) |
| Coupling | Data coupling (shared state) | Message coupling (agreed message format) |
| Timeliness | Eventually consistent | Precisely controllable (sync/async) |
| Cross-Language | Difficult (shared runtime required) | Native support (messages are universal) |
| Failure Recovery | State snapshot recovery | Message replay (ACK mechanism) |
| Best For | Single process, strong consistency | Multi-process/multi-language, async decoupling |

In our financial risk control system, we use Redis Streams between the strategy layer and execution layer because they're implemented in Python and Java respectively. Between the strategy layer and compliance layer, we use shared state because they run in the same Python process. Hybrid approaches are more common than pure single-mechanism designs.

### 3.3 Shared Vector Memory

This is an implicit communication method: Agents don't directly exchange data — they collaborate indirectly through a shared vector knowledge base. Agent A vectorizes intermediate reasoning results, observed facts, and learned experiences, storing them in the vector store. Agent B retrieves relevant information via semantic search when needed.

```
┌──────────┐                    ┌──────────┐
│ Agent A  │──vectorize write───│  Vector  │
│(Producer) │                   │ Database │
└──────────┘                    │(Shared   │
                                │ Memory)  │
                                └─────┬────┘
                                      │
                                semantic │
                                  search │
                                ┌─────▼────┐
                                │ Agent B  │
                                │(Consumer)│
                                └──────────┘
```

Think of it as a company knowledge base (Confluence / Notion). After a project ends, veterans write up their experience as docs. Later, when someone encounters a similar problem, they search, find relevant docs, and learn from them. The doc author and reader never need direct communication.

Shared vector memory works well in three scenarios. Long-term memory: Agents remember what they've learned, avoiding repeated mistakes. Cross-task knowledge reuse: different tasks share experiences; new tasks can reference historical ones. Implicit collaboration: Agents don't need real-time interaction — they work independently, passing information indirectly through the vector store.

Three critical design points must be handled correctly.

Metadata filtering: Always attach metadata to vectors (source Agent, timestamp, type). Without it, search results will include irrelevant information. A vector store without metadata is like a library without labels — retrieval efficiency is terrible.

Forgetting mechanism: You can't just keep adding without removing. Periodically clean up expired or low-relevance memories. An infinitely growing vector store degrades retrieval quality as noise accumulates.

Conflict detection: Different Agents may write contradictory information. You need version control or confidence-based ranking to resolve this. When the same fact is stored in different versions by two Agents, downstream consumers need to know which is more trustworthy.

| Design Point | Recommendation |
|-------------|---------------|
| Metadata Filtering | Attach source Agent, timestamp, and type metadata to vectors to prevent irrelevant search results |
| Forgetting Mechanism | Periodically clean up expired or low-relevance memories to prevent unbounded vector store growth |
| Conflict Detection | Use version control or confidence ranking when different Agents write contradictory information |

---

## 4. Communication Protocols

Topology and mechanisms solve the channel problem. Protocols solve the content problem: what format should messages between Agents use to ensure accurate understanding?

### 4.1 Plain Text Communication

The most primitive and most fragile approach:

```python
# Message from Agent A to Agent B
message = "Check this bug for me. I think it might be a database connection pool issue. See if max_connections is set too low."

# Agent B receives this natural language and must parse the intent itself
# Problem: How does B know if A wants to "investigate" or "fix"? Does "I think" mean A has low confidence?
```

Intent is ambiguous (investigate, fix, or just discuss?), there's no structure (downstream Agents struggle to parse), and metadata like confidence and priority can't be conveyed. Plain text communication barely works in demos — it must be replaced in production.

### 4.2 Structured Tool Calls

The industry's mainstream approach is to standardize inter-Agent communication as function calls, leveraging LLMs' native Function Calling capability.

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
      "parent_task": "Fix security vulnerability in price calculation",
      "requester_agent": "code_generator",
      "deadline": "5min"
    }
  }
}
```

The `name` field directly states the intent, structured parameters mean downstream Agents don't have to guess, `tool_call_id` makes every call traceable, and LLMs natively support Function Calling without an extra parsing layer. Compared to plain text, structured communication reduced our system's semantic drift rate from 34% to 6%.

### 4.3 Mental Model Transfer

The advanced approach is to pass not just results, but also the reasoning process and confidence level.

```json
{
  "from": "research_agent",
  "to": "decision_agent",
  "content": "Recommend using Redis as the cache layer",
  "reasoning": {
    "steps": [
      "Analyzed data access patterns: read-heavy, ~100:1 read-to-write ratio",
      "Evaluated data consistency requirements: second-level latency acceptable",
      "Compared Redis vs Memcached: Redis supports richer data structures",
      "Considered team tech stack: backend team has Redis experience"
    ],
    "assumptions": [
      "DAU does not exceed 1 million",
      "Cache data does not require strong consistency"
    ],
    "alternatives_considered": [
      {"option": "Memcached", "rejected_reason": "Limited data structure support"},
      {"option": "Local cache", "rejected_reason": "Multi-instance deployment; local cache cannot be shared"}
    ]
  },
  "confidence": 0.82,
  "risk_assessment": {
    "level": "low",
    "details": "Redis single-point-of-failure risk can be addressed with Sentinel"
  }
}
```

The downstream Agent uses confidence to decide next steps:

```python
def decision_agent(received_message):
    confidence = received_message["confidence"]

    if confidence >= 0.8:
        # High confidence — adopt directly
        return execute(received_message["content"])
    elif confidence >= 0.5:
        # Medium confidence — delegate to another Agent for review
        return delegate_to("reviewer_agent", received_message)
    else:
        # Low confidence — request re-research
        return delegate_to("research_agent", {
            "action": "redo_research",
            "feedback": received_message["reasoning"]
        })
```

This is like a medical consultation. A doctor can't just say "I think it's pneumonia." He needs to say "Based on the X-ray and blood test results, I'm 80% confident it's pneumonia, but I've also considered bronchitis — I'd recommend a CT scan to confirm." Passing reasoning is more expensive (roughly 3-5x the tokens per message compared to passing results only), but at critical decision points, the cost is justified.

### 4.4 Standardized Protocols (A2A / MCP)

Agent communication protocol standardization is one of the most important industry trends right now. Two protocols worth watching:

| Protocol | Proposed By | Scope | Core Concepts |
|----------|------------|-------|---------------|
| MCP (Model Context Protocol) | Anthropic | Agent ↔ Tools/Data Sources | Resource, Tool, Prompt |
| A2A (Agent-to-Agent) | Google | Agent ↔ Agent | Task, Artifact, Message, StatusUpdate |

MCP solves how Agents call external tools and data sources — it defines a standard interface so different LLM applications can access tools uniformly. A2A solves how Agents from different platforms and vendors interoperate — it defines standard objects like Agent Card (capability description), Task (task lifecycle), and Artifact (deliverables).

```
A2A Protocol Core Objects:

Agent Card:
  - name: "Code Review Agent"
  - skills: ["code_review", "security_audit"]
  - endpoint: "https://api.example.com/a2a"

Task:
  - id: "task-123"
  - status: "submitted" → "working" → "completed" / "failed"
  - messages: [input message list]
  - artifacts: [output artifact list]

Artifact:
  - type: "code_review_result"
  - content: {...}
  - metadata: {...}
```

The value of standardization can be measured with a simple calculation: N Agents that each need to communicate with every other require N×(N-1)/2 adapters. Your company built 5 Agents with LangChain, your partner built 3 with AutoGen, and a vendor built 2 with a custom framework — without a standard protocol, you need 45 adapters. With one, you need 10.

---

## 5. Failure Modes

The system runs great in demos but blows up in production — most likely the communication failure handling wasn't done right.

### 5.1 Semantic Drift

Agent A's intent gets distorted during transfer. Agent B understands something different from what A meant to convey.

```
Agent A: "Optimize this function's performance" (intent: reduce time complexity)
    ↓ transfer
Agent B: "Optimize function naming and code style" (understanding: improve readability)
    ↓ result
Returns code with better naming but unchanged performance
```

Two paths to solve this. First, intent confirmation: Agent B restates its understanding of the task before executing, and A confirms it. Second, structured task descriptions: define acceptance criteria with a schema instead of using plain natural language.

```python
# Structured task description to prevent semantic drift
task = {
    "action": "optimize",
    "target": "calculate_price",
    "objective": "reduce_time_complexity",  # Clear optimization target
    "metric": "execution_time",
    "current_value": "O(n^2)",
    "target_value": "O(n log n)",
    "constraint": "Do not change function signature or return values"
}
```

In our code review system, introducing structured task descriptions reduced error merges caused by semantic drift from 3-4 per week to fewer than 1 per month.

### 5.2 Context Overflow

Multi-round communication causes message lists to grow longer and longer, eventually exceeding the LLM's context window limit.

```
Round 1: 2,000 tokens
Round 2: 4,500 tokens
Round 3: 9,000 tokens
Round 4: 18,000 tokens
Round 5: 35,000 tokens  ← approaching GPT-4's 32K limit
Round 6: 💥 exceeds limit
```

Three strategies, each with tradeoffs. Sliding window keeps only the last N rounds — simple but loses early important information. Summary compression periodically condenses history into summaries — preserves key information but the summaries themselves consume tokens. Tiered memory combines short-term memory (recent messages) with long-term memory (vectorized storage) — best results but most complex to implement.

```python
def compress_context(messages: list, max_tokens: int = 4000):
    """Context compression strategy"""
    if count_tokens(messages) <= max_tokens:
        return messages

    # 1. Keep system messages and last 3 rounds
    system_msgs = [m for m in messages if m["role"] == "system"]
    recent_msgs = messages[-6:]  # Last 3 rounds = 6 messages

    # 2. Compress middle history into a summary
    old_msgs = messages[len(system_msgs):-6]
    summary = summarize(old_msgs)  # Use LLM to generate summary

    return system_msgs + [{"role": "system", "content": f"History summary: {summary}"}] + recent_msgs
```

| Strategy | Approach | Pros/Cons |
|----------|----------|-----------|
| Sliding Window | Keep only last N rounds | Simple, but loses early important info |
| Summary Compression | Periodically compress history into summaries | Preserves key info, but summaries cost tokens |
| Tiered Memory | Short-term (recent) + long-term (vectorized) memory | Best results, but complex to implement |

In real projects, tiered memory is the choice for most production systems. Pure sliding windows almost inevitably lose critical context in conversations over 10 rounds.

### 5.3 Deadlock and Livelock

Deadlock: Agent A waits for Agent B's results, B waits for C's results, C waits for A's results — all three are stuck. Livelock: Agents A and B keep passing the task back and forth, neither processes it, the system stays busy but makes no progress.

```
Deadlock example:
Agent A: "I need B's analysis results before I can give recommendations"
Agent B: "I need C's data before I can analyze"
Agent C: "I need A's recommendations before I can determine the data scope"
→ Circular wait, nobody can start

Livelock example:
Agent A: "This task should go to B"
Agent B: "No, it should go to A"
Agent A: "Actually, let's give it to B"
Agent B: "No no no, A is better suited"
→ Infinite loop, no actual work done
```

Engineering requires three lines of defense.

Global timeout: set a hard time limit on every Agent call to prevent tasks from waiting indefinitely. Loop detection: track message hashes for repeating patterns; trigger an alert when consecutive identical messages are detected. Forced escalation: when deadlock or livelock is detected, escalate the task to a Supervisor or human handler to break the cycle.

```python
# 1. Global timeout mechanism
import asyncio

async def with_timeout(coro, timeout_seconds=30):
    try:
        return await asyncio.wait_for(coro, timeout=timeout_seconds)
    except asyncio.TimeoutError:
        return {"error": "timeout", "message": "Task execution timed out"}

# 2. Loop detection
class LoopDetector:
    def __init__(self, max_repeats=3):
        self.history = []
        self.max_repeats = max_repeats

    def check(self, message):
        self.history.append(hash(message["content"]))
        if len(self.history) >= self.max_repeats * 2:
            recent = self.history[-self.max_repeats:]
            if len(set(recent)) == 1:
                return True  # Loop detected
        return False

# 3. Forced escalation
def fallback_when_stuck(agents_in_loop):
    """When deadlock/livelock is detected, escalate to a higher-level Agent"""
    return escalate_to_supervisor(
        task="Deadlock detected in inter-Agent communication. Human intervention required.",
        context=agents_in_loop
    )
```

### 5.4 Error Propagation

One Agent's output error causes all downstream Agents to make wrong decisions based on incorrect information.

```
Agent A (data collection): Incorrectly assumes API rate limit is 1000/hour (actual: 10000)
    ↓
Agent B (solution design): Designs a conservative caching strategy based on "1000 limit"
    ↓
Agent C (implementation): Implements unnecessarily complex caching logic
    ↓
Result: Over-engineered, performance actually decreased
```

Three principles for handling error propagation.

Confidence propagation: each Agent tags its output with a confidence score; downstream Agents use the score to decide how much to trust it. Outputs below 0.5 confidence should be flagged as unverified.

Cross-validation: for critical decisions, have multiple Agents independently produce answers and vote. When two or more Agents reach the same conclusion, confidence increases significantly.

Traceability: maintain the complete reasoning chain so that when problems arise, you can trace back level by level. Knowing where the error started propagating lets you fix it precisely.

Combining these three principles in our system reduced cascading failures caused by error propagation by roughly 70%.

---

## 6. Communication Cost Control

Every inter-Agent communication has a cost. Token consumption is the primary cost item. Network latency per LLM call ranges from 0.5 to 5 seconds, and a single erroneous communication that requires rework can cost several times the normal expense.

The first principle of cost control is communicate on demand — don't livestream everything. Agent A notifying Agent B in real time about every step is wasteful. Notify only when a milestone is reached. Don't sync after every thought — sync only when a complete plan is formed.

The second principle is communication tiering. Not all communication needs a full reasoning chain — a simple status sync only needs an enum value.

| Level | Method | Use Case | Token Cost |
|-------|--------|----------|------------|
| L1 Lightweight | Structured signal (status code/enum) | "Task done", "Need help" | Minimal |
| L2 Standard | Result summary + key data | Milestone reports | Medium |
| L3 Full | Complete reasoning chain + raw data | Critical decisions, task handoffs | High |

The third principle is cache reuse. Under identical input conditions, other Agents' historical outputs can be reused directly to avoid redundant requests.

```python
agent_output_cache = {}

def get_agent_output(agent_id: str, task_hash: str):
    cache_key = f"{agent_id}:{task_hash}"
    if cache_key in agent_output_cache:
        return agent_output_cache[cache_key]

    result = call_agent(agent_id, task_hash)
    agent_output_cache[cache_key] = result
    return result
```

In our system, combining these three strategies brought monthly API costs from ¥12,000 down to around ¥4,500 — a 62% reduction. Communication tiering contributed the most, followed by cache reuse.

---

## 7. Selection Guide

### Choosing Topology by Scenario

```
What's your Agent system's scenario?
│
├── Linear pipeline (A → B → C)
│   └── Centralized Orchestration (Supervisor mode)
│
├── Multi-role discussion / debate
│   └── Decentralized Collaboration (GroupChat mode)
│
├── Large complex system (>10 Agents)
│   └── Hierarchical Hybrid (Hierarchical mode)
│
└── Dynamic task assignment (don't know who should do it)
    └── Decentralized + Competition (Contract Net Protocol)
```

### Choosing Mechanism by Requirement

```
Where do your Agents run?
│
├── Single process / same runtime
│   └── Shared State (LangGraph State)
│
├── Multi-process / cross-language
│   └── Message Queue (Redis Streams / Kafka)
│
├── Need long-term memory
│   └── Shared Vector Memory (Vector Store)
│
└── Need all of the above
    └── Hybrid (State + Message Queue + Vector Memory)
```

### Choosing Protocol by Phase

```
What stage is your project in?
│
├── MVP / Prototype
│   └── Structured JSON + Tool Call (good enough, don't over-engineer)
│
├── Production
│   └── Mental Model Transfer (CoT + Confidence) + Full error handling
│
└── Cross-organization collaboration
    └── A2A / MCP Standard Protocols (interoperability first)
```

---

## 8. Closing Thoughts

The core of Multi-Agent communication design comes down to three decisions: topology decides who talks to whom, mechanism decides how data flows, and protocol decides what format they use. These three decisions are interconnected. If you choose centralized topology, you'll likely use shared state for the mechanism and structured tool calls for the protocol. If you choose hierarchical topology, you'll probably need a hybrid mechanism and protocols that pass reasoning and confidence.

The general principles boil down to five rules: communicate as little as possible, structured beats natural language, pass reasoning not just results, design for failure, and standardization is an investment.

Standard protocols like A2A and MCP are gradually maturing, but they still have a ways to go before large-scale adoption. Designing your communication architecture well now means that when you connect to a broader Agent ecosystem in the future, the foundation you've built will prove its worth.
