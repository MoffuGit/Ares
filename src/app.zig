const std = @import("std");
const zio = @import("zio");

const Allocator = std.mem.Allocator;
const Workspace = @import("workspace.zig");
const WorkspaceStore = std.ArrayList(*Workspace);
const Runtime = zio.Runtime;

pub const App = @This();

foreground_runtime: *Runtime,
background_runtime: *Runtime,

pub fn init(self: *App, gpa: Allocator) !void {
    const foreground_runtime = try Runtime.init(gpa, .{
        .executors = .auto,
        .enable_main_executor = false,
    });
    errdefer foreground_runtime.deinit();

    const background_runtime = try Runtime.init(gpa, .{
        .executors = .exact(1),
        .enable_main_executor = true,
        .enable_task_migration = false,
    });
    errdefer background_runtime.deinit();

    self.* = .{
        .foreground_runtime = undefined,
        .background_runtime = undefined,
    };
}

pub fn deinit(self: *App, gpa: Allocator) void {
    self.background_runtime.deinit();
    self.foreground_runtime.deinit();
    _ = gpa;
}
