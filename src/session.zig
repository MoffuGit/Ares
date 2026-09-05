const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;

const zqlite = @import("zqlite");

const Core = @import("core.zig");
const database = @import("database.zig");
const KVS = database.KVS;
const uuid = @import("uuid.zig");
const ent = @import("entity.zig");
const AnyEntity = ent.AnyEntity;

const log = std.log.scoped(.session);

const SESSION_KEY = "session_id";

pub const Session = @This();

id: uuid.Uuid,
any: AnyEntity,
old_id: ?uuid.Uuid,

pub fn init(
    self: *Session,
    any: AnyEntity,
    _: *Core,
    alloc: Allocator,
    conn: *const zqlite.Conn,
    io: Io,
) !void {
    const old = bkl: {
        if (KVS.read(conn, alloc, SESSION_KEY) catch
            break :bkl null) |buffer|
        {
            defer alloc.free(buffer);
            break :bkl uuid.parse(buffer);
        } else break :bkl null;
    };

    const new = uuid.new_v4(io);

    const new_value = try uuid.fmt(new, alloc);
    defer alloc.free(new_value);

    try KVS.write(conn, SESSION_KEY, new_value);

    self.* = .{
        .any = any,
        .id = new,
        .old_id = old,
    };

    log.debug("Current Session: {}\nOld Session: {?}", .{ self.id, self.old_id });
}

pub fn drop(self: *Session) void {
    self.any.drop();
}

test "Session init stores current id and reads previous id" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    var test_pool = try database.testingPool(allocator);
    defer test_pool.deinit();

    const conn = try test_pool.acquire(io);
    defer conn.release(io);

    var first: Session = undefined;
    try first.init(undefined, undefined, allocator, &conn, io);
    try testing.expect(first.old_id == null);

    const stored_first = (try KVS.read(&conn, allocator, SESSION_KEY)).?;
    defer allocator.free(stored_first);
    try testing.expectEqual(first.id, uuid.parse(stored_first));
    var second: Session = undefined;
    try second.init(undefined, undefined, allocator, &conn, io);
    try testing.expectEqual(first.id, second.old_id.?);
    try testing.expect(second.id != second.old_id.?);

    const stored_second = (try KVS.read(&conn, allocator, SESSION_KEY)).?;
    defer allocator.free(stored_second);
    try testing.expectEqual(second.id, uuid.parse(stored_second));
}

test "Session created after drop uses previous session id as old id" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    var test_pool = try database.testingPool(allocator);
    defer test_pool.deinit();

    const conn = try test_pool.acquire(io);
    defer conn.release(io);

    var first: Session = undefined;
    try first.init(undefined, undefined, allocator, &conn, io);
    const first_id = first.id;
    first = undefined;

    var second: Session = undefined;
    try second.init(undefined, undefined, allocator, &conn, io);

    try testing.expectEqual(first_id, second.old_id.?);
    try testing.expect(second.id != first_id);
}
