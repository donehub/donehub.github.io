---
title: Computer Use 桌面控制的九层安全关卡
date: 2026-04-06
tags: Computer Use
categories: Claude Code
---

Claude Code 的 Computer Use 功能让 AI 直接操控桌面环境：点击按钮、输入文字、截图分析界面状态。AI 能看见屏幕并操作鼠标键盘，带来的安全风险同样真实：误删文件、点错按钮、泄露敏感信息。为此，Claude Code 设计了一套九层安全关卡系统，每一层都可以独立拦截危险操作。底层通过 Python Bridge 实现跨语言通信，TypeScript 代理驱动 Python 执行器完成实际的桌面交互。

<!-- more -->

## 整体架构与 Python 选型

Computer Use 的整体架构是一个典型的跨语言代理模式。Claude Code（TypeScript）负责策略决策和权限控制，Python 进程负责执行实际的桌面操作，两者通过 JSON-RPC over stdio 进行通信。这个分层设计的好处是职责清晰：TypeScript 层处理安全逻辑和模型交互，Python 层专注平台 API 调用。

```
Claude Code (TypeScript)
    ↓ JSON-RPC over stdio
Python Bridge (computer_controller.py)
    ↓ Platform Abstraction
Desktop Environment
```

选择 Python 而非 TypeScript 原生实现桌面操作，核心原因是生态成熟度。pyautogui、PyObjC、xdotool 这些库已经稳定运行多年，跨平台接口一致。如果在 TypeScript 中通过 native addon 调用系统 API，维护成本会显著增加。

| 选型因素 | Python 方案 | TypeScript 原生方案 |
|---|---|---|
| 库生态 | pyautogui/PyObjC 成熟稳定 | 需要 native addon，生态碎片化 |
| 跨平台一致性 | 三平台接口统一 | 每个平台需单独封装 |
| 开发迭代速度 | 纯 Python 快速修改 | 编译 native 代码，迭代慢 |
| 维护成本 | 社区维护，更新频繁 | 需自行适配各系统 API 变更 |

## 24 个桌面操作工具

Computer Use 提供了 24 个工具，覆盖输入、显示、文件、进程四个类别。输入类工具处理鼠标点击、双击、拖拽、滚轮滚动、键盘组合键、单键按压、文字输入和剪贴板粘贴。显示类工具负责屏幕截图、获取屏幕尺寸、窗口列表查询、窗口激活、窗口位置和尺寸获取。文件类工具包括读写删除列目录移动复制和查看文件信息。进程类工具提供进程列表查询、启动新进程和终止进程三个操作。

| 类别 | 工具数 | 核心能力 |
|---|---|---|
| 输入（Input） | 9 | 鼠标点击/拖拽/滚动、键盘输入/组合键、剪贴板粘贴 |
| 显示（Display） | 6 | 截图、屏幕尺寸、窗口列表/激活/位置/尺寸 |
| 文件（File） | 7 | 读写删除列目录移动复制、文件信息查询 |
| 进程（Process） | 3 | 进程列表、启动进程、终止进程 |

以鼠标点击工具为例，工具定义通过 JSON Schema 描述参数结构，包括坐标、按钮类型、点击次数。Claude Code 将这些定义注册为可调用的 tool，模型在需要操作桌面时通过 tool_use 发起调用。

```typescript
// src/tools/ComputerUseTool/tools.ts
const computer_mouse_click = {
  name: 'computer_mouse_click',
  inputSchema: {
    type: 'object',
    properties: {
      x: { type: 'number', description: 'X coordinate' },
      y: { type: 'number', description: 'Y coordinate' },
      button: {
        type: 'string',
        enum: ['left', 'right', 'middle'],
        default: 'left'
      },
      clicks: { type: 'number', default: 1 },
    },
    required: ['x', 'y'],
  },
  description: 'Click at the specified coordinates',
}
```

## 九层安全关卡

安全设计是 Computer Use 系统的核心。九层关卡从外到内层层递进，每一层都可以独立拦截操作。这不是理论设计，而是实际代码中的检查链：操作必须通过所有关卡才能执行，任何一层返回 deny 都会立即终止。

| 关卡 | 名称 | 拦截规则 |
|---|---|---|
| Gate 1 | 功能门控 | tengu_computer_use Feature Flag 必须开启 |
| Gate 2 | 用户确认 | 首次使用弹出确认对话框，用户必须授权 |
| Gate 3 | 操作类型检查 | 写操作需要额外的写权限确认 |
| Gate 4 | 路径约束 | 文件操作限制在白名单目录，禁止访问 .git、.claude、系统目录 |
| Gate 5 | 危险命令过滤 | 拦截 rm -rf、killall 等命令，禁止访问密码管理器和银行应用 |
| Gate 6 | 屏幕边界检查 | 鼠标坐标必须在屏幕分辨率范围内，窗口操作必须针对可见窗口 |
| Gate 7 | 操作频率限制 | 每秒最多 10 次操作，连续失败 3 次自动暂停 |
| Gate 8 | 截图内容分析 | 检测密码框、私人信息等敏感内容，检测错误弹窗 |
| Gate 9 | 实时监控 | 用户随时 Ctrl+C 中断，操作日志实时输出 |

代码实现上，gateComputerUseAction 函数按顺序执行所有检查，返回 allow、deny 或 ask 三种结果。前七层在操作执行前完成检查，Gate 8 在截图后进行内容分析，Gate 9 贯穿整个操作生命周期。

```typescript
// src/tools/ComputerUseTool/security.ts
function gateComputerUseAction(
  action: ComputerUseAction,
  context: ToolUseContext,
): GateResult {
  // Gate 1: Feature Gate
  if (!feature('tengu_computer_use')) {
    return { action: 'deny', reason: 'Feature not enabled' }
  }

  // Gate 2: User Consent
  if (!context.computerUseConsent) {
    return { action: 'ask', reason: 'First-time use requires consent' }
  }

  // Gate 3: Action Type
  if (isWriteAction(action) && !context.computerUseWriteConsent) {
    return { action: 'ask', reason: 'Write operation requires confirmation' }
  }

  // Gate 4: Path Constraint
  if (action.type === 'file') {
    if (!isInAllowedDirectory(action.path, context.allowedDirectories)) {
      return { action: 'deny', reason: 'Path not in allowed directories' }
    }
  }

  // Gate 5: Dangerous Command
  if (isDangerousCommand(action)) {
    return { action: 'deny', reason: 'Dangerous command blocked' }
  }

  // Gate 6: Screen Boundary
  if (action.type === 'mouse') {
    const screenSize = getScreenSize()
    if (action.x < 0 || action.x > screenSize.width ||
        action.y < 0 || action.y > screenSize.height) {
      return { action: 'deny', reason: 'Coordinates out of screen bounds' }
    }
  }

  // Gate 7: Rate Limit
  if (isRateLimited(context.computerUseHistory)) {
    return { action: 'wait', reason: 'Rate limit exceeded', waitTime: 1000 }
  }

  // Gate 8: Screenshot Analysis (performed after capture)
  // Gate 9: Real-time Monitoring (handled by interrupt mechanism)

  return { action: 'allow' }
}
```

## 跨语言通信桥梁

TypeScript 和 Python 之间的通信基于 JSON-RPC 2.0 协议，传输层使用 stdio。TypeScript 端构造标准 JSON-RPC 请求（包含 method、params、id），写入 Python 进程的 stdin，然后从 stdout 读取响应。这种设计避免了 HTTP 开销，同时保持了协议的标准化。

```typescript
// src/tools/ComputerUseTool/bridge.ts
interface BridgeMessage {
  jsonrpc: '2.0'
  id: number
  method: string
  params: Record<string, unknown>
}

interface BridgeResponse {
  jsonrpc: '2.0'
  id: number
  result?: unknown
  error?: { code: number; message: string }
}

async function callBridge(method: string, params: unknown): Promise<unknown> {
  const message: BridgeMessage = {
    jsonrpc: '2.0',
    id: nextId++,
    method,
    params,
  }

  // 写入 stdin
  bridgeProcess.stdin.write(JSON.stringify(message) + '\n')

  // 读取 stdout
  const response = await readBridgeResponse()

  if (response.error) {
    throw new BridgeError(response.error.code, response.error.message)
  }

  return response.result
}
```

Python 端的 ComputerController 维护一个方法名到处理函数的映射表，循环读取 stdin 中的 JSON-RPC 请求，分发到对应的处理器执行，将结果或错误写回 stdout。每个请求独立处理，异常不会中断整个进程。

```python
# computer_controller.py
import json
import sys
from typing import Any

class ComputerController:
    def __init__(self):
        self.handlers = {
            'computer_mouse_click': self.mouse_click,
            'computer_keyboard_type': self.keyboard_type,
            'computer_screen_capture': self.screen_capture,
            # ... 24 个处理器
        }

    def run(self):
        while True:
            line = sys.stdin.readline()
            if not line:
                break

            request = json.loads(line)
            method = request['method']
            params = request['params']
            id = request['id']

            try:
                handler = self.handlers[method]
                result = handler(**params)
                response = {
                    'jsonrpc': '2.0',
                    'id': id,
                    'result': result
                }
            except Exception as e:
                response = {
                    'jsonrpc': '2.0',
                    'id': id,
                    'error': {'code': 1, 'message': str(e)}
                }

            sys.stdout.write(json.dumps(response) + '\n')
            sys.stdout.flush()

    def mouse_click(self, x: int, y: int, button: str = 'left'):
        import pyautogui
        pyautogui.click(x, y, button=button)

    def screen_capture(self) -> str:
        import pyautogui
        import base64
        screenshot = pyautogui.screenshot()
        # 返回 base64 编码
        return base64.b64encode(screenshot).decode('utf-8')
```

## 截图分析与窗口管理

截图是 Computer Use 感知环境的主要手段。模型决定截图后，computer_screen_capture 工具通过 Python Bridge 调用 pyautogui.screenshot()，将 PNG 编码为 Base64 返回给 Claude Code，作为 image block 注入当前对话上下文，模型通过多模态能力分析截图内容。在截图注入之前，系统会通过本地 OCR 检测敏感关键词（password、secret、api key、token 等），如果命中则对敏感区域进行模糊处理。

```typescript
// src/tools/ComputerUseTool/screenshotFilter.ts
async function filterScreenshot(
  base64Image: string,
): Promise<FilterResult> {
  // 1. 使用本地 OCR 检测敏感文本
  const detectedText = await localOcrDetect(base64Image)

  // 2. 检测敏感关键词
  const sensitiveKeywords = ['password', 'secret', 'api key', 'token']
  const foundSensitive = sensitiveKeywords.some(k =>
    detectedText.toLowerCase().includes(k)
  )

  if (foundSensitive) {
    return {
      action: 'blur',
      regions: findSensitiveRegions(detectedText),
      reason: 'Sensitive content detected',
    }
  }

  return { action: 'allow' }
}
```

窗口管理涉及三个平台各自的窗口 API 差异。系统定义了统一的 WindowInfo 接口（包含 id、title、process、position、size、visible 字段），各平台适配层负责将系统原生窗口信息转换为这个统一格式。激活窗口前会检查目标是否属于敏感应用（密码管理器、银行应用等），如果是则拒绝激活。

```typescript
// 窗口列表返回格式
interface WindowInfo {
  id: number
  title: string
  process: string
  position: { x: number; y: number }
  size: { width: number; height: number }
  visible: boolean
}

// 激活窗口的安全检查
async function activateWindow(windowId: number): Promise<void> {
  // 1. 检查窗口是否存在
  const window = await getWindowInfo(windowId)
  if (!window) {
    throw new Error('Window not found')
  }

  // 2. 检查窗口是否属于敏感应用
  const sensitiveApps = ['Keychain Access', '1Password', 'Banking App']
  if (sensitiveApps.some(app => window.title.includes(app))) {
    throw new Error('Cannot activate sensitive application')
  }

  // 3. 执行激活
  await callBridge('computer_window_activate', { window_id: windowId })
}
```

## 审计日志与中断机制

所有 Computer Use 操作都会记录审计日志，包括时间戳、操作类型、参数、执行结果（success/deny/error）、拒绝原因和执行耗时，可选附加操作后的截图。日志以 JSONL 格式持久化到 .claude/computer_use_history.jsonl，便于事后追溯和问题排查。

```typescript
interface ComputerUseLogEntry {
  timestamp: number
  action: string
  params: Record<string, unknown>
  result: 'success' | 'deny' | 'error'
  reason?: string
  duration: number
  screenshot?: string  // 操作后的截图（可选）
}

// 日志持久化到文件
const LOG_PATH = '.claude/computer_use_history.jsonl'

async function appendLog(entry: ComputerUseLogEntry): Promise<void> {
  const logLine = JSON.stringify(entry) + '\n'
  await fs.appendFile(LOG_PATH, logLine)
}
```

中断机制是安全体系的最后一道防线。用户按下 Ctrl+C 后，TypeScript 进程通知 Python Bridge 停止执行，将鼠标移到安全位置，记录中断事件到审计日志。Python 端维护一个 emergency_stop 标志，收到停止信号后退出主循环并将鼠标恢复到预设的安全坐标。这个设计确保即使在极端情况下，用户也能立即夺回控制权。

```python
# computer_controller.py
class ComputerController:
    def __init__(self):
        self.emergency_stop = False

    def run(self):
        while not self.emergency_stop:
            # ... 处理请求

    def stop(self):
        self.emergency_stop = True
        # 恢复鼠标到安全位置
        pyautogui.moveTo(self.safe_x, self.safe_y)
```

## 三平台适配

三个平台的窗口操作 API 差异显著。Windows 通过 ctypes 调用 Win32 API（GetForegroundWindow、GetWindowTextW），macOS 通过 PyObjC 访问 NSWorkspace，Linux 依赖 xdotool 命令行工具。每个平台适配层都需要实现窗口获取、激活、位置查询、尺寸查询等完整接口。

```python
# platform/windows.py
import pyautogui
import ctypes
from ctypes import wintypes

def get_active_window():
    """获取活动窗口"""
    hwnd = ctypes.windll.user32.GetForegroundWindow()
    return hwnd

def get_window_title(hwnd):
    """获取窗口标题"""
    length = ctypes.windll.user32.GetWindowTextLengthW(hwnd)
    title = ctypes.create_unicode_buffer(length + 1)
    ctypes.windll.user32.GetWindowTextW(hwnd, title, length + 1)
    return title.value
```

```python
# platform/macos.py
import pyautogui
from AppKit import NSWorkspace, NSRunningApplication

def get_active_window():
    """获取活动窗口"""
    workspace = NSWorkspace.sharedWorkspace()
    app = workspace.activeApplication()
    return app.localizedName()

def activate_window(title):
    """激活窗口"""
    workspace = NSWorkspace.sharedWorkspace()
    apps = workspace.runningApplications()
    for app in apps:
        if app.localizedName() == title:
            app.activateWithOptions_(NSApplicationActivateIgnoringOtherApps)
            break
```

```python
# platform/linux.py
import pyautogui
import subprocess

def get_active_window():
    """获取活动窗口"""
    result = subprocess.run(
        ['xdotool', 'getactivewindow'],
        capture_output=True,
        text=True
    )
    return int(result.stdout.strip())

def get_window_title(window_id):
    """获取窗口标题"""
    result = subprocess.run(
        ['xdotool', 'getwindowname', str(window_id)],
        capture_output=True,
        text=True
    )
    return result.stdout.strip()
```

## 关键源文件索引

| 文件 | 职责 |
|------|------|
| `src/tools/ComputerUseTool/ComputerUseTool.ts` | 工具定义、权限检查、安全关卡 |
| `src/tools/ComputerUseTool/bridge.ts` | Python Bridge 通信 |
| `src/tools/ComputerUseTool/security.ts` | 九层安全关卡实现 |
| `src/tools/ComputerUseTool/tools.ts` | 24 个工具定义 |
| `src/tools/ComputerUseTool/screenshotFilter.ts` | 截图内容过滤 |
| `computer_controller.py` | Python 执行器主入口 |
| `platform/windows.py` | Windows 平台适配 |
| `platform/macos.py` | macOS 平台适配 |
| `platform/linux.py` | Linux 平台适配 |

---

**系列文章导航：**
- 上一篇：[Channel 系统：IM 远程控制 Agent](/2026/04/06/078_claude-code-channel-system/)
- 下一篇：[Terminal UI：React + Ink 的 TUI 实现](/2026/04/06/086_claude-code-terminal-ui/)
