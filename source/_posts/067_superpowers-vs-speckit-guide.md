---
title: Superpowers 介绍与使用
date: 2026-02-15
tags: AI 工具
categories: AI
---

让 AI 编码助手直接写代码，最常见的问题是它拿到需求就动手，不考虑边界条件，不写测试，做着做着就偏离了原始需求。多个功能并行开发时，代码混在同一个分支上，连回滚都困难。Superpowers 是一套通过技能（Skills）让 AI 编码助手遵循严格工程流程的工作流系统，由 Jesse Vincent（Perl 专家、Markdown 发明者之一）开发。它的核心思路是让 AI 先规划、再测试、再实现、再审查，像一个有纪律的工程师那样工作，而不是一个急于交付的实习生。

<!-- more -->

## 核心理念

没有流程约束时，AI 拿到任务就开始写代码，写完就交，测试是事后补的，分支是混用的。装了 Superpowers 之后，AI 会先确认需求细节，写测试，再实现，最后在隔离的 Git Worktree 中完成开发。两者的区别可以用一句话概括：Superpowers 不是让 AI 更聪明，而是让 AI 更可靠。

它目前支持 Claude Code、Cursor、GitHub Copilot CLI、Gemini CLI、Codex CLI 和 OpenCode 等主流 AI 编码工具。Claude Code 和 Cursor 可以通过插件市场一键安装，Codex CLI 则需要手动将技能文件复制到配置目录。

| 工具 | 安装方式 |
|------|----------|
| Claude Code | `/plugin install superpowers@claude-plugins-official` |
| Cursor | `/add-plugin superpowers` |
| GitHub Copilot CLI | `copilot plugin install superpowers` |
| Gemini CLI | `gemini extensions install` |
| Codex CLI | 手动配置（克隆仓库后复制技能文件） |
| OpenCode | 手动配置 |

## 七步工作流程

Superpowers 把整个开发过程拆成七个阶段，每个阶段有明确的输入输出和约束条件。

第一阶段是头脑风暴。用户提出需求后，AI 不会直接写代码，而是通过一系列追问来澄清需求细节。比如用户说"加个登录功能"，AI 会追问登录方式、是否需要记住登录状态、安全要求等，最终输出一份设计文档，用户确认后才进入下一步。这一步的目的是防止 AI 自行脑补需求，避免做了半小时发现方向完全跑偏。

第二阶段是创建隔离工作空间。AI 自动创建新分支并初始化一个 Git Worktree，确保开发环境干净且可回滚。主项目目录不受影响，你可以在主目录继续其他工作，AI 在 Worktree 中专心开发目标功能。

第三阶段是编写计划。AI 把设计文档拆成多个小任务，每个任务预计 2 到 5 分钟完成，包含明确的文件路径、代码内容和验证步骤。任务粒度控制得很小，比如"创建评论数据模型"是一个任务，"添加评论 API"是另一个任务，而不是笼统的"实现整个评论功能"。小任务更容易审查、更容易回滚、也更容易并行。

第四阶段是子代理执行。每个任务会被派发给一个全新的子代理来执行，主代理负责审查子代理的输出。这种设计的好处是每个任务都在干净的上下文中执行，不会被前面任务积累的信息污染。主代理可以连续自主工作数小时，用户中途可以去忙别的事情。

第五阶段是强制 TDD。Superpowers 执行严格的 RED-GREEN-REFACTOR 流程：先写一个会失败的测试（RED），再写最少的代码让测试通过（GREEN），最后重构优化（REFACTOR）。如果 AI 先写了代码再写测试，代码会被删除，要求从测试重新开始。这不是建议，是硬性约束。

第六阶段是代码审查。每个任务完成后，主代理从规格合规、代码质量、测试覆盖、安全性四个维度进行审查。关键问题会直接阻塞进度，必须修复后才能继续。

第七阶段是完成分支。所有任务完成后，AI 验证全部测试通过，然后提供合并到主分支、创建 Pull Request、保留分支或丢弃更改四个选项。选择后自动清理 Worktree。

## 实战演示：给博客加评论功能

用一个具体例子来走一遍完整流程。假设你要给博客系统加一个评论功能，支持用户登录后评论。

输入需求后，AI 进入头脑风暴阶段，会问几个关键问题：评论需要审核还是直接发布？支持回复吗？支持嵌套吗？字数有限制吗？需要通知博主吗？假设你回答：直接发布，支持一层回复，500 字上限，不能发链接，不需要通知。AI 会据此生成一份设计文档，包含核心需求、技术方案（数据表结构、API 设计、前端组件）和验收标准，等你确认。

确认后 AI 创建 Worktree，然后拆出五个任务：创建评论数据模型（3 分钟）、添加评论 API（5 分钟）、评论前端组件（10 分钟）、字数限制和链接过滤（3 分钟）、集成测试（5 分钟）。每个任务都有具体的文件路径和验证条件。

进入子代理执行阶段后，AI 逐个完成任务并自动审查。你的终端大概会看到这样的输出：任务 1 完成，审查通过，继续任务 2；任务 2 完成，审查中发现一个小问题，已修复，继续任务 3。整个过程你可以离开去做别的事情。

TDD 阶段以字数验证为例：AI 先写一个测试用例，断言超过 500 字的评论应该被拒绝，运行测试，预期失败。然后写一个 `validateComment` 函数，只包含长度检查逻辑，运行测试，通过。最后重构，加入链接检测的正则表达式，再次运行测试，仍然通过。这就是完整的 RED-GREEN-REFACTOR 循环。

## 与 GitHub SpecKit 的对比

Superpowers 和 GitHub SpecKit 都属于规范驱动开发工具，但设计哲学不同。Superpowers 是独立开发者 Jesse Vincent 的作品，形态是 Skills 插件系统，核心思路是用强制流程来保证代码质量。SpecKit 是 GitHub 官方产品，形态是 CLI 加 Skills 加扩展生态，核心思路是让规范文档本身成为可执行的。

| 特性 | Superpowers | GitHub SpecKit |
|------|-------------|----------------|
| 开发者 | Jesse Vincent（独立开发者） | GitHub 官方 |
| 形态 | Skills 插件系统 | CLI + Skills + Extensions 生态 |
| 核心理念 | 流程至上，强制 TDD 和审查 | 规范至上，spec 成为可执行文档 |
| 安装方式 | `/plugin install` | `uv tool install specify-cli` |
| 项目宪法 | 无 | `/speckit.constitution` 创建 |
| 产出文件 | 动态生成 | 固定：spec.md, plan.md, tasks.md |
| TDD | 强制 RED-GREEN-REFACTOR | 推荐但不强制 |
| Git Worktree | 自动创建 | 无内置 |
| 子代理执行 | 内置 subagent-driven | 通过扩展实现 |
| 外部集成 | 有限 | Jira、Azure DevOps、Linear 等 40+ 扩展 |

SpecKit 有几个 Superpowers 没有的能力。项目宪法功能允许你定义一组项目原则（代码质量、测试要求、性能标准），后续所有开发都在这个框架下进行。扩展生态丰富，Jira 同步、代码审查、自动发布等都有现成的扩展。预设系统允许自定义术语和模板，比如把 spec.md 叫做"Voyage Manifest"，tasks.md 叫做"Crew Assignments"。

Superpowers 的差异化优势集中在三点。强制 TDD 是最大的区别，SpecKit 推荐但 Superpowers 强制执行，代码先于测试写了会被删除。Git Worktree 隔离让每个功能在独立目录开发，天然支持多功能并行。子代理驱动开发让每个任务在干净环境中执行，主代理审查质量，可以连续自主工作数小时。

两者并不冲突。社区已经创建了 `superpowers-bridge` 扩展，可以在 SpecKit 项目中调用 Superpowers 的 TDD、Worktree 和子代理能力。这种组合方式适合既需要规范管理和外部集成，又需要严格质量保障的团队。

## 适用场景与选择建议

| 场景 | 推荐方案 |
|------|----------|
| 个人开发者，追求代码质量 | Superpowers |
| 企业团队，需要 Jira/Azure DevOps 集成 | SpecKit |
| 已有完善规范流程，需要 AI 辅助执行 | SpecKit |
| 需要长时间自主运行 | Superpowers（子代理可连续工作数小时） |
| 多功能并行开发 | Superpowers（Git Worktree 隔离） |
| 两者都需要 | SpecKit + superpowers-bridge |

使用 Superpowers 时有几点经验值得注意。头脑风暴阶段不要跳过，耐心回答 AI 的追问，仔细审阅设计文档，确认后再让它动手。任务粒度要小，一个任务对应一个文件、2 到 5 分钟的工作量，审查和回滚都更方便。代码审查报告中的警告不要忽略，即使是"建议优化"级别的，让 AI 当场修复再继续。多功能并行时一定要用 Worktree，让 AI 为每个功能创建独立的 worktree 目录，从根源上避免冲突。

使用 SpecKit 时，第一步建议先创建项目宪法，定义代码质量、测试和性能方面的基本原则。然后根据团队需求选择扩展：需要 Jira 集成用 `spec-kit-jira`，需要代码审查用 `spec-kit-review`，需要自动发布用 `spec-kit-ship`。

## 常见问题

Superpowers 会拖慢开发速度吗？短期来看，头脑风暴和 TDD 确实增加了前期投入。但从长期看，需求确认减少了返工，测试先行减少了 bug 修复时间，整体效率是提升的。

子代理执行安全吗？子代理在隔离的 Worktree 环境中执行，所有产出经过主代理审查后才被采纳。

Git Worktree 占用磁盘空间吗？会占用一些空间，但分支完成后 AI 会自动清理 Worktree。也可以手动执行 `git worktree list` 查看、`git worktree remove <path>` 清理。

SpecKit 的社区扩展稳定吗？社区扩展由独立开发者维护，GitHub 官方不进行审核。生产环境使用前建议先查看源代码和测试覆盖情况。

## 参考资料

- [GitHub - obra/superpowers](https://github.com/obra/superpowers)
- [GitHub - github/spec-kit](https://github.com/github/spec-kit)
- [Superpowers 博客介绍](https://blog.fsck.com/2025/10/09/superpowers/)
- [Spec Kit 文档](https://github.github.io/spec-kit/)
- [superpowers-bridge 扩展](https://github.com/RbBtSn0w/spec-kit-extensions/tree/main/superpowers-bridge)
- [Discord 社区](https://discord.gg/Jd8Vphy9jq)
