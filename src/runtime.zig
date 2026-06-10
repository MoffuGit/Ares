const std = @import("std");
const zio = @import("zio");
const Allocator = std.mem.Allocator;

pub const Runtime = @This();

foreground: *zio.Runtime,
background: *zio.Runtime,

pub fn init(self: *Runtime, gpa: Allocator) !void {
    const foreground = try zio.Runtime.init(gpa, .{
        .executors = .auto,
        .enable_main_executor = false,
    });
    errdefer foreground.deinit();

    const background = try zio.Runtime.init(gpa, .{
        .executors = .exact(1),
        .enable_main_executor = true,
        .enable_task_migration = false,
    });
    errdefer background.deinit();

    self.* = .{
        .foreground = foreground,
        .background = background,
    };
}

pub fn deinit(self: *Runtime) void {
    self.background.deinit();
    self.foreground.deinit();
}
