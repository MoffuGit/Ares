const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const Io = std.Io;

const zqlite = @import("zqlite");

const database = @import("../database.zig");
const global = @import("../global.zig");
const uuid = @import("../uuid.zig");

pub const SerializedWindowBounds = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const SerializedWorkspace = struct {
    paths: []const []const u8,
    session: ?uuid.Uuid = null,
    window: ?SerializedWindowBounds = null,
    left_dock: ?f64 = null,
    right_dock: ?f64 = null,
    timestamp: i64 = 0,
    id: i64,

    pub fn deinit(self: SerializedWorkspace, allocator: Allocator) void {
        for (self.paths) |path| allocator.free(path);
        allocator.free(self.paths);
    }
};

const PATH_DELIMITER: u8 = ',';

fn serializePaths(allocator: Allocator, paths: []const []const u8) ![]u8 {
    if (paths.len == 0) return try allocator.alloc(u8, 0);

    var len: usize = 0;
    for (paths) |path| len += path.len + 1;
    len -= 1;

    const buffer = try allocator.alloc(u8, len);
    len = 0;
    for (paths, 0..) |path, i| {
        if (i > 0) {
            buffer[len] = PATH_DELIMITER;
            len += 1;
        }
        @memcpy(buffer[len .. len + path.len], path);
        len += path.len;
    }

    return buffer;
}

pub fn insertDefault(conn: zqlite.Conn) !i64 {
    const row = (try conn.row(
        \\INSERT INTO workspace DEFAULT VALUES
        \\RETURNING id
    , .{})) orelse return error.MissingInsertedWorkspaceId;
    defer row.deinit();

    return row.int(0);
}

pub fn setPaths(conn: zqlite.Conn, id: i64, paths: []const []const u8, allocator: Allocator) !void {
    const buffer = try serializePaths(allocator, paths);
    defer allocator.free(buffer);

    try conn.exec(
        \\UPDATE workspace
        \\SET
        \\  paths = ?,
        \\  timestamp = unixepoch()
        \\WHERE id = ?
    , .{
        buffer,
        id,
    });
}

pub fn insert(conn: zqlite.Conn, allocator: Allocator, workspace: SerializedWorkspace) !void {
    const buffer = try serializePaths(allocator, workspace.paths);
    defer allocator.free(buffer);

    const session = if (workspace.session) |id| try std.fmt.allocPrint(allocator, "{}", .{id}) else null;
    defer if (session) |text| allocator.free(text);

    const bounds = workspace.window;
    try conn.exec(
        \\INSERT INTO workspace (id, paths, session, window_x, window_y, window_width, window_height, left_dock, right_dock, timestamp)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, unixepoch())
        \\ON CONFLICT(id) DO UPDATE SET
        \\    paths = excluded.paths,
        \\    session = excluded.session,
        \\    window_x = excluded.window_x,
        \\    window_y = excluded.window_y,
        \\    window_width = excluded.window_width,
        \\    window_height = excluded.window_height,
        \\    left_dock = excluded.left_dock,
        \\    right_dock = excluded.right_dock,
        \\    timestamp = unixepoch()
    , .{
        workspace.id,
        buffer,
        session,
        if (bounds) |b| b.x else null,
        if (bounds) |b| b.y else null,
        if (bounds) |b| b.width else null,
        if (bounds) |b| b.height else null,
        if (workspace.left_dock) |dock| dock else null,
        if (workspace.right_dock) |dock| dock else null,
    });
}

pub fn setBounds(conn: zqlite.Conn, id: i64, bounds: ?SerializedWindowBounds, left_dock: ?f64, right_dock: ?f64) !void {
    try conn.exec(
        \\UPDATE workspace
        \\SET
        \\  window_x = ?,
        \\  window_y = ?,
        \\  window_width = ?,
        \\  window_height = ?,
        \\  left_dock = ?,
        \\  right_dock = ?,
        \\  timestamp = unixepoch()
        \\WHERE id = ?
    , .{
        if (bounds) |b| b.x else null,
        if (bounds) |b| b.y else null,
        if (bounds) |b| b.width else null,
        if (bounds) |b| b.height else null,
        if (left_dock) |dock| dock else null,
        if (right_dock) |dock| dock else null,
        id,
    });
}

pub fn setSession(conn: zqlite.Conn, id: i64, session: uuid.Uuid, allocator: Allocator) !void {
    const fmt = try uuid.fmt(session, allocator);
    defer allocator.free(fmt);

    try conn.exec(
        \\UPDATE workspace
        \\SET
        \\  session = ?,
        \\  timestamp = unixepoch()
        \\WHERE id = ?
    , .{
        fmt,
        id,
    });
}

pub fn get(conn: zqlite.Conn, allocator: Allocator, id: i64) !?SerializedWorkspace {
    const row = (try conn.row(
        \\SELECT id, paths, session, window_x, window_y, window_width, window_height, left_dock, right_dock, timestamp
        \\FROM workspace
        \\WHERE id = ?
    , .{id})) orelse return null;
    defer row.deinit();

    return try deserialize(allocator, row);
}

pub fn getByPaths(conn: zqlite.Conn, allocator: Allocator, paths: []const []const u8) !?SerializedWorkspace {
    const paths_text = try serializePaths(allocator, paths);
    defer allocator.free(paths_text);

    const row = (try conn.row(
        \\SELECT id, paths, session, window_x, window_y, window_width, window_height, left_dock, right_dock, timestamp
        \\FROM workspace
        \\WHERE paths = ?
    , .{paths_text})) orelse return null;
    defer row.deinit();

    return try deserialize(allocator, row);
}

pub fn deleteById(conn: zqlite.Conn, id: i64) !void {
    try conn.exec(
        \\DELETE FROM workspace
        \\WHERE id = ?
    , .{id});
}

pub fn getBySession(conn: zqlite.Conn, allocator: Allocator, session: uuid.Uuid) ![]SerializedWorkspace {
    const buffer = try uuid.fmt(session, allocator);
    defer allocator.free(buffer);

    var rows = try conn.rows(
        \\SELECT id, paths, session, window_x, window_y, window_width, window_height, left_dock, right_dock, timestamp
        \\FROM workspace
        \\WHERE session = ?
    , .{buffer});
    defer rows.deinit();

    var workspaces: std.ArrayList(SerializedWorkspace) = .empty;
    errdefer {
        for (workspaces.items) |workspace| workspace.deinit(allocator);
        workspaces.deinit(allocator);
    }

    while (rows.next()) |row| {
        try workspaces.append(allocator, try deserialize(allocator, row));
    }
    if (rows.err) |err| return err;

    return try workspaces.toOwnedSlice(allocator);
}

pub fn getAllMetadata(conn: zqlite.Conn, allocator: Allocator) ![]SerializedWorkspace {
    var rows = try conn.rows(
        \\SELECT id, paths, session, window_x, window_y, window_width, window_height, left_dock, right_dock, timestamp
        \\FROM workspace
    , .{});
    defer rows.deinit();

    var workspaces: std.ArrayList(SerializedWorkspace) = .empty;
    errdefer {
        for (workspaces.items) |workspace| workspace.deinit(allocator);
        workspaces.deinit(allocator);
    }

    while (rows.next()) |row| {
        const serialized = try deserialize(allocator, row);

        try workspaces.append(allocator, serialized);
    }
    if (rows.err) |err| return err;

    return try workspaces.toOwnedSlice(allocator);
}

fn workspaceExists(workspace: SerializedWorkspace, io: Io) bool {
    for (workspace.paths) |path| {
        std.Io.Dir.access(.cwd(), io, path, .{}) catch return false;
    }

    return true;
}

pub fn getAllMetadataAndValidate(conn: zqlite.Conn, allocator: Allocator, io: Io) ![]SerializedWorkspace {
    const workspaces = try getAllMetadata(conn, allocator);
    errdefer {
        for (workspaces) |workspace| workspace.deinit(allocator);
        allocator.free(workspaces);
    }

    var valid_count: usize = 0;
    for (workspaces) |workspace| {
        if (workspaceExists(workspace, io)) {
            if (valid_count != 0) workspaces[valid_count] = workspace;
            valid_count += 1;
        } else {
            try deleteById(conn, workspace.id);
            workspace.deinit(allocator);
        }
    }

    return try allocator.realloc(workspaces, valid_count);
}

fn deserialize(allocator: Allocator, row: zqlite.Row) !SerializedWorkspace {
    const paths_text = row.text(1);
    const session = if (row.nullableText(2)) |text| uuid.parse(text) else null;

    const path_count: usize = if (paths_text.len == 0) 0 else mem.count(u8, paths_text, &.{PATH_DELIMITER}) + 1;
    const paths = try allocator.alloc([]const u8, path_count);
    var path_index: usize = 0;
    errdefer {
        for (paths[0..path_index]) |path| allocator.free(path);
        allocator.free(paths);
    }

    var iter = mem.splitScalar(u8, paths_text, PATH_DELIMITER);
    while (iter.next()) |path| : (path_index += 1) {
        if (path_count == 0) break;
        paths[path_index] = try allocator.dupe(u8, path);
    }

    const window_bounds = if (row.nullableFloat(3)) |x| SerializedWindowBounds{
        .x = x,
        .y = row.float(4),
        .width = row.float(5),
        .height = row.float(6),
    } else null;

    const left_dock = row.nullableFloat(7);
    const right_dock = row.nullableFloat(8);

    return .{
        .id = row.int(0),
        .paths = paths,
        .session = session,
        .window = window_bounds,
        .left_dock = left_dock,
        .right_dock = right_dock,
        .timestamp = row.int(9),
    };
}

test "basic operation" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try database.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    try insert(conn, alloc, .{
        .id = 42,
        .paths = &.{ "/tmp/project", "/Users/me/workspace" },
        .window = .{ .x = 1, .y = 2, .width = 800, .height = 600 },
        .left_dock = 56,
        .right_dock = 78,
    });

    const workspace = (try get(conn, alloc, 42)).?;
    defer workspace.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), workspace.paths.len);
    try std.testing.expectEqualStrings("/tmp/project", workspace.paths[0]);
    try std.testing.expectEqualStrings("/Users/me/workspace", workspace.paths[1]);
    try std.testing.expect(workspace.session == null);
    try std.testing.expect(workspace.window != null);
    try std.testing.expectEqual(@as(f64, 1), workspace.window.?.x);
    try std.testing.expectEqual(@as(f64, 56), workspace.left_dock);
    try std.testing.expectEqual(@as(f64, 78), workspace.right_dock);
    try std.testing.expect(workspace.timestamp > 0);

    try setBounds(conn, 42, .{ .x = 78, .y = 67, .width = 80, .height = 60 }, 89, 10);

    const updated = (try get(conn, alloc, 42)).?;
    defer updated.deinit(alloc);

    try std.testing.expectEqual(SerializedWindowBounds{ .height = 60, .width = 80, .x = 78, .y = 67 }, updated.window);
    try std.testing.expectEqual(@as(f64, 89), updated.left_dock);
    try std.testing.expectEqual(@as(f64, 10), updated.right_dock);
}

test "getByPaths returns workspace matching ordered paths" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try database.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    try insert(conn, alloc, .{
        .id = 1,
        .paths = &.{ "/a/project", "/b/project" },
    });
    try insert(conn, alloc, .{
        .id = 2,
        .paths = &.{ "/a/project", "/c/project" },
    });

    const workspace = (try getByPaths(conn, alloc, &.{ "/a/project", "/b/project" })).?;
    defer workspace.deinit(alloc);

    try testing.expectEqual(@as(i64, 1), workspace.id);
    try testing.expectEqual(@as(usize, 2), workspace.paths.len);
    try testing.expectEqualStrings("/a/project", workspace.paths[0]);
    try testing.expectEqualStrings("/b/project", workspace.paths[1]);

    try testing.expect((try getByPaths(conn, alloc, &.{"/missing/project"})) == null);
}

test "insertDefault returns unique SQLite rowid workspace ids" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try database.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    const first_id = try insertDefault(conn);
    const second_id = try insertDefault(conn);

    try testing.expect(first_id > 0);
    try testing.expect(second_id > 0);
    try testing.expect(first_id != second_id);

    const first = (try get(conn, alloc, first_id)).?;
    defer first.deinit(alloc);
    const second = (try get(conn, alloc, second_id)).?;
    defer second.deinit(alloc);

    try testing.expectEqual(@as(usize, 0), first.paths.len);
    try testing.expectEqual(@as(usize, 0), second.paths.len);
}

test "setSession updates workspace session and getBySession returns matching workspaces" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try database.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    const session: uuid.Uuid = 123456789;
    const other_session: uuid.Uuid = 987654321;

    try insert(conn, alloc, .{
        .id = 1,
        .paths = &.{"/shared/one"},
    });
    try insert(conn, alloc, .{
        .id = 2,
        .paths = &.{"/shared/two"},
    });
    try insert(conn, alloc, .{
        .id = 3,
        .paths = &.{"/other/session"},
        .session = other_session,
    });

    try setSession(conn, 1, session, alloc);
    try setSession(conn, 2, session, alloc);

    const first = (try get(conn, alloc, 1)).?;
    defer first.deinit(alloc);
    try testing.expectEqual(session, first.session.?);

    const workspaces = try getBySession(conn, alloc, session);
    defer {
        for (workspaces) |workspace| workspace.deinit(alloc);
        alloc.free(workspaces);
    }

    try testing.expectEqual(@as(usize, 2), workspaces.len);
    try testing.expectEqual(@as(i64, 1), workspaces[0].id);
    try testing.expectEqual(session, workspaces[0].session.?);
    try testing.expectEqualStrings("/shared/one", workspaces[0].paths[0]);
    try testing.expectEqual(@as(i64, 2), workspaces[1].id);
    try testing.expectEqual(session, workspaces[1].session.?);
    try testing.expectEqualStrings("/shared/two", workspaces[1].paths[0]);
}

test "getAllValidMetadata returns existing workspaces" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try database.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    const path = "zig-cache-test-valid-workspace";
    try std.Io.Dir.createDir(.cwd(), io, path, .default_dir);
    defer std.Io.Dir.deleteDir(.cwd(), io, path) catch {};

    try insert(conn, alloc, .{
        .id = 1,
        .paths = &.{path},
    });

    const workspaces = try getAllMetadataAndValidate(conn, alloc, io);
    defer {
        for (workspaces) |workspace| workspace.deinit(alloc);
        alloc.free(workspaces);
    }

    try testing.expectEqual(@as(usize, 1), workspaces.len);
    try testing.expectEqual(@as(i64, 1), workspaces[0].id);
    try testing.expectEqualStrings(path, workspaces[0].paths[0]);
}

test "getAllValidMetadata removes missing workspaces" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try database.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    const existing_path = "zig-cache-test-existing-workspace";
    const missing_path = "zig-cache-test-missing-workspace";
    try std.Io.Dir.createDir(.cwd(), io, existing_path, .default_dir);
    defer std.Io.Dir.deleteDir(.cwd(), io, existing_path) catch {};

    try insert(conn, alloc, .{
        .id = 1,
        .paths = &.{existing_path},
    });
    try insert(conn, alloc, .{
        .id = 2,
        .paths = &.{missing_path},
    });

    const workspaces = try getAllMetadataAndValidate(conn, alloc, io);
    defer {
        for (workspaces) |workspace| workspace.deinit(alloc);
        alloc.free(workspaces);
    }

    try testing.expectEqual(@as(usize, 1), workspaces.len);
    try testing.expectEqual(@as(i64, 1), workspaces[0].id);
    try testing.expect((try get(conn, alloc, 2)) == null);
}
