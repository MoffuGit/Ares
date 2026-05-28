const std = @import("std");
const Allocator = std.mem.Allocator;

const Project = @import("project.zig");

pub const Workspace = @This();

project: Project,

pub fn init(self: *Workspace) !void {
    self.* = .{
        .project = undefined,
    };

    try self.project.init();
}

pub fn deinit(self: *Workspace, gpa: Allocator) void {
    self.project.deinit(gpa);
}
