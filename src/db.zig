const std = @import("std");
const Allocator = std.mem.Allocator;

const zqlite = @import("zqlite");

const constanst = @import("contants.zig");
const DB_NAME = constanst.DB_NAME;
const global = @import("global.zig");
const os = @import("os.zig");

const WORKSPACE_SCHEMA = @embedFile("db/workspace.sql");

pub var pool: *zqlite.Pool = undefined;

fn onFirstConnection(conn: zqlite.Conn, _: ?*anyopaque) !void {
    try conn.execNoArgs(WORKSPACE_SCHEMA);
}

pub fn init(gpa: Allocator) !void {
    const path = os.appSupportPath(gpa, DB_NAME) catch |err| {
        std.log.err("error resolving db path: {}", .{err});
        return err;
    };
    defer gpa.free(path);

    try std.Io.Dir.cwd().createDirPath(global.state.threaded.io(), std.fs.path.dirname(path).?);

    const slice = try gpa.dupeSentinel(u8, path, 0);
    defer gpa.free(slice);

    std.log.debug("DB PATH={s}", .{slice});

    pool = try zqlite.Pool.init(gpa, .{
        .flags = zqlite.OpenFlags.Create |
            zqlite.OpenFlags.ReadWrite |
            zqlite.OpenFlags.EXResCode,
        .path = slice,
        .on_first_connection = &onFirstConnection,
    });
}

pub fn deinit() void {
    pool.deinit();
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
