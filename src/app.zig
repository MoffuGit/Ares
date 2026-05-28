const std = @import("std");
const Allocator = std.mem.Allocator;
const Workspace = @import("workspace.zig");
const WorkspaceStore = std.ArrayList(*Workspace);

pub const App = @This();

workspaces: WorkspaceStore,

pub fn init(self: *App) !void {
    self.* = .{
        .workspaces = .empty,
    };
}

pub fn add_workspace(self: *App, workspace: *Workspace, gpa: Allocator) !void {
    try self.workspaces.append(gpa, workspace);
}

pub fn remove_workspace(self: *App, workspace: *Workspace) void {
    for (0..self.workspaces.items.len) |idx| {
        if (self.workspaces.items[idx] == workspace) {
            _ = self.workspaces.orderedRemove(idx);
            return;
        }
    }
}

pub fn deinit(self: *App, gpa: Allocator) void {
    self.workspaces.deinit(gpa);
}
