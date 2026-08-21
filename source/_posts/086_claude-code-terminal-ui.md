---
title: Terminal UI：React + Ink 的 TUI 实现
date: 2026-04-06
tags: Terminal UI
categories: Claude Code
---

> Claude Code 的终端界面不是传统的 CLI——它是一个完整的 React 应用，运行在终端中。通过 Ink 框架（自定义 React Reconciler + Yoga 布局引擎），Claude Code 实现了组件化 UI、双缓冲渲染、交互式对话框等高级特性。这是 Terminal UI 开发的教科书级案例。

<!-- more -->

## 导读：终端里的 React 应用

当你打开 Claude Code，看到的不是普通的命令行输出：

```
┌─────────────────────────────────────────────────────────────┐
│ Claude Code                                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ▶ What would you like me to help you with?                 │
│                                                             │
│ ┌─ Tools ─────────────────────────────────────────────────┐│
│ │ Read  Edit  Write  Bash  Grep  Glob  WebSearch          ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ ┌─ Context ────────────────────────────────────────────────┐│
│ │ Memory: 3 entries loaded                                 ││
│ │ MCP: 2 servers connected                                 ││
│ │ Token budget: 150,000                                    ││
│ └─────────────────────────────────────────────────────────┘│
│                                                             │
│ [Type your message or press Enter for suggestions]         │
└─────────────────────────────────────────────────────────────┘
```

这是一个**完整的 GUI 应用**，运行在终端中。背后是 React + Ink 的魔法。

---

## 一、Ink 框架基础

### 1.1 React Reconciler 架构

```
┌─────────────────────────────────────────────────────────────┐
│                    React + Ink 架构                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  React Components                                           │
│       ↓                                                     │
│  React Reconciler（自定义）                                  │
│       ↓                                                     │
│  Ink Host Config                                            │
│       ├─ createInstance() → 创建 Yoga Node                 │
│       ├─ appendChild() → 添加子节点                         │
│       ├─ removeChild() → 删除子节点                         │
│       └─ commitUpdate() → 更新属性                          │
│       ↓                                                     │
│  Yoga Layout Engine                                         │
│       ├─ Flexbox 布局计算                                   │
│       ├─ 文字测量（基于终端字符）                            │
│       └─ 位置计算                                           │
│       ↓                                                     │
│  Terminal Renderer                                          │
│       ├─ ANSI 转义序列                                      │
│       ├─ 双缓冲渲染                                         │
│       └─ 输出合并                                           │
│       ↓                                                     │
│  stdout                                                     │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 为什么选择 Ink？

| 优势 | 说明 |
|------|------|
| **React 生态** | 复用 React 的组件化思想、状态管理、生命周期 |
| **Flexbox 布局** | Yoga 引擎提供完整的 Flexbox 支持 |
| **跨平台** | Windows/macOS/Linux 终端一致性 |
| **双缓冲** | 避免闪烁，平滑更新 |

---

## 二、核心组件设计

### 2.1 组件树结构

```
<App>
  <Header>
    <Title />
    <StatusIndicator />
  </Header>
  
  <Main>
    <MessageList>
      <UserMessage />
      <AssistantMessage>
        <ToolCall />
        <ToolResult />
      </AssistantMessage>
    </MessageList>
    
    <ToolBar>
      <ToolButton tool="Read" />
      <ToolButton tool="Edit" />
      ...
    </ToolBar>
    
    <ContextPanel>
      <MemoryStatus />
      <MCPStatus />
      <TokenBudget />
    </ContextPanel>
  </Main>
  
  <Footer>
    <InputBox />
    <Suggestions />
  </Footer>
</App>
```

### 2.2 基础组件实现

```tsx
// src/components/App.tsx
import { Box, Text, useInput, useApp } from 'ink'

function App() {
  const { exit } = useApp()
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState('')

  useInput((char, key) => {
    if (key.escape) {
      exit()
    } else if (key.return) {
      handleSubmit(input)
      setInput('')
    } else {
      setInput(prev => prev + char)
    }
  })

  return (
    <Box flexDirection="column" height="100%">
      <Header />
      <Box flexGrow={1}>
        <MessageList messages={messages} />
        <ContextPanel />
      </Box>
      <Footer input={input} />
    </Box>
  )
}
```

---

## 三、布局系统

### 3.1 Yoga Flexbox

```tsx
// Flexbox 属性完全支持
<Box 
  flexDirection="column"    // 垂直布局
  justifyContent="center"   // 居中
  alignItems="stretch"      // 拉伸
  flexGrow={1}              // 占满剩余空间
  padding={1}               // 1 字符边距
  margin={2}                // 2 字符外边距
  borderStyle="single"      // 单线边框
>
  <Text>Content</Text>
</Box>
```

### 3.2 文字测量

```typescript
// ink/lib/measureText.ts
function measureText(text: string): { width: number; height: number } {
  // 1. 处理 ANSI 转义序列（不计入宽度）
  const cleanText = stripAnsi(text)
  
  // 2. 处理多行文本
  const lines = cleanText.split('\n')
  
  // 3. 每行宽度 = 字符数（考虑宽字符）
  const widths = lines.map(line => {
    // 中文字符占 2 列
    return line.split('').reduce((width, char) => {
      return width + (isFullWidth(char) ? 2 : 1)
    }, 0)
  })
  
  return {
    width: Math.max(...widths),
    height: lines.length,
  }
}
```

---

## 四、双缓冲渲染

### 4.1 渲染流程

```
┌─────────────────────────────────────────────────────────────┐
│                    双缓冲渲染流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  State Update                                               │
│       ↓                                                     │
│  Reconciler 更新 Yoga Tree                                  │
│       ↓                                                     │
│  Layout 计算                                                │
│       ↓                                                     │
│  Render to Buffer A                                         │
│       ├─ 遍历 Yoga Tree                                    │
│       ├─ 生成 ANSI 序列                                    │
│       └─ 写入 Buffer A                                     │
│       ↓                                                     │
│  Swap Buffers                                               │
│       ├─ Buffer A → Previous Frame                         │
│       ├─ Buffer B → Current Frame                          │
│       ↓                                                     │
│  Diff & Output                                              │
│       ├─ 对比 Previous vs Current                          │
│       ├─ 只输出变化的区域                                   │
│       └─ ANSI 光标移动 + 更新                               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Diff 算法

```typescript
// ink/lib/diff.ts
function diffScreens(prev: string[], curr: string[]): DiffOutput[] {
  const outputs: DiffOutput[] = []
  
  for (let y = 0; y < Math.max(prev.length, curr.length); y++) {
    const prevLine = prev[y] || ''
    const currLine = curr[y] || ''
    
    if (prevLine !== currLine) {
      // 移动光标到该行
      outputs.push({ type: 'move', x: 0, y })
      
      // 清除该行
      outputs.push({ type: 'clear_line' })
      
      // 写入新内容
      outputs.push({ type: 'write', content: currLine })
    }
  }
  
  return outputs
}
```

---

## 五、交互式组件

### 5.1 InputBox 实现

```tsx
// src/components/InputBox.tsx
import { Box, Text, useInput } from 'ink'
import { useState } from 'react'

function InputBox({ onSubmit }) {
  const [value, setValue] = useState('')
  const [cursorPosition, setCursorPosition] = useState(0)

  useInput((char, key) => {
    if (key.leftArrow) {
      setCursorPosition(Math.max(0, cursorPosition - 1))
    } else if (key.rightArrow) {
      setCursorPosition(Math.min(value.length, cursorPosition + 1))
    } else if (key.backspace) {
      setValue(prev => prev.slice(0, cursorPosition - 1) + prev.slice(cursorPosition))
      setCursorPosition(Math.max(0, cursorPosition - 1))
    } else if (key.return) {
      onSubmit(value)
      setValue('')
      setCursorPosition(0)
    } else {
      setValue(prev => prev.slice(0, cursorPosition) + char + prev.slice(cursorPosition))
      setCursorPosition(cursorPosition + 1)
    }
  })

  return (
    <Box borderStyle="single" padding={1}>
      <Text bold>▶ </Text>
      <Text>{value.slice(0, cursorPosition)}</Text>
      <Text backgroundColor="cyan">{value[cursorPosition] || ' '}</Text>
      <Text>{value.slice(cursorPosition + 1)}</Text>
    </Box>
  )
}
```

### 5.2 SelectMenu 实现

```tsx
// src/components/SelectMenu.tsx
import { Box, Text, useInput } from 'ink'

function SelectMenu({ items, onSelect }) {
  const [selectedIndex, setSelectedIndex] = useState(0)

  useInput((char, key) => {
    if (key.upArrow) {
      setSelectedIndex(Math.max(0, selectedIndex - 1))
    } else if (key.downArrow) {
      setSelectedIndex(Math.min(items.length - 1, selectedIndex + 1))
    } else if (key.return) {
      onSelect(items[selectedIndex])
    }
  })

  return (
    <Box flexDirection="column">
      {items.map((item, index) => (
        <Box key={item.value}>
          <Text color={index === selectedIndex ? 'cyan' : 'gray'}>
            {index === selectedIndex ? '▶ ' : '  '}
          </Text>
          <Text bold={index === selectedIndex}>{item.label}</Text>
        </Box>
      ))}
    </Box>
  )
}
```

---

## 六、工具调用可视化

### 6.1 ToolCall 组件

```tsx
// src/components/ToolCall.tsx
function ToolCall({ toolName, input, status }) {
  const statusColor = {
    pending: 'yellow',
    running: 'blue',
    success: 'green',
    error: 'red',
  }

  return (
    <Box flexDirection="column" borderStyle="single" borderColor={statusColor[status]}>
      <Box>
        <Text bold color={statusColor[status]}>
          ⚙ {toolName}
        </Text>
        <Text dimColor> ({status})</Text>
      </Box>
      
      {status === 'running' && (
        <Box marginLeft={2}>
          <Text dimColor>Input: {JSON.stringify(input).slice(0, 100)}</Text>
        </Box>
      )}
      
      {status === 'success' && (
        <Box marginLeft={2}>
          <Text color="green">✓ Completed in {duration}ms</Text>
        </Box>
      )}
      
      {status === 'error' && (
        <Box marginLeft={2}>
          <Text color="red">✗ {error.message}</Text>
        </Box>
      )}
    </Box>
  )
}
```

### 6.2 ToolResult 组件

```tsx
// src/components/ToolResult.tsx
function ToolResult({ output, truncated }) {
  const [expanded, setExpanded] = useState(false)
  
  const displayOutput = expanded ? output : output.slice(0, 500)
  
  return (
    <Box flexDirection="column">
      <Box borderStyle="single" borderColor="gray">
        <Text dimColor>Output:</Text>
      </Box>
      
      <Box padding={1}>
        <Text>{displayOutput}</Text>
      </Box>
      
      {truncated && !expanded && (
        <Box>
          <Text dimColor>... ({output.length - 500} more characters)</Text>
          <Text color="cyan" bold> [Press Enter to expand]</Text>
        </Box>
      )}
    </Box>
  )
}
```

---

## 七、权限对话框

### 7.1 PermissionDialog 组件

```tsx
// src/components/PermissionDialog.tsx
function PermissionDialog({ toolName, description, onAllow, onDeny }) {
  const [selected, setSelected] = useState<'allow' | 'deny'>('deny')

  useInput((char, key) => {
    if (key.leftArrow || key.rightArrow) {
      setSelected(prev => prev === 'allow' ? 'deny' : 'allow')
    } else if (key.return) {
      if (selected === 'allow') {
        onAllow()
      } else {
        onDeny()
      }
    }
  })

  return (
    <Box 
      flexDirection="column" 
      borderStyle="double" 
      borderColor="yellow"
      padding={2}
    >
      <Box>
        <Text bold color="yellow">⚠ Permission Required</Text>
      </Box>
      
      <Box marginTop={1}>
        <Text>Tool: <Text bold>{toolName}</Text></Text>
      </Box>
      
      <Box marginTop={1}>
        <Text>{description}</Text>
      </Box>
      
      <Box marginTop={2} justifyContent="space-around">
        <Box>
          <Text 
            backgroundColor={selected === 'deny' ? 'red' : undefined}
            bold={selected === 'deny'}
          >
            [Deny]
          </Text>
        </Box>
        <Box>
          <Text 
            backgroundColor={selected === 'allow' ? 'green' : undefined}
            bold={selected === 'allow'}
          >
            [Allow]
          </Text>
        </Box>
      </Box>
      
      <Box marginTop={1}>
        <Text dimColor>← → to select, Enter to confirm</Text>
      </Box>
    </Box>
  )
}
```

---

## 八、非交互模式

### 8.1 模式切换

```typescript
// src/cli.ts
function detectInteractiveMode(): boolean {
  // 1. 检查 stdout 是否是 TTY
  if (!process.stdout.isTTY) {
    return false
  }

  // 2. 检查 CI 环境
  if (process.env.CI === 'true') {
    return false
  }

  // 3. 检查 --non-interactive 参数
  if (process.argv.includes('--non-interactive')) {
    return false
  }

  return true
}
```

### 8.2 非交互输出

```typescript
// src/renderers/nonInteractive.ts
function renderNonInteractive(message: Message): void {
  switch (message.type) {
    case 'user':
      console.log(`\n> ${message.content}`)
      break
      
    case 'assistant':
      console.log(`\n${message.content}`)
      break
      
    case 'tool_use':
      console.log(`\n[Tool: ${message.toolName}]`)
      if (message.input) {
        console.log(`  Input: ${JSON.stringify(message.input)}`)
      }
      break
      
    case 'tool_result':
      console.log(`  Result: ${message.output.slice(0, 500)}`)
      break
      
    case 'error':
      console.error(`\n[Error] ${message.message}`)
      break
  }
}
```

---

## 九、颜色和样式系统

### 9.1 ANSI 颜色映射

```typescript
// src/styles/colors.ts
const COLORS = {
  // 用户消息
  user: 'cyan',
  
  // AI 响应
  assistant: 'white',
  
  // 工具调用
  tool_pending: 'yellow',
  tool_running: 'blue',
  tool_success: 'green',
  tool_error: 'red',
  
  // 状态指示
  status_active: 'green',
  status_idle: 'gray',
  status_error: 'red',
  
  // 强调
  emphasis: 'bold',
  dim: 'dim',
}

// ANSI 转义序列
const ANSI_COLORS = {
  cyan: '\x1b[36m',
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  gray: '\x1b[90m',
  bold: '\x1b[1m',
  dim: '\x1b[2m',
  reset: '\x1b[0m',
}
```

### 9.2 边框样式

```typescript
// ink/lib/borders.ts
const BORDERS = {
  single: {
    topLeft: '┌', top: '─', topRight: '┐',
    left: '│', right: '│',
    bottomLeft: '└', bottom: '─', bottomRight: '┘',
  },
  double: {
    topLeft: '╔', top: '═', topRight: '╗',
    left: '║', right: '║',
    bottomLeft: '╚', bottom: '═', bottomRight: '╝',
  },
  rounded: {
    topLeft: '╭', top: '─', topRight: '╮',
    left: '│', right: '│',
    bottomLeft: '╰', bottom: '─', bottomRight: '╯',
  },
}
```

---

## 十、性能优化

### 10.1 渲染节流

```typescript
// ink/lib/renderer.ts
const RENDER_INTERVAL = 16  // ~60fps

function scheduleRender(callback: () => void): void {
  if (renderScheduled) {
    return
  }
  
  renderScheduled = true
  setTimeout(() => {
    callback()
    renderScheduled = false
  }, RENDER_INTERVAL)
}
```

### 10.2 虚拟滚动

```typescript
// src/components/VirtualList.tsx
function VirtualList({ items, height }) {
  const [scrollTop, setScrollTop] = useState(0)
  
  // 只渲染可见区域
  const visibleStart = scrollTop
  const visibleEnd = scrollTop + height
  const visibleItems = items.slice(visibleStart, visibleEnd)

  useInput((char, key) => {
    if (key.upArrow) {
      setScrollTop(Math.max(0, scrollTop - 1))
    } else if (key.downArrow) {
      setScrollTop(Math.min(items.length - height, scrollTop + 1))
    }
  })

  return (
    <Box flexDirection="column" height={height}>
      {visibleItems.map((item, index) => (
        <Box key={visibleStart + index}>
          <Text>{item.content}</Text>
        </Box>
      ))}
    </Box>
  )
}
```

---

## 十一、关键源文件索引

| 文件 | 职责 |
|------|------|
| `src/components/App.tsx` | 主应用入口 |
| `src/components/Header.tsx` | 标题栏和状态指示 |
| `src/components/MessageList.tsx` | 消息列表渲染 |
| `src/components/ToolCall.tsx` | 工具调用可视化 |
| `src/components/InputBox.tsx` | 输入框组件 |
| `src/components/PermissionDialog.tsx` | 权限对话框 |
| `src/renderers/nonInteractive.ts` | 非交互模式渲染 |
| `src/styles/colors.ts` | 颜色系统 |
| `ink/lib/renderer.ts` | 双缓冲渲染引擎 |
| `ink/lib/measureText.ts` | 文字测量 |

---

## 十二、总结

Claude Code 的 Terminal UI 系统体现了几个核心设计原则：

1. **React 组件化**：复用 React 生态，组件化 UI 设计
2. **Flexbox 布局**：Yoga 引擎提供完整的 Flexbox 支持
3. **双缓冲渲染**：避免闪烁，只更新变化的区域
4. **交互式组件**：InputBox、SelectMenu、PermissionDialog
5. **非交互模式**：自动检测环境，降级为简单输出
6. **性能优化**：渲染节流、虚拟滚动

这个设计让终端应用拥有了 GUI 级别的交互体验，是 Terminal UI 开发的教科书级案例。

---

**系列文章导航：**
- 上一篇：[Computer Use：桌面控制的九层安全关卡](/claude-code-computer-use/)
- 系列完结