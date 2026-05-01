const std = @import("std");
const xev = @import("../global.zig").xev;
const Allocator = std.mem.Allocator;
const Thread = @import("Thread.zig");
const Watchers = @import("backend/kqueue.zig");
const shared = @import("backend/shared.zig");

const log = std.log.scoped(.monitor);

pub const Monitor = @This();
pub const Completion = shared.Completion;

alloc: Allocator,
watchers: Watchers,
thread: Thread,
thr: std.Thread,

pub fn create(alloc: Allocator) !*Monitor {
    const monitor = try alloc.create(Monitor);
    const watchers = try Watchers.init(&monitor.thread.loop, alloc);

    monitor.* = .{
        .alloc = alloc,
        .watchers = watchers,
        .thread = try Thread.init(alloc, monitor),
        .thr = undefined,
    };

    monitor.thr = try std.Thread.spawn(.{}, Thread.threadMain, .{&monitor.thread});

    return monitor;
}

pub fn destroy(self: *Monitor) void {
    {
        self.thread.stop.notify() catch |err| {
            log.err("error notifying monitor thread to stop, may stall err={}", .{err});
        };
        self.thr.join();
    }

    self.watchers.deinit();
    self.thread.deinit();

    self.alloc.destroy(self);

    log.info("Monitor closed", .{});
}

pub fn watchPath(
    self: *Monitor,
    path: []const u8,
    comp: *Completion,
    comptime Userdata: type,
    userdata: ?*Userdata,
    comptime cb: *const fn (userdata: ?*Userdata, events: u32) void,
) !void {
    const wrapped = (struct {
        fn callback(
            ud: ?*Userdata,
            _: *Completion,
            _: []const u8,
            events: u32,
        ) xev.CallbackAction {
            cb(ud, events);
            return .rearm;
        }
    }).callback;

    try self.watchers.watch(path, comp, Userdata, userdata, wrapped);
}
