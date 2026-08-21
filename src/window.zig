const std = @import("std");
const builtin = @import("builtin");

const rgfw = @import("rgfw");

pub const Window = if (builtin.is_test) TestWindow else rgfw.Window;

const TestWindow = struct {
    pub fn init(self: *@This(), name: [:0]const u8, x: i32, y: i32, w: i32, h: i32, flags: rgfw.Window.Flags) !void {
        _ = self;
        _ = name;
        _ = x;
        _ = y;
        _ = w;
        _ = h;
        _ = flags;
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};
