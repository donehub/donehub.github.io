---
title: Computer Use：桌面控制的九层安全关卡
date: 2026-04-06
tags: Computer Use
categories: Claude Code
---

> Computer Use 是 Claude Code 最具争议也最强大的能力——AI 可以直接操控你的桌面，点击按钮、输入文字、截图分析。这听起来像科幻电影，但 Claude Code 实现了一个九层安全关卡系统，确保每一步操作都在可控范围内。更关键的是，它通过 Python Bridge 实现跨语言通信，让 TypeScript 代理驱动 Python 执行器。

<!-- more -->

## 导读：当 AI 控制你的屏幕

想象这个场景：

> Claude Code 正在帮你调试一个 GUI 应用。它打开应用窗口，点击菜单，输入测试数据，截图分析结果，然后告诉你"登录按钮在点击后无响应"。

这就是 **Computer Use**——AI 直接操控桌面环境的能力。

但这也带来巨大的安全风险：AI 可能误删文件、点击错误按钮、泄露敏感信息。Claude Code 的解决方案是**九层安全关卡**，每一层都可以中断操作。

---

## 一、Computer Use 架构概览

### 1.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                    Computer Use 架构                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Claude Code (TypeScript)                                   │
│       ↓                                                     │
│  Computer Use Tool                                          │
│       ↓                                                     │
│  JSON-RPC over stdio                                        │
│       ↓                                                     │
│  Python Bridge (computer_controller.py)                     │
│       ↓                                                     │
│  Platform Abstraction Layer                                 │
│       ├─ Windows: pyautogui + Win32 API                    │
│       ├─ macOS: PyObjC + AppleScript                       │
│       └─ Linux: xdotool + Gdk/Xlib                         │
│       ↓                                                     │
│  Desktop Environment                                        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 为什么用 Python？

虽然 Claude Code 是 TypeScript 项目，但 Computer Use 使用 Python 实现：

| 原因 | 说明 |
|------|------|
| **生态成熟** | pyautogui、PyObjC 等库已稳定运行多年 |
| **跨平台** | Python GUI 库对 Windows/macOS/Linux 支持一致 |
| **快速迭代** | 不需要为每个平台单独编写 native 代码 |

---

## 二、24 个桌面操作工具

### 2.1 工具分类

```
┌─────────────────────────────────────────────────────────────┐
│                   24 个 Computer Use 工具                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  输入类（Input）                                             │
│    ├─ computer_mouse_click      左键/右键/中键点击          │
│    ├─ computer_mouse_double_click 双击                     │
│    ├─ computer_mouse_drag       拖拽操作                    │
│    ├─ computer_mouse_move       移动鼠标                    │
│    ├─ computer_mouse_scroll     滚轮滚动                    │
│    ├─ computer_keyboard_hotkey  组合键（Ctrl+C 等）         │
│    ├─ computer_keyboard_press   单键按下                    │
│    ├─ computer_keyboard_type    文字输入                    │
│    └─ computer_clipboard_paste  粘贴内容                    │
│                                                             │
│  显示类（Display）                                           │
│    ├─ computer_screen_capture   截图                        │
│    ├─ computer_screen_get_size  获取屏幕尺寸                │
│    ├─ computer_window_list      窗口列表                    │
│    ├─ computer_window_activate  激活窗口                    │
│    ├─ computer_window_get_position 窗口位置                 │
│    └─ computer_window_get_size  窗口尺寸                    │
│                                                             │
│  文件类（File）                                              │
│    ├─ computer_file_read        读取文件                    │
│    ├─ computer_file_write       写入文件                    │
│    ├─ computer_file_delete      删除文件                    │
│    ├─ computer_file_list        列出目录                    │
│    ├─ computer_file_move        移动文件                    │
│    ├─ computer_file_copy        复制文件                    │
│    └─ computer_file_info        文件信息                    │
│                                                             │
│  进程类（Process）                                           │
│    ├─ computer_process_list     进程列表                    │
│    ├─ computer_process_start    启动进程                    │
│    └─ computer_process_kill     杀死进程                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 工具定义示例

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

---

## 三、九层安全关卡

### 3.1 安全关卡架构

```
┌─────────────────────────────────────────────────────────────┐
│                    九层安全关卡                              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Gate 1: 功能门控（Feature Gate）                           │
│    └─ tengu_computer_use Feature Flag 必须开启             │
│                                                             │
│  Gate 2: 用户确认（User Consent）                           │
│    └─ 首次使用弹出确认对话框                                │
│                                                             │
│  Gate 3: 操作类型检查（Action Type）                        │
│    └─ 读写操作需要额外确认                                  │
│                                                             │
│  Gate 4: 路径约束（Path Constraint）                        │
│    ├─ 文件操作限制在白名单目录                              │
│    └─ 禁止访问 .git、.claude、系统目录                      │
│                                                             │
│  Gate 5: 危险命令过滤（Dangerous Command）                   │
│    ├─ 禁止 rm -rf、killall 等命令                          │
│    ├─ 禁止访问密码管理器、银行应用                          │
│                                                             │
│  Gate 6: 屏幕边界检查（Screen Boundary）                    │
│    ├─ 鼠标坐标必须在屏幕范围内                              │
│    └─ 窗口操作必须针对可见窗口                              │
│                                                             │
│  Gate 7: 操作频率限制（Rate Limit）                         │
│    ├─ 每秒最多 10 次操作                                    │
│    └─ 连续失败 3 次暂停                                     │
│                                                             │
│  Gate 8: 截图内容分析（Screenshot Analysis）                │
│    ├─ 检测敏感内容（密码框、私人信息）                      │
│    └─ 检测错误弹窗                                          │
│                                                             │
│  Gate 9: 实时监控（Real-time Monitoring）                   │
│    ├─ 用户可随时按 Ctrl+C 中断                             │
│    ├─ 操作日志实时输出                                      │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Gate 实现示例

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

---

## 四、Python Bridge 通信协议

### 4.1 JSON-RPC over stdio

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

### 4.2 Python 执行器

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

---

## 五、截图分析机制

### 5.1 截图流程

```
Model 决定截图
    ↓
computer_screen_capture 工具调用
    ↓
Python Bridge 执行 pyautogui.screenshot()
    ↓
PNG → Base64 编码
    ↓
返回给 Claude Code
    ↓
作为 image block 注入对话
    ↓
Model 多模态分析
```

### 5.2 截图内容过滤

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

---

## 六、窗口管理系统

### 6.1 窗口发现

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

// 示例返回
[
  { id: 1234, title: 'VS Code', process: 'code', position: { x: 0, y: 0 }, size: { width: 1920, height: 1080 }, visible: true },
  { id: 5678, title: 'Chrome', process: 'chrome', position: { x: 100, y: 100 }, size: { width: 800, height: 600 }, visible: true },
]
```

### 6.2 窗口激活策略

```typescript
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

---

## 七、操作审计日志

### 7.1 日志格式

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

// 示例日志
[
  { timestamp: 1712345678, action: 'mouse_click', params: { x: 100, y: 200 }, result: 'success', duration: 50 },
  { timestamp: 1712345680, action: 'keyboard_type', params: { text: 'hello' }, result: 'success', duration: 100 },
  { timestamp: 1712345682, action: 'file_delete', params: { path: '/etc/passwd' }, result: 'deny', reason: 'Dangerous path', duration: 0 },
]
```

### 7.2 日志存储

```typescript
// 日志持久化到文件
const LOG_PATH = '.claude/computer_use_history.jsonl'

async function appendLog(entry: ComputerUseLogEntry): Promise<void> {
  const logLine = JSON.stringify(entry) + '\n'
  await fs.appendFile(LOG_PATH, logLine)
}
```

---

## 八、中断机制

### 8.1 Ctrl+C 中断

```typescript
// 监听中断信号
process.on('SIGINT', async () => {
  // 1. 通知 Python Bridge 停止
  await callBridge('stop', {})

  // 2. 恢复鼠标状态
  await callBridge('mouse_move', { x: lastSafeX, y: lastSafeY })

  // 3. 记录中断
  appendLog({
    timestamp: Date.now(),
    action: 'interrupt',
    params: {},
    result: 'success',
    reason: 'User pressed Ctrl+C',
    duration: 0,
  })

  // 4. 提示用户
  console.log('\nComputer Use interrupted. All operations stopped.')
})
```

### 8.2 紧急停止

Python Bridge 维护一个紧急停止标志：

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

---

## 九、平台适配层

### 9.1 Windows 实现

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

### 9.2 macOS 实现

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

### 9.3 Linux 实现

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

---

## 十、关键源文件索引

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

## 十一、总结

Claude Code 的 Computer Use 系统体现了几个核心设计原则：

1. **九层防御**：从功能门控到实时监控，层层把关
2. **跨语言架构**：TypeScript 代理 + Python 执行器
3. **JSON-RPC 协议**：简单高效的跨进程通信
4. **平台抽象**：统一接口，底层适配三大操作系统
5. **审计日志**：完整记录所有操作，便于追溯
6. **用户可控**：随时 Ctrl+C 中断，恢复安全状态

这个设计让 AI 真正能够"看见"和"操控"桌面环境，同时保持高度安全性。

---

**系列文章导航：**
- 上一篇：[Channel 系统：IM 远程控制 Agent](/claude-code-channel-system/)
- 下一篇：[Terminal UI：React + Ink 的 TUI 实现](/claude-code-terminal-ui/)