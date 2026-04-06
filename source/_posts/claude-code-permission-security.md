---
title: 权限与安全：分层模型与人机协作
date: 2026-04-06
tags: Permission
categories: Claude Code
---

> AI Agent 执行命令、修改文件、访问网络——这些都是高风险操作。Claude Code 的权限系统设计了一个分层的决策模型：规则 → 模式 → 钩子 → 分类器 → 用户确认。每一层都可以独立中断工具调用，确保安全性。

<!-- more -->

## 导读：为什么权限如此重要？

想象这个场景：

> AI Agent 正在帮你重构代码，突然它执行了 `rm -rf node_modules`。

如果没有权限检查，这个命令会直接执行，删除所有依赖。但在 Claude Code 中，这个命令会触发：

1. **规则检查**：匹配 deny 规则？`rm -rf *` 通常是 deny 的
2. **模式检查**：当前是什么权限模式？`default` 模式需要确认
3. **钩子检查**：PreToolUse 钩子是否拦截？
4. **分类器检查**：安全分类器是否判定为危险？
5. **用户确认**：弹出对话框，让用户决定

每一层都是独立的防线，确保危险操作不会静默执行。

---

## 一、分层权限模型

### 1.1 权限决策层级

```
┌─────────────────────────────────────┐
│         权限规则（Rules）             │
│  来源：userSettings, projectSettings │
│        flagSettings, policySettings  │
├─────────────────────────────────────┤
│        权限模式（Modes）              │
│  default | plan | acceptEdits       │
│  bypassPermissions | auto | bubble  │
├─────────────────────────────────────┤
│         钩子（Hooks）                │
│  PreToolUse 可拦截或修改            │
├─────────────────────────────────────┤
│      安全分类器（Classifier）         │
│  ML 模型评估工具调用安全性           │
├─────────────────────────────────────┤
│         用户确认                     │
│  弹出对话框，展示详细信息            │
└─────────────────────────────────────┘
```

### 1.2 权限模式详解

```typescript
// src/types/permissions.ts
type PermissionMode =
  | 'acceptEdits'      // 工作目录内编辑自动允许
  | 'bypassPermissions' // 完全绕过权限
  | 'default'          // 默认模式，需要审批
  | 'dontAsk'          // 自动拒绝
  | 'plan'             // 计划模式
  | 'auto'             // 自动模式（AI 分类器决策）
  | 'bubble'           // 内部模式（权限冒泡到父代理）
```

**模式行为表**：

| 模式 | 读操作 | 写操作 | 危险操作 |
|------|--------|--------|----------|
| `default` | 可能询问 | 询问 | 询问 |
| `acceptEdits` | 自动 | 自动（工作目录内） | 询问 |
| `bypassPermissions` | 自动 | 自动 | 自动 |
| `dontAsk` | 自动拒绝 | 自动拒绝 | 自动拒绝 |
| `plan` | 自动 | 询问 | 询问 |
| `auto` | 分类器决策 | 分类器决策 | 询问 |
| `bubble` | 冒泡到父 | 冒泡到父 | 冒泡到父 |

---

## 二、权限决策流程

### 2.1 完整决策链

```typescript
// src/utils/permissions/permissions.ts
async function hasPermissionsToUseToolInner(
  tool: Tool,
  input: unknown,
  context: ToolUseContext,
): Promise<PermissionResult> {
  // ===== Phase 1: 否决阶段 =====
  
  // 1a. 检查工具级 deny 规则
  const denyResult = checkDenyRules(tool.name, input, context)
  if (denyResult) return { behavior: 'deny', ...denyResult }
  
  // 1b. 检查工具级 ask 规则（沙箱自动允许例外）
  const askResult = checkAskRules(tool.name, input, context)
  if (askResult && !isSandboxAutoAllow(input, context)) {
    return { behavior: 'ask', ...askResult }
  }
  
  // 1c. 工具特定权限检查
  if (tool.checkPermissions) {
    const toolResult = await tool.checkPermissions(input, context)
    if (toolResult.behavior !== 'passthrough') return toolResult
  }
  
  // 1d. 工具实现拒绝
  const implResult = checkImplementationDeny(tool, input, context)
  if (implResult) return { behavior: 'deny', ...implResult }
  
  // 1e. 需要用户交互（绕过模式也需审批）
  if (requiresUserInteraction(tool, input)) {
    return { behavior: 'ask', message: 'This operation requires user interaction' }
  }
  
  // 1f. 内容特定 ask 规则
  const contentAskResult = checkContentAskRules(tool, input, context)
  if (contentAskResult) return { behavior: 'ask', ...contentAskResult }
  
  // 1g. 安全检查（.git/, .claude/等路径）
  const safetyResult = checkPathSafety(tool, input, context)
  if (safetyResult) return { behavior: 'ask', ...safetyResult }
  
  // ===== Phase 2: 允许阶段 =====
  
  // 2a. bypassPermissions 模式检查
  if (context.permissionContext.mode === 'bypassPermissions') {
    return { behavior: 'allow', decisionReason: { type: 'mode' } }
  }
  
  // 2b. 工具级 allow 规则
  const allowResult = checkAllowRules(tool.name, input, context)
  if (allowResult) return { behavior: 'allow', ...allowResult }
  
  // ===== Phase 3: 默认 =====
  return { behavior: 'passthrough' }
}
```

### 2.2 决策原因追溯

每次权限决策都会记录原因：

```typescript
type DecisionReason =
  | { type: 'rule'; source: PermissionRuleSource; pattern: string }
  | { type: 'mode'; mode: PermissionMode }
  | { type: 'hook'; hookName: string }
  | { type: 'classifier'; score: number }
  | { type: 'user'; temporary: boolean }
```

这对于调试和审计至关重要。

---

## 三、规则匹配机制

### 3.1 规则来源

```typescript
type PermissionRuleSource =
  | 'userSettings'      // 用户全局设置
  | 'projectSettings'   // 项目设置
  | 'localSettings'     // 本地设置
  | 'policySettings'    // 策略设置（只读）
  | 'flagSettings'      // 功能标志设置
  | 'cliArg'            // CLI 参数
  | 'command'           // 命令
  | 'session'           // 会话级（临时）
```

### 3.2 规则模式匹配

```typescript
// 精确匹配
{ tool: 'Bash', behavior: 'deny' }

// 参数模式匹配
{ tool: 'Bash(git *)', behavior: 'allow' }   // 允许所有 git 命令
{ tool: 'Bash(rm -rf *)', behavior: 'deny' }  // 禁止 rm -rf

// 通配符
{ tool: 'File*', behavior: 'allow' }          // 允许所有 File 开头的工具
{ tool: '*', behavior: 'deny' }               // 禁止所有工具
```

### 3.3 子命令处理（Bash 工具）

对于复合命令（如 `cmd1 && cmd2 | cmd3`）：

```typescript
// src/tools/BashTool/bashPermissions.ts
function checkCompoundCommand(command: string, context): PermissionResult {
  // 1. 使用 tree-sitter 解析命令
  const ast = parseCommand(command)
  
  // 2. 提取所有子命令
  const subCommands = extractSubCommands(ast)
  
  // 3. 每个子命令独立检查
  for (const sub of subCommands) {
    const result = checkSubCommand(sub, context)
    if (result.behavior === 'deny') {
      return { behavior: 'deny', message: `Subcommand denied: ${sub}` }
    }
  }
  
  // 4. 所有子命令允许则整个命令允许
  return { behavior: 'allow' }
}
```

---

## 四、Bash 工具安全设计

### 4.1 安全包装器剥离

```typescript
// src/tools/BashTool/bashPermissions.ts
const SAFE_WRAPPER_PATTERNS = [
  /^timeout[ \t]+.../,  // timeout 命令
  /^time[ \t]+/,        // time 命令
  /^nice(?:[ \t]+...)?/, // nice 命令
  /^stdbuf(?:[ \t]+...)?/, // stdbuf 命令
  /^nohup[ \t]+/,       // nohup 命令
]

function stripSafeWrappers(command: string): string {
  for (const pattern of SAFE_WRAPPER_PATTERNS) {
    command = command.replace(pattern, '')
  }
  return command.trim()
}
```

**为什么剥离**：`nohup rm -rf /` 仍然是 `rm -rf /`，包装器不改变危险性。

### 4.2 Tree-sitter AST 安全解析

```typescript
// src/tools/BashTool/bashPermissions.ts
async function parseCommandRaw(command: string): Promise<ParseResult> {
  const ast = await treeSitterParse(command)
  
  if (containsCommandSubstitution(ast)) {
    return { kind: 'too-complex', reason: 'Contains command substitution' }
  }
  
  if (containsExpansion(ast)) {
    return { kind: 'too-complex', reason: 'Contains expansion' }
  }
  
  const sem = checkSemantics(ast.commands)
  if (!sem.ok) {
    return { kind: 'dangerous', reason: sem.reason }
  }
  
  return { kind: 'simple', commands: ast.commands }
}
```

**检测的危险模式**：
- `eval`、`source`、`.` 命令
- `$(...)` 命令替换
- 反引号 `` `...` `` 命令替换
- `${...}` 变量扩展
- zsh 特殊内置命令

### 4.3 安全环境变量

```typescript
const SAFE_ENV_VARS = new Set([
  'NODE_ENV', 'GOOS', 'GOARCH', 'RUST_LOG',
  'LANG', 'TZ', 'TERM', 'NO_COLOR',
  // 注意：PATH, LD_PRELOAD, PYTHONPATH 等危险变量不在白名单中
])
```

### 4.4 路径约束检查

```typescript
// src/tools/BashTool/pathValidation.ts
function validateOutputRedirect(command: BashCommand, context): ValidationResult {
  for (const redirect of command.redirects) {
    const resolvedPath = resolvePath(redirect.target)
    
    // 检查是否在允许的工作目录内
    if (!isInAllowedDirectory(resolvedPath, context)) {
      return { ok: false, reason: `Redirect path not in allowed directory: ${resolvedPath}` }
    }
    
    // 检查是否是危险路径
    if (isDangerousPath(resolvedPath)) {
      return { ok: false, reason: `Redirect to dangerous path: ${resolvedPath}` }
    }
  }
  return { ok: true }
}
```

### 4.5 cd + git 复合命令检查

防止裸仓库 RCE（Remote Code Execution）：

```typescript
function checkCdGitCompound(command: string): ValidationResult {
  const parts = parseCompoundCommand(command)
  
  for (let i = 0; i < parts.length; i++) {
    if (parts[i].startsWith('cd ') && parts[i + 1]?.startsWith('git ')) {
      const targetDir = extractCdTarget(parts[i])
      if (await isBareRepo(targetDir)) {
        return { ok: false, reason: 'Bare repo RCE risk' }
      }
    }
  }
  return { ok: true }
}
```

---

## 五、文件操作权限控制

### 5.1 危险文件和目录

```typescript
// src/utils/permissions/filesystem.ts
export const DANGEROUS_FILES = [
  '.gitconfig', '.gitmodules',
  '.bashrc', '.bash_profile', '.zshrc',
  '.ripgreprc', '.mcp.json', '.claude.json'
]

export const DANGEROUS_DIRECTORIES = [
  '.git', '.vscode', '.idea', '.claude'
]
```

### 5.2 编辑前必须读取

```typescript
// src/tools/FileEditTool/FileEditTool.ts
async function validateInput(input, context): Promise<ValidationResult> {
  // 必须先读取
  const readState = context.readFileState.get(input.file_path)
  if (!readState) {
    return { result: false, message: 'Must read file before editing' }
  }
  
  // 文件未被修改
  const currentMtime = (await stat(input.file_path)).mtimeMs
  if (currentMtime > readState.timestamp) {
    return { result: false, message: 'File was modified after reading' }
  }
  
  return { result: true }
}
```

### 5.3 自动编辑安全检查

```typescript
function checkPathSafetyForAutoEdit(path: string): SafetyCheckResult {
  // 1. 可疑 Windows 路径模式
  if (/[<>:"|?*]/.test(path)) {
    return { safe: false, message: 'Invalid characters in path' }
  }
  
  // 2. ADS（Alternate Data Stream）攻击
  if (path.includes('::')) {
    return { safe: false, message: 'ADS attack detected' }
  }
  
  // 3. 短名称绕过
  if (/~[0-9]/.test(path)) {
    return { safe: false, message: 'Short name bypass detected' }
  }
  
  // 4. 长路径前缀
  if (path.startsWith('\\\\?\\')) {
    return { safe: false, message: 'Long path prefix detected' }
  }
  
  // 5. Claude 配置文件
  if (isClaudeConfigFile(path)) {
    return { safe: false, message: 'Claude config file' }
  }
  
  return { safe: true }
}
```

---

## 六、Auto 模式分类器

### 6.1 工作原理

在 `auto` 模式下，权限决策通过 AI 分类器：

```typescript
// src/utils/permissions/yoloClassifier.ts
async function classifyWithAI(
  tool: Tool,
  input: unknown,
  context: ToolUseContext,
): Promise<PermissionResult> {
  // 1. 检查 acceptEdits 快速路径
  if (isAcceptEditsAllowed(tool, input, context)) {
    return { behavior: 'allow' }
  }
  
  // 2. 检查安全工具白名单
  if (isSafeTool(tool)) {
    return { behavior: 'allow' }
  }
  
  // 3. 调用分类器 API
  const classifierInput = tool.toAutoClassifierInput?.(input) || JSON.stringify(input)
  const score = await callClassifierAPI(classifierInput)
  
  // 4. 根据分数决策
  if (score > 0.8) {
    return { behavior: 'allow', decisionReason: { type: 'classifier', score } }
  }
  if (score < 0.2) {
    return { behavior: 'deny', decisionReason: { type: 'classifier', score } }
  }
  
  // 5. 不确定时询问用户
  return { behavior: 'ask' }
}
```

### 6.2 拒绝计数

```typescript
// 防止分类器陷入拒绝循环
const denialTracking: DenialTrackingState = {
  consecutiveDenials: 0,
  maxConsecutiveDenials: 3,
}

function handleDenial(): PermissionResult {
  denialTracking.consecutiveDenials++
  if (denialTracking.consecutiveDenials >= denialTracking.maxConsecutiveDenials) {
    // 回退到用户审批
    return { behavior: 'ask', message: 'Too many denials, please decide' }
  }
  return { behavior: 'deny' }
}
```

---

## 七、钩子拦截

### 7.1 PreToolUse 钩子

```typescript
// src/services/tools/toolHooks.ts
async function runPreToolUseHooks(
  tool: Tool,
  input: unknown,
  context: ToolUseContext,
): Promise<HookResult> {
  const hooks = getHooksForTool(tool.name, context)
  
  for (const hook of hooks) {
    const result = await executeHook(hook, {
      tool_name: tool.name,
      tool_input: input,
    })
    
    switch (result.exitCode) {
      case 0:
        // 成功，可能修改了 input
        if (result.stdout) {
          input = parseModifiedInput(result.stdout)
        }
        break
      case 2:
        // 阻塞，展示错误给模型
        return {
          blocked: true,
          message: result.stderr,
          modifiedInput: parseModifiedInput(result.stdout),
        }
      default:
        // 展示给用户
        logHookOutput(result.stdout)
        break
    }
  }
  
  return { blocked: false, modifiedInput: input }
}
```

### 7.2 钩子配置示例

```json
// settings.json
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

---

## 八、关键源文件索引

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

## 九、总结

Claude Code 的权限系统体现了几个核心设计原则：

1. **分层决策**：规则 → 模式 → 钩子 → 分类器 → 用户确认
2. **Deny 优先**：任何 deny 匹配立即拒绝
3. **AST 级安全**：使用 tree-sitter 解析 Bash 命令，检测注入
4. **路径约束**：严格限制文件操作在工作目录内
5. **编辑前读取**：防止盲目覆盖，检测并发修改
6. **可追溯性**：每个决策都有原因记录

这个设计确保了 AI Agent 的安全性，同时保持了良好的用户体验。

---

**系列文章导航：**
- 上一篇：[Skills 系统：条件激活与动态发现](/claude-code-skills-system/)
- 下一篇：[Memory 系统：跨会话持久化知识库](/claude-code-memory-system/)