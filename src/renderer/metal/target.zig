const objc = @import("objc");

const Metal = @import("../metal.zig");
const Handle = Metal.Handle;
const c = @import("c.zig");

pub const Target = @This();

drawable: objc.Object,
texture: objc.Object,
