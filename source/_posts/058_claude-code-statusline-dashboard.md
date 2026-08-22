---
title: Claude Code 仪表盘
date: 2025-10-28
tags: Claude Code DashBoard
categories: AI
---

用 Claude Code 做开发，有三个指标始终悬在心里：当前用的是哪个模型、context 还剩多少空间、这一轮对话已经烧掉多少钱。这些数字直接影响代码输出质量和你的钱包厚度，但 Claude Code 默认界面不显示它们。从 v1.0.71 开始，Claude Code 提供了 statusLine 自定义状态栏接口，可以写一个脚本来实时监控这三项关键数据。

<!-- more -->

## 三个值得盯的指标

选模型本质上是在能力和成本之间做权衡。Claude Opus 是 Anthropic 的旗舰模型，推理能力处于第一梯队，但单价也是最高的。国内开发者更多选择国产模型接入 Claude Code，比如智谱的 glm-5 和月之暗面的 kimi-k2.5，这两个模型在中文理解上表现不错，价格也比 Anthropic 官方模型低不少。状态栏显示当前模型名，能避免你以为自己在用 Opus、实际上跑了一个轻量模型的尴尬。

Context 是模型的短期工作记忆，存放着整个对话历史、代码片段和上下文信息。当 context 占用率超过 60%，模型的理解能力会明显下降，开始遗忘前面的需求或重复给出矛盾的方案。在状态栏盯着 context 进度条，能让你在占用率临近警戒线时主动精简对话或开启新会话，而不是等到输出质量明显下滑才反应过来。

每次对话都在消耗 token，而 token 直接对应费用。密集开发时一个下午可能跑掉几十美元，没有实时数据的话，月底账单往往会超出预期。把成本数字直接显示在状态栏，对控制开支有直观的约束效果。

## statusLine 接口原理

Claude Code 从 v1.0.71 开始支持自定义状态栏，核心机制是：你写一个脚本，Claude Code 每隔几秒将当前状态数据以 JSON 格式通过 stdin 传给这个脚本，脚本解析 JSON 后把需要的信息格式化输出到终端底部。这个 JSON 里包含的字段覆盖了大部分开发者关心的运行状态，比如 `model.id` 是当前模型标识（如 `glm-5`、`claude-opus-4-6`），`cost.total_cost_usd` 是本次会话累计花费（美元），`context_tokens_used` 和 `context_tokens_limit` 分别对应已用和上限的 context token 数，`usage.input_tokens` 与 `usage.output_tokens` 是输入输出的 token 明细。根据这些信息，你可以自由组合出想要的显示格式。

## Windows 平台配置

Windows 上需要用 PowerShell 脚本来解析 JSON。在 `C:\Users\<你的用户名>\.claude\` 目录下创建 `statusline.ps1` 文件，脚本从 stdin 读取 JSON，提取模型、成本、context 占用率等字段，拼接成一行状态文本输出到终端。

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

脚本写好后，编辑同目录下的 `settings.json`，添加 statusLine 配置项，`refreshInterval` 设为 5000 表示每 5 秒刷新一次，这个数字可以根据需要调整。

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -ExecutionPolicy Bypass -File C:/Users/<你的用户名>/.claude/statusline.ps1",
    "refreshInterval": 5000
  }
}
```

重启 Claude Code 后，终端底部会出现类似这样的输出：

```
Model: glm-5 | Cost: $0.1234 | Context: [##--------] 25% (50.0K/200.0K) [OK]
```

## Mac 平台配置

Mac 上的方案更简洁，用 Bash 加 `jq` 就能完成同样的工作。在 `~/.claude/` 目录下创建 `statusline.sh` 文件：

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

创建完脚本后需要赋予可执行权限，然后在 `~/.claude/settings.json` 中配置 statusLine 字段，refreshInterval 同样可以按需调整。

```bash
chmod +x ~/.claude/statusline.sh
```

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "refreshInterval": 5000
  }
}
```

重启后效果：

```
Model: claude-sonnet-4-6 | Cost: $0.0567 | Context: [######----] 65% (130.0K/200.0K) [WARN]
```

## 状态指示器含义

进度条和状态图标把 context 占用率划分成三个区间。0-60% 显示 `[OK]`，模型输出质量稳定，不需要额外操作。60-80% 显示 `[WARN]`，表示 context 接近饱和，输出质量可能开始出现波动，可以考虑精简后续提问。80% 以上显示 `[!!]`，建议尽快收尾当前对话并开启新会话，否则模型大概率会出现前后矛盾或遗忘关键上下文的情况。

| Context 使用 | 进度条 | 状态 | 含义 |
|-------------|--------|------|------|
| 0-60% | `[####------]` | `[OK]` | 安全区，质量稳定 |
| 60-80% | `[######----]` | `[WARN]` | 警告区，质量开始下降 |
| 80-100% | `[#########-]` | `[!!]` | 危险区，建议精简对话或重启会话 |

## 进阶定制思路

statusLine 接收的 JSON 数据里不只有 context 和成本。`rate_limits` 字段包含 five_hour 和 seven_day 两个维度的配额使用百分比和重置时间，`workspace` 字段里有当前 Git 分支和 worktree 状态。把这些信息也集成到状态栏，开发者可以同时监控配额消耗情况和当前分支，不需要频繁切终端跑 git 命令。

Mac 用户的终端支持 Unicode 字符，可以用方块符号替换 ASCII 的 `#` 和 `-`，进度条的视觉效果更清晰。状态指示器也可以换成彩色圆点 emoji，一眼就能分辨当前所处的区间。

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

## 社区现成方案

如果不想从零开始写脚本，社区已经有几个开源项目可以直接使用。AndyShaman 的 claude-statusline 项目集成了模型显示、context 进度条和 tokens 统计，shanraisshan 的 claude-code-status-line 则额外覆盖了 context 窗口使用率和 Git 状态。直接 clone 对应仓库按说明配置即可。

配置文件位置备忘：Windows 在 `C:\Users\<用户名>\.claude\settings.json`，Mac 在 `~/.claude/settings.json`。
