const std = @import("std");
const builtin = @import("builtin");
const time = @import("time.zig");
const mod = @import("mod.zig");
const print = @import("print.zig");

pub const ProfileLevel = enum {
    none,
    general,
    deep,
};

pub const ScopeTotals = struct {
    calls: u64 = 0,
    recursive_calls: u64 = 0,
    inclusive_ticks: u64 = 0,
    exclusive_ticks: u64 = 0,
    bytes: u64 = 0,
};

pub const Anchor = struct {
    name: []const u8,
    source: std.builtin.SourceLocation,
    parent: ?u64 = null,
    depth: u32 = 0,
    active_depth: u32 = 0,
    totals: ScopeTotals = .{},
};

pub const Frame = struct {
    anchor: u64,
    parent: ?u64,
    depth: u32,
    recursive_depth: u32,
    start_ticks: u64,
    child_inclusive_ticks: u64 = 0,
    bytes: u64,
    totals: ScopeTotals = .{},
};

pub const AnchorStack = struct {
    allocator: std.mem.Allocator,
    anchors: std.ArrayList(Anchor) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    current_frame: ?u64 = null,

    pub fn init(allocator: std.mem.Allocator) AnchorStack {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *AnchorStack) void {
        self.frames.deinit(self.allocator);
        self.anchors.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn findOrCreateAnchor(
        self: *AnchorStack,
        name: []const u8,
        source: std.builtin.SourceLocation,
        parent: ?u64,
        depth: u32,
    ) !u64 {
        for (self.anchors.items, 0..) |anchor, index| {
            if (anchor.source.line == source.line and
                std.mem.eql(u8, anchor.source.file, source.file) and
                std.mem.eql(u8, anchor.source.fn_name, source.fn_name) and
                std.mem.eql(u8, anchor.name, name))
            {
                if (self.anchors.items[index].parent == null and parent != index) {
                    self.anchors.items[index].parent = parent;
                    self.anchors.items[index].depth = depth;
                }
                return index;
            }
        }

        const id = self.anchors.items.len;
        try self.anchors.append(self.allocator, .{
            .name = name,
            .source = source,
            .parent = parent,
            .depth = depth,
        });
        return id;
    }

    pub fn reset(self: *AnchorStack) void {
        for (self.anchors.items) |*anchor| {
            anchor.active_depth = 0;
            anchor.totals = .{};
        }
        self.frames.clearRetainingCapacity();
        self.current_frame = null;
    }

    pub fn pushFrame(
        self: *AnchorStack,
        anchor_id: u64,
        start_ticks: u64,
        bytes: u64,
    ) !u64 {
        const depth: u32 = @intCast(self.frames.items.len);
        const parent = self.current_frame;
        const recursive_depth = self.anchors.items[anchor_id].active_depth;

        const frame_id = self.frames.items.len;
        try self.frames.append(self.allocator, .{
            .anchor = anchor_id,
            .parent = parent,
            .depth = depth,
            .recursive_depth = recursive_depth,
            .start_ticks = start_ticks,
            .bytes = bytes,
        });

        self.anchors.items[anchor_id].active_depth += 1;
        self.current_frame = frame_id;
        return frame_id;
    }

    pub fn popFrame(self: *AnchorStack, frame_id: u64, end_ticks: u64) ScopeTotals {
        std.debug.assert(self.current_frame == frame_id);

        const frame = self.frames.items[frame_id];
        std.debug.assert(self.anchors.items[frame.anchor].active_depth > 0);

        const inclusive_ticks = end_ticks -| frame.start_ticks;
        const exclusive_ticks = inclusive_ticks -| frame.child_inclusive_ticks;
        const totals: ScopeTotals = .{
            .calls = 1,
            .recursive_calls = if (frame.recursive_depth > 0) 1 else 0,
            .inclusive_ticks = if (frame.recursive_depth == 0) inclusive_ticks else 0,
            .exclusive_ticks = exclusive_ticks,
            .bytes = frame.bytes,
        };

        self.anchors.items[frame.anchor].totals.calls += totals.calls;
        self.anchors.items[frame.anchor].totals.recursive_calls += totals.recursive_calls;
        self.anchors.items[frame.anchor].totals.inclusive_ticks += totals.inclusive_ticks;
        self.anchors.items[frame.anchor].totals.exclusive_ticks += totals.exclusive_ticks;
        self.anchors.items[frame.anchor].totals.bytes += totals.bytes;

        if (frame.parent) |parent| {
            self.frames.items[parent].child_inclusive_ticks += inclusive_ticks;
        }

        self.anchors.items[frame.anchor].active_depth -= 1;
        self.current_frame = frame.parent;
        _ = self.frames.pop();

        return totals;
    }
};

pub const ProfilerConfig = struct {
    level: ProfileLevel,
};

pub fn Profiler(comptime config: ProfilerConfig) type {
    const enabled = config.level != .none;
    const collect_zones = config.level == .deep;

    if (!enabled) {
        return struct {
            pub const level = config.level;
            pub const is_enabled = enabled;
            pub const collects_zones = collect_zones;

            const Self = @This();

            pub fn init(self: *Self, _: std.mem.Allocator) void {
                self.* = .{};
            }

            pub fn deinit(_: *Self) void {}

            pub fn reset(_: *Self) void {}

            pub fn sample(_: *const Self) Sample(Self) {}

            pub fn beginZone(
                self: *Self,
                name: []const u8,
                bytes: u64,
                source: std.builtin.SourceLocation,
            ) Zone(Self) {
                return Zone(Self).begin(self, name, bytes, source);
            }

            pub fn log(_: *const Self) void {}
        };
    }

    return struct {
        const Self = @This();

        pub const level = config.level;
        pub const is_enabled = enabled;
        pub const collects_zones = collect_zones;

        stack: AnchorStack,
        start: u64 = 0,

        pub fn init(self: *Self, allocator: std.mem.Allocator) void {
            self.* = .{
                .stack = .init(allocator),
                .start = time.timer(),
            };
        }

        pub fn deinit(self: *Self) void {
            self.stack.deinit();
        }

        pub fn reset(self: *Self) void {
            self.stack.reset();
            self.start = 0;
        }

        pub fn beginZone(
            self: *Self,
            name: []const u8,
            bytes: u64,
            source: std.builtin.SourceLocation,
        ) Zone(Self) {
            return Zone(Self).begin(self, name, bytes, source);
        }

        pub fn sample(self: *const Self) Sample(Self) {
            return .{
                .time = time.timer() - self.start,
            };
        }

        pub fn log(_: *const Self) void {
            // return .{
            //     .level = level,
            //     .ticks = time.timer() - self.state.start,
            //     .anchors = self.state.stack.anchors.items,
            // };
            // const freq_f = @as(f64, @floatFromInt(time.timerFreq()));
            // const min_ms: f64 = 1000.0 * @as(f64, @floatFromInt(self.ticks)) / freq_f;
        }
    };
}

pub fn Sample(comptime ProfilerType: type) type {
    if (!ProfilerType.is_enabled) {
        return struct {};
    }

    return struct {
        time: u64,
    };
}

pub fn Zone(comptime ProfilerType: type) type {
    if (!ProfilerType.is_enabled) {
        return struct {
            const Self = @This();

            pub fn begin(
                _: *ProfilerType,
                _: []const u8,
                _: u64,
                _: std.builtin.SourceLocation,
            ) Self {
                return .{};
            }

            pub fn end(_: *Self) void {}
        };
    }

    return struct {
        const Self = @This();

        profiler: ?*ProfilerType = null,
        frame: ?u64 = null,

        pub fn begin(
            profiler: *ProfilerType,
            name: []const u8,
            bytes: u64,
            source: std.builtin.SourceLocation,
        ) Self {
            if (!ProfilerType.collects_zones) {
                return .{};
            }

            const parent_anchor = if (profiler.stack.current_frame) |frame_id|
                profiler.stack.frames.items[frame_id].anchor
            else
                null;
            const depth: u32 = if (profiler.stack.current_frame) |frame_id|
                profiler.stack.frames.items[frame_id].depth + 1
            else
                0;
            const anchor_id = profiler.stack.findOrCreateAnchor(name, source, parent_anchor, depth) catch @panic("profiler anchor allocation failed");
            const frame_id = profiler.stack.pushFrame(anchor_id, time.timer(), bytes) catch @panic("profiler frame allocation failed");
            return .{ .profiler = profiler, .frame = frame_id };
        }

        pub fn end(self: *Self) void {
            if (!ProfilerType.collects_zones) return;
            const profiler = self.profiler orelse return;
            const frame = self.frame orelse return;

            _ = profiler.stack.popFrame(frame, time.timer());
            self.* = .{};
        }
    };
}
