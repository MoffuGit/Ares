const objc = @import("objc");

const Metal = @import("../metal.zig");
const c = @import("c.zig");
const Frame = @import("frame.zig");

pub const Target = @This();

drawable: objc.Object,
texture: objc.Object,

pub fn complete(self: *Target, frame: *Frame) void {
    frame.buffer.msgSend(void, "presentDrawable:", .{self.drawable});
}
