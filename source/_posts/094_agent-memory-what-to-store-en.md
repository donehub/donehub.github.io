---
title: "What Should an Agent Memory System Actually Store?"
date: 2026-04-27
tags: AI Agent Memory
categories: AI
lang: en
label: 094_agent-memory-what-to-store
---

A core problem when building Agents is enabling them to remember user preferences, project context, and past mistakes across sessions. Most people's approach: create a file and dump everything "worth remembering" into it. The file grows larger, token costs climb, and most of the content is irrelevant to the current conversation.

Claude Code's memory system offers a counterintuitive design principle: the hardest engineering problem isn't "how to store" or "how to retrieve" — it's "what to store and what not to store."

---

<!-- more -->
## 1. Core Philosophy: Memory Is the Complement of Code

The design philosophy behind this memory system can be summarized in one principle: memory is the complement of code.

Sounds simple, but this is the most insightful principle in the entire design. Specifically:

| Dimension | Code/Tools Are Good At | Memory System Is Good At |
|-----------|----------------------|-------------------------|
| Timeliness | Real-time queries, authoritative sources | Cross-session accumulation, experience buildup |
| Mutability | Auto-invalidates when code updates | Needs active maintenance, can go stale |
| Granularity | Precise down to function/file | Fuzzy intent, preferences, context |

**What to store**: All information about people and context — user preferences, corrections, motivations, pointers to external resources. These live outside the code and can't be discovered without checking memory.

**What not to store**: All information about code and project state — code is real-time, queryable, and authoritative. If code can answer the question, don't let memory answer it.

Once that boundary is clear, you realize a lot of things you previously thought "should be remembered" actually shouldn't be stored at all.

---

## 2. Four Types of Memory Worth Storing

### 2.1 User Memory

User memory captures the user's role, technical background, working habits, and knowledge level.

**Good examples**:

> "This user is a data scientist, currently researching logging systems."

> "This user has written Go for ten years but is touching React for the first time."

The design intent is to let the Agent adjust its communication style and working strategy. Facing a senior backend engineer, the Agent doesn't need to explain basic concepts and can use technical terms directly. Facing a beginner, the Agent needs to provide more background context.

**Key constraint**: The purpose of memory is "how to help this person better," not "profile this person." Don't record negative judgments about the user, and don't record personal information unrelated to work.

```
❌ Don't store: "This user has a bad temper, gets angry often"
❌ Don't store: "This user likes coffee"
✅ Do store: "This user prefers concise replies, no end-of-response summaries"
```

### 2.2 Feedback Memory

This is the most carefully designed of the four memory types. The source code specifies three key requirements for it.

**Requirement 1: Rule + Reason + Applicability**

Every feedback memory must contain three parts:

```
What the rule is → Why → When to apply it
```

Here's a concrete example. The user says:

> "Don't mock the database in tests. Last quarter we had an incident because mock tests passed but the production migration failed."

If you only record "don't mock the database," the Agent won't mock in any test — including unit tests completely unrelated to database migration.

But if it knows the reason is "mocks behave differently from production, causing migration failures," it can reason: integration tests shouldn't mock, but mocking in pure-logic unit tests is fine.

The point of recording the reason is to let the Agent make judgments in new scenarios, not mechanically execute rules.

**Requirement 2: Record Affirmations, Not Just Corrections**

The source code comments are blunt about this:

> If you only record moments when the user says "don't do that," it only knows what's wrong, not what's right. Over time, it avoids everything uncertain and becomes timid.

Affirmation signals are harder to capture than correction signals, though. "Don't do that" is obvious. But when a user says "yes, that's right" or silently accepts an unusual approach, you need to actively notice those affirmation signals.

**Example**:

> User says: "Yes, using one large PR was the right call this time. Splitting it would have been meaningless overhead."

The value of this memory: next time a similar refactoring scenario comes up, the Agent knows this user prefers consolidated commits rather than many small PRs. This isn't a correction — it's a validated judgment.

**Requirement 3: Distinguish Personal Preferences from Project Conventions**

> "Don't add summaries at the end of replies" → Personal preference, valid only for this user

> "Integration tests must use a real database" → Project convention, valid for all collaborators

The source code uses scope to distinguish these. Personal preferences go in a private directory; project conventions go in a team-shared directory.

### 2.3 Project Memory

Project memory captures what's happening in the current project: who's doing what, why it needs to be done, what the deadlines are.

**Examples**:

> "All non-critical merges freeze after this Thursday. The mobile team is cutting a release branch."

> "Rewriting the auth middleware because the legal team flagged that the old token storage doesn't meet compliance requirements. So when making decisions, prioritize compliance over technical elegance."

**Key rule: Convert relative dates to absolute dates**

When a user says "freeze on Thursday," memory stores the specific date, like "2026-03-07." The reason: memory spans sessions. If you store "Thursday," looking at this memory next week leaves you guessing which Thursday.

**Another characteristic: Decays quickly**

Project state from a month ago is probably outdated. So the source code requires project memory to record the "why." Even if the fact becomes stale, the underlying motivation remains useful.

```
Fact stale: "Rewriting auth middleware" → Probably already done
Motivation still valid: "Compliance takes priority over technical elegance" → This decision principle remains valid long-term
```

### 2.4 Reference Memory

Reference memory records where external resources live: which system tracks bugs, where the monitoring dashboard is, which platform hosts design docs.

**Examples**:

> "Pipeline-related bugs are all tracked in the INGEST project on Linear."

> "API latency monitoring dashboard is at grafana.internal/d/api-latency. Use this when on-call."

This is the simplest of the four types, but also the most practical — essentially an index of "where to find information."

---

## 3. Five Things You Shouldn't Store

This section is where the entire design becomes most insightful. Many people's first instinct when building a memory system is to store everything, including things they shouldn't.

### 3.1 Code Patterns, Architecture, File Paths, Project Structure

This is the most counterintuitive rule. Many people think the Agent should remember "what framework the project uses, how directories are organized, which file handles what." Claude Code's design principle says don't store these. The reason is direct: this information can be read from the code. The Agent can always retrieve the current project structure by reading code and searching.

Storing this in memory creates two problems:

```
Problem 1: Wasted space
Every conversation loads a bunch of information that could be queried in real time

Problem 2: Staleness risk
Code changes but memory doesn't update → Agent makes decisions based on stale info → Hard to catch
```

The underlying principle: if information can be derived from the current project state, don't store it in memory. Memory only stores things "you can't see by looking at the code."

### 3.2 Version Control History

Who changed what, recent commit history — just query the version control tool. Git is real-time and authoritative. No need for memory to store a potentially stale copy.

### 3.3 Debugging Approaches and Fixes

The fix is already in the code, and the commit message has the context. Storing "how it was fixed" is pointless because the code itself is the best reference.

### 3.4 Things Already in Configuration Files

If your project has a CLAUDE.md or other config files that define coding conventions, the memory system doesn't need to store a copy.

Duplicate storage wastes space and creates confusion when the two copies diverge.

```
Config file says: "Use pnpm"
Memory file says: "Use npm"
→ Agent receives contradictory instructions
```

### 3.5 Transient Task Details

What's currently being worked on, intermediate state within a conversation — these are short-term, belong to the current session's context, and shouldn't enter long-term memory.

---

## 4. One Especially Important Rule

Even if the user explicitly asks you to remember something, if it falls into one of the five categories above, don't store it.

**Example**:

> User: "Remember this week's PR list"

The Agent shouldn't store the PR list directly. Instead, it should push back:

> "Is there something in these PRs that surprised you or wasn't obvious? That's the part worth remembering."

Activity logs aren't memory. Insights distilled from activity are.

When a user asks to store something that shouldn't be stored, the correct approach is to extract the value point. The PR list itself shouldn't be stored, but if a particular PR's handling made the user think "that was the right approach," that judgment is worth storing as feedback memory.

---

## 5. Information Source Decision Tree

The principles above organized into a decision flow:

```
Can this information be obtained in real time from code/tools?
         │
         ├── Yes → Don't store, query in real time
         │
         └── No → What type is it?
                         │
                         ├── User characteristics → User memory
                         ├── Correction/affirmation → Feedback memory
                         ├── Project dynamics → Project memory
                         └── External resources → Reference memory
```

---

## 6. Common Mistakes in Practice

### Treating Memory as Project Documentation

```
❌ Store: "src/auth directory handles authentication logic, contains middleware.ts and token.ts"
✅ Query in real time: Glob + Read tools
```

### Treating Memory as Chat Logs

```
❌ Store: "User asked about Redis configuration yesterday, I answered..."
✅ Don't store: This is session context, not long-term memory
```

### Recording Rules Without Reasons

```
❌ Store: "Don't use forEach"
✅ Store: "Avoid forEach in async functions because forEach doesn't wait for
         Promise completion. Previously caused batch writes to execute only halfway.
         Applicable to async batch operations"
```

### Recording Only Corrections, Not Affirmations

```
❌ Only store: "Don't add summaries at the end of replies"
✅ Also store: "User confirmed: using one large PR for refactoring was right,
    splitting it would have increased overhead"
```

---

## 7. Memory System Quality Checklist

Before writing a memory entry, ask yourself these questions:

```
□ Does it store something code can answer?        → Delete or ask the user
□ Does it include "why"?                           → Add the motivation
□ Does it specify applicability scope?             → Add project/module boundaries
□ Are relative dates converted to absolute dates?  → "Tomorrow" → "2026-03-16"
□ Do similar memories exist?                       → Merge and deduplicate
□ Is sensitive information filtered?               → Reject passwords, keys, PII
```

---

## Final Thoughts

The most instructive aspect of Claude Code's memory system isn't its storage format or retrieval mechanism — it's that boundary line: memory is the complement of code. This principle turns the seemingly subjective question of "what to store" into a design decision with clear judgment criteria.

From this principle, the four types of memory worth storing share a common trait: they're all things you can't read from code. User preferences, the reasons behind corrections, the motivation for project decisions, the location of external resources — this information doesn't exist in any project file. It exists only in people and context. Conversely, the five things not worth storing also share a common trait: code, Git, and config files already provide authoritative answers. Storing another copy just creates noise and staleness risk.

The most common mistake when building memory systems is "better to store too much than too little." But memory file token costs are real — every memory entry gets loaded in every conversation. The burden of storing ten low-value memories far outweighs the help of one high-value memory. "Less but better" isn't a slogan — it's an engineering necessity under token cost constraints.

---

**Related posts**:
- [Memory System: Cross-Session Persistent Knowledge Base](/2026/04/06/081_claude-code-memory-system/) — Technical implementation details of Claude Code's memory system
- [Claude Code Source Code Deep Dive Series](/categories/Claude-Code/) — More Claude Code architecture analysis
