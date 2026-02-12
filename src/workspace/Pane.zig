const std = @import("std");
const lib = @import("../lib.zig");
const vaxis = @import("vaxis");

const Allocator = std.mem.Allocator;
const Buffer = lib.Buffer;
const Element = lib.Element;
const Project = @import("Project.zig");
const EditorView = @import("views/EditorView.zig");

const Pane = @This();

pub const View = union(enum) {
    editor: *EditorView,

    pub fn onEntry(self: View, id: u64) void {
        switch (self) {
            .editor => |v| v.onEntry(id),
        }
    }

    pub fn draw(self: View, element: *Element, buffer: *Buffer) void {
        switch (self) {
            .editor => |v| v.draw(element, buffer),
        }
    }

    pub fn destroy(self: View, alloc: Allocator) void {
        switch (self) {
            .editor => |v| v.destroy(alloc),
        }
    }
};

alloc: Allocator,
element: *Element,
entry: ?u64 = null,
project: *Project,
view: View,

pub fn create(alloc: Allocator, project: *Project, view: View) !*Pane {
    const pane = try alloc.create(Pane);
    errdefer alloc.destroy(pane);

    const element = try alloc.create(Element);
    errdefer alloc.destroy(element);

    element.* = Element.init(alloc, .{
        .userdata = pane,
        .drawFn = drawFn,
        .style = .{
            .width = .{ .percent = 100 },
            .height = .{ .percent = 100 },
        },
    });

    pane.* = .{
        .element = element,
        .alloc = alloc,
        .project = project,
        .view = view,
    };

    return pane;
}

fn drawFn(element: *Element, buffer: *Buffer) void {
    const self: *Pane = @ptrCast(@alignCast(element.userdata));
    self.view.draw(element, buffer);
}

pub fn setEntry(self: *Pane, entry: u64) void {
    self.entry = entry;
    self.view.onEntry(entry);
}

/// Called when this pane becomes the active/selected pane.
/// Syncs the pane's current entry back to the project.
pub fn select(self: *Pane) void {
    self.project.selected_entry = self.entry;
}

pub fn destroy(self: *Pane) void {
    self.view.destroy(self.alloc);
    self.element.deinit();
    self.alloc.destroy(self.element);
    self.alloc.destroy(self);
}
