const objc = @import("objc");

const Metal = @import("../metal.zig");
const c = @import("c.zig");
const Frame = @import("frame.zig");

pub const Target = @This();

drawable: objc.Object,
texture: objc.Object,
