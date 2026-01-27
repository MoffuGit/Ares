const std = @import("std");
const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const Buffer = @import("Buffer.zig");
const Window = @import("Window.zig");
const Element = @import("element/mod.zig").Element;
const Style = @import("element/mod.zig").Style;
const Layout = @import("element/mod.zig").Layout;

pub const Debug = @This();

pub fn dumpToFile(window: *Window, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    var buf: [4096]u8 = undefined;
    var file_writer = std.fs.File.Writer.init(file, &buf);
    const writer = &file_writer.interface;
    defer writer.flush() catch {};

    try writer.writeAll(("=" ** 80) ++ "\n");
    try writer.writeAll("ARES DEBUG DUMP\n");
    try writer.writeAll(("=" ** 80) ++ "\n\n");

    if (window.screen.current_buffer) |buffer| {
        try dumpScreenCells(writer, buffer);
    } else {
        try writer.writeAll("No current buffer available\n\n");
    }

    try writer.writeAll("\n");
    try writer.writeAll(("=" ** 80) ++ "\n");
    try writer.writeAll("ELEMENT TREE\n");
    try writer.writeAll(("=" ** 80) ++ "\n\n");

    try dumpElementTree(writer, window.root, 0);
}

fn dumpScreenCells(writer: anytype, buffer: *Buffer) !void {
    try writer.writeAll("SCREEN CELLS\n");
    try writer.writeAll(("-" ** 40) ++ "\n");
    try writer.print("Dimensions: {}x{}\n\n", .{ buffer.width, buffer.height });

    var row: u16 = 0;
    while (row < buffer.height) : (row += 1) {
        var col: u16 = 0;
        while (col < buffer.width) : (col += 1) {
            if (buffer.readCell(col, row)) |cell| {
                const char = cell.char.grapheme;
                if (char.len > 0) {
                    try writer.writeAll(char);
                } else {
                    try writer.writeByte(' ');
                }
            } else {
                try writer.writeByte(' ');
            }
        }
        try writer.writeByte('\n');
    }

    try writer.writeAll("\n--- Cell Details ---\n");
    row = 0;
    while (row < buffer.height) : (row += 1) {
        var col: u16 = 0;
        while (col < buffer.width) : (col += 1) {
            if (buffer.readCell(col, row)) |cell| {
                if (cell.char.grapheme.len > 0 and !isEmptyCell(cell)) {
                    try writer.print("[{},{}] char=\"{s}\" ", .{ col, row, cell.char.grapheme });
                    try dumpCellStyle(writer, cell.style);
                    try writer.writeByte('\n');
                }
            }
        }
    }
}

fn isEmptyCell(cell: Cell) bool {
    if (cell.char.grapheme.len == 0) return true;
    if (cell.char.grapheme.len == 1 and cell.char.grapheme[0] == ' ') {
        return cell.style.fg == .default and cell.style.bg == .default;
    }
    return false;
}

fn dumpCellStyle(writer: anytype, style: Cell.Style) !void {
    try writer.writeAll("style={");
    try writer.print("fg={}, bg={}", .{ style.fg, style.bg });
    if (style.bold) try writer.writeAll(", bold");
    if (style.italic) try writer.writeAll(", italic");
    if (style.ul_style != .off) try writer.print(", ul_style={}", .{style.ul_style});
    if (style.strikethrough) try writer.writeAll(", strikethrough");
    if (style.dim) try writer.writeAll(", dim");
    if (style.reverse) try writer.writeAll(", reverse");
    if (style.blink) try writer.writeAll(", blink");
    if (style.invisible) try writer.writeAll(", invisible");
    try writer.writeAll("}");
}

fn dumpElementTree(writer: anytype, element: *Element, depth: usize) !void {
    const indent = "  " ** 32;
    const prefix = indent[0 .. depth * 2];

    try writer.print("{s}Element: \"{s}\" (num={})\n", .{ prefix, element.id, element.num });
    try writer.print("{s}  State:\n", .{prefix});
    try writer.print("{s}    visible: {}\n", .{ prefix, element.visible });
    try writer.print("{s}    removed: {}\n", .{ prefix, element.removed });
    try writer.print("{s}    focused: {}\n", .{ prefix, element.focused });
    try writer.print("{s}    hovered: {}\n", .{ prefix, element.hovered });
    try writer.print("{s}    dragging: {}\n", .{ prefix, element.dragging });
    try writer.print("{s}    zIndex: {}\n", .{ prefix, element.zIndex });

    try writer.print("{s}  Layout:\n", .{prefix});
    try dumpLayout(writer, element.layout, prefix);

    try writer.print("{s}  Style:\n", .{prefix});
    try dumpStyle(writer, element.style, prefix);

    if (element.childrens) |childrens| {
        try writer.print("{s}  Children ({}):\n", .{ prefix, childrens.by_order.items.len });
        for (childrens.by_order.items) |child| {
            try dumpElementTree(writer, child, depth + 2);
        }
    }

    try writer.writeByte('\n');
}

fn dumpLayout(writer: anytype, layout: Layout, prefix: []const u8) !void {
    try writer.print("{s}    position: (left={}, top={}, right={}, bottom={})\n", .{
        prefix, layout.left, layout.top, layout.right, layout.bottom,
    });
    try writer.print("{s}    size: (width={}, height={})\n", .{
        prefix, layout.width, layout.height,
    });
    try writer.print("{s}    direction: {}\n", .{ prefix, layout.direction });
    try writer.print("{s}    had_overflow: {}\n", .{ prefix, layout.had_overflow });
    try writer.print("{s}    margin: (l={}, t={}, r={}, b={})\n", .{
        prefix,
        layout.margin.left,
        layout.margin.top,
        layout.margin.right,
        layout.margin.bottom,
    });
    try writer.print("{s}    border: (l={}, t={}, r={}, b={})\n", .{
        prefix,
        layout.border.left,
        layout.border.top,
        layout.border.right,
        layout.border.bottom,
    });
    try writer.print("{s}    padding: (l={}, t={}, r={}, b={})\n", .{
        prefix,
        layout.padding.left,
        layout.padding.top,
        layout.padding.right,
        layout.padding.bottom,
    });
}

fn dumpStyle(writer: anytype, style: Style, prefix: []const u8) !void {
    try writer.print("{s}    direction: {}\n", .{ prefix, style.direction });
    try writer.print("{s}    flex_direction: {}\n", .{ prefix, style.flex_direction });
    try writer.print("{s}    justify_content: {}\n", .{ prefix, style.justify_content });
    try writer.print("{s}    align_content: {}\n", .{ prefix, style.align_content });
    try writer.print("{s}    align_items: {}\n", .{ prefix, style.align_items });
    try writer.print("{s}    align_self: {}\n", .{ prefix, style.align_self });
    try writer.print("{s}    position_type: {}\n", .{ prefix, style.position_type });
    try writer.print("{s}    flex_wrap: {}\n", .{ prefix, style.flex_wrap });
    try writer.print("{s}    overflow: {}\n", .{ prefix, style.overflow });
    try writer.print("{s}    display: {}\n", .{ prefix, style.display });
    try writer.print("{s}    box_sizing: {}\n", .{ prefix, style.box_sizing });

    if (style.flex) |f| {
        try writer.print("{s}    flex: {d}\n", .{ prefix, f });
    }
    try writer.print("{s}    flex_grow: {d}\n", .{ prefix, style.flex_grow });
    try writer.print("{s}    flex_shrink: {d}\n", .{ prefix, style.flex_shrink });
    try writer.print("{s}    flex_basis: {}\n", .{ prefix, style.flex_basis });

    try writer.print("{s}    width: {}\n", .{ prefix, style.width });
    try writer.print("{s}    height: {}\n", .{ prefix, style.height });
    try writer.print("{s}    min_width: {}\n", .{ prefix, style.min_width });
    try writer.print("{s}    min_height: {}\n", .{ prefix, style.min_height });
    try writer.print("{s}    max_width: {}\n", .{ prefix, style.max_width });
    try writer.print("{s}    max_height: {}\n", .{ prefix, style.max_height });

    if (style.aspect_ratio) |ar| {
        try writer.print("{s}    aspect_ratio: {d}\n", .{ prefix, ar });
    }

    try dumpStyleEdges(writer, "position", style.position, prefix);
    try dumpStyleEdges(writer, "margin", style.margin, prefix);
    try dumpStyleEdges(writer, "padding", style.padding, prefix);
    try dumpStyleBorderEdges(writer, style.border, prefix);
    try dumpStyleGap(writer, style.gap, prefix);
}

fn dumpStyleEdges(writer: anytype, name: []const u8, edges: Style.Edges, prefix: []const u8) !void {
    var has_values = false;
    inline for (@typeInfo(Style.Edges).@"struct".fields) |field| {
        if (@field(edges, field.name) != .undefined) {
            has_values = true;
            break;
        }
    }

    if (has_values) {
        try writer.print("{s}    {s}: ", .{ prefix, name });
        inline for (@typeInfo(Style.Edges).@"struct".fields, 0..) |field, i| {
            const val = @field(edges, field.name);
            if (val != .undefined) {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("{s}={}", .{ field.name, val });
            }
        }
        try writer.writeByte('\n');
    }
}

fn dumpStyleBorderEdges(writer: anytype, edges: Style.BorderEdges, prefix: []const u8) !void {
    var has_values = false;
    inline for (@typeInfo(Style.BorderEdges).@"struct".fields) |field| {
        if (@field(edges, field.name) != null) {
            has_values = true;
            break;
        }
    }

    if (has_values) {
        try writer.print("{s}    border: ", .{prefix});
        var first = true;
        inline for (@typeInfo(Style.BorderEdges).@"struct".fields) |field| {
            if (@field(edges, field.name)) |val| {
                if (!first) try writer.writeAll(", ");
                first = false;
                try writer.print("{s}={d}", .{ field.name, val });
            }
        }
        try writer.writeByte('\n');
    }
}

fn dumpStyleGap(writer: anytype, gap: Style.Gap, prefix: []const u8) !void {
    var has_values = false;
    if (gap.column != .undefined or gap.row != .undefined or gap.all != .undefined) {
        has_values = true;
    }

    if (has_values) {
        try writer.print("{s}    gap: ", .{prefix});
        var first = true;
        if (gap.column != .undefined) {
            try writer.print("column={}", .{gap.column});
            first = false;
        }
        if (gap.row != .undefined) {
            if (!first) try writer.writeAll(", ");
            try writer.print("row={}", .{gap.row});
            first = false;
        }
        if (gap.all != .undefined) {
            if (!first) try writer.writeAll(", ");
            try writer.print("all={}", .{gap.all});
        }
        try writer.writeByte('\n');
    }
}
