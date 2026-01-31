const std = @import("std");
const vaxis = @import("vaxis");
const global = @import("../global.zig");

const elementpkg = @import("../element/mod.zig");
const Element = elementpkg.Element;
const Scrollable = elementpkg.Scrollable;
const Style = elementpkg.Style;
const Buffer = @import("../Buffer.zig");
const worktree_mod = @import("mod.zig");
const Worktree = worktree_mod.Worktree;
const Entry = worktree_mod.Entry;
const Kind = worktree_mod.Kind;

const Allocator = std.mem.Allocator;
const gwidth = vaxis.gwidth.gwidth;
const HitGrid = @import("../HitGrid.zig");

pub const FileTree = @This();

scrollable: *Scrollable,
content: *Element,
worktree: *Worktree,

pub fn create(alloc: Allocator, wt: *Worktree) !*FileTree {
    const self = try alloc.create(FileTree);

    const scrollable = try Scrollable.init(alloc, .{});

    const content = try alloc.create(Element);
    content.* = Element.init(alloc, .{
        .id = "file-tree-content",
        .userdata = self,
        .updateFn = onUpdate,
        .beforeDrawFn = draw,
        .style = .{
            .flex_shrink = 0,
            .width = .{ .percent = 100 },
        },
    });

    try scrollable.inner.addChild(content);

    self.* = .{
        .scrollable = scrollable,
        .content = content,
        .worktree = wt,
    };

    try scrollable.outer.addEventListener(.click, onClick);

    return self;
}

pub fn getElement(self: *FileTree) *Element {
    return self.scrollable.outer;
}

pub fn destroy(self: *FileTree, alloc: Allocator) void {
    self.content.deinit();
    alloc.destroy(self.content);
    self.scrollable.deinit(alloc);
    alloc.destroy(self);
}

fn onClick(element: *Element, _: Element.EventData) void {
    if (element.context) |ctx| {
        ctx.setFocus(element);
    }
}

fn onMouseEnter(element: *Element, _: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const file_tree: *FileTree = @ptrCast(@alignCast(self.userdata));
    file_tree.hovered = true;
    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}

fn onMouseLeave(element: *Element, _: Element.EventData) void {
    const self: *Scrollable = @ptrCast(@alignCast(element.userdata));
    const file_tree: *FileTree = @ptrCast(@alignCast(self.userdata));
    file_tree.hovered = false;
    if (element.context) |ctx| {
        ctx.requestDraw();
    }
}

fn onUpdate(element: *Element) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));

    var height: f32 = 0.0;

    {
        self.worktree.snapshot.mutex.lock();
        defer self.worktree.snapshot.mutex.unlock();

        var it = self.worktree.snapshot.entries.iter();

        while (it.next()) |_| {
            height += 1.0;
        }
    }

    element.style.height = .{ .point = height };
    element.node.setHeight(.{ .point = height });
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));

    const x = element.layout.left;
    const y = element.layout.top;
    const viewport_height = self.scrollable.outer.layout.height;

    const skip: usize = @intCast(self.scrollable.scroll_y);
    const max_visible: usize = @intCast(viewport_height);

    self.worktree.snapshot.mutex.lock();
    defer self.worktree.snapshot.mutex.unlock();

    var it = self.worktree.snapshot.entries.iter();
    var index: usize = 0;
    var row: usize = 0;

    while (it.next()) |entry| {
        if (index < skip) {
            index += 1;
            continue;
        }

        if (row >= max_visible) break;

        const icon: []const u8 = switch (entry.value.kind) {
            .dir => ">",
            .file => " ",
        };

        var col: u16 = 0;
        const row_y = y + @as(u16, @intCast(row));

        col = writeText(buffer, x, row_y, icon, buffer.width);
        _ = writeText(buffer, x + col, row_y, entry.value.path, buffer.width);

        index += 1;
        row += 1;
    }
}

fn writeText(buffer: *Buffer, start_x: u16, y: u16, text: []const u8, max_width: u16) u16 {
    var col: u16 = 0;
    var iter = vaxis.unicode.graphemeIterator(text);
    while (iter.next()) |grapheme| {
        const s = grapheme.bytes(text);
        const w = gwidth(s, .unicode);
        if (start_x + col + w > max_width) break;
        buffer.writeCell(start_x + col, y, .{
            .char = .{ .grapheme = s, .width = @intCast(w) },
            .style = .{
                .bg = global.settings.theme.bg,
                .fg = global.settings.theme.fg,
            },
        });
        col += w;
    }
    return col;
}
