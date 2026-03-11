import { render, useApp, useKeydown } from "@ares/tui-solid"
import { createSignal, onMount } from "solid-js"

function Counter() {
  const [count, setCount] = createSignal(0)
  const app = useApp()

  onMount(() => {
    setInterval(() => setCount((c) => c + 1), 1000)
  })

  useKeydown((event) => {
    const data = event.data as { codepoint: number; mods: number }
    // Ctrl+C to quit
    if (data.codepoint === 99 && (data.mods & 4) !== 0) {
      app.destroy()
      process.exit(0)
    }
    // Up arrow to increment
    if (data.codepoint === 65) setCount((c) => c + 1)
    // Down arrow to decrement
    if (data.codepoint === 66) setCount((c) => c - 1)
  })

  return (
    <box bg="#1a1a2e" width={{ percent: 100 }} height={{ percent: 100 }} justifyContent="center" alignItems="center">
      <box fg="#e0e0e0" width={{ point: 20 }} height={{ point: 1 }}>
        Count: {count()}
      </box>
    </box>
  )
}

render(Counter)
