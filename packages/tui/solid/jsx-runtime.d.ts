import type {
  BoxProps,
  Color,
  Style,
  Segment,
  BoxBorder,
  BoxShadow,
  TextAlign,
  EventHandler,
} from "@ares/tui-core/elements"
import type { BoxElement } from "@ares/tui-core/elements"
import type { TuiNode } from "./src/reconciler"

type CamelCase<S extends string> = S extends `${infer P}_${infer Q}` ? `${P}${Capitalize<CamelCase<Q>>}` : S

type CamelCaseStyle = {
  [K in keyof Style as CamelCase<K & string>]?: Style[K]
}

declare namespace JSX {
  type Element = TuiNode | ArrayElement | string | number | boolean | null | undefined

  type ArrayElement = Array<Element>

  interface IntrinsicElements {
    box: {
      ref?: (el: BoxElement) => void
      children?: Element
      focused?: boolean
      style?: Style

      bg?: Color | string
      fg?: Color | string
      opacity?: number
      segments?: Segment[]
      text_align?: TextAlign
      rounded?: number
      border?: BoxBorder
      shadow?: BoxShadow
      zIndex?: number
    } & Partial<CamelCaseStyle> & {
        [key: `on:${string}`]: EventHandler
      }
  }

  interface ElementChildrenAttribute {
    children: {}
  }
}
