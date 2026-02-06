const std = @import("std");
const vaxis = @import("vaxis");
const global = @import("../global.zig");
const lib = @import("../lib.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const HitGrid = lib.HitGrid;
const Scrollable = @import("primitives/Scrollable.zig");
const Style = Element.Style;
const worktree_mod = @import("../worktree/mod.zig");
const Worktree = worktree_mod.Worktree;
const Entry = worktree_mod.Entry;
const Kind = worktree_mod.Kind;
const Context = @import("../app/mod.zig").Context;
const subspkg = @import("../app/subscriptions.zig");

const Allocator = std.mem.Allocator;
const gwidth = vaxis.gwidth.gwidth;

pub const FileTree = @This();

alloc: Allocator,
scrollable: *Scrollable,
content: *Element,
worktree: *Worktree,
initialized: bool = false,

expanded_entries: std.AutoHashMap(u64, void),
visible_entries: std.ArrayList(u64) = .{},

selected_entry: ?u64 = null,

pub fn create(alloc: Allocator, wt: *Worktree, ctx: *Context) !*FileTree {
    const self = try alloc.create(FileTree);

    const scrollable = try Scrollable.init(alloc, .{
        .outer = .{ .width = .{ .percent = 100 }, .height = .{ .percent = 100 } },
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
            .width = .{ .percent = 100 },
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
        .worktree = wt,
    };

    try ctx.subscribe(.worktreeUpdatedEntries, .{
        .userdata = self,
        .callback = onWorktreeUpdated,
    });

    try content.addEventListener(.click, onClick);

    return self;
}

pub fn hitFn(element: *Element, grid: *HitGrid) void {
    element.hitSelf(grid);
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
    const row_in_element = mouse.row -| element.layout.top;
    const index = @as(usize, @intCast(self.scrollable.scroll_y)) + row_in_element;
    if (index < self.visible_entries.items.len) {
        self.selected_entry = self.visible_entries.items[index];
    }
    element.context.?.requestDraw();
}

fn onWorktreeUpdated(userdata: ?*anyopaque, _: subspkg.EventData) void {
    const self: *FileTree = @ptrCast(@alignCast(userdata));
    if (self.initialized) return;
    self.initialized = true;

    self.worktree.snapshot.mutex.lock();
    defer self.worktree.snapshot.mutex.unlock();

    var it = self.worktree.snapshot.entries.iter();
    while (it.next()) |entry| {
        if (std.mem.count(u8, entry.key, "/") != 1) continue;
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

    element.fill(buffer, .{
        .style = .{
            .bg = global.settings.theme.bg,
            .fg = global.settings.theme.fg,
        },
    });

    const x = element.layout.left;
    const y = element.layout.top;
    const viewport_height = self.scrollable.outer.layout.height;

    const skip: usize = @intCast(self.scrollable.scroll_y);
    const max_visible: usize = @intCast(viewport_height);

    self.worktree.snapshot.mutex.lock();
    defer self.worktree.snapshot.mutex.unlock();

    const end = @min(skip + max_visible, self.visible_entries.items.len);
    for (self.visible_entries.items[skip..end], 0..) |id, row| {
        const path = self.worktree.snapshot.getPathById(id) orelse continue;
        const entry = self.worktree.snapshot.entries.get(path) catch continue;

        const is_selected = self.selected_entry != null and self.selected_entry.? == id;
        const bg: vaxis.Color = if (is_selected) .{ .rgb = .{ 255, 0, 0 } } else global.settings.theme.bg;

        const icon: []const u8 = switch (entry.kind) {
            .dir => ">",
            .file => " ",
        };

        const row_y = y + @as(u16, @intCast(row));
        const col = writeText(buffer, x, row_y, icon, buffer.width, bg);
        _ = writeText(buffer, x + col, row_y, path, buffer.width, bg);
    }
}

fn writeText(buffer: *Buffer, start_x: u16, y: u16, text: []const u8, max_width: u16, bg: vaxis.Color) u16 {
    var col: u16 = 0;
    var iter = vaxis.unicode.graphemeIterator(text);
    while (iter.next()) |grapheme| {
        const s = grapheme.bytes(text);
        const w = gwidth(s, .unicode);
        if (start_x + col + w > max_width) break;
        buffer.writeCell(start_x + col, y, .{
            .char = .{ .grapheme = s, .width = @intCast(w) },
            .style = .{
                .bg = bg,
                .fg = global.settings.theme.fg,
            },
        });
        col += w;
    }
    return col;
}
