const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;
const Io = std.Io;

const zqlite = @import("zqlite");

const db = @import("../db.zig");
const global = @import("../global.zig");

pub const SerializedWindowBounds = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const SerializedWorkspace = struct {
    paths: []const []const u8,
    session: ?u128 = null,
    window: ?SerializedWindowBounds = null,
    timestamp: ?i64 = null,
    id: i64,

    pub fn deinit(self: SerializedWorkspace, allocator: Allocator) void {
        for (self.paths) |path| allocator.free(path);
        allocator.free(self.paths);
    }
};

const PATH_DELIMITER: u8 = ',';

pub fn insert(conn: zqlite.Conn, allocator: Allocator, workspace: SerializedWorkspace) !void {
    var len: usize = 0;
    for (workspace.paths) |path| len += path.len + 1;
    len -= 1;

    const buffer = try allocator.alloc(u8, len);
    defer allocator.free(buffer);

    len = 0;
    for (workspace.paths, 0..) |path, i| {
        if (i > 0) {
            buffer[len] = ',';
            len += 1;
        }
        @memcpy(buffer[len .. len + path.len], path);
        len += path.len;
    }

    const session = if (workspace.session) |id| try std.fmt.allocPrint(allocator, "{}", .{id}) else null;
    defer if (session) |text| allocator.free(text);

    const bounds = workspace.window;
    try conn.exec(
        \\INSERT INTO workspace (id, paths, session, window_x, window_y, window_width, window_height, timestamp)
        \\VALUES (?, ?, ?, ?, ?, ?, ?, unixepoch())
        \\ON CONFLICT(id) DO UPDATE SET
        \\    paths = excluded.paths,
        \\    session = excluded.session,
        \\    window_x = excluded.window_x,
        \\    window_y = excluded.window_y,
        \\    window_width = excluded.window_width,
        \\    window_height = excluded.window_height,
        \\    timestamp = unixepoch()
    , .{
        workspace.id,
        buffer,
        session,
        if (bounds) |b| b.x else null,
        if (bounds) |b| b.y else null,
        if (bounds) |b| b.width else null,
        if (bounds) |b| b.height else null,
    });
}

pub fn get(conn: zqlite.Conn, allocator: Allocator, id: i64) !?SerializedWorkspace {
    const row = (try conn.row(
        \\SELECT id, paths, session, window_x, window_y, window_width, window_height, timestamp
        \\FROM workspace
        \\WHERE id = ?
    , .{id})) orelse return null;
    defer row.deinit();

    return try deserialize(allocator, row);
}

fn deleteById(conn: zqlite.Conn, id: i64) !void {
    try conn.exec(
        \\DELETE FROM workspace
        \\WHERE id = ?
    , .{id});
}

pub fn getBySession(conn: zqlite.Conn, allocator: Allocator, session: u128) ![]SerializedWorkspace {
    var rows = try conn.rows(
        \\SELECT id, paths, session, window_x, window_y, window_width, window_height, timestamp
        \\FROM workspace
        \\WHERE session = ?
    , .{session});
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
        \\SELECT id, paths, timestamp
        \\FROM workspace
    , .{});
    defer rows.deinit();

    var workspaces: std.ArrayList(SerializedWorkspace) = .empty;
    errdefer {
        for (workspaces.items) |workspace| workspace.deinit(allocator);
        workspaces.deinit(allocator);
    }

    while (rows.next()) |row| {
        const paths_text = row.text(1);
        const path_count: usize = if (paths_text.len == 0) 0 else mem.count(u8, paths_text, &.{PATH_DELIMITER}) + 1;
        const paths = try allocator.alloc([]const u8, path_count);
        var path_index: usize = 0;
        errdefer {
            for (paths[0..path_index]) |path| allocator.free(path);
            allocator.free(paths);
        }

        var iter = mem.splitScalar(u8, paths_text, PATH_DELIMITER);
        while (iter.next()) |path| : (path_index += 1) {
            paths[path_index] = try allocator.dupe(u8, path);
        }

        try workspaces.append(allocator, .{
            .id = row.int(0),
            .paths = paths,
            .timestamp = row.nullableInt(2),
        });
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
    const session = if (row.nullableText(2)) |text| try std.fmt.parseInt(u128, text, 10) else null;

    const path_count: usize = if (paths_text.len == 0) 0 else mem.count(u8, paths_text, &.{PATH_DELIMITER}) + 1;
    const paths = try allocator.alloc([]const u8, path_count);
    var path_index: usize = 0;
    errdefer {
        for (paths[0..path_index]) |path| allocator.free(path);
        allocator.free(paths);
    }

    var iter = mem.splitScalar(u8, paths_text, PATH_DELIMITER);
    while (iter.next()) |path| : (path_index += 1) {
        paths[path_index] = try allocator.dupe(u8, path);
    }

    const window_bounds = if (row.nullableFloat(3)) |x| SerializedWindowBounds{
        .x = x,
        .y = row.float(4),
        .width = row.float(5),
        .height = row.float(6),
    } else null;

    return .{
        .id = row.int(0),
        .paths = paths,
        .session = session,
        .window = window_bounds,
        .timestamp = row.nullableInt(7),
    };
}

test "insert and get workspace paths using delimiter" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try db.testingPool(alloc);
    defer pool.deinit();

    const conn = try pool.acquire(io);
    defer conn.release(io);

    try insert(conn, alloc, .{
        .id = 42,
        .paths = &.{ "/tmp/project", "/Users/me/workspace" },
        .window = .{ .x = 1, .y = 2, .width = 800, .height = 600 },
    });

    const workspace = (try get(conn, alloc, 42)).?;
    defer workspace.deinit(alloc);

    try std.testing.expectEqual(@as(usize, 2), workspace.paths.len);
    try std.testing.expectEqualStrings("/tmp/project", workspace.paths[0]);
    try std.testing.expectEqualStrings("/Users/me/workspace", workspace.paths[1]);
    try std.testing.expect(workspace.session == null);
    try std.testing.expect(workspace.window != null);
    try std.testing.expectEqual(@as(f64, 1), workspace.window.?.x);
    try std.testing.expect(workspace.timestamp != null);
}

test "getAllValidMetadata returns existing workspaces" {
    const alloc = testing.allocator;
    const io = testing.io;

    var pool = try db.testingPool(alloc);
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

    var pool = try db.testingPool(alloc);
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
