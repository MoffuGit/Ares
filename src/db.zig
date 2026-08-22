const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const zqlite = @import("zqlite");

const constanst = @import("constants.zig");
const DB_NAME = constanst.DB_NAME;
const global = @import("global.zig");

const log = std.log.scoped(.database);

const WORKSPACE_SCHEMA = @embedFile("db/workspace.sql");
const KEY_VALUE_STORE = @embedFile("db/key_value_store.sql");

pub var pool: *zqlite.Pool = undefined;

fn onFirstConnection(_conn: zqlite.Conn, _: ?*anyopaque) !void {
    try _conn.execNoArgs(KEY_VALUE_STORE);
    try _conn.execNoArgs(WORKSPACE_SCHEMA);
}

pub fn init(_: Allocator) !void {
    unreachable;
}

pub fn deinit() void {
    pool.deinit();
}

pub fn acquire(io: Io) !zqlite.Conn {
    return try pool.acquire(io);
}

pub fn release(io: Io, conn: zqlite.Conn) void {
    pool.release(io, conn);
}

pub fn testingPool(allocator: Allocator) !*zqlite.Pool {
    return try zqlite.Pool.init(allocator, .{
        .size = 1,
        .flags = zqlite.OpenFlags.Create |
            zqlite.OpenFlags.ReadWrite |
            zqlite.OpenFlags.EXResCode,
        .path = ":memory:",
        .on_first_connection = &onFirstConnection,
    });
}

pub const KVS = struct {
    pub fn read(conn: *const zqlite.Conn, allocator: Allocator, key: []const u8) !?[]const u8 {
        const row = (try conn.row(
            \\SELECT value
            \\FROM key_value_store
            \\WHERE key = ?
        , .{key})) orelse return null;
        defer row.deinit();

        const value = row.text(0);
        return try allocator.dupe(u8, value);
    }

    pub fn write(conn: *const zqlite.Conn, key: []const u8, value: []const u8) !void {
        try conn.exec(
            \\INSERT INTO key_value_store (key, value)
            \\VALUES (?, ?)
            \\ON CONFLICT(key) DO UPDATE SET
            \\    value = excluded.value
        , .{ key, value });
    }

    pub fn delete(conn: *const zqlite.Conn, key: []const u8) !void {
        try conn.exec(
            \\DELETE FROM key_value_store
            \\WHERE key = ?
        , .{key});
    }
};

test "KVS read write and delete" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    var test_pool = try testingPool(allocator);
    defer test_pool.deinit();

    const conn = try test_pool.acquire(io);
    defer conn.release(io);

    try KVS.write(&conn, "theme", "dark");
    const first = (try KVS.read(&conn, allocator, "theme")).?;
    defer allocator.free(first);
    try testing.expectEqualStrings("dark", first);

    try KVS.write(&conn, "theme", "light");
    const updated = (try KVS.read(&conn, allocator, "theme")).?;
    defer allocator.free(updated);
    try testing.expectEqualStrings("light", updated);

    try KVS.delete(&conn, "theme");
    try testing.expect(try KVS.read(&conn, allocator, "theme") == null);
}
