const std = @import("std");
const Context = @import("../app/mod.zig").Context;
const TopBar = @import("../components/TopBar.zig");

pub const Project = @import("Project.zig");
pub const View = @import("View.zig");

pub const Workspace = @This();

alloc: std.mem.Allocator,
ctx: *Context,
project: ?*Project,
view: *View,
top_bar: *TopBar,

left_dock: void,
right_dock: void,
top_dock: void,
bottom_dock: void,
toasts: void,

pub fn create(alloc: std.mem.Allocator, ctx: *Context) !*Workspace {
    const workspace = try alloc.create(Workspace);
    errdefer alloc.destroy(workspace);

    const view = try View.create(alloc);
    errdefer view.destroy(alloc);

    const top_bar = try TopBar.create(alloc, workspace);
    errdefer top_bar.destroy(alloc);

    try view.addTopBar(top_bar.getElement());

    try ctx.app.root().addChild(view.root);

    workspace.* = .{
        .alloc = alloc,
        .ctx = ctx,
        .project = null,
        .view = view,
        .top_bar = top_bar,
        .left_dock = {},
        .right_dock = {},
        .top_dock = {},
        .bottom_dock = {},
        .toasts = {},
    };
    return workspace;
}

pub fn destroy(self: *Workspace) void {
    if (self.project) |project| {
        project.destroy(self.alloc);
    }
    self.top_bar.destroy(self.alloc);
    self.view.destroy(self.alloc);
    self.alloc.destroy(self);
}

pub fn getElement(self: *Workspace) *@import("../lib.zig").Element {
    return self.view.getElement();
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
