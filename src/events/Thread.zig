const Thread = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("../global.zig").xev;

const Loop = @import("../Loop.zig");

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.events_thread);

alloc: Allocator,
tty: *vaxis.Tty,
mailbox: *Loop.Mailbox,
wakeup: xev.Async,
running: std.atomic.Value(bool),

pub fn init(alloc: Allocator, tty: *vaxis.Tty, mailbox: *Loop.Mailbox, wakeup: xev.Async) Thread {
    return .{
        .alloc = alloc,
        .tty = tty,
        .mailbox = mailbox,
        .wakeup = wakeup,
        .running = std.atomic.Value(bool).init(true),
    };
}

pub fn stop(self: *Thread) void {
    self.running.store(false, .release);
}

pub fn threadMain(self: *Thread) void {
    self.threadMain_() catch |err| {
        log.warn("error in read thread err={}", .{err});
    };
}

fn threadMain_(self: *Thread) !void {
    defer log.debug("read thread exited", .{});
    log.debug("starting read thread", .{});

    var parser: vaxis.Parser = .{};
    var buf: [1024]u8 = undefined;
    var read_start: usize = 0;

    read_loop: while (self.running.load(.acquire)) {
        const n = try self.tty.read(buf[read_start..]);
        var seq_start: usize = 0;
        while (seq_start < n) {
            const result = try parser.parse(buf[seq_start..n], self.alloc);
            if (result.n == 0) {
                const initial_start = seq_start;
                while (seq_start < n) : (seq_start += 1) {
                    buf[seq_start - initial_start] = buf[seq_start];
                }
                read_start = seq_start - initial_start + 1;
                continue :read_loop;
            }
            read_start = 0;
            seq_start += result.n;

            const event = result.event orelse continue;
            try self.handleEvent(event);

            try self.wakeup.notify();
        }
    }
}

fn handleEvent(self: *Thread, event: vaxis.Event) !void {
    switch (event) {
        .winsize => |size| {
            _ = self.mailbox.push(.{ .resize = size }, .instant);
        },
        .key_press => |key| {
            _ = self.mailbox.push(.{ .event = .{ .key_press = key } }, .instant);
        },
        .key_release => |key| {
            _ = self.mailbox.push(.{ .event = .{ .key_release = key } }, .instant);
        },
        .focus_in => {
            _ = self.mailbox.push(.{ .event = .focus }, .instant);
        },
        .focus_out => {
            _ = self.mailbox.push(.{ .event = .blur }, .instant);
        },
        .mouse => |mouse| {
            _ = self.mailbox.push(.{ .event = .{ .mouse = mouse } }, .instant);
        },
        else => {},
    }
}
