const std = @import("std");
const lib = @import("../lib.zig");

const Context = @import("../app/mod.zig").Context;
const TopBar = @import("../components/TopBar.zig");
const BottomBar = @import("../components/BottomBar.zig");
const Dock = @import("../components/Dock.zig");
const FileTree = @import("../components/FileTree.zig");
const Element = lib.Element;
const Buffer = lib.Buffer;
const global = @import("../global.zig");

pub const Project = @import("Project.zig");

pub const Workspace = @This();

alloc: std.mem.Allocator,
ctx: *Context,
project: ?*Project,

element: *Element,

center_wrapper: *Element,
center_column: *Element,
center: *Element,

top_bar: *TopBar,
bottom_bar: *BottomBar,

left_dock: ?*Dock,
right_dock: ?*Dock,
top_dock: ?*Dock,
bottom_dock: ?*Dock,

file_tree: ?*FileTree,

pub fn create(alloc: std.mem.Allocator, ctx: *Context) !*Workspace {
    const workspace = try alloc.create(Workspace);
    errdefer alloc.destroy(workspace);

    const element = try alloc.create(Element);
    errdefer alloc.destroy(element);

    const center_wrapper = try alloc.create(Element);
    errdefer alloc.destroy(center_wrapper);

    const center_column = try alloc.create(Element);
    errdefer alloc.destroy(center_column);

    const center = try alloc.create(Element);
    errdefer alloc.destroy(center);

    element.* = Element.init(alloc, .{
        .id = "workspace",
        .userdata = workspace,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
            .flex_direction = .column,
        },
    });

    try element.addEventListener(.key_press, onKeyPress);

    center_wrapper.* = Element.init(alloc, .{ .id = "center-wrapper", .style = .{
        .flex_grow = 1,
        .flex_direction = .row,
    }, .drawFn = (struct {
        pub fn draw(_element: *Element, buffer: *Buffer) void {
            const theme = global.settings.theme;
            _element.fill(buffer, .{
                .style = .{
                    .bg = theme.mutedBg,
                },
            });
        }
    }.draw) });

    center_column.* = Element.init(alloc, .{
        .id = "center-column",
        .style = .{
            .flex_grow = 1,
            .flex_direction = .column,
        },
    });

    center.* = Element.init(alloc, .{
        .id = "center",
        .style = .{
            .flex_grow = 1,
        },
    });

    const top_bar = try TopBar.create(alloc, workspace);
    errdefer top_bar.destroy(alloc);

    const bottom_bar = try BottomBar.create(alloc, workspace);
    errdefer bottom_bar.destroy(alloc);

    try center_column.addChild(center);
    try center_wrapper.addChild(center_column);

    try element.addChild(top_bar.element);
    try element.addChild(center_wrapper);
    try element.addChild(bottom_bar.element);

    try ctx.app.root().addChild(element);

    ctx.app.window.setFocus(element);

    workspace.* = .{
        .alloc = alloc,
        .ctx = ctx,
        .project = null,
        .center_wrapper = center_wrapper,
        .center_column = center_column,
        .center = center,
        .element = element,
        .top_bar = top_bar,
        .bottom_bar = bottom_bar,
        .left_dock = null,
        .right_dock = null,
        .top_dock = null,
        .bottom_dock = null,
        .file_tree = null,
    };
    return workspace;
}

pub fn destroy(self: *Workspace) void {
    if (self.left_dock) |dock| dock.destroy(self.alloc);
    if (self.right_dock) |dock| dock.destroy(self.alloc);
    if (self.top_dock) |dock| dock.destroy(self.alloc);
    if (self.bottom_dock) |dock| dock.destroy(self.alloc);
    if (self.file_tree) |ft| ft.destroy(self.alloc);
    if (self.project) |project| {
        project.destroy(self.alloc);
    }
    self.center.deinit();
    self.center_column.deinit();
    self.center_wrapper.deinit();
    self.element.deinit();
    self.alloc.destroy(self.center);
    self.alloc.destroy(self.center_column);
    self.alloc.destroy(self.center_wrapper);
    self.alloc.destroy(self.element);
    self.bottom_bar.destroy(self.alloc);
    self.top_bar.destroy(self.alloc);
    self.alloc.destroy(self);
}

pub fn toggleDock(self: *Workspace, side: Dock.Side) !void {
    const dock_ptr = switch (side) {
        .left => &self.left_dock,
        .right => &self.right_dock,
        .top => &self.top_dock,
        .bottom => &self.bottom_dock,
    };

    if (dock_ptr.*) |dock| {
        if (dock.element.removed) {
            try self.addDockToTree(side, dock);
        } else {
            dock.hide();
        }
    } else {
        const dock = try Dock.create(self.alloc, side, 30);
        dock_ptr.* = dock;
        try self.addDockToTree(side, dock);
    }
}

fn addDockToTree(self: *Workspace, side: Dock.Side, dock: *Dock) !void {
    switch (side) {
        .left => {
            if (self.file_tree) |ft| {
                const ft_elem = ft.getElement();
                if (ft_elem.parent != dock.element) {
                    try dock.element.addChild(ft_elem);
                }
            }
            try self.center_wrapper.insertChild(dock.element, 0);
        },
        .right => try self.center_wrapper.addChild(dock.element),
        .top => try self.center_column.insertChild(dock.element, 0),
        .bottom => try self.center_column.addChild(dock.element),
    }
}

pub fn showDock(self: *Workspace, side: Dock.Side) !*Dock {
    const dock_ptr = switch (side) {
        .left => &self.left_dock,
        .right => &self.right_dock,
        .top => &self.top_dock,
        .bottom => &self.bottom_dock,
    };

    if (dock_ptr.*) |dock| return dock;

    const dock = try Dock.create(self.alloc, side, 30);
    dock_ptr.* = dock;

    switch (side) {
        .left => try self.center_wrapper.insertChild(dock.element, 0),
        .right => try self.center_wrapper.addChild(dock.element),
        .top => try self.center_column.insertChild(dock.element, 0),
        .bottom => try self.center_column.addChild(dock.element),
    }

    return dock;
}

pub fn hideDock(self: *Workspace, side: Dock.Side) void {
    const dock_ptr = switch (side) {
        .left => &self.left_dock,
        .right => &self.right_dock,
        .top => &self.top_dock,
        .bottom => &self.bottom_dock,
    };

    if (dock_ptr.*) |dock| {
        dock.destroy(self.alloc);
        dock_ptr.* = null;
    }
}

pub fn openProject(self: *Workspace, abs_path: []const u8) !void {
    if (self.project) |project| {
        if (self.file_tree) |ft| {
            ft.destroy(self.alloc);
            self.file_tree = null;
        }
        project.destroy(self.alloc);
    }
    self.project = try Project.create(self.alloc, abs_path, self.ctx);
    self.file_tree = try FileTree.create(self.alloc, self.project.?.worktree, self.ctx);
}

pub fn closeProject(self: *Workspace) void {
    if (self.project) |project| {
        if (self.file_tree) |ft| {
            ft.destroy(self.alloc);
            self.file_tree = null;
        }
        project.destroy(self.alloc);
        self.project = null;
    }
}

fn onKeyPress(element: *Element, data: Element.EventData) void {
    const self: *Workspace = @ptrCast(@alignCast(element.userdata));
    const key_data = data.key_press;

    if (key_data.key.matches('l', .{ .super = true })) {
        self.toggleDock(.left) catch {};
        key_data.ctx.stopPropagation();
        element.context.?.requestDraw();
    }
}
