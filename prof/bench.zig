const std = @import("std");
const mod = @import("mod.zig");
const print = @import("print.zig");
const time = @import("time.zig");
const Profiler = mod.Profiler;
const Snapshot = mod.Snapshot;
const bench_enabled = mod.bench_enabled;

const Benchmark = @This();

allocator: std.mem.Allocator,
config: Config,
profiler: Profiler,

pub const Config = struct {
    name: []const u8 = "benchmark",
    max_iter: ?usize = 1,
    stop_ms: ?u64 = null,
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
    timings: Timing,

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
        // stdoutPrint("| NAME | RUNS | FAILS |\n", .{});
        // stdoutPrint("| {s} | {d} | {d} |\n", .{ self.config.name, result.iterations, result.failures });
        //
        // stdoutPrint("\nMEASUREMENTS\n", .{});
        // stdoutPrint("| KIND | MIN MS | MAX MS | AVG MS |\n", .{});
        // stdoutPrint(
        //     "| TIME | {d:.3} | {d:.3} | {d:.3} |\n",
        //     .{
        //         if (result.timings.min_ticks) |ticks| self.profiler.ticksToMs(ticks) else 0,
        //         self.profiler.ticksToMs(result.timings.max_ticks),
        //         self.profiler.ticksToMs(result.timings.avgTicks()),
        //     },
        // );
        //
        // if (Profiler.collects_zones) {
        //     if (self.best_profile) |snapshot_value| {
        //         stdoutPrint("\nBEST PROFILE\n", .{});
        //         snapshot_value.log();
        //     }
        // }
    }
};

pub fn init(self: *Benchmark, allocator: std.mem.Allocator, config: Config) void {
    self.* = .{
        .allocator = allocator,
        .config = config,
        .profiler = undefined,
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
    if (!bench_enabled) return .{ .status = .skipped };

    if (self.config.max_iter == null and self.config.stop_ms == null) {
        return error.UnboundedBenchmark;
    }

    if (!Profiler.is_enabled and self.config.stop_ms != null) {
        return error.BenchmarkTimerDisabled;
    }

    const max_ticks = if (self.config.stop_ms) |ms| time.msToTicks(ms) else std.math.maxInt(u64);
    const max_iter = self.config.max_iter orelse std.math.maxInt(usize);
    var acc_ticks: u64 = 0;

    var data: Data = .{};
    while (data.iterations + data.failures < max_iter) {
        self.profiler.init(self.allocator);
        defer self.profiler.deinit();

        const failed = if (callback(ctx, &self.profiler)) |_| false else |_| failed: {
            data.failures += 1;
            break :failed true;
        };

        const sample = self.profiler.sample();

        if (failed) {
            acc_ticks += sample.time;
            if (acc_ticks >= max_ticks) break;
            continue;
        }

        if (data.add(sample.time)) {
            acc_ticks = 0;
        } else {
            acc_ticks += sample.time;
            if (acc_ticks >= max_ticks) break;
        }
    }

    if (data.iterations == 0) {
        return .{
            .status = .completed,
            .iterations = 0,
            .failures = data.failures,
            .timings = .{ .max = 0, .min = 0, .mean = 0 },
        };
    }

    return Result.fromData(data);
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
    max: f64,
    min: f64,
    mean: f64,
};
