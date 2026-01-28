const std = @import("std");
const vaxis = @import("vaxis");
const Element = @import("../element/mod.zig").Element;
const Style = @import("../element/mod.zig").Style;
const Buffer = @import("../Buffer.zig");
const worktree_mod = @import("mod.zig");
const Worktree = worktree_mod.Worktree;
const Entry = worktree_mod.Entry;
const Kind = worktree_mod.Kind;

const Allocator = std.mem.Allocator;
const gwidth = vaxis.gwidth.gwidth;
const HitGrid = @import("../HitGrid.zig");

pub const FileTree = @This();

element: Element,
worktree: *Worktree,
scroll_offset: usize = 0,

pub fn create(alloc: Allocator, wt: *Worktree) !*FileTree {
    const self = try alloc.create(FileTree);
    self.* = .{
        .element = Element.init(alloc, .{
            .id = "file-tree",
            .userdata = self,
            .drawFn = draw,
            .hitGridFn = hit,
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
            },
        }),
        .worktree = wt,
    };

    try self.element.addEventListener(.key_press, onKeyPress);
    try self.element.addEventListener(.wheel, onWheel);
    try self.element.addEventListener(.click, onClick);

    return self;
}

pub fn destroy(self: *FileTree, alloc: Allocator) void {
    self.element.deinit();
    alloc.destroy(self);
}

fn onKeyPress(element: *Element, data: Element.EventData) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));
    const key = data.key_press.key;

    if (key.matches('j', .{}) or key.matches(vaxis.Key.down, .{})) {
        self.scroll_offset += 1;
    } else if (key.matches('k', .{}) or key.matches(vaxis.Key.up, .{})) {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    }
}

fn onWheel(element: *Element, data: Element.EventData) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));
    const mouse = data.wheel.mouse;

    if (mouse.button == .wheel_up) {
        if (self.scroll_offset > 0) {
            self.scroll_offset -= 1;
        }
    } else if (mouse.button == .wheel_down) {
        self.scroll_offset += 1;
    }
}

fn onClick(element: *Element, _: Element.EventData) void {
    if (element.context) |ctx| {
        ctx.setFocus(element);
    }
}

fn hit(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(
        element.layout.left,
        element.layout.top,
        element.layout.width,
        element.layout.height,
        element.num,
    );
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *FileTree = @ptrCast(@alignCast(element.userdata));

    const x = element.layout.left;
    const y = element.layout.top;
    const height = element.layout.height;

    self.worktree.snapshot.mutex.lock();
    defer self.worktree.snapshot.mutex.unlock();

    var it = self.worktree.snapshot.entries.iter();
    var row: usize = 0;
    var skip: usize = self.scroll_offset;

    while (it.next()) |entry| {
        if (skip > 0) {
            skip -= 1;
            continue;
        }

        if (row >= height) break;

        const icon: []const u8 = switch (entry.value.kind) {
            .dir => ">",
            .file => " ",
        };

        var col: u16 = 0;
        const row_y = y + @as(u16, @intCast(row));

        col = writeText(buffer, x, row_y, icon, buffer.width);
        _ = writeText(buffer, x + col, row_y, entry.value.path, buffer.width);

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
        });
        col += w;
    }
    return col;
}
