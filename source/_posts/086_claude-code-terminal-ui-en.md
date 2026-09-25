---
title: "The Terminal UI Built with React and Ink"
date: 2026-04-06
tags: Terminal UI
categories: Claude Code
lang: en
label: 086_claude-code-terminal-ui
---

## A React App Inside Your Terminal

Claude Code's terminal interface is not a traditional line-by-line CLI output. It's a full React application. Using Ink — a React renderer for terminals — it delivers componentized UI, Flexbox layout, double-buffered rendering, and interactive dialogs. Choosing Ink over traditional libraries like ncurses or blessed came down to one thing: tapping the React ecosystem. Component-based architecture, state management, lifecycle hooks, and developer familiarity — all of it transfers directly.

Ink's architecture has four layers. React Components get converted into Ink Host Config calls through a custom React Reconciler. The Host Config uses the Yoga layout engine to compute Flexbox layouts in terminal character units. The Terminal Renderer then converts those layout results into ANSI escape sequences written to stdout. The result: terminal UI development feels close to web frontend work, but you keep terminal-grade performance.

<!-- more -->

## Core Components and Layout

The component tree follows a typical GUI application pattern. App serves as the root component, containing Header (title and status indicators), Main (message list, toolbar, context panel), and Footer (input box and suggestions). Within the message list, AssistantMessage nests ToolCall and ToolResult child components, forming a tree-structured message hierarchy.

The layout system is powered by the Yoga engine with full Flexbox support: flexDirection, justifyContent, alignItems, flexGrow, padding, margin, borderStyle, and more. One key difference from the browser environment is the unit of measurement — the terminal uses characters, not pixels. A `padding: 1` means one character of padding on each side.

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

Text measurement is the foundation here. The Yoga engine needs to know every text segment's width and height to lay things out correctly. The measurement process handles three issues: ANSI escape sequences don't count toward width (they're control characters that take no display space), multi-line text requires per-line calculation, and CJK characters occupy 2 columns (full-width characters).

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

## Double-Buffered Rendering

Double buffering is the key technique for avoiding terminal flicker. The rendering pipeline has five steps: a state update triggers the Reconciler to update the Yoga Tree, the Layout engine recalculates positions, the frame renders into Buffer A (producing ANSI sequences), buffers swap (Buffer A becomes Previous Frame, Buffer B becomes Current Frame), and a diff between the two frames produces output only for changed regions.

The diff algorithm compares Previous and Current frames line by line. Only lines with actual content changes generate ANSI cursor movement and write instructions. This design reduces each frame's output from the entire screen to just the changed lines, cutting terminal I/O significantly.

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

Rendering also has a throttle mechanism with a 16ms interval (roughly 60fps). Multiple state updates within the same render interval get merged into a single render pass, avoiding excessive terminal refreshes.

## Interactive Components

Terminal interaction relies on the `useInput` Hook to capture keyboard events. The InputBox component handles character input, cursor movement (left/right arrows), backspace deletion, and enter-to-submit. It maintains cursor position and text content through string concatenation.

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

The SelectMenu component uses up/down arrows to navigate an option list with enter to confirm. The PermissionDialog component uses left/right arrows to toggle between Allow and Deny, with enter to submit. The common pattern across these components: `useState` manages selection state, `useInput` captures keyboard events, and conditional rendering highlights the currently selected item.

## Tool Call Visualization

The ToolCall component displays different colored borders and icons based on tool execution status (pending/running/success/error). Running state shows an input parameter summary, success shows elapsed time, and error displays the error message. The ToolResult component truncates long output (default 500 characters), and users can press enter to expand the full content.

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

This state-driven visual design lets users perceive the progress and result of each tool call at a glance, without reading raw logs.

## Virtual Scrolling for Long Lists

When the conversation history grows long, the message list can contain hundreds of entries. The virtual scrolling component renders only the items in the visible region, using `scrollTop` state to control the visible window. Up/down arrow keys update `scrollTop` and recalculate which items are visible.

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

Virtual scrolling drops rendering cost from O(n) to O(visible), eliminating terminal refresh stutter in long conversation scenarios.

## Non-Interactive Mode

Claude Code automatically detects its runtime environment. In non-TTY environments (piped output, CI, `--non-interactive` flag), it switches to a simplified output mode. Detection checks whether stdout is a TTY, whether the `CI=true` environment variable is set, and whether the `--non-interactive` flag is present.

In non-interactive mode, messages output as plain text: user messages get prefixed with `>`, assistant messages output directly, tool calls show `[Tool: name]` with input parameters, tool results show the first 500 characters, and errors display as `[Error] message`. This degradation ensures Claude Code works as a pipe command (`echo "fix bug" | claude`) where output needs to be parseable by other tools.

## Colors and Style System

The color system defines a unified semantic mapping: cyan for user messages, white for assistant messages, four colors for tool status (pending yellow, running blue, success green, error red), and status indicators using green for active, gray for idle, red for error. These colors are implemented through ANSI escape sequences with support for bold, dim, and other text modifiers.

Border styles come in three variants: single (single line), double (double line), and rounded (rounded corners). The permission dialog uses double-line borders with a yellow theme, visually separating it from regular components and emphasizing its importance.

## Key Source Files

| File | Responsibility |
|------|----------------|
| `src/components/App.tsx` | Main application entry point |
| `src/components/Header.tsx` | Title bar and status indicators |
| `src/components/MessageList.tsx` | Message list rendering |
| `src/components/ToolCall.tsx` | Tool call visualization |
| `src/components/InputBox.tsx` | Input box component |
| `src/components/PermissionDialog.tsx` | Permission dialog |
| `src/renderers/nonInteractive.ts` | Non-interactive mode rendering |
| `src/styles/colors.ts` | Color system |
| `ink/lib/renderer.ts` | Double-buffered rendering engine |
| `ink/lib/measureText.ts` | Text measurement |

---

**Series Navigation:**
- Previous: [Computer Use: Nine Layers of Security for Desktop Control](/2026/04/06/079_claude-code-computer-use/)
- End of series
