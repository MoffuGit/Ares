const std = @import("std");
const vaxis = @import("vaxis");
const builtin = @import("builtin");
const posix = std.posix;

const log = std.log.scoped(.app);

const Allocator = std.mem.Allocator;

const App = @This();

alloc: Allocator,

tty: *vaxis.Tty,

pub fn init(alloc: Allocator, tty: *vaxis.Tty) !App {
    return .{ .alloc = alloc, .tty = tty };
}

pub fn deinit(self: *App) void {
    _ = self;
}

pub fn run(self: *App) !void {
    var parser: vaxis.Parser = .{};

    var buf: [1024]u8 = undefined;
    var read_start: usize = 0;

    var cache: vaxis.GraphemeCache = .{};

    const winsize = try vaxis.Tty.getWinsize(self.tty.fd);
    log.err("winsize {}", .{winsize});

    while (true) {
        const n = self.tty.read(buf[read_start..]) catch |err| {
            if (err == error.WouldBlock) continue else return err;
        };
        var seq_start: usize = 0;
        while (seq_start < n) {
            const result = try parser.parse(buf[seq_start..n], self.alloc);
            if (result.n == 0) {
                // copy the read to the beginning. We don't use memcpy because
                // this could be overlapping, and it's also rare
                const initial_start = seq_start;
                while (seq_start < n) : (seq_start += 1) {
                    buf[seq_start - initial_start] = buf[seq_start];
                }
                read_start = seq_start - initial_start + 1;
                continue;
            }
            read_start = 0;
            seq_start += result.n;

            const event = result.event orelse continue;
            try self.eventCallback(&cache, event);
        }
    }
}

fn eventCallback(self: *App, cache: *vaxis.GraphemeCache, event: vaxis.Event) !void {
    _ = self;
    _ = cache;
    log.err("event: {}", .{event});
}
