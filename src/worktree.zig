const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
const Scanner = @import("worktree/scanner.zig");
const Snapshot = @import("worktree/snapshot.zig");

pub const Worktree = @This();
pub const Options = struct {
    abs_path: []const u8,
};

arena: ArenaAllocator,
gpa: Allocator,
io: Io,

snapshot: Snapshot,
scanner: Scanner,

pub fn init(self: *Worktree, gpa: Allocator, io: Io, opts: Options) !void {
    self.* = .{
        .arena = ArenaAllocator.init(gpa),
        .gpa = gpa,
        .io = io,
        .snapshot = undefined,
        .scanner = undefined,
    };
    const arena = self.arena.allocator();
    errdefer _ = self.arena.reset(.free_all);

    const abs_root = try arena.dupe(u8, opts.abs_path);
    const basename = std.fs.path.basename(abs_root);
    const root_name = try arena.dupe(u8, basename);

    try self.snapshot.init(abs_root, root_name, gpa);

    try self.scanner.init(arena, gpa, &self.snapshot);
    try self.scanner.run(io);
}

pub fn deinit(self: *Worktree) void {
    self.scanner.deinit(self.io);
    _ = self.arena.reset(.free_all);
}
