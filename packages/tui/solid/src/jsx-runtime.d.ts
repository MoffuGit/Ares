import type { Style, Color, BoxBorder, BoxShadow, TextAlign, Segment, EventHandler } from "@ares/tui-core/elements";

type StyleShorthand = {
    flexGrow?: number;
    flexShrink?: number;
    flexBasis?: Style["flex_basis"];
    flexDirection?: Style["flex_direction"];
    justifyContent?: Style["justify_content"];
    alignContent?: Style["align_content"];
    alignItems?: Style["align_items"];
    alignSelf?: Style["align_self"];
    flexWrap?: Style["flex_wrap"];
    overflow?: Style["overflow"];
    display?: Style["display"];
    width?: Style["width"];
    height?: Style["height"];
    minWidth?: Style["min_width"];
    minHeight?: Style["min_height"];
    maxWidth?: Style["max_width"];
    maxHeight?: Style["max_height"];
    aspectRatio?: number;
    positionType?: Style["position_type"];
    direction?: Style["direction"];
    boxSizing?: Style["box_sizing"];
    flex?: number;
};

type EventProps = {
    [K in `on:${string}`]?: EventHandler;
} & {
    onClick?: EventHandler;
    onKeydown?: EventHandler;
    onKeyup?: EventHandler;
    onMousedown?: EventHandler;
    onMouseup?: EventHandler;
    onMousemove?: EventHandler;
    onMouseenter?: EventHandler;
    onMouseleave?: EventHandler;
    onWheel?: EventHandler;
    onFocus?: EventHandler;
    onBlur?: EventHandler;
    onResize?: EventHandler;
};

interface BoxAttributes extends StyleShorthand, EventProps {
    ref?: (el: import("@ares/tui-core/elements").BoxElement) => void;
    style?: Style;
    bg?: Color | string;
    fg?: Color | string;
    color?: Color | string;
    background?: Color | string;
    opacity?: number;
    zIndex?: number;
    rounded?: number;
    border?: BoxBorder;
    shadow?: BoxShadow;
    textAlign?: TextAlign;
    text_align?: TextAlign;
    segments?: Segment[];
    children?: unknown;
}

declare module "solid-js" {
    namespace JSX {
        interface IntrinsicElements {
            box: BoxAttributes;
        }
    }
}
