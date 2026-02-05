const std = @import("std");
const Context = @import("../app/mod.zig").Context;

pub const Project = @import("Project.zig");

pub const Workspace = @This();

alloc: std.mem.Allocator,
ctx: *Context,
project: ?*Project,

left_dock: void,
right_dock: void,
top_dock: void,
bottom_dock: void,
top_bar: void,
bottom_bar: void,
toasts: void,
center: void,

pub fn create(alloc: std.mem.Allocator, ctx: *Context) !*Workspace {
    const workspace = try alloc.create(Workspace);
    workspace.* = .{
        .alloc = alloc,
        .ctx = ctx,
        .project = null,
        .left_dock = {},
        .right_dock = {},
        .top_dock = {},
        .bottom_dock = {},
        .top_bar = {},
        .bottom_bar = {},
        .toasts = {},
    };
    return workspace;
}

pub fn destroy(self: *Workspace) void {
    if (self.project) |project| {
        project.destroy(self.alloc);
    }
    self.alloc.destroy(self);
}

pub fn openProject(self: *Workspace, abs_path: []const u8) !void {
    if (self.project) |project| {
        project.destroy(self.alloc);
    }
    self.project = try Project.create(self.alloc, abs_path, self.ctx);
}

pub fn closeProject(self: *Workspace) void {
    if (self.project) |project| {
        project.destroy(self.alloc);
        self.project = null;
    }
}
