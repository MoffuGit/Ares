const std = @import("std");
const Io = std.Io;
const mod = @import("mod.zig");
const time = @import("time.zig");
const Profiler = mod.Profiler;
const Sample = mod.Sample;
const bench = mod.bench;

const Benchmark = @This();

allocator: std.mem.Allocator,
config: Config,
samples: std.ArrayList(Sample) = .empty,
failures: u64 = 0,
profiler: *Profiler,

pub const RunFlags = struct {
    best: bool = false,
    worst: bool = false,
    failed: bool = false,
};

pub const Config = struct {
    name: ?[]const u8 = null,
    min_iter: usize = 1,
    max_iter: ?usize = null,
    stop_ms: ?u64 = 1000,
    profiler: ?*Profiler = null,
};

pub const Status = enum {
    skipped,
    completed,
};

pub const Stats = struct {
    total_ms: f64,
    mean_ms: f64,
    min_ms: f64,
    max_ms: f64,

    pub fn computeTime(samples: *std.ArrayList(Sample)) !Stats {
        std.debug.assert(samples.items.len > 0);

        std.mem.sort(Sample, samples.items, {}, Sample.sort);

        const len = samples.items.len;

        var sum: u128 = 0;
        for (samples.items) |v| sum += v.time;
        const mean_ticks: u64 = @intCast(sum / len);

        var var_acc: u128 = 0;
        for (samples.items) |v| {
            const d: i128 = @as(i128, @intCast(v.time)) - @as(i128, @intCast(mean_ticks));
            var_acc += @intCast(d * d);
        }

        return .{
            .total_ms = time.ticksToMs(sum),
            .mean_ms = time.ticksToMs(mean_ticks),
            .min_ms = time.ticksToMs(samples.items[0].time),
            .max_ms = time.ticksToMs(samples.items[len - 1].time),
        };
    }
};

pub const Result = struct {
    const Self = @This();

    status: Status,
    iterations: usize = 0,
    failures: u64 = 0,
    time: ?Stats = null,
    name: ?[]const u8 = null,

    pub fn log(self: *const Self, io: Io, file: Io.File) !void {
        var buffer: [4096]u8 = undefined;
        var w: Io.File.Writer = .init(file, io, &buffer);
        const writer: *Io.Writer = &w.interface;
        defer writer.flush() catch {};

        var terminal: Io.Terminal = .{
            .writer = writer,
            .mode = .escape_codes,
        };

        if (self.status == .skipped or self.iterations == 0) return;

        const time_stats = self.time orelse return;

        try writer.print("\n\n", .{});
        try terminal.setColor(.bold);
        try writer.writeAll(self.name orelse "BENCHMARK");
        try terminal.setColor(.dim);
        if (self.iterations > 1) {
            try writer.print(" ({d} runs)", .{self.iterations});
        } else {
            try writer.print(" ({d} run)", .{self.iterations});
        }
        try terminal.setColor(.reset);
        try writer.writeAll("\n");

        try terminal.setColor(.bold);
        const measurement_label = "  measurement";
        try writer.writeAll(measurement_label);
        try writer.splatByteAll(' ', NAME_COL_WIDTH - measurement_label.len);
        try writer.writeAll("mean");

        try writer.splatByteAll(' ', 12);
        try writer.writeAll("min");
        try writer.writeAll(" … ");
        try writer.writeAll("max\n");
        try terminal.setColor(.reset);

        try printMeasurement(writer, "time", time_stats);

        try writer.print("\n\n", .{});
    }
};

const NAME_COL_WIDTH: usize = 23;
const MEAN_COL_WIDTH: usize = 16;
const RANGE_COL_WIDTH: usize = 20;

fn printMeasurement(writer: *Io.Writer, label: []const u8, stats: Stats) !void {
    var buf_mean: [32]u8 = undefined;
    var buf_min: [32]u8 = undefined;
    var buf_max: [32]u8 = undefined;

    var name_buf: [NAME_COL_WIDTH + 8]u8 = undefined;
    const name_str = try std.fmt.bufPrint(&name_buf, "  {s}", .{label});
    try writer.writeAll(name_str);
    if (name_str.len < NAME_COL_WIDTH) {
        try writer.splatByteAll(' ', NAME_COL_WIDTH - name_str.len);
    } else {
        try writer.writeByte(' ');
    }

    const mean_str = try std.fmt.bufPrint(&buf_mean, "{f}", .{time.Duration{ .ms = stats.mean_ms }});
    try writer.writeAll(mean_str);
    const mean_written = mean_str.len + 3;
    if (mean_written < MEAN_COL_WIDTH) {
        try writer.splatByteAll(' ', MEAN_COL_WIDTH - mean_written);
    } else {
        try writer.writeByte(' ');
    }

    // min … max
    const min_str = try std.fmt.bufPrint(&buf_min, "{f}", .{time.Duration{ .ms = stats.min_ms }});
    const max_str = try std.fmt.bufPrint(&buf_max, "{f}", .{time.Duration{ .ms = stats.max_ms }});
    try writer.writeAll(min_str);
    try writer.writeAll(" … ");
    try writer.writeAll(max_str);
    const range_written = min_str.len + 3 + max_str.len;
    if (range_written < RANGE_COL_WIDTH) {
        try writer.splatByteAll(' ', RANGE_COL_WIDTH - range_written);
    } else {
        try writer.writeByte(' ');
    }

    try writer.writeAll("\n");
}

pub fn init(
    self: *Benchmark,
    allocator: std.mem.Allocator,
    config: Config,
) void {
    self.* = .{
        .allocator = allocator,
        .profiler = config.profiler orelse &mod.profiler,
        .config = config,
    };
}

pub fn deinit(self: *Benchmark) void {
    self.samples.deinit(self.allocator);
}

pub fn run(
    self: *Benchmark,
    comptime Context: type,
    context: *Context,
    alloc: std.mem.Allocator,
    io: std.Io,
    callback: *const fn (ctx: *Context, alloc: std.mem.Allocator, io: std.Io, profiler: *Profiler) anyerror!void,
) !Result {
    if (!bench) return .{ .status = .skipped, .name = self.config.name };

    if (self.config.max_iter == null and self.config.stop_ms == null) {
        return error.UnboundedBenchmark;
    }

    if (self.config.max_iter) |mx| {
        if (mx < self.config.min_iter) return error.MinIterExceedsMaxIter;
    }

    self.samples.clearRetainingCapacity();
    self.failures = 0;

    const max_ticks = if (self.config.stop_ms) |ms| time.msToTicks(ms) else std.math.maxInt(u64);
    const max_iter = self.config.max_iter orelse std.math.maxInt(usize);
    const min_iter = self.config.min_iter;
    var acc_ticks: u64 = 0;
    var best_time: u64 = std.math.maxInt(u64);
    var worst_time: u64 = 0;

    while (self.samples.items.len + self.failures < max_iter) {
        self.profiler.init(io, self.allocator);
        defer self.profiler.deinit();

        const cb_result = callback(context, alloc, io, self.profiler);
        const failed = if (cb_result) |_| false else |_| true;

        const sample = self.profiler.sample();

        var flags: RunFlags = .{ .failed = failed };

        if (failed) {
            self.failures += 1;
        } else {
            try self.samples.append(self.allocator, sample);
            if (sample.time < best_time) {
                flags.best = true;
                best_time = sample.time;
            }
            if (sample.time > worst_time) {
                flags.worst = true;
                worst_time = sample.time;
            }
        }

        if (failed) {
            acc_ticks += sample.time;
            if (acc_ticks >= max_ticks and self.samples.items.len + self.failures >= min_iter) break;
            continue;
        }

        if (flags.best) {
            acc_ticks = 0;
        } else {
            acc_ticks += sample.time;
            if (acc_ticks >= max_ticks and self.samples.items.len + self.failures >= min_iter) break;
        }
    }

    if (self.samples.items.len == 0) {
        return .{
            .status = .completed,
            .iterations = 0,
            .failures = self.failures,
            .time = null,
            .name = self.config.name,
        };
    }

    const time_stats = try Stats.computeTime(&self.samples);

    return .{
        .status = .completed,
        .iterations = self.samples.items.len,
        .failures = self.failures,
        .time = time_stats,
        .name = self.config.name,
    };
}
