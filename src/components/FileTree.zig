const std = @import("std");
const vaxis = @import("vaxis");
const global = @import("../global.zig");
const lib = @import("../lib.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const HitGrid = lib.HitGrid;
const Project = @import("../workspace/Project.zig");
const Scrollable = Element.Scrollable;
const Style = Element.Style;
const worktreepkg = @import("../worktree/mod.zig");
const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;
const Kind = worktreepkg.Kind;
const Context = @import("../app/mod.zig").Context;
const subspkg = @import("../app/subscriptions.zig");

const Allocator = std.mem.Allocator;
const gwidth = vaxis.gwidth.gwidth;

pub const FileTree = @This();

alloc: Allocator,
scrollable: *Scrollable,
content: *Element,
project: *Project,

expanded_entries: std.AutoHashMap(u64, void),
visible_entries: std.ArrayList(u64) = .{},

pub fn create(alloc: Allocator, project: *Project, ctx: *Context) !*FileTree {
    const self = try alloc.create(FileTree);
    const theme = global.settings.theme;

    const scrollable = try Scrollable.init(alloc, .{
        .outer = .{ .width = .{ .percent = 100 }, .height = .{ .percent = 100 } },
        .thumb = theme.scrollThumb,
        .track = theme.scrollTrack,
    });

    const content = try alloc.create(Element);
    content.* = Element.init(alloc, .{
        .id = "file-tree-content",
        .userdata = self,
        .updateFn = onUpdate,
        .beforeDrawFn = draw,
        .hitFn = hitFn,
        .style = .{
            .flex_shrink = 0,
            .width = .stretch,
            .margin = .{
                .horizontal = .{ .point = 1 },
            },
        },
    });

    try scrollable.inner.addChild(content);

    var map = std.AutoHashMap(u64, void).init(alloc);
    errdefer map.deinit();

    self.* = .{
        .alloc = alloc,
        .expanded_entries = map,
        .scrollable = scrollable,
        .content = content,
        .project = project,
    };

    try ctx.subscribe(.worktreeUpdatedEntries, .{
        .userdata = self,
        .callback = onWorktreeUpdated,
    });

    try content.addEventListener(.click, onClick);

    return self;
}

pub fn hitFn(element: *Element, grid: *HitGrid) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));
    const layout = self.scrollable.outer.layout;
    grid.fillRect(element.layout.left, element.layout.top, layout.width, layout.height, element.num);
}

pub fn getElement(self: *FileTree) *Element {
    return self.scrollable.outer;
}

pub fn destroy(self: *FileTree, alloc: Allocator) void {
    self.expanded_entries.deinit();
    self.visible_entries.deinit(alloc);
    self.content.deinit();
    alloc.destroy(self.content);
    self.scrollable.deinit(alloc);
    alloc.destroy(self);
}

fn onClick(element: *Element, data: Element.EventData) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));
    const mouse = data.click.mouse;
    const index = self.scrollable.childRowFromScreenY(element, mouse.row) orelse return;
    if (index < self.visible_entries.items.len) {
        const id = self.visible_entries.items[index];

        const is_dir = blk: {
            self.project.worktree.snapshot.mutex.lock();
            defer self.project.worktree.snapshot.mutex.unlock();
            const path = self.project.worktree.snapshot.getPathById(id) orelse break :blk false;
            const entry = self.project.worktree.snapshot.entries.get(path) catch break :blk false;
            break :blk entry.kind == .dir;
        };

        if (is_dir) {
            if (self.expanded_entries.contains(id)) {
                _ = self.expanded_entries.remove(id);
            } else {
                self.expanded_entries.put(id, {}) catch {};
            }
            self.rebuildVisibleEntries();
        } else {
            self.project.selected_entry = id;
        }
    }
    element.context.?.requestDraw();
}

fn onWorktreeUpdated(userdata: ?*anyopaque, _: subspkg.EventData) void {
    const self: *FileTree = @ptrCast(@alignCast(userdata));

    var it = self.project.worktree.snapshot.entries.iter();

    if (it.next()) |root| {
        if (root.value.kind == .dir) {
            self.expanded_entries.put(root.value.id, {}) catch {};
        }
    }

    self.rebuildVisibleEntries();
    if (self.content.context) |ctx| {
        ctx.requestDraw();
    }
}

fn rebuildVisibleEntries(self: *FileTree) void {
    self.visible_entries.clearRetainingCapacity();

    self.project.worktree.snapshot.mutex.lock();
    defer self.project.worktree.snapshot.mutex.unlock();

    var it = self.project.worktree.snapshot.entries.iter();
    while (it.next()) |entry| {
        if (std.mem.indexOfScalar(u8, entry.key, '/') != null) continue;

        self.visible_entries.append(self.alloc, entry.value.id) catch continue;

        if (entry.value.kind == .dir and self.expanded_entries.contains(entry.value.id)) {
            self.appendDirectChildren(entry.key);
        }
    }
}

fn appendDirectChildren(self: *FileTree, dir_path: []const u8) void {
    var prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/", .{dir_path}) catch return;

    // dirs first
    var dir_it = self.project.worktree.snapshot.entries.rangeFrom(prefix);
    while (dir_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.key, prefix)) break;
        const rest = entry.key[prefix.len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) continue;
        if (entry.value.kind != .dir) continue;
        self.visible_entries.append(self.alloc, entry.value.id) catch continue;

        if (self.expanded_entries.contains(entry.value.id)) {
            self.appendDirectChildren(entry.key);
        }
    }

    // then files
    var file_it = self.project.worktree.snapshot.entries.rangeFrom(prefix);
    while (file_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.key, prefix)) break;
        const rest = entry.key[prefix.len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) continue;
        if (entry.value.kind != .file) continue;
        self.visible_entries.append(self.alloc, entry.value.id) catch continue;
    }
}

fn onUpdate(element: *Element) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));
    const height: f32 = @floatFromInt(self.visible_entries.items.len);
    element.style.height = .{ .point = height };
    element.node.setHeight(.{ .point = height });
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));

    const span = self.scrollable.visibleRowSpan(element);
    const outer_top = self.scrollable.outer.layout.top;
    const print_base: u16 = outer_top -| element.layout.top;

    self.project.worktree.snapshot.mutex.lock();
    defer self.project.worktree.snapshot.mutex.unlock();

    const all = self.visible_entries.items;
    const end = @min(span.end, all.len);
    for (span.start..end) |abs_i| {
        const id = all[abs_i];
        const path = self.project.worktree.snapshot.getPathById(id) orelse continue;
        const entry = self.project.worktree.snapshot.entries.get(path) catch continue;
        const vp_row: u16 = @intCast(abs_i - span.start);
        const print_row = print_base + vp_row;

        const is_selected = self.project.selected_entry != null and self.project.selected_entry.? == id;

        const icon: []const u8 = switch (entry.kind) {
            .dir => if (self.expanded_entries.contains(entry.id)) " " else "󰉋 ",
            .file => " ",
        };

        if (is_selected) {
            const screen_y = element.layout.top + print_row;
            buffer.fillRect(self.scrollable.outer.layout.left, screen_y, element.layout.width, 1, .{ .style = .{ .bg = global.settings.theme.mutedBg } });
        }

        const display_name = if (std.mem.lastIndexOfScalar(u8, path, '/')) |sep| path[sep + 1 ..] else path;
        const depth: u16 = @intCast(std.mem.count(u8, path, "/"));

        const guide_fg = global.settings.theme.fg.setAlpha(0.27);
        const guide_style: vaxis.Cell.Style = .{ .fg = guide_fg, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } };
        var d: u16 = 0;
        while (d < depth) : (d += 1) {
            const guide = "│";
            _ = element.print(
                buffer,
                &.{.{ .text = guide, .style = guide_style }},
                .{ .row_offset = print_row, .col_offset = d * 2 },
            );
        }

        const indent: u16 = depth * 2;
        _ = element.print(
            buffer,
            &.{
                .{
                    .text = icon,
                    .style = .{ .fg = global.settings.theme.fg, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } },
                },
                .{
                    .text = display_name,
                    .style = .{ .fg = global.settings.theme.fg, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } },
                },
            },
            .{ .row_offset = print_row, .col_offset = indent, .wrap = .none },
        );
    }
}
