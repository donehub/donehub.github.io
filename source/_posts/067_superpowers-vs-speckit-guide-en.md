---
title: Superpowers vs SpecKit — A Practical Guide
date: 2026-02-15
tags: AI Tools
categories: AI
lang: en
label: 067_superpowers-vs-speckit-guide
---

The most common problem with letting an AI coding assistant write code directly is that it starts coding the moment it gets a requirement — without considering edge cases, without writing tests, and halfway through it drifts from the original spec. When multiple features are being developed in parallel, code gets tangled on the same branch and rollback becomes a headache. Superpowers is a workflow system that uses Skills to make AI coding assistants follow a disciplined engineering process, built by Jesse Vincent (Perl veteran and one of Markdown's co-creators). Its core idea: make the AI plan first, test first, implement, then review — work like a disciplined engineer, not an intern racing to ship.

<!-- more -->

## Core Philosophy

Without process constraints, an AI takes a task and immediately writes code, delivers when done, adds tests after the fact, and shares branches with other work. After installing Superpowers, the AI first clarifies requirement details, writes tests, then implements, and develops in an isolated Git Worktree. The difference boils down to one sentence: Superpowers doesn't make the AI smarter — it makes the AI more reliable.

It currently supports Claude Code, Cursor, GitHub Copilot CLI, Gemini CLI, Codex CLI, and OpenCode. Claude Code and Cursor can install via plugin marketplace with one command; Codex CLI requires manually copying skill files to the config directory.

| Tool | Installation |
|------|----------|
| Claude Code | `/plugin install superpowers@claude-plugins-official` |
| Cursor | `/add-plugin superpowers` |
| GitHub Copilot CLI | `copilot plugin install superpowers` |
| Gemini CLI | `gemini extensions install` |
| Codex CLI | Manual setup (clone repo, copy skill files) |
| OpenCode | Manual setup |

## The Seven-Step Workflow

Superpowers breaks the entire development process into seven stages, each with clear inputs, outputs, and constraints.

Stage one is brainstorming. After the user states a requirement, the AI doesn't start coding — it asks a series of clarifying questions. Say the user says "add a login feature." The AI will ask about login methods, session persistence, security requirements, and so on. The output is a design document that the user must confirm before moving forward. The point is to prevent the AI from filling in gaps with its own assumptions, avoiding the scenario where it works for half an hour only to realize the direction is completely wrong.

Stage two is creating an isolated workspace. The AI automatically creates a new branch and initializes a Git Worktree, keeping the development environment clean and rollback-ready. The main project directory stays untouched — you can keep working on other things in the main directory while the AI develops the target feature in the Worktree.

Stage three is planning. The AI breaks the design document into multiple small tasks, each estimated at 2 to 5 minutes, with explicit file paths, code content, and verification steps. Task granularity is kept small: "create the comment data model" is one task, "add the comment API" is another — not a vague "implement the entire comment feature." Small tasks are easier to review, easier to roll back, and easier to parallelize.

Stage four is subagent execution. Each task gets dispatched to a fresh subagent, with the main agent reviewing the subagent's output. The benefit is that each task runs in a clean context, uncontaminated by information accumulated from previous tasks. The main agent can work autonomously for hours — the user can step away and do something else.

Stage five is enforced TDD. Superpowers runs a strict RED-GREEN-REFACTOR cycle: write a failing test first (RED), write the minimum code to make it pass (GREEN), then refactor (REFACTOR). If the AI writes code before tests, the code gets deleted and it has to start over from the test. This isn't a suggestion — it's a hard constraint.

Stage six is code review. After each task completes, the main agent reviews across four dimensions: spec compliance, code quality, test coverage, and security. Critical issues block progress and must be fixed before continuing.

Stage seven is completing the branch. Once all tasks are done, the AI verifies all tests pass, then offers four options: merge to main branch, create a Pull Request, keep the branch, or discard changes. After selection, the Worktree gets cleaned up automatically.

## Walkthrough: Adding Comments to a Blog

Let's run through the full flow with a concrete example. Say you want to add a comment feature to a blog system, supporting user login and commenting.

After entering the requirement, the AI enters brainstorming and asks key questions: should comments be moderated or published directly? Are replies supported? Nested? Is there a character limit? Should the author be notified? Suppose you answer: publish directly, one level of replies, 500-character limit, no links allowed, no author notification. The AI generates a design document covering core requirements, technical approach (database schema, API design, frontend components), and acceptance criteria — then waits for your confirmation.

After confirmation, the AI creates a Worktree, then breaks out five tasks: create comment data model (3 min), add comment API (5 min), comment frontend component (10 min), character limit and link filtering (3 min), integration tests (5 min). Each task has specific file paths and verification conditions.

In the subagent execution phase, the AI completes tasks one by one with automatic review. Your terminal will show something like: Task 1 done, review passed, moving to Task 2; Task 2 done, review found a minor issue, fixed, moving to Task 3. You can step away during this process.

The TDD phase uses character limit validation as an example: the AI writes a test case asserting that comments over 500 characters should be rejected, runs the test, expects failure. Then it writes a `validateComment` function with just the length check logic, runs the test, it passes. Finally it refactors, adding a regex for link detection, runs tests again, still passing. That's a complete RED-GREEN-REFACTOR cycle.

## Comparison with GitHub SpecKit

Superpowers and GitHub SpecKit are both spec-driven development tools, but they have different design philosophies. Superpowers is the work of independent developer Jesse Vincent, taking the form of a Skills plugin system; its core approach is using enforced process to guarantee code quality. SpecKit is an official GitHub product, taking the form of CLI + Skills + extension ecosystem; its core approach is making spec documents themselves executable.

| Feature | Superpowers | GitHub SpecKit |
|------|-------------|----------------|
| Developer | Jesse Vincent (independent) | GitHub official |
| Form | Skills plugin system | CLI + Skills + Extensions ecosystem |
| Core philosophy | Process-first, enforced TDD and review | Spec-first, spec becomes executable document |
| Installation | `/plugin install` | `uv tool install specify-cli` |
| Project constitution | None | Created via `/speckit.constitution` |
| Output files | Dynamically generated | Fixed: spec.md, plan.md, tasks.md |
| TDD | Enforced RED-GREEN-REFACTOR | Recommended but not enforced |
| Git Worktree | Auto-created | Not built-in |
| Subagent execution | Built-in subagent-driven | Via extensions |
| External integrations | Limited | 40+ extensions: Jira, Azure DevOps, Linear, etc. |

SpecKit has capabilities Superpowers lacks. The project constitution lets you define a set of project principles (code quality, test requirements, performance standards) that all subsequent development must follow. The extension ecosystem is rich — Jira sync, code review, automated releases all have ready-made extensions. The preset system allows custom terminology and templates, like calling spec.md a "Voyage Manifest" and tasks.md "Crew Assignments."

Superpowers' differentiating advantages cluster in three areas. Enforced TDD is the biggest difference — SpecKit recommends it, Superpowers mandates it; code written before tests gets deleted. Git Worktree isolation develops each feature in a separate directory, naturally supporting parallel feature development. Subagent-driven development runs each task in a clean environment with the main agent reviewing quality, enabling hours of autonomous work.

The two aren't mutually exclusive. The community has created a `superpowers-bridge` extension that lets SpecKit projects call on Superpowers' TDD, Worktree, and subagent capabilities. This combination suits teams that need both spec management with external integrations and strict quality assurance.

## When to Use Which

| Scenario | Recommended |
|------|----------|
| Individual developer, pursuing code quality | Superpowers |
| Enterprise team, needs Jira/Azure DevOps integration | SpecKit |
| Existing spec process, needs AI-assisted execution | SpecKit |
| Needs long autonomous runs | Superpowers (subagents work for hours) |
| Parallel feature development | Superpowers (Git Worktree isolation) |
| Need both | SpecKit + superpowers-bridge |

A few practical tips when using Superpowers. Don't skip the brainstorming stage — answer the AI's follow-up questions patiently, review the design document carefully, confirm before letting it proceed. Keep task granularity small: one task maps to one file, 2-5 minutes of work, making review and rollback much easier. Don't ignore warnings in code review reports — even "suggested optimization" items should be fixed on the spot before continuing. When developing multiple features in parallel, always use Worktrees; have the AI create an independent worktree directory per feature to avoid conflicts at the source.

When using SpecKit, the first step should be creating a project constitution defining basic principles around code quality, testing, and performance. Then pick extensions based on team needs: `spec-kit-jira` for Jira integration, `spec-kit-review` for code review, `spec-kit-ship` for automated releases.

## Common Questions

Does Superpowers slow down development? Short-term, brainstorming and TDD do add upfront investment. Long-term, requirement confirmation reduces rework, test-first reduces bug-fixing time, and overall efficiency goes up.

Is subagent execution safe? Subagents run in an isolated Worktree environment, and all output goes through main agent review before being accepted.

Does Git Worktree eat disk space? It uses some space, but the AI auto-cleans Worktrees after branch completion. You can also manually run `git worktree list` to check and `git worktree remove <path>` to clean up.

Are SpecKit community extensions stable? Community extensions are maintained by independent developers and not reviewed by GitHub. Check source code and test coverage before using in production.

## References

- [GitHub - obra/superpowers](https://github.com/obra/superpowers)
- [GitHub - github/spec-kit](https://github.com/github/spec-kit)
- [Superpowers Blog Introduction](https://blog.fsck.com/2025/10/09/superpowers/)
- [Spec Kit Documentation](https://github.github.io/spec-kit/)
- [superpowers-bridge Extension](https://github.com/RbBtSn0w/spec-kit-extensions/tree/main/superpowers-bridge)
- [Discord Community](https://discord.gg/Jd8Vphy9jq)
