const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Snapshot = @import("snapshot.zig");
const assert = std.debug.assert;

const Scanner = @This();

const State = struct {
    phase: Phase,
    snapshot: Snapshot,
};

const Phase = enum {
    Initial,
    Events,
};

group: Io.Group,

mutex: Io.Mutex,
state: State,
gpa: Allocator,
arena: Allocator,

abs_root: []u8,

pub fn init(self: *Scanner, arena: Allocator, gpa: Allocator, abs_root: []u8) !void {
    self.* = .{
        .arena = arena,
        .group = .init,
        .mutex = .init,
        .gpa = gpa,
        .state = .{
            .phase = .Initial,
            .snapshot = undefined,
        },
        .abs_root = abs_root,
    };

    try self.state.snapshot.init(gpa);
}

pub fn run(self: *Scanner, io: Io) !void {
    var dir = try Io.Dir.openDirAbsolute(io, self.abs_root, .{ .iterate = true });
    defer dir.close(io);

    var walker = try dir.walk(self.gpa);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        const child =
            self.arena.dupe(u8, entry.path) catch |err| {
                std.log.err("ah: {}", .{err});
                continue;
            };

        self.state.snapshot.insert(self.gpa, child) catch |err| {
            std.log.err("eh: {} path: {s}", .{ err, child });
            continue;
        };
    }
}

pub fn runAsync(self: *Scanner, io: Io) !void {
    assert(self.state.phase == .Initial);
    try self.group.concurrent(io, scanPath, .{ self, io, self.abs_root });
    try self.group.await(io);
}

pub fn deinit(self: *Scanner, io: Io) void {
    self.group.cancel(io);
    self.state.snapshot.deinit(self.gpa);
}

fn scanPath(
    self: *Scanner,
    io: Io,
    abs_path: []u8,
) Io.Cancelable!void {
    const stat = Io.Dir.cwd().statFile(io, abs_path, .{}) catch |err| {
        if (err == error.Canceled) return error.Canceled;
        return;
    };

    switch (stat.kind) {
        .directory => {
            self.scanDir(io, abs_path) catch |err| {
                if (err == error.Canceled) return error.Canceled;
            };
        },
        else => {
            // sym_link / block_device / etc — ignored for now.
        },
    }
}

fn scanDir(self: *Scanner, io: Io, abs_path: []const u8) !void {
    var dir = try Io.Dir.openDirAbsolute(io, abs_path, .{ .iterate = true });
    defer dir.close(io);

    var childrens: std.ArrayList([]u8) = .empty;
    defer childrens.deinit(self.gpa);

    var iter = dir.iterate();
    while (try iter.next(io)) |entry| {
        switch (entry.kind) {
            .directory => {
                const child = std.fs.path.join(self.arena, &.{ abs_path, entry.name }) catch {
                    continue;
                };

                try childrens.append(self.gpa, child);

                try self.group.concurrent(io, scanPath, .{ self, io, child });
            },
            .file => {
                const child = std.fs.path.join(self.arena, &.{ abs_path, entry.name }) catch {
                    continue;
                };
                try childrens.append(self.gpa, child);
            },
            else => {},
        }
    }

    try self.mutex.lock(io);
    defer self.mutex.unlock(io);

    for (childrens.items) |children| {
        self.state.snapshot.insert(self.gpa, children) catch |err| {
            std.log.err("path: {s}, err: {}", .{ children, err });
        };
    }
}
