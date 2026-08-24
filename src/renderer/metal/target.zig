const objc = @import("objc");
const c = @import("c.zig");

const Metal = @import("../metal.zig");
const Handler = Metal.Handler;
pub const Target = @This();

drawable: objc.Object,
texture: objc.Object,

pub fn init(self: *Target, handler: Handler) void {
    const drawable = handler.layer.msgSend(objc.Object, "nextDrawable", .{});
    const texture = drawable.msgSend(objc.Object, "texture", .{});

    self.* = .{ .drawable = drawable, .texture = texture };
}

pub fn present(self: *Target) void {
    self.drawable.msgSend(void, "present", .{});
}

pub fn deinit(self: *Target) void {
    self.drawable.release();
    self.texture.release();
}
