const std = @import("std");
const vaxis = @import("vaxis");
const unicode = vaxis.unicode;
const gwidth = vaxis.gwidth.gwidth;
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const HitGrid = lib.HitGrid;
const Project = @import("../Project.zig");
const Scrollable = Element.Scrollable;
const Input = Element.Input;

const Allocator = std.mem.Allocator;

const Editor = @This();

project: *Project,
entry: ?u64 = null,

scroll: *Scrollable,
input: *Input,

pub fn create(alloc: Allocator, project: *Project) !*Editor {
    const self = try alloc.create(Editor);
    errdefer alloc.destroy(self);

    const theme = global.settings.theme;

    const scroll = try Scrollable.init(alloc, .{
        .outer = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
        },
        .thumb = theme.scrollThumb,
        .track = theme.scrollTrack,
    });
    errdefer scroll.deinit(alloc);

    const input = try Input.create(alloc, .{ .drawFn = drawInput, .updateFn = updateInput, .hitFn = hitInput }, .{
        .element = .{
            .style = .{
                .flex_shrink = 0,
                .width = .stretch,
            },
        },
        .multiline = true,
    });
    errdefer input.destroy();

    self.* = .{
        .project = project,
        .scroll = scroll,
        .input = input,
    };

    try scroll.inner.addChild(input.element.elem());

    try project.ctx.app.subscribe(.bufferUpdated, Editor, self, bufferUpdated);
    return self;
}

pub fn getElement(self: *Editor) *Element {
    return self.scroll.outer;
}

pub fn bufferUpdated(self: *Editor, _: lib.App.EventData) void {
    self.loadBuffer();
    self.project.ctx.requestDraw();
}

pub fn onEntry(self: *Editor, id: u64) void {
    self.entry = id;
    self.loadBuffer();
}

pub fn loadBuffer(self: *Editor) void {
    const id = self.entry orelse return;
    const entry_buffer = self.project.buffer_store.open(id) orelse return;
    if (entry_buffer.state != .ready) return;
    const bytes = entry_buffer.bytes() orelse return;

    self.input.buf.clearRetainingCapacity();
    self.input.buf.appendSliceBefore(bytes) catch return;
    self.input.buf.moveGap(0);
    self.input.cursor_col = 0;
    self.input.cursor_row = 0;
}

fn hitInput(_: *Input, element: *Element, grid: *HitGrid) void {
    const scroll: *Scrollable = @ptrCast(@alignCast(element.parent.?.parent.?.userdata));
    const layout = scroll.outer.layout;
    grid.fillRect(element.layout.left, element.layout.top, layout.width, layout.height, element.num);
}

fn updateInput(input: *Input, element: *Element) void {
    const line_count = countLines(input);
    const height: f32 = @floatFromInt(line_count);
    element.style.height = .{ .point = height };
    element.node.setHeight(.{ .point = height });
}

fn countLines(input: *Input) u16 {
    var lines: u16 = 1;
    for (input.buf.items) |c| {
        if (c == '\n') lines += 1;
    }
    for (input.buf.secondHalf()) |c| {
        if (c == '\n') lines += 1;
    }
    return lines;
}

fn drawInput(input: *Input, element: *Element, buffer: *Buffer) void {
    const scroll: *Scrollable = @ptrCast(@alignCast(element.parent.?.parent.?.userdata));
    const theme = global.settings.theme;
    const layout = element.layout;
    const width = layout.width;

    const span = scroll.visibleRowSpan(element);
    const outer_top = scroll.outer.layout.top;
    const print_base: u16 = outer_top -| layout.top;

    const before = input.buf.items;
    const after = input.buf.secondHalf();

    var row: u16 = 0;
    var col: u16 = 0;

    // Draw content before cursor
    var iter_before = unicode.graphemeIterator(before);
    while (iter_before.next()) |grapheme| {
        const s = grapheme.bytes(before);
        if (std.mem.eql(u8, s, "\n")) {
            row += 1;
            col = 0;
            continue;
        }
        const w: u16 = @intCast(gwidth(s, .unicode));
        if (row >= span.start and row < span.end and col + w <= width) {
            const vp_row = print_base + @as(u16, @intCast(row - span.start));
            buffer.setCell(layout.left + col, layout.top + vp_row, .{
                .char = .{ .grapheme = s, .width = @intCast(w) },
                .style = .{ .fg = theme.fg, .bg = theme.bg },
            });
        }
        col += w;
    }

    // Draw cursor
    const cursor_char = blk: {
        var it = unicode.graphemeIterator(after);
        if (it.next()) |g| {
            const s = g.bytes(after);
            if (!std.mem.eql(u8, s, "\n")) break :blk s;
        }
        break :blk " ";
    };
    const cursor_w: u16 = @intCast(@max(1, gwidth(cursor_char, .unicode)));
    if (row >= span.start and row < span.end and col + cursor_w <= width) {
        const vp_row = print_base + @as(u16, @intCast(row - span.start));
        buffer.setCell(layout.left + col, layout.top + vp_row, .{
            .char = .{ .grapheme = cursor_char, .width = @intCast(cursor_w) },
            .style = .{ .fg = theme.bg, .bg = theme.fg },
        });
    }

    // Advance past cursor character in after-buffer
    var iter_after = unicode.graphemeIterator(after);
    const skip_first = if (iter_after.next()) |g| !std.mem.eql(u8, g.bytes(after), "\n") else false;

    if (skip_first) {
        col += cursor_w;
    } else {
        // Cursor was on a newline or end of content, advance line
        if (after.len > 0 and after[0] == '\n') {
            row += 1;
            col = 0;
            // skip the newline in iter_after (already consumed by next() above)
        }
    }

    // Draw content after cursor
    while (iter_after.next()) |grapheme| {
        const s = grapheme.bytes(after);
        if (std.mem.eql(u8, s, "\n")) {
            row += 1;
            col = 0;
            continue;
        }
        const w: u16 = @intCast(gwidth(s, .unicode));
        if (row >= span.start and row < span.end and col + w <= width) {
            const vp_row = print_base + @as(u16, @intCast(row - span.start));
            buffer.setCell(layout.left + col, layout.top + vp_row, .{
                .char = .{ .grapheme = s, .width = @intCast(w) },
                .style = .{ .fg = theme.fg, .bg = theme.bg },
            });
        }
        col += w;
    }
}

pub fn destroy(self: *Editor, alloc: Allocator) void {
    self.input.destroy();
    self.scroll.deinit(alloc);
    alloc.destroy(self);
}
