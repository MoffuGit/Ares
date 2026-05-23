const std = @import("std");

pub fn timerFreq() u64 {
    var val: u64 = undefined;

    asm volatile ("mrs %[val], cntfrq_el0"
        : [val] "=r" (val),
    );

    return val;
}

pub fn timer() u64 {
    var val: u64 = undefined;

    asm volatile ("mrs %[val], cntvct_el0"
        : [val] "=r" (val),
    );

    return val;
}

pub fn msToTicks(ms: u64) u64 {
    if (ms == 0) return 0;
    return ms * timerFreq() / 1000;
}

pub fn ticksToMs(ticks: anytype) f64 {
    if (ticks == 0) return 0.0;

    return @as(f64, @floatFromInt(ticks)) * 1000.0 / @as(f64, @floatFromInt(timerFreq()));
}

pub const Duration = struct {
    ms: f64,

    pub fn fromTicks(ticks: u65) Duration {
        return .{ .ms = ticksToMs(ticks) };
    }

    pub fn format(self: Duration, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const ms = self.ms;
        if (ms >= 1_000.0) {
            try writer.print("{d:.3}s", .{ms / 1_000.0});
        } else if (ms >= 1.0) {
            try writer.print("{d:.3}ms", .{ms});
        } else if (ms >= 0.001) {
            try writer.print("{d:.3}us", .{ms * 1_000.0});
        } else {
            try writer.print("{d:.3}ns", .{ms * 1_000_000.0});
        }
    }
};
