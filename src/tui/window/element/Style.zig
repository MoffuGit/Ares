const yoga = @import("yoga");
const Node = @import("Node.zig");

pub const Style = @This();

direction: Direction = .inherit,
flex_direction: FlexDirection = .column,
justify_content: Justify = .flex_start,
align_content: Align = .auto,
align_items: Align = .stretch,
align_self: Align = .auto,
position_type: PositionType = .relative,
flex_wrap: Wrap = .no_wrap,
overflow: Overflow = .visible,
display: Display = .flex,
box_sizing: BoxSizing = .border_box,

flex: ?f32 = null,
flex_grow: f32 = 0,
flex_shrink: f32 = 1,
flex_basis: StyleValue = .auto,

position: Edges = .{},
margin: Edges = .{},
padding: Edges = .{},
border: BorderEdges = .{},

gap: Gap = .{},

width: StyleValue = .auto,
height: StyleValue = .auto,
min_width: StyleValue = .auto,
min_height: StyleValue = .auto,
max_width: StyleValue = .undefined,
max_height: StyleValue = .undefined,

aspect_ratio: ?f32 = null,

pub const Direction = enum(c_uint) {
    inherit = yoga.YGDirectionInherit,
    ltr = yoga.YGDirectionLTR,
    rtl = yoga.YGDirectionRTL,
};

pub const FlexDirection = enum(c_uint) {
    column = yoga.YGFlexDirectionColumn,
    column_reverse = yoga.YGFlexDirectionColumnReverse,
    row = yoga.YGFlexDirectionRow,
    row_reverse = yoga.YGFlexDirectionRowReverse,
};

pub const Justify = enum(c_uint) {
    flex_start = yoga.YGJustifyFlexStart,
    center = yoga.YGJustifyCenter,
    flex_end = yoga.YGJustifyFlexEnd,
    space_between = yoga.YGJustifySpaceBetween,
    space_around = yoga.YGJustifySpaceAround,
    space_evenly = yoga.YGJustifySpaceEvenly,
};

pub const Align = enum(c_uint) {
    auto = yoga.YGAlignAuto,
    flex_start = yoga.YGAlignFlexStart,
    center = yoga.YGAlignCenter,
    flex_end = yoga.YGAlignFlexEnd,
    stretch = yoga.YGAlignStretch,
    baseline = yoga.YGAlignBaseline,
    space_between = yoga.YGAlignSpaceBetween,
    space_around = yoga.YGAlignSpaceAround,
    space_evenly = yoga.YGAlignSpaceEvenly,
};

pub const PositionType = enum(c_uint) {
    static = yoga.YGPositionTypeStatic,
    relative = yoga.YGPositionTypeRelative,
    absolute = yoga.YGPositionTypeAbsolute,
};

pub const Wrap = enum(c_uint) {
    no_wrap = yoga.YGWrapNoWrap,
    wrap = yoga.YGWrapWrap,
    wrap_reverse = yoga.YGWrapWrapReverse,
};

pub const Overflow = enum(c_uint) {
    visible = yoga.YGOverflowVisible,
    hidden = yoga.YGOverflowHidden,
    scroll = yoga.YGOverflowScroll,
};

pub const Display = enum(c_uint) {
    flex = yoga.YGDisplayFlex,
    none = yoga.YGDisplayNone,
    contents = yoga.YGDisplayContents,
};

pub const BoxSizing = enum(c_uint) {
    border_box = yoga.YGBoxSizingBorderBox,
    content_box = yoga.YGBoxSizingContentBox,
};

pub const Edge = enum(c_uint) {
    left = yoga.YGEdgeLeft,
    top = yoga.YGEdgeTop,
    right = yoga.YGEdgeRight,
    bottom = yoga.YGEdgeBottom,
    start = yoga.YGEdgeStart,
    end = yoga.YGEdgeEnd,
    horizontal = yoga.YGEdgeHorizontal,
    vertical = yoga.YGEdgeVertical,
    all = yoga.YGEdgeAll,
};

pub const Gutter = enum(c_uint) {
    column = yoga.YGGutterColumn,
    row = yoga.YGGutterRow,
    all = yoga.YGGutterAll,
};

pub const StyleValue = union(enum) {
    undefined,
    auto,
    point: f32,
    percent: f32,
    max_content,
    fit_content,
    stretch,

    pub fn toYGValue(self: StyleValue) yoga.YGValue {
        return switch (self) {
            .undefined => .{ .value = yoga.YGUndefined, .unit = yoga.YGUnitUndefined },
            .auto => .{ .value = yoga.YGUndefined, .unit = yoga.YGUnitAuto },
            .point => |v| .{ .value = v, .unit = yoga.YGUnitPoint },
            .percent => |v| .{ .value = v, .unit = yoga.YGUnitPercent },
            .max_content => .{ .value = yoga.YGUndefined, .unit = yoga.YGUnitMaxContent },
            .fit_content => .{ .value = yoga.YGUndefined, .unit = yoga.YGUnitFitContent },
            .stretch => .{ .value = yoga.YGUndefined, .unit = yoga.YGUnitStretch },
        };
    }

    pub fn fromYGValue(value: yoga.YGValue) StyleValue {
        return switch (value.unit) {
            yoga.YGUnitUndefined => .undefined,
            yoga.YGUnitAuto => .auto,
            yoga.YGUnitPoint => .{ .point = value.value },
            yoga.YGUnitPercent => .{ .percent = value.value },
            yoga.YGUnitMaxContent => .max_content,
            yoga.YGUnitFitContent => .fit_content,
            yoga.YGUnitStretch => .stretch,
            else => .undefined,
        };
    }

    pub fn px(value: f32) StyleValue {
        return .{ .point = value };
    }

    pub fn pct(value: f32) StyleValue {
        return .{ .percent = value };
    }
};

pub const Edges = struct {
    left: StyleValue = .undefined,
    top: StyleValue = .undefined,
    right: StyleValue = .undefined,
    bottom: StyleValue = .undefined,
    start: StyleValue = .undefined,
    end: StyleValue = .undefined,
    horizontal: StyleValue = .undefined,
    vertical: StyleValue = .undefined,
    all: StyleValue = .undefined,

    pub fn uniform(value: StyleValue) Edges {
        return .{ .all = value };
    }

    pub fn symmetric(h: StyleValue, v: StyleValue) Edges {
        return .{ .horizontal = h, .vertical = v };
    }

    pub fn ltrb(l: StyleValue, t: StyleValue, r: StyleValue, b: StyleValue) Edges {
        return .{ .left = l, .top = t, .right = r, .bottom = b };
    }
};

pub const BorderEdges = struct {
    left: ?f32 = null,
    top: ?f32 = null,
    right: ?f32 = null,
    bottom: ?f32 = null,
    start: ?f32 = null,
    end: ?f32 = null,
    horizontal: ?f32 = null,
    vertical: ?f32 = null,
    all: ?f32 = null,

    pub fn uniform(value: f32) BorderEdges {
        return .{ .all = value };
    }
};

pub const Gap = struct {
    column: StyleValue = .undefined,
    row: StyleValue = .undefined,
    all: StyleValue = .undefined,

    pub fn uniform(value: StyleValue) Gap {
        return .{ .all = value };
    }

    pub fn axes(col: StyleValue, r: StyleValue) Gap {
        return .{ .column = col, .row = r };
    }
};

pub fn apply(self: *const Style, node: Node) void {
    node.setDirection(self.direction);
    node.setFlexDirection(self.flex_direction);
    node.setJustifyContent(self.justify_content);
    node.setAlignContent(self.align_content);
    node.setAlignItems(self.align_items);
    node.setAlignSelf(self.align_self);
    node.setPositionType(self.position_type);
    node.setFlexWrap(self.flex_wrap);
    node.setOverflow(self.overflow);
    node.setDisplay(self.display);
    node.setBoxSizing(self.box_sizing);

    if (self.flex) |f| node.setFlex(f);
    node.setFlexGrow(self.flex_grow);
    node.setFlexShrink(self.flex_shrink);
    node.setFlexBasis(self.flex_basis);

    applyEdges(node, self.position, Node.setPosition);
    applyEdges(node, self.margin, Node.setMargin);
    applyEdges(node, self.padding, Node.setPadding);
    applyBorderEdges(node, self.border);

    applyGap(node, self.gap);

    node.setWidth(self.width);
    node.setHeight(self.height);
    node.setMinWidth(self.min_width);
    node.setMinHeight(self.min_height);
    node.setMaxWidth(self.max_width);
    node.setMaxHeight(self.max_height);

    if (self.aspect_ratio) |ar| {
        node.setAspectRatio(ar);
    }
}

fn applyEdges(node: Node, edges: Edges, setter: *const fn (Node, Edge, StyleValue) void) void {
    const edge_values = [_]struct { edge: Edge, value: StyleValue }{
        .{ .edge = .left, .value = edges.left },
        .{ .edge = .top, .value = edges.top },
        .{ .edge = .right, .value = edges.right },
        .{ .edge = .bottom, .value = edges.bottom },
        .{ .edge = .start, .value = edges.start },
        .{ .edge = .end, .value = edges.end },
        .{ .edge = .horizontal, .value = edges.horizontal },
        .{ .edge = .vertical, .value = edges.vertical },
        .{ .edge = .all, .value = edges.all },
    };

    for (edge_values) |ev| {
        if (ev.value != .undefined) {
            setter(node, ev.edge, ev.value);
        }
    }
}

fn applyBorderEdges(node: Node, edges: BorderEdges) void {
    const edge_values = [_]struct { edge: Edge, value: ?f32 }{
        .{ .edge = .left, .value = edges.left },
        .{ .edge = .top, .value = edges.top },
        .{ .edge = .right, .value = edges.right },
        .{ .edge = .bottom, .value = edges.bottom },
        .{ .edge = .start, .value = edges.start },
        .{ .edge = .end, .value = edges.end },
        .{ .edge = .horizontal, .value = edges.horizontal },
        .{ .edge = .vertical, .value = edges.vertical },
        .{ .edge = .all, .value = edges.all },
    };

    for (edge_values) |ev| {
        if (ev.value) |v| {
            node.setBorder(ev.edge, v);
        }
    }
}

fn applyGap(node: Node, gap: Gap) void {
    const gap_values = [_]struct { gutter: Gutter, value: StyleValue }{
        .{ .gutter = .column, .value = gap.column },
        .{ .gutter = .row, .value = gap.row },
        .{ .gutter = .all, .value = gap.all },
    };

    for (gap_values) |gv| {
        if (gv.value != .undefined) {
            node.setGap(gv.gutter, gv.value);
        }
    }
}
