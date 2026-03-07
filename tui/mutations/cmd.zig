const Element = @import("../window/element/mod.zig");
const Style = Element.Style;

pub const CmdType = enum(u8) {
    create = 0,
    set_props = 1,
    append_child = 2,
    insert_before = 3,
    remove_child = 4,
    delete = 5,
    set_root = 6,
    set_focus = 7,
};

pub const ElementType = enum(u8) {
    box = 0,
};

pub const TextAlign = enum {
    left,
    center,
    right,
    justify,
};

pub const EdgeValues = struct {
    left: ?Style.StyleValue = null,
    top: ?Style.StyleValue = null,
    right: ?Style.StyleValue = null,
    bottom: ?Style.StyleValue = null,
    start: ?Style.StyleValue = null,
    end: ?Style.StyleValue = null,
    horizontal: ?Style.StyleValue = null,
    vertical: ?Style.StyleValue = null,
    all: ?Style.StyleValue = null,
};

pub const BorderEdgeValues = struct {
    left: ?f32 = null,
    top: ?f32 = null,
    right: ?f32 = null,
    bottom: ?f32 = null,
    start: ?f32 = null,
    end: ?f32 = null,
    horizontal: ?f32 = null,
    vertical: ?f32 = null,
    all: ?f32 = null,
};

pub const GapValues = struct {
    column: ?Style.StyleValue = null,
    row: ?Style.StyleValue = null,
    all: ?Style.StyleValue = null,
};

pub const StylePatch = struct {
    direction: ?Style.Direction = null,
    flex_direction: ?Style.FlexDirection = null,
    justify_content: ?Style.Justify = null,
    align_content: ?Style.Align = null,
    align_items: ?Style.Align = null,
    align_self: ?Style.Align = null,
    position_type: ?Style.PositionType = null,
    flex_wrap: ?Style.Wrap = null,
    overflow: ?Style.Overflow = null,
    display: ?Style.Display = null,
    box_sizing: ?Style.BoxSizing = null,

    flex: ?f32 = null,
    flex_grow: ?f32 = null,
    flex_shrink: ?f32 = null,
    flex_basis: ?Style.StyleValue = null,

    width: ?Style.StyleValue = null,
    height: ?Style.StyleValue = null,
    min_width: ?Style.StyleValue = null,
    min_height: ?Style.StyleValue = null,
    max_width: ?Style.StyleValue = null,
    max_height: ?Style.StyleValue = null,

    aspect_ratio: ?f32 = null,

    position: ?EdgeValues = null,
    margin: ?EdgeValues = null,
    padding: ?EdgeValues = null,
    border: ?BorderEdgeValues = null,

    gap: ?GapValues = null,
};

pub const ColorValue = union(enum) {
    default,
    rgb: [3]u8,
    rgba: [4]u8,
};

pub const BoxProps = struct {
    opacity: ?f32 = null,
    text_align: ?TextAlign = null,
    rounded: ?f32 = null,
    bg: ?ColorValue = null,
    fg: ?ColorValue = null,
};

pub const Props = struct {
    z_index: ?usize = null,
    style: ?StylePatch = null,
    box: ?BoxProps = null,
};

pub const Command = union(CmdType) {
    create: struct { id: u64, element_type: ElementType },
    set_props: struct { id: u64, props: Props },
    append_child: struct { id: u64, child_id: u64 },
    insert_before: struct { id: u64, child_id: u64, before_id: u64 },
    remove_child: struct { id: u64, child_id: u64 },
    delete: struct { id: u64 },
    set_root: struct { id: u64 },
    set_focus: struct { id: u64 },
};
