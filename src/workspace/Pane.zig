const std = @import("std");
const lib = @import("../lib.zig");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;
const Buffer = lib.Buffer;
const Element = lib.Element;
const Project = @import("Project.zig");

const Pane = @This();

alloc: Allocator,
element: *Element,
entry: ?u64 = null,
project: *Project,

pub fn create(alloc: Allocator, project: *Project) !*Pane {
    const pane = try alloc.create(Pane);
    errdefer alloc.destroy(pane);

    const element = try alloc.create(Element);
    errdefer alloc.destroy(element);

    element.* = Element.init(alloc, .{
        .userdata = pane,
        .drawFn = draw,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
        },
    });

    pane.* = .{
        .element = element,
        .alloc = alloc,
        .project = project,
    };

    return pane;
}

pub fn draw(element: *Element, buffer: *Buffer) void {
    const self: *Pane = @ptrCast(@alignCast(element.userdata));

    if (self.entry) |id| {
        if (self.project.buffer_store.open(id)) |entry_buffer| {
            switch (entry_buffer.state) {
                .loading => {
                    _ = element.print(buffer, &.{.{ .text = "loading" }}, .{ .wrap = .none, .text_align = .center });
                },
                .ready => {
                    if (entry_buffer.bytes()) |bytes| {
                        _ = element.print(buffer, &.{.{ .text = bytes }}, .{});
                    }
                },
                else => {},
            }
        }
    }
}

pub fn setEntry(self: *Pane, entry: u64) void {
    self.entry = entry;
}

pub fn destroy(self: *Pane) void {
    self.element.deinit();
    self.alloc.destroy(self.element);
    self.alloc.destroy(self);
}
