const std = @import("std");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Buffer = lib.Buffer;
const Element = lib.Element;
const Project = @import("../Project.zig");
const Scrollable = Element.Scrollable;
const Input = Element.Input;

const Allocator = std.mem.Allocator;

const EditorView = @This();

project: *Project,
entry: ?u64 = null,
scroll: *Scrollable,
input: *Input,

pub fn create(alloc: Allocator, project: *Project) !*EditorView {
    const self = try alloc.create(EditorView);
    errdefer alloc.destroy(self);

    const scroll = try Scrollable.init(alloc, .{});
    errdefer scroll.deinit(alloc);

    const input = try Input.create(alloc, .{}, .{});
    errdefer input.destroy();

    self.* = .{
        .project = project,
        .scroll = scroll,
        .input = input,
    };

    try project.ctx.app.subscribe(.bufferUpdated, EditorView, self, bufferUpdated);
    return self;
}

pub fn bufferUpdated(self: *EditorView, _: lib.App.EventData) void {
    self.project.ctx.requestDraw();
}

pub fn onEntry(self: *EditorView, id: u64) void {
    self.entry = id;
}

pub fn draw(self: *EditorView, element: *Element, buffer: *Buffer) void {
    const theme = global.settings.theme;
    if (self.entry) |id| {
        if (self.project.buffer_store.open(id)) |entry_buffer| {
            switch (entry_buffer.state) {
                .loading => {
                    _ = element.print(buffer, &.{.{ .text = "loading" }}, .{ .wrap = .none, .text_align = .center });
                },
                .ready => {
                    if (entry_buffer.bytes()) |bytes| {
                        _ = element.print(buffer, &.{.{ .text = bytes, .style = .{ .bg = theme.mutedBg, .fg = theme.mutedFg } }}, .{});
                    }
                },
                else => {},
            }
        }
    }
}

pub fn destroy(self: *EditorView, alloc: Allocator) void {
    self.scroll.deinit(alloc);
    self.input.destroy();
    alloc.destroy(self);
}
