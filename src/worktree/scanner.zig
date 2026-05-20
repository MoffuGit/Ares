const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Snapshot = @import("snapshot.zig");
const assert = std.debug.assert;

const Scanner = @This();

const State = struct {
    phase: Phase,
    list: std.ArrayList([]const u8),
    // snapshot: Snapshot,
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
            .list = .empty,
            // .snapshot = undefined,
        },
        .abs_root = abs_root,
    };

    // try self.state.snapshot.init(gpa);
}

pub fn run(self: *Scanner, io: Io) !void {
    assert(self.state.phase == .Initial);
    try self.group.concurrent(io, scanPath, .{ self, io, self.abs_root });
    try self.group.await(io);
}

pub fn deinit(self: *Scanner, io: Io) void {
    self.group.cancel(io);
    self.state.list.deinit(self.gpa);
    // self.state.snapshot.deinit();
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
        self.state.list.append(self.gpa, children) catch |err| {
            std.log.err("path: {s}, err: {}", .{ children, err });
        };
        // self.state.snapshot.insert(children)
    }
}
