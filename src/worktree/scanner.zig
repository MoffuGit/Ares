const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;

const Scanner = @This();

const State = struct {
    phase: Phase,
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

pub fn init(self: *Scanner, arena: Allocator, gpa: Allocator, abs_root: []u8) void {
    self.* = .{
        .arena = arena,
        .group = .init,
        .mutex = .init,
        .gpa = gpa,
        .state = .{
            .phase = .Initial,
        },
        .abs_root = abs_root,
    };
}

pub fn run(
    self: *Scanner,
    _: Io,
) !void {
    assert(self.state.phase == .Initial);

    // try self.group.concurrent(
    //     io,
    //     runScan,
    //     .{
    //         io, self.gpa, &self.group,
    //         Scan{
    //             .state = &self.state,
    //             .path = self.abs_root,
    //         },
    //     },
    // );
}

pub fn deinit(self: *Scanner, io: Io) void {
    self.group.cancel(io);
}
