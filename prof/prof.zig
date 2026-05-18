// const std = @import("std");
// const builtin = @import("builtin");
// const build_options = @import("odyssey_build_options");
//
// pub const ProfileLevel = enum {
//     none,
//     general,
//     deep,
// };
//
// pub const configured_level: ProfileLevel = std.meta.stringToEnum(ProfileLevel, build_options.profile_level) orelse
//     @compileError("invalid odyssey_build_options.profile_level");
//
// pub const bench_enabled: bool = build_options.bench_enabled;
//
// pub const AnchorId = usize;
// pub const FrameId = usize;
// pub const BlockId = u64;
//
// pub const ScopeTotals = struct {
//     calls: u64 = 0,
//     recursive_calls: u64 = 0,
//     inclusive_ticks: u64 = 0,
//     exclusive_ticks: u64 = 0,
//     bytes: u64 = 0,
// };
//
// pub const TimeStats = struct {
//     samples: u64 = 0,
//     total_ticks: u64 = 0,
//     min_ticks: ?u64 = null,
//     max_ticks: u64 = 0,
//     last_ticks: u64 = 0,
//
//     pub fn add(self: *TimeStats, ticks: u64) bool {
//         self.samples += 1;
//         self.total_ticks += ticks;
//         self.last_ticks = ticks;
//         const is_new_min = self.min_ticks == null or ticks < self.min_ticks.?;
//         if (is_new_min) {
//             self.min_ticks = ticks;
//         }
//         if (ticks > self.max_ticks) {
//             self.max_ticks = ticks;
//         }
//         return is_new_min;
//     }
//
//     pub fn avgTicks(self: TimeStats) u64 {
//         return if (self.samples == 0) 0 else self.total_ticks / self.samples;
//     }
// };
//
// pub const Anchor = struct {
//     name: []const u8,
//     source: std.builtin.SourceLocation,
//     parent: ?AnchorId = null,
//     depth: u32 = 0,
//     active_depth: u32 = 0,
//     totals: ScopeTotals = .{},
// };
//
// pub const Frame = struct {
//     anchor: AnchorId,
//     parent: ?FrameId,
//     block: BlockId,
//     depth: u32,
//     recursive_depth: u32,
//     start_ticks: u64,
//     child_inclusive_ticks: u64 = 0,
//     bytes: u64,
//     totals: ScopeTotals = .{},
// };
//
// pub const AnchorStack = struct {
//     allocator: std.mem.Allocator,
//     anchors: std.ArrayList(Anchor) = .empty,
//     frames: std.ArrayList(Frame) = .empty,
//     current_frame: ?FrameId = null,
//     current_block: BlockId = 0,
//
//     pub fn init(allocator: std.mem.Allocator) AnchorStack {
//         return .{ .allocator = allocator };
//     }
//
//     pub fn deinit(self: *AnchorStack) void {
//         self.frames.deinit(self.allocator);
//         self.anchors.deinit(self.allocator);
//         self.* = undefined;
//     }
//
//     pub fn beginBlock(self: *AnchorStack) BlockId {
//         self.current_block += 1;
//         return self.current_block;
//     }
//
//     pub fn findOrCreateAnchor(
//         self: *AnchorStack,
//         name: []const u8,
//         source: std.builtin.SourceLocation,
//         parent: ?AnchorId,
//         depth: u32,
//     ) !AnchorId {
//         for (self.anchors.items, 0..) |anchor, index| {
//             if (anchor.source.line == source.line and
//                 std.mem.eql(u8, anchor.source.file, source.file) and
//                 std.mem.eql(u8, anchor.source.fn_name, source.fn_name) and
//                 std.mem.eql(u8, anchor.name, name))
//             {
//                 if (self.anchors.items[index].parent == null and parent != index) {
//                     self.anchors.items[index].parent = parent;
//                     self.anchors.items[index].depth = depth;
//                 }
//                 return index;
//             }
//         }
//
//         const id = self.anchors.items.len;
//         try self.anchors.append(self.allocator, .{
//             .name = name,
//             .source = source,
//             .parent = parent,
//             .depth = depth,
//         });
//         return id;
//     }
//
//     pub fn reset(self: *AnchorStack) void {
//         for (self.anchors.items) |*anchor| {
//             anchor.active_depth = 0;
//             anchor.totals = .{};
//         }
//         self.frames.clearRetainingCapacity();
//         self.current_frame = null;
//         self.current_block = 0;
//     }
//
//     pub fn pushFrame(
//         self: *AnchorStack,
//         anchor_id: AnchorId,
//         start_ticks: u64,
//         bytes: u64,
//     ) !FrameId {
//         const depth: u32 = @intCast(self.frames.items.len);
//         const parent = self.current_frame;
//         const recursive_depth = self.anchors.items[anchor_id].active_depth;
//
//         const frame_id = self.frames.items.len;
//         try self.frames.append(self.allocator, .{
//             .anchor = anchor_id,
//             .parent = parent,
//             .block = self.current_block,
//             .depth = depth,
//             .recursive_depth = recursive_depth,
//             .start_ticks = start_ticks,
//             .bytes = bytes,
//         });
//
//         self.anchors.items[anchor_id].active_depth += 1;
//         self.current_frame = frame_id;
//         return frame_id;
//     }
//
//     pub fn popFrame(self: *AnchorStack, frame_id: FrameId, end_ticks: u64) ScopeTotals {
//         std.debug.assert(self.current_frame == frame_id);
//
//         const frame = self.frames.items[frame_id];
//         std.debug.assert(self.anchors.items[frame.anchor].active_depth > 0);
//
//         const inclusive_ticks = end_ticks -| frame.start_ticks;
//         const exclusive_ticks = inclusive_ticks -| frame.child_inclusive_ticks;
//         const totals: ScopeTotals = .{
//             .calls = 1,
//             .recursive_calls = if (frame.recursive_depth > 0) 1 else 0,
//             .inclusive_ticks = if (frame.recursive_depth == 0) inclusive_ticks else 0,
//             .exclusive_ticks = exclusive_ticks,
//             .bytes = frame.bytes,
//         };
//
//         self.anchors.items[frame.anchor].totals.calls += totals.calls;
//         self.anchors.items[frame.anchor].totals.recursive_calls += totals.recursive_calls;
//         self.anchors.items[frame.anchor].totals.inclusive_ticks += totals.inclusive_ticks;
//         self.anchors.items[frame.anchor].totals.exclusive_ticks += totals.exclusive_ticks;
//         self.anchors.items[frame.anchor].totals.bytes += totals.bytes;
//
//         if (frame.parent) |parent| {
//             self.frames.items[parent].child_inclusive_ticks += inclusive_ticks;
//         }
//
//         self.anchors.items[frame.anchor].active_depth -= 1;
//         self.current_frame = frame.parent;
//         _ = self.frames.pop();
//
//         return totals;
//     }
// };
//
// pub const ProfileSnapshot = struct {
//     level: ProfileLevel,
//     timer_frequency: u64,
//     elapsed_ticks: u64,
//     anchors: []Anchor = &.{},
//
//     pub fn deinit(self: *ProfileSnapshot, allocator: std.mem.Allocator) void {
//         allocator.free(self.anchors);
//         self.* = undefined;
//     }
//
//     pub fn log(self: *const ProfileSnapshot) void {
//         stdoutPrint("PROFILER\n", .{});
//         stdoutPrint("| LEVEL | TIME MS |\n", .{});
//         stdoutPrint("| {s} | {d:.3} |\n", .{ @tagName(self.level), scaleTicksToMs(self.elapsed_ticks, self.timer_frequency) });
//
//         if (self.level != .deep) return;
//
//         stdoutPrint("\nZONES\n", .{});
//         stdoutPrint("| SCOPE | PARENT | CALLS | RECURSIVE | INCLUSIVE MS | EXCLUSIVE MS | EXCLUSIVE BYTES |\n", .{});
//         for (self.anchors, 0..) |anchor, index| {
//             _ = index;
//             const parent_name = if (anchor.parent) |parent| self.anchors[parent].name else "ROOT";
//             stdoutPrint(
//                 "| {s}{s} | {s} | {d} | {d} | {d:.3} | {d:.3} | {d} |\n",
//                 .{
//                     indentation(anchor.depth),
//                     anchor.name,
//                     parent_name,
//                     anchor.totals.calls,
//                     anchor.totals.recursive_calls,
//                     scaleTicksToMs(anchor.totals.inclusive_ticks, self.timer_frequency),
//                     scaleTicksToMs(anchor.totals.exclusive_ticks, self.timer_frequency),
//                     anchor.totals.bytes,
//                 },
//             );
//         }
//     }
// };
//
// pub const ProfilerConfig = struct {
//     level: ProfileLevel = configured_level,
// };
//
// pub const Profiler = ProfilerType(.{});
// pub const Zone = ZoneType(Profiler);
//
// pub fn ProfilerType(comptime config: ProfilerConfig) type {
//     const enabled = config.level != .none;
//     const collect_zones = config.level == .deep;
//
//     const State = if (enabled) struct {
//         stack: AnchorStack,
//         timer_frequency: u64,
//         elapsed_ticks: u64 = 0,
//         active_started_at: u64 = 0,
//     } else void;
//
//     return struct {
//         const Self = @This();
//
//         pub const level = config.level;
//         pub const is_enabled = enabled;
//         pub const collects_zones = collect_zones;
//
//         state: State,
//
//         pub fn init(allocator: std.mem.Allocator) Self {
//             if (!enabled) {
//                 return .{ .state = {} };
//             }
//
//             return .{ .state = .{
//                 .stack = .init(allocator),
//                 .timer_frequency = macTimerFrequency(),
//             } };
//         }
//
//         pub fn deinit(self: *Self) void {
//             if (!enabled) return;
//             self.state.stack.deinit();
//         }
//
//         pub fn reset(self: *Self) void {
//             if (!enabled) return;
//             self.state.stack.reset();
//             self.state.elapsed_ticks = 0;
//             self.state.active_started_at = 0;
//         }
//
//         pub fn beginRun(self: *Self) void {
//             if (!enabled) return;
//             _ = self.state.stack.beginBlock();
//             self.state.active_started_at = macTimerRead();
//         }
//
//         pub fn endRun(self: *Self) u64 {
//             if (!enabled) return 0;
//
//             const elapsed = macTimerRead() -| self.state.active_started_at;
//             self.state.elapsed_ticks += elapsed;
//             self.state.active_started_at = 0;
//             return elapsed;
//         }
//
//         pub fn beginBlock(self: *Self) BlockId {
//             if (!enabled) return 0;
//             return self.state.stack.beginBlock();
//         }
//
//         pub fn beginZone(
//             self: *Self,
//             name: []const u8,
//             bytes: u64,
//             source: std.builtin.SourceLocation,
//         ) ZoneType(Self) {
//             return ZoneType(Self).begin(self, name, bytes, source);
//         }
//
//         pub fn ticksToNs(self: *const Self, ticks: u64) u64 {
//             if (!enabled) return 0;
//             return scaleTicksToNs(ticks, self.state.timer_frequency);
//         }
//
//         pub fn ticksToMs(self: *const Self, ticks: u64) f64 {
//             if (!enabled) return 0;
//             return scaleTicksToMs(ticks, self.state.timer_frequency);
//         }
//
//         pub fn nsToTicks(self: *const Self, ns: u64) u64 {
//             if (!enabled) return 0;
//             return scaleNsToTicks(ns, self.state.timer_frequency);
//         }
//
//         pub fn snapshot(self: *const Self, allocator: std.mem.Allocator) !ProfileSnapshot {
//             if (!enabled) return .{ .level = .none, .timer_frequency = 1, .elapsed_ticks = 0 };
//
//             const anchors = if (collect_zones)
//                 try allocator.dupe(Anchor, self.state.stack.anchors.items)
//             else
//                 try allocator.alloc(Anchor, 0);
//
//             return .{
//                 .level = level,
//                 .timer_frequency = self.state.timer_frequency,
//                 .elapsed_ticks = self.state.elapsed_ticks,
//                 .anchors = anchors,
//             };
//         }
//
//         pub fn log(self: *const Self) void {
//             if (!enabled) return;
//             const snapshot_value: ProfileSnapshot = .{
//                 .level = level,
//                 .timer_frequency = self.state.timer_frequency,
//                 .elapsed_ticks = self.state.elapsed_ticks,
//                 .anchors = if (collect_zones) self.state.stack.anchors.items else &.{},
//             };
//             snapshot_value.log();
//         }
//     };
// }
//
// pub fn ZoneType(comptime ProfilerT: type) type {
//     return struct {
//         const Self = @This();
//
//         profiler: ?*ProfilerT = null,
//         frame: ?FrameId = null,
//
//         pub fn begin(
//             profiler: *ProfilerT,
//             name: []const u8,
//             bytes: u64,
//             source: std.builtin.SourceLocation,
//         ) Self {
//             if (!ProfilerT.collects_zones) {
//                 return .{};
//             }
//
//             const parent_anchor = if (profiler.state.stack.current_frame) |frame_id|
//                 profiler.state.stack.frames.items[frame_id].anchor
//             else
//                 null;
//             const depth: u32 = if (profiler.state.stack.current_frame) |frame_id|
//                 profiler.state.stack.frames.items[frame_id].depth + 1
//             else
//                 0;
//             const anchor_id = profiler.state.stack.findOrCreateAnchor(name, source, parent_anchor, depth) catch @panic("profiler anchor allocation failed");
//             const frame_id = profiler.state.stack.pushFrame(anchor_id, macTimerRead(), bytes) catch @panic("profiler frame allocation failed");
//             return .{ .profiler = profiler, .frame = frame_id };
//         }
//
//         pub fn end(self: *Self) void {
//             if (!ProfilerT.collects_zones) return;
//             const profiler = self.profiler orelse return;
//             const frame = self.frame orelse return;
//
//             _ = profiler.state.stack.popFrame(frame, macTimerRead());
//             self.* = .{};
//         }
//     };
// }
//
// pub const Benchmark = struct {
//     allocator: std.mem.Allocator,
//     config: Config,
//     profiler: Profiler,
//     best_profile: ?ProfileSnapshot = null,
//
//     pub const Config = struct {
//         name: []const u8 = "benchmark",
//         max_iterations: ?usize = 1,
//         max_time_without_new_min_ns: ?u64 = null,
//     };
//
//     pub const Status = enum {
//         skipped,
//         completed,
//     };
//
//     pub const Result = struct {
//         status: Status,
//         iterations: usize = 0,
//         failures: usize = 0,
//         timings: TimeStats = .{},
//         min_iteration_ns: ?u64 = null,
//     };
//
//     pub fn Callback(comptime Context: type) type {
//         return *const fn (ctx: ?*Context, profiler: *Profiler) anyerror!void;
//     }
//
//     pub fn init(allocator: std.mem.Allocator, config: Config) Benchmark {
//         return .{
//             .allocator = allocator,
//             .config = config,
//             .profiler = .init(allocator),
//         };
//     }
//
//     pub fn deinit(self: *Benchmark) void {
//         if (self.best_profile) |*snapshot_value| {
//             snapshot_value.deinit(self.allocator);
//         }
//         self.profiler.deinit();
//         self.* = undefined;
//     }
//
//     pub fn log(self: *const Benchmark, result: Result) void {
//         stdoutPrint("BENCHMARK RUNS\n", .{});
//         stdoutPrint("| NAME | RUNS | FAILS |\n", .{});
//         stdoutPrint("| {s} | {d} | {d} |\n", .{ self.config.name, result.iterations, result.failures });
//
//         stdoutPrint("\nMEASUREMENTS\n", .{});
//         stdoutPrint("| KIND | MIN MS | MAX MS | AVG MS |\n", .{});
//         stdoutPrint(
//             "| TIME | {d:.3} | {d:.3} | {d:.3} |\n",
//             .{
//                 if (result.timings.min_ticks) |ticks| self.profiler.ticksToMs(ticks) else 0,
//                 self.profiler.ticksToMs(result.timings.max_ticks),
//                 self.profiler.ticksToMs(result.timings.avgTicks()),
//             },
//         );
//
//         if (Profiler.collects_zones) {
//             if (self.best_profile) |snapshot_value| {
//                 stdoutPrint("\nBEST PROFILE\n", .{});
//                 snapshot_value.log();
//             }
//         }
//     }
//
//     pub fn run(
//         self: *Benchmark,
//         comptime Context: type,
//         ctx: ?*Context,
//         callback: Callback(Context),
//     ) !Result {
//         if (!bench_enabled) return .{ .status = .skipped };
//         if (self.config.max_iterations == null and self.config.max_time_without_new_min_ns == null) {
//             return error.UnboundedBenchmark;
//         }
//         if (!Profiler.is_enabled and self.config.max_time_without_new_min_ns != null) {
//             return error.BenchmarkTimerDisabled;
//         }
//
//         var result: Result = .{ .status = .completed };
//         var ticks_without_new_min: u64 = 0;
//         const max_ticks_without_new_min = if (self.config.max_time_without_new_min_ns) |ns| self.profiler.nsToTicks(ns) else null;
//
//         while (self.config.max_iterations == null or result.iterations < self.config.max_iterations.?) {
//             self.profiler.reset();
//             self.profiler.beginRun();
//             const failed = if (callback(ctx, &self.profiler)) |_| false else |_| failed: {
//                 result.failures += 1;
//                 break :failed true;
//             };
//             const elapsed_ticks = self.profiler.endRun();
//
//             result.iterations += 1;
//             if (Profiler.is_enabled) {
//                 if (failed) {
//                     if (max_ticks_without_new_min) |limit| {
//                         ticks_without_new_min += elapsed_ticks;
//                         if (ticks_without_new_min >= limit) break;
//                     }
//                     continue;
//                 }
//
//                 const is_new_min = result.timings.add(elapsed_ticks);
//                 if (is_new_min) {
//                     result.min_iteration_ns = self.profiler.ticksToNs(elapsed_ticks);
//                     ticks_without_new_min = 0;
//
//                     if (Profiler.collects_zones) {
//                         if (self.best_profile) |*snapshot_value| {
//                             snapshot_value.deinit(self.allocator);
//                             self.best_profile = null;
//                         }
//                         self.best_profile = try self.profiler.snapshot(self.allocator);
//                     }
//                 } else if (max_ticks_without_new_min) |limit| {
//                     ticks_without_new_min += elapsed_ticks;
//                     if (ticks_without_new_min >= limit) break;
//                 }
//             }
//         }
//
//         return result;
//     }
// };
//
// fn scaleTicksToNs(ticks: u64, frequency: u64) u64 {
//     return @intCast((@as(u128, ticks) * std.time.ns_per_s) / frequency);
// }
//
// fn scaleTicksToMs(ticks: u64, frequency: u64) f64 {
//     return @as(f64, @floatFromInt(ticks)) * 1000.0 / @as(f64, @floatFromInt(frequency));
// }
//
// fn scaleNsToTicks(ns: u64, frequency: u64) u64 {
//     return @intCast((@as(u128, ns) * frequency) / std.time.ns_per_s);
// }
//
// fn indentation(depth: u32) []const u8 {
//     return switch (@min(depth, 8)) {
//         0 => "",
//         1 => "  ",
//         2 => "    ",
//         3 => "      ",
//         4 => "        ",
//         5 => "          ",
//         6 => "            ",
//         7 => "              ",
//         else => "                ",
//     };
// }
//
// fn stdoutPrint(comptime format: []const u8, args: anytype) void {
//     var buffer: [4096]u8 = undefined;
//     const text = std.fmt.bufPrint(&buffer, format, args) catch return;
//     writeAllStdout(text);
// }
//
// fn writeAllStdout(bytes: []const u8) void {
//     var written: usize = 0;
//     while (written < bytes.len) {
//         const amount = std.c.write(std.posix.STDOUT_FILENO, bytes[written..].ptr, bytes.len - written);
//         if (amount <= 0) return;
//         written += @intCast(amount);
//     }
// }
//
// fn macTimerFrequency() u64 {
//     comptime assertMacTimerSupported();
//
//     var val: u64 = undefined;
//     asm volatile ("mrs %[val], cntfrq_el0"
//         : [val] "=r" (val),
//     );
//     return val;
// }
//
// fn macTimerRead() u64 {
//     comptime assertMacTimerSupported();
//
//     var val: u64 = undefined;
//     asm volatile ("mrs %[val], cntvct_el0"
//         : [val] "=r" (val),
//     );
//     return val;
// }
//
// fn assertMacTimerSupported() void {
//     if (builtin.os.tag != .macos or builtin.cpu.arch != .aarch64) {
//         @compileError("Odyssey profiler currently requires the macOS aarch64 virtual counter timer");
//     }
// }
