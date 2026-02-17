const std = @import("std");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Buffer = lib.Buffer;
const Element = lib.Element;
const Project = @import("../Project.zig");
const Scrollable = Element.Scrollable;
const Input = Element.Input;

const Allocator = std.mem.Allocator;

const Editor = @This();
const EditorElement = Element.TypedElement(Editor);

project: *Project,
entry: ?u64 = null,

element: EditorElement,

scroll: *Scrollable,
input: *Input,

pub fn create(alloc: Allocator, project: *Project) !*Editor {
    const self = try alloc.create(Editor);
    errdefer alloc.destroy(self);

    const scroll = try Scrollable.init(alloc, .{});
    errdefer scroll.deinit(alloc);

    const input = try Input.create(alloc, .{}, .{});
    errdefer input.destroy();

    self.* = .{
        .project = project,
        .scroll = scroll,
        .input = input,
        .element = EditorElement.init(
            alloc,
            self,
            .{},
            .{
                .style = .{
                    .width = .{ .percent = 100 },
                    .height = .{ .percent = 100 },
                    .padding = .{ .all = .{ .point = 1 } },
                },
            },
        ),
    };

    try self.element.childs(.{scroll.outer});
    try scroll.inner.addChild(input.element.elem());

    try project.ctx.app.subscribe(.bufferUpdated, Editor, self, bufferUpdated);
    return self;
}

pub fn bufferUpdated(self: *Editor, _: lib.App.EventData) void {
    self.project.ctx.requestDraw();
}

pub fn onEntry(self: *Editor, id: u64) void {
    self.entry = id;
}

pub fn draw(self: *Editor, element: *Element, buffer: *Buffer) void {
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

pub fn destroy(self: *Editor, alloc: Allocator) void {
    self.scroll.deinit(alloc);
    self.input.destroy();
    self.element.deinit();
    alloc.destroy(self);
}
