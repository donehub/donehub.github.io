---
title: "Computer Use — Nine Security Gates for Desktop Control"
date: 2026-04-06
tags: Computer Use
categories: Claude Code
lang: en
label: 079_claude-code-computer-use
---

Claude Code's Computer Use feature lets AI directly operate the desktop environment: clicking buttons, typing text, taking screenshots to analyze interface state. Giving AI screen access plus mouse and keyboard control introduces real risks: accidental file deletion, misclicks, sensitive data leaks. To address this, Claude Code implements a nine-layer security gate system where each layer can independently intercept dangerous operations. Under the hood, a Python Bridge handles the cross-language work — a TypeScript proxy drives a Python executor that performs the actual desktop interactions.

<!-- more -->

## Overall Architecture and the Python Choice

Computer Use follows a typical cross-language proxy pattern. Claude Code (TypeScript) handles strategy decisions and permission control; a Python process executes the actual desktop operations. The two communicate via JSON-RPC over stdio. The split keeps responsibilities clear: TypeScript handles security and model interaction, Python handles platform API calls.

```
Claude Code (TypeScript)
    ↓ JSON-RPC over stdio
Python Bridge (computer_controller.py)
    ↓ Platform Abstraction
Desktop Environment
```

The core reason for choosing Python over TypeScript native for desktop operations is ecosystem maturity. Libraries like pyautogui, PyObjC, and xdotool have been running stably for years with consistent cross-platform interfaces. Implementing desktop operations in TypeScript through native addons would significantly increase maintenance cost.

| Factor | Python Approach | TypeScript Native |
|--------|----------------|-------------------|
| Library ecosystem | pyautogui/PyObjC — mature and stable | Requires native addons, fragmented ecosystem |
| Cross-platform consistency | Unified interface across 3 platforms | Each platform needs separate wrapping |
| Development iteration speed | Pure Python, fast to modify | Compile native code, slow iteration |
| Maintenance cost | Community-maintained, frequent updates | Self-maintained, adapt to each system's API changes |

## 24 Desktop Operation Tools

Computer Use provides 24 tools covering four categories: input, display, file, and process. Input tools handle mouse clicks, double-clicks, drag-and-drop, scroll wheel, keyboard shortcuts, single key presses, text input, and clipboard paste. Display tools handle screenshots, screen dimensions, window list queries, window activation, and window position/size retrieval. File tools include read, write, delete, list directory, move, copy, and file info. Process tools provide process list queries, launching new processes, and terminating processes.

| Category | Tools | Core Capabilities |
|----------|-------|-------------------|
| Input | 9 | Mouse click/drag/scroll, keyboard input/shortcuts, clipboard paste |
| Display | 6 | Screenshot, screen size, window list/activate/position/size |
| File | 7 | Read/write/delete/list/move/copy, file info queries |
| Process | 3 | Process list, launch process, terminate process |

Taking the mouse click tool as an example, tool definitions describe parameter structure via JSON Schema, including coordinates, button type, and click count. Claude Code registers these definitions as callable tools, and the model initiates calls through `tool_use` when desktop operations are needed.

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

## Nine Security Gates

Security design is the heart of the Computer Use system. Nine gates progress from outside to inside, each capable of independently intercepting operations. This isn't theoretical — it's an actual check chain in the code. Operations must pass all gates to execute; any gate returning deny immediately terminates the operation.

| Gate | Name | Interception Rule |
|------|------|-------------------|
| Gate 1 | Feature gate | tengu_computer_use Feature Flag must be enabled |
| Gate 2 | User consent | First-time use shows confirmation dialog, user must authorize |
| Gate 3 | Action type check | Write operations require additional write permission confirmation |
| Gate 4 | Path constraints | File operations restricted to allowlisted directories; .git, .claude, system directories blocked |
| Gate 5 | Dangerous command filter | Blocks rm -rf, killall, etc.; password managers and banking apps blocked |
| Gate 6 | Screen boundary check | Mouse coordinates must be within screen resolution; window operations must target visible windows |
| Gate 7 | Rate limiting | Max 10 operations per second; 3 consecutive failures trigger auto-pause |
| Gate 8 | Screenshot content analysis | Detects password fields, private info, and other sensitive content; detects error dialogs |
| Gate 9 | Real-time monitoring | User can Ctrl+C interrupt at any time; operation logs output in real time |

In code, the `gateComputerUseAction` function executes all checks in order, returning allow, deny, or ask. The first seven gates complete before execution; Gate 8 runs after screenshot capture; Gate 9 spans the entire operation lifecycle.

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

## Cross-Language Communication Bridge

Communication between TypeScript and Python is based on JSON-RPC 2.0 protocol over stdio transport. The TypeScript side constructs standard JSON-RPC requests (with method, params, id), writes them to the Python process's stdin, then reads responses from stdout. This design avoids HTTP overhead while keeping the protocol standardized.

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

  // Write to stdin
  bridgeProcess.stdin.write(JSON.stringify(message) + '\n')

  // Read from stdout
  const response = await readBridgeResponse()

  if (response.error) {
    throw new BridgeError(response.error.code, response.error.message)
  }

  return response.result
}
```

The Python-side ComputerController maintains a method-name-to-handler mapping table, loops reading JSON-RPC requests from stdin, dispatches to the corresponding handler, and writes results or errors back to stdout. Each request is handled independently — exceptions don't crash the entire process.

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
            # ... 24 handlers
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
        # Return base64 encoded
        return base64.b64encode(screenshot).decode('utf-8')
```

## Screenshot Analysis and Window Management

Screenshots are Computer Use's primary way of perceiving the environment. When the model decides to take a screenshot, the `computer_screen_capture` tool calls `pyautogui.screenshot()` through the Python Bridge, encodes the PNG as Base64, and returns it to Claude Code. It gets injected as an image block into the current conversation context, where the model analyzes it through multimodal capabilities. Before injection, the system runs local OCR to detect sensitive keywords (password, secret, api key, token, etc.) and blurs sensitive regions if any are found.

```typescript
// src/tools/ComputerUseTool/screenshotFilter.ts
async function filterScreenshot(
  base64Image: string,
): Promise<FilterResult> {
  // 1. Use local OCR to detect sensitive text
  const detectedText = await localOcrDetect(base64Image)

  // 2. Check for sensitive keywords
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

Window management involves handling API differences across three platforms. The system defines a unified WindowInfo interface (with id, title, process, position, size, visible fields), and each platform adapter converts native window info into this format. Before activating a window, the system checks if it belongs to a sensitive application (password managers, banking apps, etc.) and refuses activation if so.

```typescript
// Window list return format
interface WindowInfo {
  id: number
  title: string
  process: string
  position: { x: number; y: number }
  size: { width: number; height: number }
  visible: boolean
}

// Security check for window activation
async function activateWindow(windowId: number): Promise<void> {
  // 1. Check if window exists
  const window = await getWindowInfo(windowId)
  if (!window) {
    throw new Error('Window not found')
  }

  // 2. Check if window belongs to a sensitive app
  const sensitiveApps = ['Keychain Access', '1Password', 'Banking App']
  if (sensitiveApps.some(app => window.title.includes(app))) {
    throw new Error('Cannot activate sensitive application')
  }

  // 3. Execute activation
  await callBridge('computer_window_activate', { window_id: windowId })
}
```

## Audit Logs and Interrupt Mechanism

All Computer Use operations are logged to an audit trail, including timestamp, action type, parameters, execution result (success/deny/error), rejection reason, and duration, with optional post-action screenshots. Logs persist in JSONL format to `.claude/computer_use_history.jsonl` for post-incident investigation and debugging.

```typescript
interface ComputerUseLogEntry {
  timestamp: number
  action: string
  params: Record<string, unknown>
  result: 'success' | 'deny' | 'error'
  reason?: string
  duration: number
  screenshot?: string  // Post-action screenshot (optional)
}

// Log persistence to file
const LOG_PATH = '.claude/computer_use_history.jsonl'

async function appendLog(entry: ComputerUseLogEntry): Promise<void> {
  const logLine = JSON.stringify(entry) + '\n'
  await fs.appendFile(LOG_PATH, logLine)
}
```

The interrupt mechanism is the last line of defense in the security system. When the user presses Ctrl+C, the TypeScript process notifies the Python Bridge to stop execution, moves the mouse to a safe position, and records the interrupt event in the audit log. The Python side maintains an `emergency_stop` flag — upon receiving the stop signal, it exits the main loop and restores the mouse to preset safe coordinates. This design ensures the user can immediately reclaim control even in extreme situations.

```python
# computer_controller.py
class ComputerController:
    def __init__(self):
        self.emergency_stop = False

    def run(self):
        while not self.emergency_stop:
            # ... handle requests

    def stop(self):
        self.emergency_stop = True
        # Restore mouse to safe position
        pyautogui.moveTo(self.safe_x, self.safe_y)
```

## Three-Platform Adaptation

Window operation APIs differ significantly across the three platforms. Windows uses ctypes to call Win32 APIs (GetForegroundWindow, GetWindowTextW). macOS uses PyObjC to access NSWorkspace. Linux depends on the xdotool command-line tool. Each platform adapter must implement the full interface: window retrieval, activation, position queries, and size queries.

```python
# platform/windows.py
import pyautogui
import ctypes
from ctypes import wintypes

def get_active_window():
    """Get the active window"""
    hwnd = ctypes.windll.user32.GetForegroundWindow()
    return hwnd

def get_window_title(hwnd):
    """Get window title"""
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
    """Get the active window"""
    workspace = NSWorkspace.sharedWorkspace()
    app = workspace.activeApplication()
    return app.localizedName()

def activate_window(title):
    """Activate a window"""
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
    """Get the active window"""
    result = subprocess.run(
        ['xdotool', 'getactivewindow'],
        capture_output=True,
        text=True
    )
    return int(result.stdout.strip())

def get_window_title(window_id):
    """Get window title"""
    result = subprocess.run(
        ['xdotool', 'getwindowname', str(window_id)],
        capture_output=True,
        text=True
    )
    return result.stdout.strip()
```

## Key Source File Index

| File | Responsibility |
|------|----------------|
| `src/tools/ComputerUseTool/ComputerUseTool.ts` | Tool definitions, permission checks, security gates |
| `src/tools/ComputerUseTool/bridge.ts` | Python Bridge communication |
| `src/tools/ComputerUseTool/security.ts` | Nine-layer security gate implementation |
| `src/tools/ComputerUseTool/tools.ts` | 24 tool definitions |
| `src/tools/ComputerUseTool/screenshotFilter.ts` | Screenshot content filtering |
| `computer_controller.py` | Python executor entry point |
| `platform/windows.py` | Windows platform adapter |
| `platform/macos.py` | macOS platform adapter |
| `platform/linux.py` | Linux platform adapter |

---

**Series Navigation:**
- Previous: [Channel System: Controlling Your Agent from Any IM App](/2026/04/06/078_claude-code-channel-system/)
- Next: [Terminal UI: Building a TUI with React and Ink](/2026/04/06/086_claude-code-terminal-ui/)
