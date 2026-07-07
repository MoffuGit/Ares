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
gpa: Allocator,
conn: zqlite.Conn,
arena: heap.ArenaAllocator,
project: Entity(Project),
paths: std.ArrayList([]u8),
id: i64,

pub fn init(
    self: *Workspace,
    ctx: Context(Workspace),
    options: Options,
    io: Io,
) !void {
    const conn = try db.acquire(io);
    errdefer db.release(io, conn);

    self.* = .{
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

    self.id = if (try Workspace.persistence.getByPaths(conn, self.gpa, self.paths.items)) |serialized| id: {
        defer serialized.deinit(self.gpa);
        break :id serialized.id;
    } else id: {
        const new_id = try Workspace.persistence.insertDefault(conn);
        try Workspace.persistence.insert(conn, self.gpa, .{ .id = new_id, .paths = self.paths.items });
        break :id new_id;
    };
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
