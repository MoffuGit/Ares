const std = @import("std");

const zqlite = @import("zqlite");

pub const SerializedWorkspace = struct {
    id: i64,
    paths: []const []const u8,
    window_bounds: ?WindowBounds = null,

    pub const WindowBounds = struct {
        x: f64,
        y: f64,
        width: f64,
        height: f64,
    };

    pub fn deinit(self: SerializedWorkspace, allocator: std.mem.Allocator) void {
        for (self.paths) |path| allocator.free(path);
        allocator.free(self.paths);
    }
};

pub fn get(conn: zqlite.Conn, allocator: std.mem.Allocator, id: i64) !?SerializedWorkspace {
    const row = (try conn.row(
        \\SELECT paths, window_x, window_y, window_width, window_height
        \\FROM workspace
        \\WHERE id = ?
    , .{id})) orelse return null;
    defer row.deinit();

    const paths = try std.json.parseFromSliceLeaky([]const []const u8, allocator, row.text(0), .{});
    errdefer {
        for (paths) |path| allocator.free(path);
        allocator.free(paths);
    }

    const window_bounds = if (row.nullableFloat(1)) |x| SerializedWorkspace.WindowBounds{
        .x = x,
        .y = row.float(2),
        .width = row.float(3),
        .height = row.float(4),
    } else null;

    return .{
        .id = id,
        .paths = paths,
        .window_bounds = window_bounds,
    };
}

pub fn put(conn: zqlite.Conn, allocator: std.mem.Allocator, workspace: SerializedWorkspace) !void {
    const paths = try std.json.stringifyAlloc(allocator, workspace.paths, .{});
    defer allocator.free(paths);

    const bounds = workspace.window_bounds;
    try conn.exec(
        \\INSERT INTO workspace (id, paths, window_x, window_y, window_width, window_height)
        \\VALUES (?, ?, ?, ?, ?, ?)
        \\ON CONFLICT(id) DO UPDATE SET
        \\    paths = excluded.paths,
        \\    window_x = excluded.window_x,
        \\    window_y = excluded.window_y,
        \\    window_width = excluded.window_width,
        \\    window_height = excluded.window_height
    , .{
        workspace.id,
        paths,
        if (bounds) |b| b.x else null,
        if (bounds) |b| b.y else null,
        if (bounds) |b| b.width else null,
        if (bounds) |b| b.height else null,
    });
}
