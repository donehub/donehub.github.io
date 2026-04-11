---
title: Claude Code 仪表盘
date: 2025-10-28
tags: Claude Code DashBoard
categories: AI
---

> 用 Claude Code 写代码的时候，你有没有过这种焦虑：不知道当前用的什么模型、context 还剩多少、这一轮对话花了多少钱？这三个指标直接影响代码质量和你的钱包，但 Claude Code 默认不显示。好在有个 statusLine 功能，可以自定义一个「仪表盘」实时监控这些数据。

<!-- more -->

## 为什么要关注这三个指标？

### 1. 模型类型

不同模型能力不同、价格不同：

| 模型 | 能力 | 价格 |
|------|------|------|
| Claude Opus | 最强推理能力 | 最贵 |
| glm-5 | 智谱出品，中文能力强 | 国内定价 |
| kimi-k2.5 | 月之暗面，长文本处理强 | 国内定价 |

Claude 系列是 Anthropic 的旗舰模型，但国内开发者更多使用国产模型接入 Claude Code，比如智谱的 **glm-5**、月之暗面的 **kimi-k2.5**。这些模型性价比高，中文理解能力也不错。

### 2. Context 使用率

Context 就像 AI 的「短期记忆」，存着你之前的对话、代码片段。当 context 快满了（超过 60%），AI 的理解能力会明显下降——就像一个人记不住刚才说了什么，回答质量自然变差。

### 3. Token 成本

每次对话都要花钱。如果你不知道花了多少，月底收到账单可能会怀疑是不是被盗刷了。

---

## statusLine：Claude Code 的「仪表盘」接口

Claude Code 从 v1.0.71 开始支持自定义状态栏（statusLine）。原理很简单：

1. 你写一个脚本（Windows 用 PowerShell，Mac 用 Bash）
2. Claude Code 每隔几秒把当前状态数据以 JSON 形式传给脚本
3. 脚本解析 JSON，输出你想显示的内容

### JSON 数据结构

脚本会收到以下字段：

| 字段 | 说明 |
|------|------|
| `model.id` | 当前模型 ID（如 `glm-5`、`claude-opus-4-6`） |
| `cost.total_cost_usd` | 会话累计成本（美元） |
| `context_tokens_used` | 已使用的 context tokens |
| `context_tokens_limit` | Context 上限（通常是 200000） |
| `usage.input_tokens` | 输入 tokens |
| `usage.output_tokens` | 输出 tokens |

---

## Windows 平台方案

### 第一步：创建 PowerShell 脚本

在 `C:\Users\<你的用户名>\.claude\` 目录下创建 `statusline.ps1` 文件：

```powershell
# Claude Code Status Line Script
# 从 stdin 读取 JSON 数据并显示状态栏

$jsonInput = [Console]::In.ReadToEnd()

try {
    $data = $jsonInput | ConvertFrom-Json

    # 提取模型（model 可能是对象或字符串）
    $modelRaw = $data.model
    $model = if ($modelRaw.id) { $modelRaw.id } elseif ($modelRaw -is [string]) { $modelRaw } else { "unknown" }

    # 提取成本
    $cost = if ($data.cost -and $data.cost.total_cost_usd) { 
        [math]::Round([double]$data.cost.total_cost_usd, 4) 
    } else { "0" }

    # 提取 context
    $contextUsed = if ($data.context_tokens_used) { [int]$data.context_tokens_used } else { 0 }
    $contextLimit = if ($data.context_tokens_limit) { [int]$data.context_tokens_limit } else { 200000 }

    # 计算百分比
    $percentage = if ($contextLimit -gt 0) { 
        [math]::Round(($contextUsed * 100 / $contextLimit), 1) 
    } else { 0 }

    # 创建进度条（10 格）
    $filledBars = [math]::Floor($percentage / 10)
    $bar = ""
    for ($i = 0; $i -lt 10; $i++) {
        if ($i -lt $filledBars) { $bar += "#" } else { $bar += "-" }
    }

    # 状态指示器
    $statusIcon = if ($percentage -ge 80) { "[!!]" } elseif ($percentage -ge 60) { "[WARN]" } else { "[OK]" }

    # 格式化 token 数字
    function Format-Tokens($tokens) {
        $t = [int]$tokens
        if ($t -ge 1000000) { return "{0:N2}M" -f ($t / 1000000) }
        elseif ($t -ge 1000) { return "{0:N1}K" -f ($t / 1000) }
        else { return $t.ToString() }
    }

    $usedFormatted = Format-Tokens $contextUsed
    $limitFormatted = Format-Tokens $contextLimit

    # 输出状态栏
    $costDisplay = "$" + $cost
    Write-Output "Model: $model | Cost: $costDisplay | Context: [$bar] $percentage% ($usedFormatted/$limitFormatted) $statusIcon"

} catch {
    Write-Output "Status: unavailable"
}
```

### 第二步：修改 settings.json

编辑 `C:\Users\<你的用户名>\.claude\settings.json`，添加 `statusLine` 配置：

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -ExecutionPolicy Bypass -File C:/Users/<你的用户名>/.claude/statusline.ps1",
    "refreshInterval": 5000
  }
}
```

`refreshInterval: 5000` 表示每 5 秒刷新一次。

### 第三步：重启生效

关闭 Claude Code，重新打开。终端底部会显示：

```
Model: glm-5 | Cost: $0.1234 | Context: [##--------] 25% (50.0K/200.0K) [OK]
```

---

## Mac 平台方案

### 第一步：创建 Bash 脚本

在 `~/.claude/` 目录下创建 `statusline.sh` 文件：

```bash
#!/bin/bash
set -euo pipefail

# 读取 JSON 输入
input=$(cat)

# 提取字段（model 可能是对象或字符串）
model=$(echo "$input" | jq -r '.model.id // .model // "unknown"')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // "0"')
context_used=$(echo "$input" | jq -r '.context_tokens_used // 0')
context_limit=$(echo "$input" | jq -r '.context_tokens_limit // 200000')

# 计算百分比
if [ "$context_limit" -gt 0 ]; then
    percentage=$(awk "BEGIN {printf \"%.1f\", $context_used * 100 / $context_limit}")
else
    percentage=0
fi

# 创建进度条（10 格）
filled=$((percentage / 10))
bar=""
for i in $(seq 1 10); do
    if [ $i -le $filled ]; then
        bar="${bar}#"
    else
        bar="${bar}-"
    fi
done

# 状态指示器
if [ $(awk "BEGIN {print ($percentage >= 80)}") -eq 1 ]; then
    status="[!!]"
elif [ $(awk "BEGIN {print ($percentage >= 60)}") -eq 1 ]; then
    status="[WARN]"
else
    status="[OK]"
fi

# 格式化 token 数字
format_tokens() {
    local tokens=$1
    if [ $tokens -ge 1000000 ]; then
        awk "BEGIN {printf \"%.2fM\", $tokens / 1000000}"
    elif [ $tokens -ge 1000 ]; then
        awk "BEGIN {printf \"%.1fK\", $tokens / 1000}"
    else
        echo $tokens
    fi
}

used_formatted=$(format_tokens $context_used)
limit_formatted=$(format_tokens $context_limit)

# 输出状态栏
echo "Model: $model | Cost: \$$cost | Context: [$bar] ${percentage}% ($used_formatted/$limit_formatted) $status"
```

### 第二步：设置可执行权限

```bash
chmod +x ~/.claude/statusline.sh
```

### 第三步：修改 settings.json

编辑 `~/.claude/settings.json`，添加配置：

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "refreshInterval": 5000
  }
}
```

### 第四步：重启生效

重启 Claude Code 后，终端底部会显示：

```
Model: claude-sonnet-4-6 | Cost: $0.0567 | Context: [######----] 65% (130.0K/200.0K) [WARN]
```

---

## 状态指示器说明

进度条和状态图标帮你一眼判断当前状态：

| Context 使用 | 进度条 | 状态 | 含义 |
|-------------|--------|------|------|
| 0-60% | `[####------]` | `[OK]` | 安全区，质量稳定 |
| 60-80% | `[######----]` | `[WARN]` | 警告区，质量开始下降 |
| 80-100% | `[#########-]` | `[!!]` | 危险区，建议精简对话或重启会话 |

---

## 进阶定制

### 添加更多指标

JSON 数据里还有很多字段可以挖掘：

```json
{
  "rate_limits": {
    "five_hour": { "used_percentage": 45, "resets_at": "2025-04-11T22:00:00Z" },
    "seven_day": { "used_percentage": 12, "resets_at": "2025-04-18T00:00:00Z" }
  },
  "workspace": {
    "git_branch": "feature/login",
    "git_worktree": false
  }
}
```

你可以把 Git 分支、Rate Limit 重置时间也加到状态栏。

### 使用 Unicode 字符（Mac）

Mac 终端支持 Unicode，可以用更美观的字符：

```bash
# 进度条用方块字符
bar=""
for i in $(seq 1 10); do
    if [ $i -le $filled ]; then
        bar="${bar}█"
    else
        bar="${bar}░"
    fi
done

# 状态用 emoji
if [ $(awk "BEGIN {print ($percentage >= 80)}") -eq 1 ]; then
    status="🔴"
elif [ $(awk "BEGIN {print ($percentage >= 60)}") -eq 1 ]; then
    status="🟠"
else
    status="🟢"
fi
```

---

## 社区资源

已经有开发者分享了现成的 statusLine 脚本：

- **[AndyShaman/claude-statusline](https://github.com/AndyShaman/claude-statusline)** - 显示模型、context 进度条、tokens
- **[shanraisshan/claude-code-status-line](https://github.com/shanraisshan/claude-code-status-line)** - 显示 context 窗口使用率、Git 状态

不想自己写脚本的，可以直接 clone 这些仓库使用。

---

## 小结

Claude Code 的 statusLine 功能让你可以：

1. **实时监控模型** - 确保用的是预期的模型
2. **跟踪 context 使用** - 超过 60% 时提醒自己精简对话
3. **控制成本** - 知道花了多少钱，心中有数

Windows 用 PowerShell，Mac 用 Bash，配置好脚本和 settings.json 就能生效。如果你有更复杂的需求，可以自行扩展脚本，把 Rate Limit、Git 状态等信息也加进去。

**关键配置文件位置：**

- Windows: `C:\Users\<用户名>\.claude\settings.json`
- Mac: `~/.claude/settings.json`