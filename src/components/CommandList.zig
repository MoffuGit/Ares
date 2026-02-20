const std = @import("std");
const vaxis = @import("vaxis");
const unicode = vaxis.unicode;
const gwidth = vaxis.gwidth.gwidth;
const global = @import("../global.zig");
const lib = @import("../lib.zig");
const CommandEntry = @import("Command.zig").CommandEntry;
const CommandId = @import("Command.zig").CommandId;

const Element = lib.Element;
const Box = Element.Box;
const Buffer = lib.Buffer;
const Allocator = std.mem.Allocator;

const CommandList = @This();

alloc: Allocator,
container: *Box,
list_element: *Element.Element,

entries: []const CommandEntry = &.{},
selected: usize = 0,
scroll: usize = 0,

pub fn create(alloc: Allocator) !*CommandList {
    const self = try alloc.create(CommandList);
    errdefer alloc.destroy(self);

    const container = try Box.init(alloc, .{
        .style = .{
            .width = .{ .percent = 100 },
            .flex_grow = 1,
        },
    });
    errdefer container.deinit(alloc);

    const list_element = try alloc.create(Element.Element);
    errdefer alloc.destroy(list_element);

    list_element.* = Element.Element.init(alloc, .{
        .id = "command-list",
        .userdata = self,
        .drawFn = drawList,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
            .border = .{ .top = 1 },
        },
    });

    try container.element.childs(.{list_element});

    self.* = .{
        .alloc = alloc,
        .container = container,
        .list_element = list_element,
    };

    return self;
}

pub fn setEntries(self: *CommandList, entries: []const CommandEntry) void {
    self.entries = entries;
    self.selected = 0;
    self.scroll = 0;
}

pub fn moveSelection(self: *CommandList, delta: i32) void {
    if (self.entries.len == 0) return;
    const len: i32 = @intCast(self.entries.len);
    var new: i32 = @as(i32, @intCast(self.selected)) + delta;
    if (new < 0) new = 0;
    if (new >= len) new = len - 1;
    self.selected = @intCast(new);
}

pub fn scrollPage(self: *CommandList, direction: i32) void {
    const visible: i32 = @intCast(self.list_element.layout.height -| self.list_element.layout.border.top);
    const half = @max(1, @divTrunc(visible, 2));
    self.moveSelection(half * direction);
}

pub fn moveToTop(self: *CommandList) void {
    self.selected = 0;
    self.scroll = 0;
}

pub fn moveToBottom(self: *CommandList) void {
    if (self.entries.len == 0) return;
    self.selected = self.entries.len - 1;
}

pub fn selectedId(self: *CommandList) ?CommandId {
    if (self.entries.len == 0) return null;
    return self.entries[self.selected].id;
}

fn drawList(element: *Element.Element, buffer: *Buffer) void {
    const self: *CommandList = @ptrCast(@alignCast(element.userdata orelse return));
    const layout = element.layout;
    const theme = global.settings.theme;

    element.fill(buffer, .{ .style = .{ .bg = theme.bg } });

    // Draw top border separator
    {
        var bx: u16 = 0;
        while (bx < layout.width) : (bx += 1) {
            buffer.writeCell(layout.left + bx, layout.top, .{
                .char = .{ .grapheme = "▁", .width = 1 },
                .style = .{ .fg = theme.border, .bg = theme.bg },
            });
        }
    }

    if (self.entries.len == 0) return;

    const content_top = layout.top + layout.border.top;
    const content_width = layout.width;
    const content_height = layout.height -| layout.border.top;

    if (content_height == 0) return;

    const visible_rows: usize = @intCast(content_height);

    // Adjust scroll so selected is visible
    if (self.selected < self.scroll) {
        self.scroll = self.selected;
    } else if (self.selected >= self.scroll + visible_rows) {
        self.scroll = self.selected - visible_rows + 1;
    }

    var row: usize = 0;
    while (row < visible_rows) : (row += 1) {
        const idx = self.scroll + row;
        if (idx >= self.entries.len) break;

        const entry = self.entries[idx];
        const y: u16 = content_top + @as(u16, @intCast(row));
        const is_selected = idx == self.selected;

        const row_bg = if (is_selected) theme.mutedBg else theme.bg;
        const row_fg = theme.fg;

        // Fill row background
        buffer.fillRect(layout.left, y, content_width, 1, .{
            .style = .{ .bg = row_bg },
        });

        var col: u16 = 1;

        // Draw title
        var title_iter = unicode.graphemeIterator(entry.title);
        while (title_iter.next()) |grapheme| {
            const s = grapheme.bytes(entry.title);
            const w: u16 = @intCast(gwidth(s, .unicode));
            if (col + w > content_width) break;
            buffer.writeCell(layout.left + col, y, .{
                .char = .{ .grapheme = s, .width = @intCast(w) },
                .style = .{ .fg = row_fg, .bg = row_bg },
            });
            col += w;
        }

        // Draw owner name (muted)
        col += 1;
        var owner_iter = unicode.graphemeIterator(entry.owner_name);
        while (owner_iter.next()) |grapheme| {
            const s = grapheme.bytes(entry.owner_name);
            const w: u16 = @intCast(gwidth(s, .unicode));
            if (col + w > content_width) break;
            buffer.writeCell(layout.left + col, y, .{
                .char = .{ .grapheme = s, .width = @intCast(w) },
                .style = .{ .fg = theme.border, .bg = row_bg },
            });
            col += w;
        }

        // Draw binding right-aligned
        if (entry.binding) |binding| {
            const bind_len = blk: {
                var len: u16 = 0;
                var bind_iter = unicode.graphemeIterator(binding);
                while (bind_iter.next()) |grapheme| {
                    const s = grapheme.bytes(binding);
                    len += @intCast(gwidth(s, .unicode));
                }
                break :blk len;
            };

            const bind_start = if (content_width > bind_len + 1) content_width - bind_len - 1 else 0;
            var bcol = bind_start;
            var bind_draw_iter = unicode.graphemeIterator(binding);
            while (bind_draw_iter.next()) |grapheme| {
                const s = grapheme.bytes(binding);
                const w: u16 = @intCast(gwidth(s, .unicode));
                if (bcol + w > content_width) break;
                buffer.writeCell(layout.left + bcol, y, .{
                    .char = .{ .grapheme = s, .width = @intCast(w) },
                    .style = .{ .fg = theme.border, .bg = row_bg },
                });
                bcol += w;
            }
        }
    }
}

pub fn destroy(self: *CommandList) void {
    self.list_element.deinit();
    self.alloc.destroy(self.list_element);
    self.container.deinit(self.alloc);
    self.alloc.destroy(self);
}
