---
title: React + Ink 构建的终端界面
date: 2026-04-06
tags: Terminal UI
categories: Claude Code
---

## 终端里的 React 应用

Claude Code 的终端界面不是传统的 CLI 逐行输出，而是一个完整的 React 应用。它通过 Ink 框架（React 的终端渲染器）实现了组件化 UI、Flexbox 布局、双缓冲渲染和交互式对话框。选择 Ink 而非 ncurses 或 blessed 这类传统终端 UI 库，核心原因是复用 React 生态：组件化思想、状态管理、生命周期、以及开发者的熟悉度。

Ink 的架构分为四层。React Components 通过自定义的 React Reconciler 转换为 Ink Host Config 调用，Host Config 使用 Yoga 布局引擎计算 Flexbox 布局（基于终端字符单位），最终 Terminal Renderer 将布局结果转换为 ANSI 转义序列输出到 stdout。这个架构让终端 UI 开发体验接近 Web 前端，同时保持了终端应用的性能特征。

<!-- more -->

## 核心组件与布局

组件树结构遵循典型的 GUI 应用模式：App 作为根组件，包含 Header（标题和状态指示）、Main（消息列表、工具栏、上下文面板）和 Footer（输入框和建议）。消息列表中的 AssistantMessage 嵌套 ToolCall 和 ToolResult 子组件，形成树状的消息结构。

布局系统基于 Yoga 引擎，支持完整的 Flexbox 属性：flexDirection、justifyContent、alignItems、flexGrow、padding、margin、borderStyle 等。终端环境与浏览器的一个关键差异是尺寸单位——终端以字符为单位，padding: 1 表示 1 个字符的边距，而非像素。

```tsx
// src/components/App.tsx
function App() {
  const { exit } = useApp()
  const [messages, setMessages] = useState<Message[]>([])
  const [input, setInput] = useState('')

  useInput((char, key) => {
    if (key.escape) exit()
    else if (key.return) { handleSubmit(input); setInput('') }
    else setInput(prev => prev + char)
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

文字测量是终端布局的基础。Yoga 引擎需要知道每段文本的宽度和高度才能正确计算布局。测量过程需要处理三个问题：ANSI 转义序列不计入宽度（它们是控制字符，不占显示空间）、多行文本需要逐行计算、中文字符占 2 列（全角字符）。

```typescript
function measureText(text: string): { width: number; height: number } {
  const cleanText = stripAnsi(text)
  const lines = cleanText.split('\n')
  const widths = lines.map(line =>
    line.split('').reduce((width, char) => width + (isFullWidth(char) ? 2 : 1), 0)
  )
  return { width: Math.max(...widths), height: lines.length }
}
```

## 双缓冲渲染

双缓冲是避免终端闪烁的关键技术。渲染流程分为五步：状态更新触发 Reconciler 更新 Yoga Tree，Layout 引擎重新计算布局，渲染到 Buffer A（生成 ANSI 序列），交换缓冲区（Buffer A 变为 Previous Frame，Buffer B 变为 Current Frame），Diff 对比两帧差异只输出变化的区域。

Diff 算法逐行对比 Previous 和 Current 帧，只有内容不同的行才会生成 ANSI 光标移动和写入指令。这个设计将每帧的输出量从整个屏幕缩小到变化的行，大幅减少终端 I/O。

```typescript
function diffScreens(prev: string[], curr: string[]): DiffOutput[] {
  const outputs: DiffOutput[] = []
  for (let y = 0; y < Math.max(prev.length, curr.length); y++) {
    const prevLine = prev[y] || ''
    const currLine = curr[y] || ''
    if (prevLine !== currLine) {
      outputs.push({ type: 'move', x: 0, y })
      outputs.push({ type: 'clear_line' })
      outputs.push({ type: 'write', content: currLine })
    }
  }
  return outputs
}
```

渲染还有节流机制，间隔 16ms（约 60fps）。多次状态更新如果在同一个渲染间隔内发生，会合并为一次渲染，避免频繁的终端刷新。

## 交互式组件

终端中的交互依赖 `useInput` Hook 捕获键盘事件。InputBox 组件处理字符输入、光标移动（左右箭头）、退格删除和回车提交，通过拼接字符串的方式维护光标位置和文本内容。

```tsx
function InputBox({ onSubmit }) {
  const [value, setValue] = useState('')
  const [cursorPosition, setCursorPosition] = useState(0)

  useInput((char, key) => {
    if (key.leftArrow) setCursorPosition(Math.max(0, cursorPosition - 1))
    else if (key.rightArrow) setCursorPosition(Math.min(value.length, cursorPosition + 1))
    else if (key.backspace) {
      setValue(prev => prev.slice(0, cursorPosition - 1) + prev.slice(cursorPosition))
      setCursorPosition(Math.max(0, cursorPosition - 1))
    }
    else if (key.return) { onSubmit(value); setValue(''); setCursorPosition(0) }
    else {
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

SelectMenu 组件用上下箭头导航选项列表，回车确认。PermissionDialog 组件用左右箭头在 Allow/Deny 之间切换，回车提交。这些组件的共同模式是：`useState` 管理选中状态，`useInput` 捕获键盘事件，条件渲染高亮当前选中项。

## 工具调用与结果可视化

ToolCall 组件根据工具执行状态（pending/running/success/error）显示不同颜色的边框和图标。运行中显示输入参数摘要，成功显示耗时，错误显示错误信息。ToolResult 组件对长输出做截断处理（默认 500 字符），用户可以通过回车键展开完整内容。

```tsx
function ToolCall({ toolName, input, status }) {
  const statusColor = { pending: 'yellow', running: 'blue', success: 'green', error: 'red' }

  return (
    <Box flexDirection="column" borderStyle="single" borderColor={statusColor[status]}>
      <Box>
        <Text bold color={statusColor[status]}>⚙ {toolName}</Text>
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

这种状态驱动的可视化设计让用户能直观感知每个工具调用的进度和结果，不需要阅读原始日志。

## 长列表的虚拟滚动

当对话历史很长时，消息列表可能包含数百条消息。虚拟滚动组件只渲染可见区域的条目，通过 `scrollTop` 状态控制可见窗口，上下箭头滚动时更新 `scrollTop` 并重新计算可见条目。

```tsx
function VirtualList({ items, height }) {
  const [scrollTop, setScrollTop] = useState(0)
  const visibleItems = items.slice(scrollTop, scrollTop + height)

  useInput((char, key) => {
    if (key.upArrow) setScrollTop(Math.max(0, scrollTop - 1))
    else if (key.downArrow) setScrollTop(Math.min(items.length - height, scrollTop + 1))
  })

  return (
    <Box flexDirection="column" height={height}>
      {visibleItems.map((item, index) => (
        <Box key={scrollTop + index}><Text>{item.content}</Text></Box>
      ))}
    </Box>
  )
}
```

虚拟滚动将渲染成本从 O(n) 降到 O(visible)，在长对话场景下避免了终端刷新的卡顿。

## 非交互模式

Claude Code 会自动检测运行环境，在非 TTY 环境（管道、CI 环境、`--non-interactive` 参数）下切换为简单输出模式。检测逻辑依次检查 stdout 是否是 TTY、是否设置了 `CI=true` 环境变量、是否包含 `--non-interactive` 参数。

非交互模式下，消息以纯文本形式输出：用户消息前加 `>`，助手消息直接输出，工具调用显示 `[Tool: name]` 和输入参数，工具结果显示前 500 字符，错误显示 `[Error] message`。这种降级确保 Claude Code 可以作为管道命令使用（`echo "fix bug" | claude`），输出可以被其他工具解析。

## 颜色和样式系统

颜色系统定义了统一的语义映射：用户消息用 cyan，助手消息用 white，工具状态用四色（pending 黄色、running 蓝色、success 绿色、error 红色），状态指示用 active 绿色、idle 灰色、error 红色。这些颜色通过 ANSI 转义序列实现，支持 bold、dim 等修饰。

边框样式有三种：single（单线）、double（双线）、rounded（圆角）。权限对话框使用双线边框和黄色主题，视觉上区别于普通组件，强调其重要性。

## 关键源文件

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

**系列文章导航：**
- 上一篇：[Computer Use：桌面控制的九层安全关卡](/2026/04/06/079_claude-code-computer-use/)
- 系列完结
