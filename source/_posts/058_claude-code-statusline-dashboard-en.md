---
title: Building a Claude Code Status Bar Dashboard
date: 2025-10-28
lang: en
label: 058_claude-code-statusline-dashboard
tags: Claude Code DashBoard
categories: AI
---

When you're developing with Claude Code, three numbers are always lurking in the back of your mind: which model you're currently running, how much context headroom is left, and how much money this session has burned through. These figures directly affect output quality and your wallet, but Claude Code's default interface doesn't show any of them. Starting from v1.0.71, Claude Code exposes a `statusLine` custom status bar interface — you can write a script to monitor all three in real time.

<!-- more -->

## Three Metrics Worth Watching

Picking a model is fundamentally a trade-off between capability and cost. Claude Opus is Anthropic's flagship, with top-tier reasoning ability and the highest unit price to match. Many Chinese developers opt for domestic models inside Claude Code instead — Zhipu's glm-5 and Moonshot's kimi-k2.5 are popular picks. Both perform well on Chinese comprehension and cost significantly less than Anthropic's own models. Having the current model name on the status bar prevents the awkward moment where you think you're running Opus but it's actually a lightweight model.

Context is the model's short-term working memory — it holds the entire conversation history, code snippets, and contextual information. When context usage crosses 60%, the model's comprehension drops noticeably. It starts forgetting earlier requirements or producing contradictory suggestions. Watching the context progress bar on the status bar lets you proactively slim down the conversation or start a new session as you approach the warning threshold, instead of waiting until output quality visibly degrades.

Every conversation burns tokens, and tokens map directly to dollars. During intensive development sessions, an afternoon can run up tens of dollars. Without real-time visibility, the monthly bill always seems to overshoot expectations. Putting the cost figure right on the status bar has a visceral effect on spending discipline.

## How the statusLine Interface Works

Claude Code has supported a custom status bar since v1.0.71. The mechanism is straightforward: you write a script, and Claude Code feeds the current state as JSON through stdin to that script every few seconds. The script parses the JSON and formats the fields you care about into a single line of text at the bottom of the terminal. The JSON covers most of the runtime state developers care about: `model.id` is the current model identifier (e.g. `glm-5`, `claude-opus-4-6`), `cost.total_cost_usd` is the cumulative session cost in dollars, `context_tokens_used` and `context_tokens_limit` give you the consumed and total context token counts, and `usage.input_tokens` and `usage.output_tokens` break down the input/output token details. You can compose these into whatever display format you like.

## Windows Setup

On Windows, you need a PowerShell script to parse the JSON. Create a `statusline.ps1` file under `C:\Users\<your username>\.claude\`. The script reads JSON from stdin, extracts the model, cost, context usage percentage, and other fields, then outputs a formatted status line to the terminal.

```powershell
# Claude Code Status Line Script
# Reads JSON from stdin and displays a status bar

$jsonInput = [Console]::In.ReadToEnd()

try {
    $data = $jsonInput | ConvertFrom-Json

    # Extract model (model can be an object or string)
    $modelRaw = $data.model
    $model = if ($modelRaw.id) { $modelRaw.id } elseif ($modelRaw -is [string]) { $modelRaw } else { "unknown" }

    # Extract cost
    $cost = if ($data.cost -and $data.cost.total_cost_usd) {
        [math]::Round([double]$data.cost.total_cost_usd, 4)
    } else { "0" }

    # Extract context
    $contextUsed = if ($data.context_tokens_used) { [int]$data.context_tokens_used } else { 0 }
    $contextLimit = if ($data.context_tokens_limit) { [int]$data.context_tokens_limit } else { 200000 }

    # Calculate percentage
    $percentage = if ($contextLimit -gt 0) {
        [math]::Round(($contextUsed * 100 / $contextLimit), 1)
    } else { 0 }

    # Create progress bar (10 slots)
    $filledBars = [math]::Floor($percentage / 10)
    $bar = ""
    for ($i = 0; $i -lt 10; $i++) {
        if ($i -lt $filledBars) { $bar += "#" } else { $bar += "-" }
    }

    # Status indicator
    $statusIcon = if ($percentage -ge 80) { "[!!]" } elseif ($percentage -ge 60) { "[WARN]" } else { "[OK]" }

    # Format token numbers
    function Format-Tokens($tokens) {
        $t = [int]$tokens
        if ($t -ge 1000000) { return "{0:N2}M" -f ($t / 1000000) }
        elseif ($t -ge 1000) { return "{0:N1}K" -f ($t / 1000) }
        else { return $t.ToString() }
    }

    $usedFormatted = Format-Tokens $contextUsed
    $limitFormatted = Format-Tokens $contextLimit

    # Output status line
    $costDisplay = "$" + $cost
    Write-Output "Model: $model | Cost: $costDisplay | Context: [$bar] $percentage% ($usedFormatted/$limitFormatted) $statusIcon"

} catch {
    Write-Output "Status: unavailable"
}
```

Once the script is ready, edit `settings.json` in the same directory and add the statusLine configuration. Set `refreshInterval` to 5000 for a 5-second refresh — adjust as needed.

```json
{
  "statusLine": {
    "type": "command",
    "command": "powershell -ExecutionPolicy Bypass -File C:/Users/<your username>/.claude/statusline.ps1",
    "refreshInterval": 5000
  }
}
```

After restarting Claude Code, you'll see something like this at the bottom of the terminal:

```
Model: glm-5 | Cost: $0.1234 | Context: [##--------] 25% (50.0K/200.0K) [OK]
```

## Mac Setup

The Mac approach is leaner — Bash plus `jq` handles the same job. Create a `statusline.sh` file under `~/.claude/`:

```bash
#!/bin/bash
set -euo pipefail

# Read JSON input
input=$(cat)

# Extract fields (model can be an object or string)
model=$(echo "$input" | jq -r '.model.id // .model // "unknown"')
cost=$(echo "$input" | jq -r '.cost.total_cost_usd // "0"')
context_used=$(echo "$input" | jq -r '.context_tokens_used // 0')
context_limit=$(echo "$input" | jq -r '.context_tokens_limit // 200000')

# Calculate percentage
if [ "$context_limit" -gt 0 ]; then
    percentage=$(awk "BEGIN {printf \"%.1f\", $context_used * 100 / $context_limit}")
else
    percentage=0
fi

# Create progress bar (10 slots)
filled=$((percentage / 10))
bar=""
for i in $(seq 1 10); do
    if [ $i -le $filled ]; then
        bar="${bar}#"
    else
        bar="${bar}-"
    fi
done

# Status indicator
if [ $(awk "BEGIN {print ($percentage >= 80)}") -eq 1 ]; then
    status="[!!]"
elif [ $(awk "BEGIN {print ($percentage >= 60)}") -eq 1 ]; then
    status="[WARN]"
else
    status="[OK]"
fi

# Format token numbers
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

# Output status line
echo "Model: $model | Cost: \$$cost | Context: [$bar] ${percentage}% ($used_formatted/$limit_formatted) $status"
```

After creating the script, grant it executable permission, then configure the statusLine field in `~/.claude/settings.json`. The refreshInterval works the same way.

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

After restarting:

```
Model: claude-sonnet-4-6 | Cost: $0.0567 | Context: [######----] 65% (130.0K/200.0K) [WARN]
```

## What the Status Indicators Mean

The progress bar and status icon divide context usage into three bands. 0–60% shows `[OK]` — model output quality is stable, no action needed. 60–80% shows `[WARN]` — context is approaching saturation, output quality may start fluctuating, consider trimming your upcoming prompts. Above 80% shows `[!!]` — wrap up the current conversation and start a new session soon, or the model will likely produce contradictions or forget key context.

| Context Usage | Progress Bar | Status | Meaning |
|-------------|--------|------|------|
| 0-60% | `[####------]` | `[OK]` | Safe zone, stable quality |
| 60-80% | `[######----]` | `[WARN]` | Warning zone, quality starting to dip |
| 80-100% | `[#########-]` | `[!!]` | Danger zone, slim down conversation or restart session |

## Customization Ideas

The JSON that statusLine receives contains more than just context and cost. The `rate_limits` field has quota usage percentages and reset times across two dimensions: five-hour and seven-day windows. The `workspace` field holds the current Git branch and worktree state. Integrating those into the status bar lets you monitor quota consumption and branch context without constantly switching terminals to run git commands.

Mac terminals support Unicode characters, so you can swap the ASCII `#` and `-` for block symbols — the progress bar looks noticeably cleaner. Status indicators can also become colored circle emojis for instant visual differentiation.

```bash
# Progress bar with block characters
bar=""
for i in $(seq 1 10); do
    if [ $i -le $filled ]; then
        bar="${bar}█"
    else
        bar="${bar}░"
    fi
done

# Status with emoji
if [ $(awk "BEGIN {print ($percentage >= 80)}") -eq 1 ]; then
    status="🔴"
elif [ $(awk "BEGIN {print ($percentage >= 60)}") -eq 1 ]; then
    status="🟠"
else
    status="🟢"
fi
```

## Ready-Made Community Options

If you don't want to write a script from scratch, a few open-source projects are already available. AndyShaman's claude-statusline project integrates model display, context progress bar, and token statistics. shanraisshan's claude-code-status-line additionally covers context window usage and Git status. Just clone the repo and follow the setup instructions.

Config file locations for reference: Windows at `C:\Users\<username>\.claude\settings.json`, Mac at `~/.claude/settings.json`.
