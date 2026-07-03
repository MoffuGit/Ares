const std = @import("std");
const App = @import("app.zig");
const Context = App.Context;
const Entity = App.Entity;
const Project = @import("project.zig");
const heap = std.heap;

pub const Workspace = @This();

arena: heap.ArenaAllocator,
project: Entity(Project),

pub fn init(self: *Workspace, ctx: Context(Workspace)) !void {
    self.* = .{
        .arena = .init(ctx.gpa()),
        .project = try .new(ctx.app, .{self.arena.allocator()}),
    };
}

pub fn deinit(self: *Workspace) void {
    self.arena.deinit();
    self.project.drop();
}
