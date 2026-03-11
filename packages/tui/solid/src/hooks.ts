import { TuiApp } from "@ares/tui-core/app"
import type { Element, ElementEvent, EventHandler } from "@ares/tui-core/elements"
import { createContext, onCleanup, onMount, useContext } from "solid-js"

export const AppContext = createContext<TuiApp>()

export const useApp = (): TuiApp => {
  const app = useContext(AppContext)
  if (!app) {
    throw new Error("useApp must be called within a render() tree")
  }
  return app
}

export const useKeydown = (callback: EventHandler) => {
  const app = useApp()

  onMount(() => {
    app.root?.on("keydown", callback)
  })

  onCleanup(() => {
    app.root?.off("keydown", callback)
  })
}

export const useKeyup = (callback: EventHandler) => {
  const app = useApp()

  onMount(() => {
    app.root?.on("keyup", callback)
  })

  onCleanup(() => {
    app.root?.off("keyup", callback)
  })
}

export const useResize = (callback: EventHandler) => {
  const app = useApp()

  onMount(() => {
    app.root?.on("resize", callback)
  })

  onCleanup(() => {
    app.root?.off("resize", callback)
  })
}
