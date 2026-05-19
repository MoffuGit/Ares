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
