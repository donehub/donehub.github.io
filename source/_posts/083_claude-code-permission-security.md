---
title: 权限决策的五层防线
date: 2026-04-06
tags: Permission
categories: Claude Code
---

## Agent 执行权限的核心矛盾

AI Agent 需要执行命令、修改文件、访问网络才能完成编程任务，但这些操作都具有破坏性风险。权限系统需要在"让 Agent 高效工作"和"防止危险操作"之间找到平衡点。过于宽松会导致不可逆的损害，过于严格会让 Agent 寸步难行，每次操作都需要人工确认。

Claude Code 的权限系统通过五层决策机制解决这个问题。每一层都可以独立中断工具调用，从确定性的规则匹配到概率性的 AI 分类器，层层递进，最终由用户兜底。

<!-- more -->

## 五层决策架构

权限决策按照固定的顺序执行，分为否决阶段、允许阶段和默认三个阶段。

第一层是权限规则。系统检查工具名称和输入参数是否匹配 deny 或 allow 规则。deny 规则优先级最高，任何匹配都会立即拒绝。规则支持精确匹配（`Bash`）、参数模式匹配（`Bash(git *)`允许所有 git 命令，`Bash(rm -rf *)`禁止删除）、以及通配符（`File*`匹配所有文件工具）。规则来源有八种：用户全局设置、项目设置、本地设置、策略设置、功能标志、CLI 参数、命令和会话级临时规则。

第二层是权限模式。七种模式对应不同的自动化程度：`default`模式下所有写操作需要确认；`acceptEdits`模式下工作目录内的编辑自动允许；`bypassPermissions`完全绕过权限检查；`dontAsk`自动拒绝所有操作；`plan`模式只读操作自动允许，写操作需要确认；`auto`模式由 AI 分类器决策；`bubble`模式将权限请求冒泡到父代理终端。

| 模式 | 读操作 | 写操作 | 危险操作 |
|------|--------|--------|----------|
| `default` | 可能询问 | 询问 | 询问 |
| `acceptEdits` | 自动 | 自动（工作目录内） | 询问 |
| `bypassPermissions` | 自动 | 自动 | 自动 |
| `dontAsk` | 自动拒绝 | 自动拒绝 | 自动拒绝 |
| `plan` | 自动 | 询问 | 询问 |
| `auto` | 分类器决策 | 分类器决策 | 询问 |
| `bubble` | 冒泡到父 | 冒泡到父 | 冒泡到父 |

第三层是钩子拦截。PreToolUse 钩子在工具执行前运行，可以拦截、修改或阻塞操作。钩子退出码 0 表示成功（可能修改了输入），退出码 2 表示阻塞（展示错误信息给模型），其他退出码展示给用户。

第四层是安全分类器。在 `auto` 模式下，AI 分类器评估工具调用的安全性，返回 0-1 之间的分数。分数高于 0.8 自动允许，低于 0.2 自动拒绝，中间区间询问用户。分类器有拒绝计数机制，连续拒绝 3 次后回退到用户审批，防止陷入拒绝循环。

第五层是用户确认。如果前四层都没有做出决定，系统弹出对话框展示操作详情，由用户最终判断。

## 决策原因追溯

每次权限决策都会记录原因，用于调试和审计：

```typescript
type DecisionReason =
  | { type: 'rule'; source: PermissionRuleSource; pattern: string }
  | { type: 'mode'; mode: PermissionMode }
  | { type: 'hook'; hookName: string }
  | { type: 'classifier'; score: number }
  | { type: 'user'; temporary: boolean }
```

这个设计让权限系统的行为完全可解释。当用户遇到意外的允许或拒绝时，可以通过决策原因追溯到具体是哪一层、哪条规则、哪个分数做出的判断。

## Bash 命令的安全解析

Bash 工具是权限控制最复杂的场景，因为命令语法灵活，可以通过管道、重定向、命令替换等方式隐藏危险操作。

安全包装器剥离是第一道处理。`nohup rm -rf /`、`timeout 10 rm -rf /`、`nice rm -rf /` 这些命令中的包装器不改变底层操作的危险性，系统会剥离 timeout、time、nice、stdbuf、nohup 等包装器，直接检查核心命令。

复合命令分解是第二道处理。对于 `cmd1 && cmd2 | cmd3` 这样的管道或链式命令，系统使用 tree-sitter 解析命令 AST，提取所有子命令，每个子命令独立检查权限。任何一个子命令被拒绝，整个命令就被拒绝。

Tree-sitter AST 解析还能检测更隐蔽的危险模式：`eval`和`source`命令可以执行任意代码，`$(...)`和反引号命令替换可以注入恶意命令，`${...}`变量扩展可能泄露敏感信息，zsh 特殊内置命令有副作用。包含命令替换或复杂扩展的命令会被标记为"too-complex"，需要用户手动确认。

路径约束检查是第三道处理。输出重定向的目标路径必须在允许的工作目录内，不能写入 `.git`、`.vscode`、`.claude` 等危险目录。系统还会检测 `cd` 加 `git` 的复合命令，防止裸仓库 RCE 攻击。

## 文件操作的安全约束

文件编辑有一个硬性前提：必须先读取文件。`readFileState` 记录每个文件的读取时间戳，编辑时检查文件是否在读取后被修改。如果文件在读取后被外部修改，编辑会被拒绝，防止覆盖并发更新。

危险文件和目录有额外的保护。`.gitconfig`、`.gitmodules`、`.bashrc`、`.zshrc`、`.claude.json` 等文件，以及 `.git`、`.vscode`、`.idea`、`.claude` 等目录，修改这些路径会触发额外的安全检查。

路径安全检查还覆盖了多种攻击向量：可疑的 Windows 路径字符（`<>:"|?*`）、ADS（Alternate Data Stream）攻击（`::`语法）、短名称绕过（`~1`等 8.3 格式）、长路径前缀（`\\?\`）等。这些检查确保 Agent 不会通过路径混淆绕过权限控制。

## Auto 模式的分类器逻辑

`auto` 模式让 AI 分类器代替用户做权限决策。分类器首先检查快速路径：如果操作在 `acceptEdits` 允许范围内，或者是已知的安全工具（只读操作），直接放行。否则调用分类器 API 评估操作的安全性。

```typescript
async function classifyWithAI(tool, input, context): Promise<PermissionResult> {
  // 快速路径：acceptEdits 或安全工具白名单
  if (isAcceptEditsAllowed(tool, input, context)) return { behavior: 'allow' }
  if (isSafeTool(tool)) return { behavior: 'allow' }

  // 调用分类器 API
  const score = await callClassifierAPI(tool.toAutoClassifierInput?.(input) || JSON.stringify(input))

  if (score > 0.8) return { behavior: 'allow', decisionReason: { type: 'classifier', score } }
  if (score < 0.2) return { behavior: 'deny', decisionReason: { type: 'classifier', score } }

  // 不确定区间，询问用户
  return { behavior: 'ask' }
}
```

分类器的拒绝计数机制防止系统陷入死循环。如果连续 3 次被分类器拒绝，系统会回退到用户审批模式，让用户决定是否继续。这个设计避免了 Agent 在分类器边界案例上反复尝试、反复被拒的无效循环。

## 钩子拦截机制

钩子让用户可以在工具执行前后插入自定义逻辑。PreToolUse 钩子在工具执行前运行，可以检查、修改输入参数，或者直接阻塞操作。PostToolUse 钩子在工具执行后运行，通常用于自动化检查（如 lint、format）。

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash(rm *)",
      "hooks": [{
        "type": "command",
        "command": "echo 'Deletion blocked' && exit 2"
      }]
    }],
    "PostToolUse": [{
      "matcher": "Edit",
      "hooks": [{
        "type": "command",
        "command": "npm run lint"
      }]
    }]
  }
}
```

matcher 支持与权限规则相同的模式匹配语法，可以精确到具体的工具参数。这个机制让权限系统具备高度可扩展性，用户可以根据项目需求定义自己的安全策略，而不需要修改核心代码。

## 关键源文件

| 文件 | 职责 |
|------|------|
| `src/types/permissions.ts` | 权限类型定义 |
| `src/utils/permissions/permissions.ts` | 权限检查核心逻辑 |
| `src/utils/permissions/filesystem.ts` | 文件系统权限控制 |
| `src/utils/permissions/shellRuleMatching.ts` | Shell 规则匹配 |
| `src/utils/permissions/bashClassifier.ts` | Bash 分类器 |
| `src/utils/permissions/yoloClassifier.ts` | Auto 模式分类器 |
| `src/tools/BashTool/bashPermissions.ts` | Bash 权限检查 |
| `src/tools/BashTool/pathValidation.ts` | Bash 路径验证 |
| `src/tools/FileEditTool/FileEditTool.ts` | 文件编辑工具实现 |
| `src/services/tools/toolHooks.ts` | 工具钩子 |

---

**系列文章导航：**
- 上一篇：[Skills 系统：条件激活与动态发现](/2026/04/06/084_claude-code-skills-system/)
- 下一篇：[跨会话记忆：四种类型与自动提取机制](/2026/04/06/081_claude-code-memory-system/)
