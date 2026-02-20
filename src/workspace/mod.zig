const std = @import("std");
const lib = @import("../lib.zig");

const Context = @import("../app/mod.zig").Context;
const TopBar = @import("../components/TopBar.zig");
const BottomBar = @import("../components/BottomBar.zig");
const Dock = @import("../components/Dock.zig");
const FileTree = @import("../components/FileTree.zig");
const StyledTabs = @import("../components/styled/Tabs.zig");
const Tabs = StyledTabs.Tabs(.block);
const Element = lib.Element;
const Buffer = lib.Buffer;
const global = @import("../global.zig");
const Pane = @import("Pane.zig");
const EditorView = @import("views/EditorView.zig");
const Command = @import("../components/Command.zig");
const App = @import("../app/mod.zig");

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

tabs: *Tabs,
panes: std.ArrayList(*Pane) = .{},
active_pane: ?*Pane = null,

command: *Command,

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

    const command = try Command.create(alloc, ctx);
    errdefer command.destroy();

    element.* = Element.init(alloc, .{
        .id = "workspace",
        .userdata = workspace,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
            .flex_direction = .column,
        },
    });

    _ = try ctx.app.subscribe(.keymap_action, Workspace, workspace, onKeyAction);

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

    const tabs = try Tabs.create(alloc);

    try top_bar.element.elem().addChild(tabs.inner.list);
    try center.addChild(tabs.inner.container);

    try center_column.insertChild(top_dock.element, 0);
    try center_column.addChild(center);
    try center_column.addChild(bottom_dock.element);

    try center_wrapper.insertChild(left_dock.element, 0);
    try center_wrapper.addChild(center_column);
    try center_wrapper.addChild(right_dock.element);

    try element.addChild(top_bar.element.elem());
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
        .tabs = tabs,
        .file_tree = null,
        .command = command,
    };

    try workspace.registerCommandActions();

    return workspace;
}

fn registerCommandActions(self: *Workspace) !void {
    const owner: *anyopaque = @ptrCast(self);
    const Action = @import("../keymaps/mod.zig").Action;
    const entries = [_]struct { title: []const u8, action: Action }{
        .{ .title = "New Tab", .action = .{ .workspace = .new_tab } },
        .{ .title = "Close Tab", .action = .{ .workspace = .close_active_tab } },
        .{ .title = "Next Tab", .action = .{ .workspace = .next_tab } },
        .{ .title = "Previous Tab", .action = .{ .workspace = .prev_tab } },
        .{ .title = "Toggle Left Dock", .action = .{ .workspace = .toggle_left_dock } },
        .{ .title = "Toggle Right Dock", .action = .{ .workspace = .toggle_right_dock } },
    };
    for (entries) |entry| {
        _ = try self.command.register(
            owner,
            "Workspace",
            entry.title,
            .{ .dispatch = entry.action },
        );
    }
}

pub fn destroy(self: *Workspace) void {
    self.command.destroy();
    self.left_dock.destroy(self.alloc);
    self.right_dock.destroy(self.alloc);
    self.top_dock.destroy(self.alloc);
    self.bottom_dock.destroy(self.alloc);
    self.tabs.destroy();
    if (self.file_tree) |ft| ft.destroy(self.alloc);
    if (self.project) |project| {
        project.destroy(self.alloc);
    }
    for (self.panes.items) |pane| {
        pane.destroy();
    }
    self.panes.deinit(self.alloc);
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

    const editor = EditorView.create(self.alloc, self.project.?) catch return;
    const pane = Pane.create(self.alloc, self.project.?, .{ .editor = editor }) catch return;

    self.panes.append(self.alloc, pane) catch return;

    const tab = self.tabs.newTab(.{ .userdata = pane }) catch return;
    self.tabs.select(tab.id);

    tab.content.addChild(pane.element()) catch return;

    self.active_pane = pane;

    const ft = try FileTree.create(self.alloc, self.project.?, self, self.ctx);
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

pub fn closeActiveTab(self: *Workspace) void {
    if (self.tabs.inner.values.items.len == 1) return;
    const selected_id = self.tabs.inner.selected orelse return;
    const index = self.tabs.inner.indexOf(selected_id) orelse return;
    const tab = self.tabs.inner.values.items[index];

    const pane: ?*Pane = if (tab.userdata) |ud| @ptrCast(@alignCast(ud)) else null;
    if (pane) |p| p.element().remove();

    self.tabs.closeTab(selected_id);

    if (pane) |p| {
        for (self.panes.items, 0..) |item, i| {
            if (item == p) {
                _ = self.panes.orderedRemove(i);
                break;
            }
        }
        p.destroy();
    }

    self.syncActivePaneFromTab();
}

fn syncActivePaneFromTab(self: *Workspace) void {
    const selected_id = self.tabs.inner.selected orelse {
        self.active_pane = null;
        return;
    };
    const index = self.tabs.inner.indexOf(selected_id) orelse return;
    const tab = self.tabs.inner.values.items[index];
    if (tab.userdata) |ud| {
        const pane: *Pane = @ptrCast(@alignCast(ud));
        self.active_pane = pane;
        pane.select();
    }
}

/// Called by external components (e.g., FileTree) to notify the active pane
/// that an entry was selected.
pub fn setActiveEntry(self: *Workspace, entry_id: u64) void {
    if (self.active_pane) |pane| {
        pane.setEntry(entry_id);
    }
}

fn onKeyAction(self: *Workspace, data: App.EventData) void {
    const key_data = data.keymap_action;

    switch (key_data.action) {
        .workspace => |ws| switch (ws) {
            .close_active_tab => {
                self.closeActiveTab();
            },
            .new_tab => {
                if (self.project) |project| {
                    const editor = EditorView.create(self.alloc, project) catch return;
                    const pane = Pane.create(self.alloc, project, .{ .editor = editor }) catch return;

                    self.panes.append(self.alloc, pane) catch return;

                    const tab = self.tabs.newTab(.{ .userdata = pane }) catch return;
                    self.tabs.select(tab.id);

                    tab.content.addChild(pane.element()) catch return;

                    if (project.selected_entry) |id| {
                        pane.setEntry(id);
                    }

                    self.active_pane = pane;
                    pane.select();
                }
            },
            .next_tab => {
                self.tabs.next();
                self.syncActivePaneFromTab();
            },
            .prev_tab => {
                self.tabs.prev();
                self.syncActivePaneFromTab();
            },
            .toggle_left_dock => {
                self.toggleDock(.left);
            },
            .toggle_right_dock => {
                self.toggleDock(.right);
            },
            .toggle_command_palette => {
                self.command.toggleShow();
            },
            .enter_insert => {
                global.mode = .insert;
            },
            .enter_normal => {
                global.mode = .normal;
            },
            .enter_visual => {
                global.mode = .visual;
            },
        },
        else => {},
    }

    self.ctx.requestDraw();
}
