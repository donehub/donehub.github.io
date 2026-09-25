---
title: GraphRAG vs Standard RAG — When to Use Each
date: 2026-03-10
tags: [GraphRAG]
categories: [AI]
lang: en
label: 068_graphrag-vs-rag-scenarios
---

Building a knowledge base Q&A system in an enterprise usually comes with a choice: use standard vector-retrieval RAG, or use Microsoft's GraphRAG? The two differ significantly in technical approach and suitable scenarios. Picking the wrong one means either insufficient retrieval accuracy or excessive engineering complexity. This article analyzes the capability boundaries and best-use timing of both approaches from a practical scenario perspective.

<!-- more -->

## What Standard RAG Can Actually Do

RAG (Retrieval-Augmented Generation) works like this: split documents into chunks, vector-embed them, store in a vector database; when a user queries, vectorize the query, retrieve the TopK most semantically similar chunks, and feed them to the LLM for answer generation. The mechanism is essentially text-segment similarity matching, and what it does well versus what it can't do has a very clear boundary.

Standard RAG excels at single-point factual queries — questions where the complete answer lives inside a single chunk. Things like "what's the API timeout?", "what features does the product support?", "when was GPT-4 released?" — straightforward factual questions. As long as the answer is clearly stated in some chunk, standard RAG can retrieve it accurately. These questions account for over 70% of enterprise knowledge base queries, forming RAG's most solid base.

## What It Genuinely Cannot Do

Standard RAG's weakness is that it finds segments but can't always connect the relationships between them. Consider a real scenario: a user enters a multi-condition query looking for a phone good for video, with decent battery life, and stable user reviews. Standard RAG might retrieve Chunk A "XX phone has a powerful imaging system, outstanding video capability," Chunk B "XX phone has a 5500mAh battery, excellent battery life," Chunk C "User review: used for six months, system is stable." The problem is A, B, and C might come from three different documents describing three different phones. Standard RAG throws all three chunks at the LLM, which then has no idea which phone actually satisfies all three conditions.

This is standard RAG's fundamental limitation: its retrieval unit is the text segment, not the entity, and certainly not the relationship. It's good at "finding similar text," bad at "finding answers satisfying multiple relational constraints." This limitation becomes inescapable in four types of scenarios.

## Multi-Dimensional Correlated Queries

Multi-dimensional correlated queries aren't simple multi-condition filtering. Multi-condition filtering is `price < 5000 AND brand = Huawei` — SQL can handle that. Multi-dimensional correlated queries mean: multiple dimensions have structured relationships between them, requiring navigation and intersection along those relationships.

Product recommendation systems are a typical scenario. Product knowledge isn't a flat table — it's a relationship network: each product connects to brand, price segment, core selling points, target audience, user reputation, and other attribute nodes. When a user asks "any flagship good for video, strong performance, stable reputation?", standard RAG's approach is fuzzy matching in text, separately retrieving "strong imaging," "strong performance," "good reputation" segments, then letting the LLM guess. GraphRAG builds knowledge into a graph and navigates along relationship edges: find the "imaging flagship" node, "performance flagship" node, "stable user reputation" node, then take the intersection of their connected product entities. This isn't a semantic similarity problem — it's a graph traversal problem.

The root cause is retrieval space mismatch. Standard RAG's retrieval space is vector space, measuring how similar two text segments are; multi-dimensional correlated queries need relationship space, requiring path-finding along entity relationships. Two completely different spaces — using the wrong tool produces wildly different results.

## Global Summarization and Hidden Relationship Discovery

Global summarization questions ask about the whole picture, not a single point. Things like "what are the trends in high-end phones in recent years?", "what's the current tech landscape of the AI Agent industry?", "how are the company's departments' businesses connected?" The answers to these questions are scattered across the entire corpus, not in any single chunk. Standard RAG's TopK most similar chunks tend to be fragmented: Chunk 1 covers imaging, Chunk 2 covers chips, Chunk 3 covers pricing, Chunk 4 covers AI features. The LLM gets these fragments and can only stitch them together, producing an answer that covers everything but offers no insight — reads like a table of contents, not an analysis.

GraphRAG solves this through community detection and hierarchical summarization. The approach has three steps: first, use a community detection algorithm (like Leiden) to partition the knowledge graph into semantic communities — entities within each community are tightly related, communities are relatively loose from each other; second, generate a local summary for each community; third, aggregate all local summaries into a global view. This hierarchical summarization mechanism is naturally suited for "overall trends" and "industry landscape" questions, because it doesn't piece together fragments — it starts from structured communities, each with its own theme and insights, and merging them yields the global view.

Another class of problems standard RAG can't handle is hidden relationship discovery. Two entities might never be directly stated as related in any text, but their connection can be inferred through intermediate nodes. Product A and Product B might never have been directly compared in any document, but their attributes heavily overlap: both are in the high-end price segment, both target business users, both excel at imaging. In graph structure, Product A and Product B aren't directly connected, but they share many of the same neighbor nodes — this structural proximity is the hidden relationship. Standard RAG retrieves based on semantic similarity between query and chunks; if no document puts Product A and Product B in the same text passage, there's no way to discover their connection.

Business scenarios relying on hidden relationship discovery are actually quite broad. Competitive analysis needs to find products not directly compared but substantially overlapping; risk investigation needs to trace from multiple seemingly unrelated accounts through intermediate nodes to find they share the same controller; drug discovery needs to find two target proteins never mentioned in the same paper but discovered through pathway networks to be in the same signaling pathway. Standard RAG can't do any of this, because its information unit is the text segment, not the entity relationship graph.

## Cross-Document Causal Chain Tracing

Some answers require linking multiple pieces of information across documents to derive a root cause. A typical example is "root cause analysis of XX project delay." The real answer might be scattered across: the requirements document records a major mid-project requirement change, the schedule shows key developers were reassigned to other projects, the dev weekly mentions unexpected issues in API integration testing, QA feedback flags a third-party SDK bug blocking test progress, client communication records show the client added features during acceptance.

Standard RAG is most likely to retrieve a single segment from some document, like a meeting note: "This meeting confirmed a two-week project delay, mainly due to requirement changes." Not wrong, but incomplete. The real root cause is the result of multiple compounding factors; looking at only one of them misleads decision-making.

GraphRAG models people, requirements, tasks, timelines, risks, and dependencies all as graph nodes and edges. Starting from the "project delay" symptom, following relationship edges traces multiple causal paths: requirement changes affected Task A which blocked Task B ultimately causing delay; developer reassignment left Task A understaffed causing delay; SDK bug blocked integration causing delay; client's new requirements caused rework in acceptance causing delay. This is a multi-path convergence problem on a graph, not something text similarity can solve.

## Why You Can't Just Go All-In on GraphRAG

After covering what GraphRAG does well, we have to face its engineering cost head-on. GraphRAG's indexing phase isn't even in the same order of magnitude as standard RAG.

| Phase | Standard RAG | GraphRAG |
|------|----------|----------|
| Document processing | Chunk splitting | Entity extraction + relationship extraction |
| Index construction | Vector embedding | Graph build + community detection + per-community summarization |
| LLM calls | Low (embedding only) | Extremely high (extraction and summarization both call LLM) |
| Index time | Minutes | Hours or even days (depending on corpus size) |
| Query latency | Milliseconds to seconds | Seconds to tens of seconds (traversal + synthesis) |
| Storage cost | Vector database | Graph DB + vector DB + summary storage |

A quantitative example: for a 1-million-token enterprise knowledge base, standard RAG's indexing cost might be just a few dollars in embedding fees. GraphRAG's indexing phase (entity extraction, relationship extraction, community summarization) could cost tens or even hundreds of dollars in LLM calls. That's before counting query-phase costs — each GraphRAG query traverses more nodes, reads more relationships, and synthesizes longer contexts, all token costs.

If 80%+ of your scenarios are simple factual questions, going with GraphRAG is over-engineering. More expensive, higher latency, and simple question quality might actually be worse.

## Hybrid Routing Architecture

People who've actually built production systems don't choose between standard RAG and GraphRAG. The right approach is hybrid routing: route queries to different processing engines based on query type — simple facts go to standard RAG, structured queries go to SQL, relational reasoning and global summarization go to GraphRAG, then unify answer synthesis.

The Query Router is the heart of hybrid routing, responsible for classifying user questions and routing to the appropriate retrieval engine. There are three implementation approaches, from light to heavy. First is rule-based routing, using keyword and sentence pattern matching — fast and cheap:

```python
def route_query(query: str) -> str:
    # Global summarization keywords
    summary_keywords = ["trend", "landscape", "overall", "summary", "overview", "development"]
    if any(kw in query for kw in summary_keywords):
        return "graphrag_summary"

    # Structured query keywords
    if "how many" in query or "when" in query or "what is" in query:
        return "normal_rag"

    # Relational reasoning keywords
    relation_keywords = ["related", "impact", "cause", "depend", "shared"]
    if any(kw in query for kw in relation_keywords):
        return "graphrag_relation"

    return "normal_rag"  # Default to standard RAG
```

Second is LLM classification routing, using a small model (like GPT-4o-mini) to classify the query — more accurate but with additional latency and cost:

```python
ROUTER_PROMPT = """
Classify the following user question into one of these types:
- factual: simple factual query, answer is in some text passage
- sql: can be converted to a structured query
- relation: requires cross-entity relationship reasoning
- summary: requires global summarization or trend analysis

User question: {query}
Type:
"""
```

Third is hybrid routing: rules first, fall back to LLM when rules can't decide, balancing cost and latency.

The routing strategy's core principle: default to standard RAG, only route to GraphRAG when clearly needed. Most queries are simple factual questions — GraphRAG should be the special forces, not the regular army. If you reverse this and run everything through GraphRAG, costs go up, latency goes up, and simple question accuracy actually drops because GraphRAG's longer context and more noise make the LLM more prone to distraction.

## Scenario-to-Tool Mapping

| Question Type | Example | Recommended Tool | Reason |
|---------|------|---------|------|
| Single-point fact | "What's the API timeout?" | Standard RAG / SQL | Answer is in a chunk — don't use a sledgehammer on a nail |
| Multi-condition filter | "Huawei phones under 5000" | SQL / structured query | This is a database job |
| Multi-entity relationship | "Flagship good for video with solid reputation" | GraphRAG | Needs intersection along relationship edges |
| Global trends | "AI Agent industry landscape" | GraphRAG | Needs community summarization |
| Hidden relationship discovery | "Association analysis of two accounts" | GraphRAG | Needs graph structure inference |
| Cross-document causal tracing | "Root cause of project delay" | GraphRAG | Needs multi-path convergence |
| Simple comparison | "Difference between A and B" | Standard RAG | Just concatenate two text segments |

The right approach to technology selection isn't listing a technology's advantages. It's first clearly stating the existing solution's capability boundaries, then what the new solution fills in, and finally engineering the two together. If you can articulate that selection logic clearly, you're not chasing hype — you've actually built systems, hit the walls, and thought it through.
