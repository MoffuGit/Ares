const std = @import("std");
const heap = std.heap;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zqlite = @import("zqlite");

const App = @import("app.zig");
const Context = App.Context;
const Entity = App.Entity;
const db = @import("db.zig");
const Project = @import("project.zig");
const uuid = @import("uuid.zig");
pub const persistence = @import("workspace/persistence.zig");
pub const SerializedWorkspace = persistence.SerializedWorkspace;

pub const Workspace = @This();

pub const Options = struct {
    paths: []const []const u8,
    session: uuid.Uuid,
};

io: Io,
id: i64,
gpa: Allocator,
conn: zqlite.Conn,
session: uuid.Uuid,
arena: heap.ArenaAllocator,
project: Entity(Project),
paths: std.ArrayList([]u8),

pub fn init(
    self: *Workspace,
    ctx: Context(Workspace),
    options: Options,
    io: Io,
) !void {
    const conn = try db.acquire(io);
    errdefer db.release(io, conn);

    self.* = .{
        .session = options.session,
        .id = undefined,
        .io = io,
        .gpa = ctx.gpa(),
        .conn = conn,
        .arena = .init(ctx.gpa()),
        .paths = undefined,
        .project = try .new(ctx.app, .{self.arena.allocator()}),
    };
    errdefer self.arena.deinit();

    self.paths = try .initCapacity(self.arena.allocator(), options.paths.len);

    for (options.paths) |path| {
        const copy = try self.arena.allocator().dupe(u8, path);
        self.paths.appendAssumeCapacity(copy);
    }

    self.id = if (try persistence.getByPaths(conn, self.gpa, self.paths.items)) |serialized| id: {
        defer serialized.deinit(self.gpa);
        break :id serialized.id;
    } else id: {
        const new_id = try persistence.insertDefault(conn);
        try persistence.setPaths(conn, new_id, self.paths.items, self.gpa);
        break :id new_id;
    };
}

pub fn markForRestoration(self: *Workspace) !void {
    try persistence.setSession(self.conn, self.id, self.session, self.gpa);
}

pub fn drop(self: *Workspace) void {
    self.project.drop();
}

pub fn deinit(self: *Workspace) void {
    db.release(self.io, self.conn);
    self.arena.deinit();
}

test {
    _ = persistence;
}
