import type {
  Color,
  Style,
  Segment,
  BoxBorder,
  BoxShadow,
  ScrollableProps,
  TextAlign,
  EventHandler,
} from "@ares/tui-core/elements"
import type { BoxElement, ScrollableElement } from "@ares/tui-core/elements"
import type { TuiNode } from "./src/reconciler"

type CamelCase<S extends string> = S extends `${infer P}_${infer Q}` ? `${P}${Capitalize<CamelCase<Q>>}` : S

type CamelCaseStyle = {
  [K in keyof Style as CamelCase<K & string>]?: Style[K]
}

type NativeElementProps<TElement> = {
  ref?: (el: TElement) => void
  children?: Element
  focused?: boolean
  style?: Style
  zIndex?: number
} & Partial<CamelCaseStyle> & {
    [key: `on:${string}`]: EventHandler
  }

declare namespace JSX {
  type Element = TuiNode | ArrayElement | string | number | boolean | null | undefined

  type ArrayElement = Array<Element>

  interface IntrinsicElements {
    box: NativeElementProps<BoxElement> & {
      bg?: Color | string
      fg?: Color | string
      opacity?: number
      segments?: Segment[]
      text_align?: TextAlign
      rounded?: number
      border?: BoxBorder
      shadow?: BoxShadow
    }
    scrollable: NativeElementProps<ScrollableElement> & {
      mode?: ScrollableProps["mode"]
    }
  }

  interface ElementChildrenAttribute {
    children: {}
  }
}
