const Thread = @This();

const std = @import("std");
const vaxis = @import("vaxis");
const xev = @import("xev").Dynamic;
const log = std.log.scoped(.events_thread);

const Allocator = std.mem.Allocator;
const SharedContext = @import("SharedContext.zig");
const Loop = @import("Loop.zig");

alloc: Allocator,
shared_context: *SharedContext,
loop: *Loop,
running: std.atomic.Value(bool),

pub fn init(alloc: Allocator, shared: *SharedContext, loop: *Loop) Thread {
    return .{
        .shared_context = shared,
        .loop = loop,
        .alloc = alloc,
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

    var tty = self.shared_context.tty;
    var parser: vaxis.Parser = .{};
    var buf: [1024]u8 = undefined;
    var read_start: usize = 0;

    read_loop: while (self.running.load(.acquire)) {
        const n = try tty.read(buf[read_start..]);
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

            try self.loop.wakeup.notify();
        }
    }
}

//NOTE:
//the string that's part of key press and release
//can get deallocated after a while, if i start having problems with that
//is because i should store a copy and use the copy instead
fn handleEvent(self: *Thread, event: vaxis.Event) !void {
    const mailbox = self.loop.mailbox;

    switch (event) {
        .color_scheme => |scheme| {
            _ = mailbox.push(.{ .app = .{ .scheme = scheme } }, .instant);
        },
        .winsize => |size| {
            vaxis.Tty.resetSignalHandler();
            _ = mailbox.push(.{ .window = .{ .resize = size } }, .instant);
        },
        .key_press => |key| {
            _ = mailbox.push(.{ .window = .{ .event = .{ .key_press = key } } }, .instant);
        },
        .key_release => |key| {
            _ = mailbox.push(.{ .window = .{ .event = .{ .key_release = key } } }, .instant);
        },
        .focus_in => {
            _ = mailbox.push(.{ .window = .{ .event = .focus } }, .instant);
        },
        .focus_out => {
            _ = mailbox.push(.{ .window = .{ .event = .blur } }, .instant);
        },
        .mouse => |mouse| {
            _ = mailbox.push(.{ .window = .{ .event = .{ .mouse = mouse } } }, .instant);
        },
        else => {},
    }
}
