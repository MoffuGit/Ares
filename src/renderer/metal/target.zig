const objc = @import("objc");

const Metal = @import("../metal.zig");
const c = @import("c.zig");
const Frame = @import("frame.zig");

pub const Target = @This();

drawable: objc.Object,
texture: objc.Object,

pub fn init(layer: objc.Object) Target {
    const drawable = layer.msgSend(objc.Object, "nextDrawable", .{});
    const texture = drawable.msgSend(objc.Object, "texture", .{});

    return .{ .drawable = drawable, .texture = texture };
}
