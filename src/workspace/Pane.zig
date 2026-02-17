const std = @import("std");
const lib = @import("../lib.zig");

const Allocator = std.mem.Allocator;
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

    pub fn element(self: View) *Element {
        switch (self) {
            .editor => |v| return v.getElement(),
        }
    }

    pub fn destroy(self: View, alloc: Allocator) void {
        switch (self) {
            .editor => |v| v.destroy(alloc),
        }
    }
};

alloc: Allocator,
entry: ?u64 = null,
project: *Project,
view: View,

pub fn create(alloc: Allocator, project: *Project, view: View) !*Pane {
    const pane = try alloc.create(Pane);

    pane.* = .{
        .alloc = alloc,
        .project = project,
        .view = view,
    };

    return pane;
}

pub fn element(self: *Pane) *Element {
    return self.view.element();
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
    self.alloc.destroy(self);
}
