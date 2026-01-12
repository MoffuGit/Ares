const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

pub const panic = vaxis.panic_handler;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const global = &@import("global.zig").state;

pub fn main() !void {
    try global.init();
    defer global.deinit();

    const alloc = global.alloc;

    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ms_per_s);

    var pct: u8 = 0;
    var dir: enum {
        up,
        down,
    } = .up;

    const fg = [_]u8{ 192, 202, 245, 255 };
    const bg = [_]u8{ 0, 0, 0, 255 };

    // block until we get a resize
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| if (key.matches('c', .{ .ctrl = true })) return,
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
                break;
            },
        }
    }

    const tick_ms: u64 = @divFloor(std.time.ms_per_s, 120);
    var next_frame_ms: u64 = @intCast(std.time.milliTimestamp());

    while (true) {
        const now_ms: u64 = @intCast(std.time.milliTimestamp());
        if (now_ms >= next_frame_ms) {
            // Deadline exceeded. Schedule the next frame
            next_frame_ms = now_ms + tick_ms;
        } else {
            // Sleep until the deadline
            std.Thread.sleep((next_frame_ms - now_ms) * std.time.ns_per_ms);
            next_frame_ms += tick_ms;
        }

        while (loop.tryEvent()) |event| {
            switch (event) {
                .key_press => |key| if (key.matches('c', .{ .ctrl = true })) return,
                .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
            }
        }

        const win = vx.window();
        win.clear();

        win.fill(.{ .style = .{ .bg = .{ .rgb = .{ 0, 0, 0 } }, .fg = .{ .rgba = .{ 0, 0, 0, 255 } } } });

        var color = fg;
        color[3] = pct;

        const style: vaxis.Style = .{ .fg = .{ .rgba = color }, .bg = .{ .rgba = bg } };

        const segment: vaxis.Segment = .{
            .text = vaxis.logo,
            .style = style,
        };

        const center = vaxis.widgets.alignment.center(win, 28, 4);
        _ = center.printSegment(segment, .{ .wrap = .grapheme });

        try vx.render(tty.writer());

        switch (dir) {
            .up => {
                pct += 1;
                if (pct == 255) dir = .down;
            },
            .down => {
                pct -= 1;
                if (pct == 0) dir = .up;
            },
        }
    }
}
