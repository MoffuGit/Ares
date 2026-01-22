const std = @import("std");
const yoga = @import("yoga");

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

pub fn apply(self: *const Style, node: yoga.YGNodeRef) void {
    yoga.YGNodeStyleSetDirection(node, @intFromEnum(self.direction));
    yoga.YGNodeStyleSetFlexDirection(node, @intFromEnum(self.flex_direction));
    yoga.YGNodeStyleSetJustifyContent(node, @intFromEnum(self.justify_content));
    yoga.YGNodeStyleSetAlignContent(node, @intFromEnum(self.align_content));
    yoga.YGNodeStyleSetAlignItems(node, @intFromEnum(self.align_items));
    yoga.YGNodeStyleSetAlignSelf(node, @intFromEnum(self.align_self));
    yoga.YGNodeStyleSetPositionType(node, @intFromEnum(self.position_type));
    yoga.YGNodeStyleSetFlexWrap(node, @intFromEnum(self.flex_wrap));
    yoga.YGNodeStyleSetOverflow(node, @intFromEnum(self.overflow));
    yoga.YGNodeStyleSetDisplay(node, @intFromEnum(self.display));
    yoga.YGNodeStyleSetBoxSizing(node, @intFromEnum(self.box_sizing));

    if (self.flex) |f| yoga.YGNodeStyleSetFlex(node, f);
    yoga.YGNodeStyleSetFlexGrow(node, self.flex_grow);
    yoga.YGNodeStyleSetFlexShrink(node, self.flex_shrink);
    applyStyleValue(node, self.flex_basis, setFlexBasis);

    applyEdges(node, self.position, setPosition);
    applyEdges(node, self.margin, setMargin);
    applyEdges(node, self.padding, setPadding);
    applyBorderEdges(node, self.border);

    applyGap(node, self.gap);

    applyStyleValue(node, self.width, setWidth);
    applyStyleValue(node, self.height, setHeight);
    applyStyleValue(node, self.min_width, setMinWidth);
    applyStyleValue(node, self.min_height, setMinHeight);
    applyStyleValue(node, self.max_width, setMaxWidth);
    applyStyleValue(node, self.max_height, setMaxHeight);

    if (self.aspect_ratio) |ar| {
        yoga.YGNodeStyleSetAspectRatio(node, ar);
    }
}

const SetValueFn = *const fn (yoga.YGNodeRef, f32) callconv(.c) void;
const SetAutoFn = *const fn (yoga.YGNodeRef) callconv(.c) void;
const SetMaxContentFn = *const fn (yoga.YGNodeRef) callconv(.c) void;
const SetFitContentFn = *const fn (yoga.YGNodeRef) callconv(.c) void;
const SetStretchFn = *const fn (yoga.YGNodeRef) callconv(.c) void;

const DimensionSetters = struct {
    point: SetValueFn,
    percent: SetValueFn,
    auto: ?SetAutoFn = null,
    max_content: ?SetMaxContentFn = null,
    fit_content: ?SetFitContentFn = null,
    stretch_fn: ?SetStretchFn = null,
};

const setFlexBasis = DimensionSetters{
    .point = yoga.YGNodeStyleSetFlexBasis,
    .percent = yoga.YGNodeStyleSetFlexBasisPercent,
    .auto = yoga.YGNodeStyleSetFlexBasisAuto,
    .max_content = yoga.YGNodeStyleSetFlexBasisMaxContent,
    .fit_content = yoga.YGNodeStyleSetFlexBasisFitContent,
    .stretch_fn = yoga.YGNodeStyleSetFlexBasisStretch,
};

const setWidth = DimensionSetters{
    .point = yoga.YGNodeStyleSetWidth,
    .percent = yoga.YGNodeStyleSetWidthPercent,
    .auto = yoga.YGNodeStyleSetWidthAuto,
    .max_content = yoga.YGNodeStyleSetWidthMaxContent,
    .fit_content = yoga.YGNodeStyleSetWidthFitContent,
    .stretch_fn = yoga.YGNodeStyleSetWidthStretch,
};

const setHeight = DimensionSetters{
    .point = yoga.YGNodeStyleSetHeight,
    .percent = yoga.YGNodeStyleSetHeightPercent,
    .auto = yoga.YGNodeStyleSetHeightAuto,
    .max_content = yoga.YGNodeStyleSetHeightMaxContent,
    .fit_content = yoga.YGNodeStyleSetHeightFitContent,
    .stretch_fn = yoga.YGNodeStyleSetHeightStretch,
};

const setMinWidth = DimensionSetters{
    .point = yoga.YGNodeStyleSetMinWidth,
    .percent = yoga.YGNodeStyleSetMinWidthPercent,
    .max_content = yoga.YGNodeStyleSetMinWidthMaxContent,
    .fit_content = yoga.YGNodeStyleSetMinWidthFitContent,
    .stretch_fn = yoga.YGNodeStyleSetMinWidthStretch,
};

const setMinHeight = DimensionSetters{
    .point = yoga.YGNodeStyleSetMinHeight,
    .percent = yoga.YGNodeStyleSetMinHeightPercent,
    .max_content = yoga.YGNodeStyleSetMinHeightMaxContent,
    .fit_content = yoga.YGNodeStyleSetMinHeightFitContent,
    .stretch_fn = yoga.YGNodeStyleSetMinHeightStretch,
};

const setMaxWidth = DimensionSetters{
    .point = yoga.YGNodeStyleSetMaxWidth,
    .percent = yoga.YGNodeStyleSetMaxWidthPercent,
    .max_content = yoga.YGNodeStyleSetMaxWidthMaxContent,
    .fit_content = yoga.YGNodeStyleSetMaxWidthFitContent,
    .stretch_fn = yoga.YGNodeStyleSetMaxWidthStretch,
};

const setMaxHeight = DimensionSetters{
    .point = yoga.YGNodeStyleSetMaxHeight,
    .percent = yoga.YGNodeStyleSetMaxHeightPercent,
    .max_content = yoga.YGNodeStyleSetMaxHeightMaxContent,
    .fit_content = yoga.YGNodeStyleSetMaxHeightFitContent,
    .stretch_fn = yoga.YGNodeStyleSetMaxHeightStretch,
};

fn applyStyleValue(node: yoga.YGNodeRef, value: StyleValue, setters: DimensionSetters) void {
    switch (value) {
        .undefined => {},
        .auto => if (setters.auto) |f| f(node),
        .point => |v| setters.point(node, v),
        .percent => |v| setters.percent(node, v),
        .max_content => if (setters.max_content) |f| f(node),
        .fit_content => if (setters.fit_content) |f| f(node),
        .stretch => if (setters.stretch_fn) |f| f(node),
    }
}

const EdgeSetValueFn = *const fn (yoga.YGNodeRef, c_uint, f32) callconv(.c) void;
const EdgeSetAutoFn = *const fn (yoga.YGNodeRef, c_uint) callconv(.c) void;

const EdgeSetters = struct {
    point: EdgeSetValueFn,
    percent: EdgeSetValueFn,
    auto: ?EdgeSetAutoFn = null,
};

const setPosition = EdgeSetters{
    .point = yoga.YGNodeStyleSetPosition,
    .percent = yoga.YGNodeStyleSetPositionPercent,
    .auto = yoga.YGNodeStyleSetPositionAuto,
};

const setMargin = EdgeSetters{
    .point = yoga.YGNodeStyleSetMargin,
    .percent = yoga.YGNodeStyleSetMarginPercent,
    .auto = yoga.YGNodeStyleSetMarginAuto,
};

const setPadding = EdgeSetters{
    .point = yoga.YGNodeStyleSetPadding,
    .percent = yoga.YGNodeStyleSetPaddingPercent,
};

fn applyEdges(node: yoga.YGNodeRef, edges: Edges, setters: EdgeSetters) void {
    const edge_values = [_]struct { edge: c_uint, value: StyleValue }{
        .{ .edge = yoga.YGEdgeLeft, .value = edges.left },
        .{ .edge = yoga.YGEdgeTop, .value = edges.top },
        .{ .edge = yoga.YGEdgeRight, .value = edges.right },
        .{ .edge = yoga.YGEdgeBottom, .value = edges.bottom },
        .{ .edge = yoga.YGEdgeStart, .value = edges.start },
        .{ .edge = yoga.YGEdgeEnd, .value = edges.end },
        .{ .edge = yoga.YGEdgeHorizontal, .value = edges.horizontal },
        .{ .edge = yoga.YGEdgeVertical, .value = edges.vertical },
        .{ .edge = yoga.YGEdgeAll, .value = edges.all },
    };

    for (edge_values) |ev| {
        switch (ev.value) {
            .undefined => {},
            .auto => if (setters.auto) |f| f(node, ev.edge),
            .point => |v| setters.point(node, ev.edge, v),
            .percent => |v| setters.percent(node, ev.edge, v),
            else => {},
        }
    }
}

fn applyBorderEdges(node: yoga.YGNodeRef, edges: BorderEdges) void {
    const edge_values = [_]struct { edge: c_uint, value: ?f32 }{
        .{ .edge = yoga.YGEdgeLeft, .value = edges.left },
        .{ .edge = yoga.YGEdgeTop, .value = edges.top },
        .{ .edge = yoga.YGEdgeRight, .value = edges.right },
        .{ .edge = yoga.YGEdgeBottom, .value = edges.bottom },
        .{ .edge = yoga.YGEdgeStart, .value = edges.start },
        .{ .edge = yoga.YGEdgeEnd, .value = edges.end },
        .{ .edge = yoga.YGEdgeHorizontal, .value = edges.horizontal },
        .{ .edge = yoga.YGEdgeVertical, .value = edges.vertical },
        .{ .edge = yoga.YGEdgeAll, .value = edges.all },
    };

    for (edge_values) |ev| {
        if (ev.value) |v| {
            yoga.YGNodeStyleSetBorder(node, ev.edge, v);
        }
    }
}

fn applyGap(node: yoga.YGNodeRef, gap: Gap) void {
    const gap_values = [_]struct { gutter: c_uint, value: StyleValue }{
        .{ .gutter = yoga.YGGutterColumn, .value = gap.column },
        .{ .gutter = yoga.YGGutterRow, .value = gap.row },
        .{ .gutter = yoga.YGGutterAll, .value = gap.all },
    };

    for (gap_values) |gv| {
        switch (gv.value) {
            .undefined => {},
            .point => |v| yoga.YGNodeStyleSetGap(node, gv.gutter, v),
            .percent => |v| yoga.YGNodeStyleSetGapPercent(node, gv.gutter, v),
            else => {},
        }
    }
}
