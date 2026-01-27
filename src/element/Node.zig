pub const yoga = @import("yoga");
const Style = @import("Style.zig");

const Node = @This();

var config: yoga.YGConfigRef = null;

yg_node: yoga.YGNodeRef,
index: usize,

fn getConfig() yoga.YGConfigRef {
    if (config == null) {
        config = yoga.YGConfigNew();
        yoga.YGConfigSetPointScaleFactor(config, 2.0);
    }
    return config;
}

pub fn init(index: usize) Node {
    return .{
        .yg_node = yoga.YGNodeNewWithConfig(getConfig()),
        .index = index,
    };
}

pub fn deinit(self: *Node) void {
    yoga.YGNodeFree(self.yg_node);
}

pub fn insertChild(self: Node, child: Node, index: usize) void {
    yoga.YGNodeInsertChild(self.yg_node, child.yg_node, index);
}

pub fn removeChild(self: Node, child: Node) void {
    yoga.YGNodeRemoveChild(self.yg_node, child.yg_node);
}

pub fn removeAllChildrens(self: Node) void {
    yoga.YGNodeRemoveAllChildren(self.yg_node);
}

pub fn setDirection(self: Node, direction: Style.Direction) void {
    yoga.YGNodeStyleSetDirection(self.yg_node, @intFromEnum(direction));
}

pub fn setFlexDirection(self: Node, flex_direction: Style.FlexDirection) void {
    yoga.YGNodeStyleSetFlexDirection(self.yg_node, @intFromEnum(flex_direction));
}

pub fn setJustifyContent(self: Node, justify: Style.Justify) void {
    yoga.YGNodeStyleSetJustifyContent(self.yg_node, @intFromEnum(justify));
}

pub fn setAlignContent(self: Node, alignment: Style.Align) void {
    yoga.YGNodeStyleSetAlignContent(self.yg_node, @intFromEnum(alignment));
}

pub fn setAlignItems(self: Node, alignment: Style.Align) void {
    yoga.YGNodeStyleSetAlignItems(self.yg_node, @intFromEnum(alignment));
}

pub fn setAlignSelf(self: Node, alignment: Style.Align) void {
    yoga.YGNodeStyleSetAlignSelf(self.yg_node, @intFromEnum(alignment));
}

pub fn setPositionType(self: Node, position_type: Style.PositionType) void {
    yoga.YGNodeStyleSetPositionType(self.yg_node, @intFromEnum(position_type));
}

pub fn setFlexWrap(self: Node, wrap: Style.Wrap) void {
    yoga.YGNodeStyleSetFlexWrap(self.yg_node, @intFromEnum(wrap));
}

pub fn setOverflow(self: Node, overflow: Style.Overflow) void {
    yoga.YGNodeStyleSetOverflow(self.yg_node, @intFromEnum(overflow));
}

pub fn setDisplay(self: Node, display: Style.Display) void {
    yoga.YGNodeStyleSetDisplay(self.yg_node, @intFromEnum(display));
}

pub fn setBoxSizing(self: Node, box_sizing: Style.BoxSizing) void {
    yoga.YGNodeStyleSetBoxSizing(self.yg_node, @intFromEnum(box_sizing));
}

pub fn setFlex(self: Node, flex: f32) void {
    yoga.YGNodeStyleSetFlex(self.yg_node, flex);
}

pub fn setFlexGrow(self: Node, flex_grow: f32) void {
    yoga.YGNodeStyleSetFlexGrow(self.yg_node, flex_grow);
}

pub fn setFlexShrink(self: Node, flex_shrink: f32) void {
    yoga.YGNodeStyleSetFlexShrink(self.yg_node, flex_shrink);
}

pub fn setFlexBasis(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => yoga.YGNodeStyleSetFlexBasisAuto(self.yg_node),
        .point => |v| yoga.YGNodeStyleSetFlexBasis(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetFlexBasisPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetFlexBasisMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetFlexBasisFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetFlexBasisStretch(self.yg_node),
    }
}

pub fn setWidth(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => yoga.YGNodeStyleSetWidthAuto(self.yg_node),
        .point => |v| yoga.YGNodeStyleSetWidth(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetWidthPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetWidthMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetWidthFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetWidthStretch(self.yg_node),
    }
}

pub fn setHeight(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => yoga.YGNodeStyleSetHeightAuto(self.yg_node),
        .point => |v| yoga.YGNodeStyleSetHeight(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetHeightPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetHeightMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetHeightFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetHeightStretch(self.yg_node),
    }
}

pub fn setMinWidth(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => {},
        .point => |v| yoga.YGNodeStyleSetMinWidth(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetMinWidthPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetMinWidthMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetMinWidthFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetMinWidthStretch(self.yg_node),
    }
}

pub fn setMinHeight(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => {},
        .point => |v| yoga.YGNodeStyleSetMinHeight(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetMinHeightPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetMinHeightMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetMinHeightFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetMinHeightStretch(self.yg_node),
    }
}

pub fn setMaxWidth(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => {},
        .point => |v| yoga.YGNodeStyleSetMaxWidth(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetMaxWidthPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetMaxWidthMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetMaxWidthFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetMaxWidthStretch(self.yg_node),
    }
}

pub fn setMaxHeight(self: Node, value: Style.StyleValue) void {
    switch (value) {
        .undefined => {},
        .auto => {},
        .point => |v| yoga.YGNodeStyleSetMaxHeight(self.yg_node, v),
        .percent => |v| yoga.YGNodeStyleSetMaxHeightPercent(self.yg_node, v),
        .max_content => yoga.YGNodeStyleSetMaxHeightMaxContent(self.yg_node),
        .fit_content => yoga.YGNodeStyleSetMaxHeightFitContent(self.yg_node),
        .stretch => yoga.YGNodeStyleSetMaxHeightStretch(self.yg_node),
    }
}

pub fn setAspectRatio(self: Node, aspect_ratio: f32) void {
    yoga.YGNodeStyleSetAspectRatio(self.yg_node, aspect_ratio);
}

pub fn setPosition(self: Node, edge: Style.Edge, value: Style.StyleValue) void {
    const e = @intFromEnum(edge);
    switch (value) {
        .undefined => {},
        .auto => yoga.YGNodeStyleSetPositionAuto(self.yg_node, e),
        .point => |v| yoga.YGNodeStyleSetPosition(self.yg_node, e, v),
        .percent => |v| yoga.YGNodeStyleSetPositionPercent(self.yg_node, e, v),
        else => {},
    }
}

pub fn setMargin(self: Node, edge: Style.Edge, value: Style.StyleValue) void {
    const e = @intFromEnum(edge);
    switch (value) {
        .undefined => {},
        .auto => yoga.YGNodeStyleSetMarginAuto(self.yg_node, e),
        .point => |v| yoga.YGNodeStyleSetMargin(self.yg_node, e, v),
        .percent => |v| yoga.YGNodeStyleSetMarginPercent(self.yg_node, e, v),
        else => {},
    }
}

pub fn setPadding(self: Node, edge: Style.Edge, value: Style.StyleValue) void {
    const e = @intFromEnum(edge);
    switch (value) {
        .undefined => {},
        .point => |v| yoga.YGNodeStyleSetPadding(self.yg_node, e, v),
        .percent => |v| yoga.YGNodeStyleSetPaddingPercent(self.yg_node, e, v),
        else => {},
    }
}

pub fn setBorder(self: Node, edge: Style.Edge, value: f32) void {
    yoga.YGNodeStyleSetBorder(self.yg_node, @intFromEnum(edge), value);
}

pub fn setGap(self: Node, gutter: Style.Gutter, value: Style.StyleValue) void {
    const g = @intFromEnum(gutter);
    switch (value) {
        .undefined => {},
        .point => |v| yoga.YGNodeStyleSetGap(self.yg_node, g, v),
        .percent => |v| yoga.YGNodeStyleSetGapPercent(self.yg_node, g, v),
        else => {},
    }
}
