const std = @import("std");
const Allocator = std.mem.Allocator;
const zqlite = @import("zqlite");
const os = @import("os.zig");
const constanst = @import("contants.zig");
const global = @import("global.zig");
const DB_NAME = constanst.DB_NAME;
const schema_sql = @embedFile("persistence/schema.sql");

pub var pool: *zqlite.Pool = undefined;

fn onFirstConnection(conn: zqlite.Conn, _: ?*anyopaque) !void {
    try conn.execNoArgs(schema_sql);
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
