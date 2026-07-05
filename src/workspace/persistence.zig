const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;
const testing = std.testing;

const zqlite = @import("zqlite");

const db = @import("../db.zig");

pub const WindowBounds = struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
};

pub const SerializedWindowBounds = WindowBounds;

pub const SerializedWorkspace = struct {
    id: i64,
    paths: []const []const u8,
    session: ?[]const u8 = null,
    window: ?SerializedWindowBounds = null,
    timestamp: ?i64 = null,

    pub fn deinit(self: SerializedWorkspace, allocator: Allocator) void {
        for (self.paths) |path| allocator.free(path);
        allocator.free(self.paths);
        if (self.session) |session| allocator.free(session);
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
        workspace.session,
        if (bounds) |b| b.x else null,
        if (bounds) |b| b.y else null,
        if (bounds) |b| b.width else null,
        if (bounds) |b| b.height else null,
    });
}

pub fn get(conn: zqlite.Conn, allocator: Allocator, id: i64) !?SerializedWorkspace {
    const row = (try conn.row(
        \\SELECT paths, session, window_x, window_y, window_width, window_height, timestamp
        \\FROM workspace
        \\WHERE id = ?
    , .{id})) orelse return null;
    defer row.deinit();

    const paths_text = row.text(0);
    const session = if (row.nullableText(1)) |text| try allocator.dupe(u8, text) else null;
    errdefer if (session) |text| allocator.free(text);

    const path_count: usize = if (paths_text.len == 0) 0 else mem.count(u8, paths_text, &.{PATH_DELIMITER}) + 1;
    const paths = try allocator.alloc([]const u8, path_count);
    errdefer {
        for (paths) |path| allocator.free(path);
        allocator.free(paths);
    }

    var path_index: usize = 0;
    var iter = mem.splitScalar(u8, paths_text, PATH_DELIMITER);
    while (iter.next()) |path| : (path_index += 1) {
        paths[path_index] = try allocator.dupe(u8, path);
    }

    const window_bounds = if (row.nullableFloat(2)) |x| SerializedWindowBounds{
        .x = x,
        .y = row.float(3),
        .width = row.float(4),
        .height = row.float(5),
    } else null;

    return .{
        .id = id,
        .paths = paths,
        .session = session,
        .window = window_bounds,
        .timestamp = row.nullableInt(6),
    };
}

//NOTE:
//i need two functions
//one that get me the workspaces that have a session == to x
//and another that returns all saved workspaces
//the process will be as follows:
//try to get prev session workspaces,
//if we have none, we open a window with our list of
//all prev saved workspaces

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
