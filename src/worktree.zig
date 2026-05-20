const std = @import("std");
const Allocator = std.mem.Allocator;
const ArenaAllocator = std.heap.ArenaAllocator;
const Io = std.Io;
const Scanner = @import("worktree/scanner.zig");

pub const Worktree = @This();
pub const Options = struct {
    abs_path: []const u8,
};

arena: ArenaAllocator,
gpa: Allocator,
io: Io,

scanner: Scanner,

pub fn init(self: *Worktree, gpa: Allocator, io: Io, opts: Options) !void {
    self.* = .{
        .arena = ArenaAllocator.init(gpa),
        .gpa = gpa,
        .io = io,
        .scanner = undefined,
    };

    errdefer _ = self.arena.reset(.free_all);

    const arena = self.arena.allocator();
    const abs_root = try arena.dupe(u8, opts.abs_path);

    self.scanner.init(arena, gpa, abs_root);
    try self.scanner.run(io);
}

pub fn deinit(self: *Worktree) void {
    self.scanner.deinit(self.io);
    _ = self.arena.reset(.free_all);
}
