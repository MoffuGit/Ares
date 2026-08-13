const std = @import("std");
const heap = std.heap;
const Io = std.Io;
const Allocator = std.mem.Allocator;

const zqlite = @import("zqlite");

const App = @import("app.zig");
const Context = App.Context;
const ent = @import("entity.zig");
const Entity = ent.Entity;
const db = @import("db.zig");
const Project = @import("project.zig");
const uuid = @import("uuid.zig");
pub const persistence = @import("workspace/persistence.zig");
pub const SerializedWorkspace = persistence.SerializedWorkspace;

pub const Workspace = @This();

io: Io,
id: i64,
conn: zqlite.Conn,
session: uuid.Uuid,
arena: heap.ArenaAllocator,
project: Entity(Project),
paths: std.ArrayList([]u8),

pub fn init(
    self: *Workspace,
    ctx: Context(Workspace),
    paths: []const []const u8,
    session: uuid.Uuid,
    io: Io,
) !void {
    const conn = try db.acquire(io);
    errdefer db.release(io, conn);

    const gpa = ctx.gpa();

    self.* = .{
        .session = session,
        .id = undefined,
        .io = io,
        .conn = conn,
        .arena = .init(gpa),
        .paths = undefined,
        .project = undefined,
    };
    errdefer self.arena.deinit();

    self.paths = try .initCapacity(self.arena.allocator(), paths.len);

    for (paths) |path| {
        const copy = try self.arena.allocator().dupe(u8, path);
        self.paths.appendAssumeCapacity(copy);
    }

    self.project = try ctx.app.new(Project, Project.init, .{
        Project.Options{
            .arena = self.arena.allocator(),
            .paths = self.paths.items,
            .io = io,
        },
    });
    errdefer self.project.drop();

    self.id = if (try persistence.getByPaths(conn, gpa, self.paths.items)) |serialized| id: {
        defer serialized.deinit(gpa);
        break :id serialized.id;
    } else id: {
        const new_id = try persistence.insertDefault(conn);
        try persistence.setPaths(conn, new_id, self.paths.items, gpa);
        break :id new_id;
    };
}

pub fn markForRestoration(self: *const Workspace, gpa: Allocator) !void {
    try persistence.setSession(self.conn, self.id, self.session, gpa);
}

pub fn setBounds(self: *const Workspace, bounds: ?persistence.SerializedWindowBounds, left_dock: ?f64, right_dock: ?f64) !void {
    try persistence.setBounds(self.conn, self.id, bounds, left_dock, right_dock);
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
