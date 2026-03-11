import { TuiApp } from "@ares/tui-core/app"
import { BoxElement } from "@ares/tui-core/elements"
import { _render, createComponent } from "./src/reconciler"
import { AppContext } from "./src/hooks"

type DisposeFn = () => void

export function render(App: () => any): { app: TuiApp; dispose: DisposeFn } {
  const app = new TuiApp()

  const root = new BoxElement()
  root.setStyle({
    width: { percent: 100 },
    height: { percent: 100 },
  })
  app.setRoot(root)

  const dispose = _render(
    () =>
      createComponent(AppContext.Provider, {
        get value() {
          return app
        },
        get children() {
          return createComponent(App, {})
        },
      }),
    root,
  )

  app.start()

  return {
    app,
    dispose() {
      dispose()
      app.destroy()
    },
  }
}

export { _render, createComponent, createElement, createTextNode, insertNode, insert, spread, setProp, mergeProps, effect, memo, use } from "./src/reconciler"
export { TextNode, SlotNode, type TuiNode } from "./src/reconciler"
export { AppContext, useApp, useKeydown, useKeyup, useResize } from "./src/hooks"
export { parseColor } from "./src/utils"
export type { JSX } from "./jsx-runtime"
