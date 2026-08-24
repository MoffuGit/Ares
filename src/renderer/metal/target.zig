const objc = @import("objc");
const c = @import("c.zig");

pub const Target = @This();

drawable: objc.Object,

pub fn init(layer: objc.Object) !Target {
    const drawable = layer.msgSend(objc.Object, "nextDrawable", .{});

    return .{ .drawable = drawable };
}

pub fn deinit(self: *Target) void {
    self.drawable.release();
}
