---
title: Multi-Agent System Design Principles
date: 2026-02-11
categories: Multi-Agent
tags: [AI]
lang: en
label: 066_multi-agent-system-design
---

In real-world LLM engineering, the core challenge of multi-agent systems isn't making a single Agent smarter — it's making multiple Agents collaborate efficiently while keeping the system controllable. When tasks scale from single-turn conversations to scenarios requiring parallel processing of dozens of subtasks, a system left to its own devices will almost inevitably sink into context overflow, task conflicts, or runaway token consumption. This article breaks down a battle-tested multi-agent architecture design, covering task decomposition, subagent spawning, state management, and concurrency control.

<!-- more -->

## Dynamic Outline and Task Scheduling

When the main Agent receives a complex task, its first move shouldn't be jumping straight into execution — it should generate a Dynamic Outline. This outline serves as the system-level task tracker, recording the real-time status of every subtask. Take a task like researching the technology roadmaps of 75 tech companies: the outline breaks this into 75 sub-items and marks each one's progress in real time — which are done, which are in progress, which haven't been assigned. Before dispatching new work, the main Agent reads the outline's current state to see what's unclaimed, then decides who gets what. The outline is the single source of truth for the entire system; who's doing what and how far along they are is always visible at a glance.

When the outline contains unassigned subtasks, the main Agent spawns multiple independent Subagents via the `delegate_task` tool. Each Subagent picks up its own subtask and runs in parallel, without interfering with others. In the research example, the main Agent might call `delegate_task` four times in one batch, spawning Subagents for Apple, Google, Microsoft, and Amazon — all four start crawling and analyzing simultaneously. The main Agent's role is like an orchestra conductor: it doesn't play any instrument itself, just monitors each section's progress and corrects deviations. Clean role definitions and strict boundary enforcement are what make this scheduling mechanism actually work.

## Information Convergence

When a Subagent returns results, there's one hard constraint it must follow: it cannot pass raw collected content back to the main Agent. If every Subagent dumped the full tens of thousands of characters it crawled, the main Agent's context window would fill up fast, tanking its reasoning quality. Token costs would spike as well, directly driving up system operating costs.

The solution is to add a mandatory compression step to each Subagent's execution flow. A Subagent's workflow has four stages: crawl raw data, analyze and extract key information, self-compress into distilled conclusions, and return a concise brief. That last step is the critical one — before returning, the Subagent must compress raw content into a high-density summary, filtering out noise and redundancy. What the main Agent receives is always a refined brief, preserving its context space so reasoning capacity doesn't get diluted by mountains of raw data. The information flow direction is diverge-then-converge, with each subnode bearing compression responsibility. This is the foundational design that prevents the system from descending into chaos.

## Flat Architecture and Concurrency Limits

Another risk to guard against is uncontrolled Subagent proliferation. If a Subagent encountering a difficult subtask is allowed to spawn its own Subagents, you get recursive spawning chains. Each generation spawns the next, token consumption grows exponentially, and the system quickly enters a death loop.

Two hard constraints in the architecture prevent this. The first is generation isolation: only the main Agent has permission to call `delegate_task`; regular Subagents are forbidden from spawning new ones. The entire architecture stays strictly flat, eliminating recursive spawning at the code level. The second is physical rate limiting: set a concurrency cap in code, say a maximum of 20 Subagents running simultaneously, with excess requests queued. Both constraints share the same underlying idea — using engineering determinism to limit the unpredictability of model behavior. Models will make random mistakes, but engineering constraints don't break because of model randomness.

## State Conflicts and Centralized Scheduling

Once Subagent counts reach a certain scale, task conflicts and state overwrites become unavoidable. Two Subagents might get assigned overlapping task scopes, duplicating effort, or one Subagent's output might overwrite another's intermediate results. The dynamic outline steps in as the conflict arbitration center.

When dispatching tasks, the main Agent enforces strict boundary partitioning based on the outline's current state. In code logic, every pending task is checked before dispatch to confirm it hasn't already been claimed by another Subagent or already completed, ensuring no duplicate dispatches. The main Agent eliminates task overlap before it happens. The outline thus becomes the system's single source of truth — each Subagent only knows its own task boundaries, while the main Agent maintains global state consistency through the outline. All Subagents run their own lanes without interfering with each other.

## Evaluating a Non-Deterministic System

A dynamic system like this may follow a different call sequence on every run, which makes traditional unit testing essentially useless. You can't assert that the system called a specific tool at a specific step, because the next run might take a completely different path. The approach that has matured in the industry is LLM-as-a-Judge: have a more capable model act as judge and score the main Agent's final report across structured dimensions. The judge model evaluates information completeness, logical coherence, and factual accuracy. Through large-scale automated evaluation, the team can quantitatively determine whether output quality has actually improved after each system adjustment, instead of blindly switching between different random execution paths.
