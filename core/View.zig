const std = @import("std");
const Allocator = std.mem.Allocator;
// const Editor = @import("editor/Editor.zig");
const View = @This();

pub const Kind = enum(u8) {
    editor = 0,
    terminal = 1,
};

// pub const CoreView = union(Kind) {
//     editor: Editor,
// };

alloc: Allocator,
// coreView: CoreView,

pub fn create(alloc: Allocator, kind: Kind, layer_ptr: *anyopaque) !*View {
    _ = layer_ptr;
    _ = kind;
    const view = try alloc.create(View);
    errdefer alloc.destroy(view);

    view.* = .{
        .alloc = alloc,
        // .coreView = switch (kind) {
        //     .editor => .{ .editor = Editor },
        // },
    };

    return view;
}

pub fn resize(self: *View, width: u32, height: u32) void {
    _ = self;
    _ = width;
    _ = height;
    // self.gpu.resize(width, height);
}

pub fn destroy(self: *View) void {
    // switch (self.renderer) {
    //     inline else => |*r| r.deinit(),
    // }
    // self.gpu.destroy();
    self.alloc.destroy(self);
}
