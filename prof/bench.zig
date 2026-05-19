const std = @import("std");
const mod = @import("mod.zig");
const print = @import("print.zig");
const time = @import("time.zig");
const Profiler = mod.Profiler;
const bench_enabled = mod.bench_enabled;

const Benchmark = @This();

allocator: std.mem.Allocator,
config: Config,
ctx: ?*anyopaque = null,
data: Data = .{},
profiler: Profiler = undefined,

pub const RunFlags = struct {
    is_best: bool = false,
    is_worst: bool = false,
    failed: bool = false,
};

pub const Hook = *const fn (b: *Benchmark, ctx: ?*anyopaque) void;
pub const AfterEachHook = *const fn (b: *Benchmark, ctx: ?*anyopaque, flags: RunFlags) void;

pub const Hooks = struct {
    before_all: ?Hook = null,
    after_all: ?Hook = null,
    before_each: ?Hook = null,
    after_each: ?AfterEachHook = null,
};

pub const Config = struct {
    name: []const u8 = "benchmark",
    min_iter: usize = 1,
    max_iter: ?usize = 1,
    stop_ms: ?u64 = null,
    hooks: Hooks = .{},
};

pub const Status = enum {
    skipped,
    completed,
};

pub const Result = struct {
    const Self = @This();

    status: Status,
    iterations: usize = 0,
    failures: usize = 0,
    timings: Timing = .{},

    pub fn fromData(data: Data) Self {
        const max = time.ticksToMs(data.max_ticks);
        const min = time.ticksToMs(data.min_ticks);
        const mean = time.ticksToMs(data.acc / data.iterations);

        return .{
            .status = .completed,
            .iterations = data.iterations,
            .failures = data.failures,
            .timings = .{
                .max = max,
                .min = min,
                .mean = mean,
            },
        };
    }

    pub fn log(self: *const Self) void {
        print.print("BENCHMARK RUNS\n", .{});
        print.print("best: {}", .{self.timings.min});
    }
};

pub fn init(self: *Benchmark, allocator: std.mem.Allocator, config: Config) void {
    self.* = .{
        .allocator = allocator,
        .config = config,
    };
}

pub fn deinit(self: *Benchmark) void {
    _ = self;
}

pub fn run(
    self: *Benchmark,
    comptime Context: type,
    ctx: ?*Context,
    callback: *const fn (ctx: ?*Context, profiler: *Profiler) anyerror!void,
) !Result {
    if (!bench_enabled) return .{ .status = .skipped, .timings = .{} };

    if (self.config.max_iter == null and self.config.stop_ms == null) {
        return error.UnboundedBenchmark;
    }

    if (!Profiler.is_enabled and self.config.stop_ms != null) {
        return error.BenchmarkTimerDisabled;
    }

    if (self.config.max_iter) |mx| {
        if (mx < self.config.min_iter) return error.MinIterExceedsMaxIter;
    }

    self.ctx = if (ctx) |c| @as(*anyopaque, @ptrCast(c)) else null;
    self.data = .{};

    if (self.config.hooks.before_all) |hook| hook(self, self.ctx);

    const max_ticks = if (self.config.stop_ms) |ms| time.msToTicks(ms) else std.math.maxInt(u64);
    const max_iter = self.config.max_iter orelse std.math.maxInt(usize);
    const min_iter = self.config.min_iter;
    var acc_ticks: u64 = 0;
    var best_time: u64 = std.math.maxInt(u64);
    var worst_time: u64 = 0;

    while (self.data.iterations + self.data.failures < max_iter) {
        if (self.config.hooks.before_each) |hook| hook(self, self.ctx);

        self.profiler.init(self.allocator);
        defer self.profiler.deinit();

        const cb_result = callback(ctx, &self.profiler);
        const failed = if (cb_result) |_| false else |_| true;
        const sample = self.profiler.sample();

        var flags: RunFlags = .{ .failed = failed };

        if (failed) {
            self.data.failures += 1;
        } else {
            _ = self.data.add(sample.time);
            if (sample.time < best_time) {
                flags.is_best = true;
                best_time = sample.time;
            }
            if (sample.time > worst_time) {
                flags.is_worst = true;
                worst_time = sample.time;
            }
        }

        if (self.config.hooks.after_each) |hook| hook(self, self.ctx, flags);

        if (failed) {
            acc_ticks += sample.time;
            if (acc_ticks >= max_ticks and self.data.iterations + self.data.failures >= min_iter) break;
            continue;
        }

        if (flags.is_best) {
            acc_ticks = 0;
        } else {
            acc_ticks += sample.time;
            if (acc_ticks >= max_ticks and self.data.iterations + self.data.failures >= min_iter) break;
        }
    }

    if (self.config.hooks.after_all) |hook| hook(self, self.ctx);

    if (self.data.iterations == 0) {
        return .{
            .status = .completed,
            .iterations = 0,
            .failures = self.data.failures,
            .timings = .{},
        };
    }

    return Result.fromData(self.data);
}

pub const Data = struct {
    min_ticks: u64 = std.math.maxInt(u64),
    max_ticks: u64 = 0,
    acc: u64 = 0,
    iterations: u64 = 0,
    failures: u64 = 0,

    pub fn add(self: *Data, ticks: u64) bool {
        self.iterations += 1;
        self.acc += ticks;

        if (ticks > self.max_ticks) self.max_ticks = ticks;

        if (self.min_ticks > ticks) {
            self.min_ticks = ticks;
            return true;
        }

        return false;
    }
};

const Timing = struct {
    max: f64 = 0,
    min: f64 = 0,
    mean: f64 = 0,
};
