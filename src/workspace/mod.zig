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
file_tree: ?*FileTree,

element: *Element,

center_wrapper: *Element,
center_column: *Element,
center: *Element,

top_bar: *TopBar,
bottom_bar: *BottomBar,

left_dock: *Dock,
right_dock: *Dock,
top_dock: *Dock,
bottom_dock: *Dock,

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

    center_wrapper.* = Element.init(alloc, .{ .id = "center-wrapper", .zIndex = 10, .style = .{
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

    const left_dock = try Dock.create(alloc, .left, 30, false);
    errdefer left_dock.destroy(alloc);

    const right_dock = try Dock.create(alloc, .right, 30, false);
    errdefer right_dock.destroy(alloc);

    const top_dock = try Dock.create(alloc, .top, 30, false);
    errdefer top_dock.destroy(alloc);

    const bottom_dock = try Dock.create(alloc, .bottom, 30, false);
    errdefer bottom_dock.destroy(alloc);

    try center_column.insertChild(top_dock.element, 0);
    try center_column.addChild(center);
    try center_column.addChild(bottom_dock.element);

    try center_wrapper.insertChild(left_dock.element, 0);
    try center_wrapper.addChild(center_column);
    try center_wrapper.addChild(right_dock.element);

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
        .left_dock = left_dock,
        .right_dock = right_dock,
        .top_dock = top_dock,
        .bottom_dock = bottom_dock,
        .file_tree = null,
    };

    return workspace;
}

pub fn destroy(self: *Workspace) void {
    self.left_dock.destroy(self.alloc);
    self.right_dock.destroy(self.alloc);
    self.top_dock.destroy(self.alloc);
    self.bottom_dock.destroy(self.alloc);
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

pub fn toggleDock(self: *Workspace, side: Dock.Side) void {
    self.getDock(side).toggleHidden();
}

pub fn getDock(self: *Workspace, side: Dock.Side) *Dock {
    return switch (side) {
        .left => self.left_dock,
        .right => self.right_dock,
        .top => self.top_dock,
        .bottom => self.bottom_dock,
    };
}

pub fn showDock(self: *Workspace, side: Dock.Side) *Dock {
    const dock = self.getDock(side);
    dock.element.show();
    return dock;
}

pub fn hideDock(self: *Workspace, side: Dock.Side) void {
    self.getDock(side).element.hide();
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
    const ft = try FileTree.create(self.alloc, self.project.?, self.ctx);
    self.file_tree = ft;
    try self.left_dock.element.addChild(ft.getElement());
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
        self.toggleDock(.left);
        key_data.ctx.stopPropagation();
        element.context.?.requestDraw();
    }

    if (key_data.key.matches('t', .{ .ctrl = true })) {
        key_data.ctx.stopPropagation();
        element.context.?.requestDraw();
    }

    if (key_data.key.matches('\t', .{ .shift = true })) {
        key_data.ctx.stopPropagation();
        element.context.?.requestDraw();
    } else if (key_data.key.matches('\t', .{})) {
        key_data.ctx.stopPropagation();
        element.context.?.requestDraw();
    }

    if (key_data.key.matches('q', .{ .ctrl = true })) {
        key_data.ctx.stopPropagation();
        element.context.?.requestDraw();
    }
}
