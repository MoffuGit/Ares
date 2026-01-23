pub const yoga = @import("yoga");

const Node = @This();

var config: yoga.YGConfigRef = null;

yg_node: yoga.YGNodeRef,
index: usize,

fn getConfig() yoga.YGConfigRef {
    if (config == null) {
        config = yoga.YGConfigNew();
        yoga.YGConfigSetPointScaleFactor(config, 1.0);
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

pub fn insertChild(self: Node, child: Node) void {
    const count = yoga.YGNodeGetChildCount(self.yg_node);
    yoga.YGNodeInsertChild(self.yg_node, child.yg_node, count);
}

pub fn removeChild(self: Node, child: Node) void {
    yoga.YGNodeRemoveChild(self.yg_node, child.yg_node);
}
