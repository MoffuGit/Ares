const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const time = @import("time.zig");

pub const ProfileLevel = enum {
    none,
    general,
    deep,
};

pub fn Profiler(comptime profile_level: ProfileLevel) type {
    if (profile_level == .none) {
        return struct {
            const Self = @This();

            pub fn init(self: *Self, _: Io, _: Allocator) void {
                self.* = .{};
            }

            pub fn deinit(_: *Self) void {}

            pub fn reset(_: *Self) void {}

            pub fn sample(_: *const Self) Sample(profile_level) {
                return .{};
            }

            pub fn beginZone(
                self: *Self,
                name: []const u8,
                source: std.builtin.SourceLocation,
            ) Zone(profile_level) {
                return Zone(profile_level).begin(self, name, source);
            }

            pub fn log(_: *const Self, _: Io, _: Io.File) !void {}
        };
    }

    return struct {
        const Self = @This();

        gpa: Allocator = undefined,
        io: Io = undefined,
        rwlock: Io.RwLock = .init,
        threads: std.AutoHashMapUnmanaged(u64, *Thread) = .empty,
        start: u64 = 0,

        pub fn init(self: *Self, io: Io, gpa: Allocator) void {
            self.* = .{
                .gpa = gpa,
                .io = io,
                .rwlock = .init,
                .threads = .empty,
                .start = time.timer(),
            };
        }

        pub fn deinit(self: *Self) void {
            var it = self.threads.valueIterator();
            while (it.next()) |thread_ptr| {
                thread_ptr.*.deinit();
                self.gpa.destroy(thread_ptr.*);
            }
            self.threads.deinit(self.gpa);
            self.* = .{};
        }

        pub fn reset(self: *Self) void {
            self.rwlock.lockUncancelable(self.io);
            defer self.rwlock.unlock(self.io);

            var it = self.threads.valueIterator();
            while (it.next()) |thread_ptr| {
                thread_ptr.*.reset();
            }
            self.start = time.timer();
        }

        pub fn sample(self: *const Self) Sample(profile_level) {
            return .{
                .time = time.timer() - self.start,
            };
        }

        pub fn beginZone(
            self: *Self,
            name: []const u8,
            source: std.builtin.SourceLocation,
        ) Zone(profile_level) {
            return Zone(profile_level).begin(self, name, source);
        }

        pub fn threadState(self: *Self) !*Thread {
            const tid: u64 = @intCast(std.Thread.getCurrentId());

            self.rwlock.lockSharedUncancelable(self.io);
            if (self.threads.get(tid)) |t| {
                self.rwlock.unlockShared(self.io);
                return t;
            }
            self.rwlock.unlockShared(self.io);

            self.rwlock.lockUncancelable(self.io);
            defer self.rwlock.unlock(self.io);

            if (self.threads.get(tid)) |t| return t;

            const thread = try self.gpa.create(Thread);
            errdefer self.gpa.destroy(thread);
            thread.* = Thread.init(self.gpa);
            errdefer thread.deinit();

            try self.threads.put(self.gpa, tid, thread);
            return thread;
        }

        pub fn log(_: *const Self, _: Io, _: Io.File) !void {}
    };
}

pub fn Zone(comptime profile_level: ProfileLevel) type {
    if (profile_level != .deep) {
        return struct {
            const Self = @This();

            pub fn begin(
                _: *Profiler(profile_level),
                _: []const u8,
                _: std.builtin.SourceLocation,
            ) Self {
                return .{};
            }

            pub fn end(_: *Self) void {}

            pub fn log(
                _: *const Self,
                _: Io,
                _: Io.File,
            ) !void {}
        };
    }

    return struct {
        const Self = @This();

        state: ?*Thread = null,
        anchor_index: ?u32 = null,
        frame_index: ?u32 = null,

        pub fn begin(
            profiler: *Profiler(profile_level),
            name: []const u8,
            source: std.builtin.SourceLocation,
        ) Self {
            const state = profiler.threadState() catch
                @panic("profiler thread state allocation failed");

            const parent_anchor: ?u32 = if (state.current_frame) |fi|
                state.frames.items[fi].anchor
            else
                null;
            const depth: u32 = if (state.current_frame) |fi|
                state.frames.items[fi].depth + 1
            else
                0;

            const anchor_id = state.findOrCreateAnchor(name, source, parent_anchor, depth) catch
                @panic("profiler anchor allocation failed");
            const frame_id = state.pushFrame(anchor_id, time.timer()) catch
                @panic("profiler frame allocation failed");

            return .{
                .state = state,
                .anchor_index = anchor_id,
                .frame_index = frame_id,
            };
        }

        pub fn end(self: *Self) void {
            const state = self.state orelse return;
            const frame = self.frame_index orelse return;
            _ = state.popFrame(frame, time.timer());
            self.frame_index = null;
            self.state = null;
            self.anchor_index = null;
        }

        pub fn log(self: *const Self, io: Io, file: Io.File) !void {
            const state = self.state orelse return;
            const anchor_idx = self.anchor_index orelse return;

            var buffer: [4096]u8 = undefined;
            var w: Io.File.Writer = .init(file, io, &buffer);
            const writer: *Io.Writer = &w.interface;
            defer writer.flush() catch {};

            const now = time.timer();

            try printAnchor(writer, state, anchor_idx, now, 0);
        }

        pub fn logTree(self: *const Self, io: Io, file: Io.File) !void {
            const state = self.state orelse return;
            const anchor_idx = self.anchor_index orelse return;

            var buffer: [4096]u8 = undefined;
            var w: Io.File.Writer = .init(file, io, &buffer);
            const writer: *Io.Writer = &w.interface;
            defer writer.flush() catch {};

            const now = time.timer();

            try printAnchor(writer, state, anchor_idx, now, 0);
            try printChildren(writer, state, anchor_idx, now, 1);
        }
    };
}

/// `anchor.totals` only reflects completed invocations. Add the in-progress
/// contribution of every currently-active frame bound to this anchor so the
/// caller sees the live picture mid-zone.
fn liveTotals(state: *Thread, idx: u32, now: u64) ScopeTotals {
    var totals = state.anchors.items[idx].totals;
    for (state.frames.items) |f| {
        if (f.anchor != idx) continue;
        const inc = now -| f.start_ticks;
        const exc = inc -| f.child_inclusive_ticks;
        totals.calls += 1;
        if (f.recursive_depth > 0) {
            totals.recursive_calls += 1;
        } else {
            totals.inclusive_ticks += inc;
        }
        totals.exclusive_ticks += exc;
    }
    return totals;
}

fn printAnchor(writer: *Io.Writer, state: *Thread, idx: u32, now: u64, indent: u32) !void {
    const anchor = state.anchors.items[idx];
    const totals = liveTotals(state, idx, now);
    try writer.splatByteAll(' ', @as(usize, indent) * 2);
    try writer.print("{s}: calls={d} inclusive={f} exclusive={f}\n", .{
        anchor.name,
        totals.calls,
        time.Duration.fromTicks(totals.inclusive_ticks),
        time.Duration.fromTicks(totals.exclusive_ticks),
    });
}

fn printChildren(writer: *Io.Writer, state: *Thread, parent_idx: u32, now: u64, indent: u32) !void {
    for (state.anchors.items, 0..) |a, i| {
        const p = a.parent orelse continue;
        if (p != parent_idx) continue;
        const child_idx: u32 = @intCast(i);
        try printAnchor(writer, state, child_idx, now, indent);
        try printChildren(writer, state, child_idx, now, indent + 1);
    }
}

pub fn Sample(comptime profile_level: ProfileLevel) type {
    if (profile_level == .none) {
        return struct {
            const Self = @This();
            pub fn sort(_: void, _: Self, _: Self) bool {
                return false;
            }
        };
    }

    return struct {
        const Self = @This();
        time: u64,
        pub fn sort(_: void, a: Self, b: Self) bool {
            return a.time < b.time;
        }
    };
}

pub const Thread = struct {
    const Self = @This();

    gpa: Allocator,
    anchors: std.ArrayList(Anchor),
    frames: std.ArrayList(Frame),
    current_frame: ?u32,

    pub fn init(gpa: Allocator) Self {
        return .{
            .gpa = gpa,
            .anchors = .empty,
            .frames = .empty,
            .current_frame = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.anchors.deinit(self.gpa);
        self.frames.deinit(self.gpa);
        self.* = undefined;
    }

    pub fn reset(self: *Self) void {
        for (self.anchors.items) |*anchor| {
            anchor.active_depth = 0;
            anchor.totals = .{};
        }
        self.frames.clearRetainingCapacity();
        self.current_frame = null;
    }

    pub fn findOrCreateAnchor(
        self: *Self,
        name: []const u8,
        source: std.builtin.SourceLocation,
        parent: ?u32,
        depth: u32,
    ) !u32 {
        for (self.anchors.items, 0..) |anchor, index| {
            if (anchor.source.line == source.line and
                std.mem.eql(u8, anchor.source.file, source.file) and
                std.mem.eql(u8, anchor.source.fn_name, source.fn_name) and
                std.mem.eql(u8, anchor.name, name))
            {
                if (self.anchors.items[index].parent == null and parent != @as(u32, @intCast(index))) {
                    self.anchors.items[index].parent = parent;
                    self.anchors.items[index].depth = depth;
                }
                return @intCast(index);
            }
        }

        const id: u32 = @intCast(self.anchors.items.len);
        try self.anchors.append(self.gpa, .{
            .name = name,
            .source = source,
            .parent = parent,
            .depth = depth,
        });
        return id;
    }

    pub fn pushFrame(
        self: *Self,
        anchor_id: u32,
        start_ticks: u64,
    ) !u32 {
        const depth: u32 = @intCast(self.frames.items.len);
        const parent = self.current_frame;
        const recursive_depth = self.anchors.items[anchor_id].active_depth;

        const frame_id: u32 = @intCast(self.frames.items.len);
        try self.frames.append(self.gpa, .{
            .anchor = anchor_id,
            .parent = parent,
            .depth = depth,
            .recursive_depth = recursive_depth,
            .start_ticks = start_ticks,
        });

        self.anchors.items[anchor_id].active_depth += 1;
        self.current_frame = frame_id;
        return frame_id;
    }

    pub fn popFrame(self: *Self, frame_id: u32, end_ticks: u64) ScopeTotals {
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
        };

        const anchor = &self.anchors.items[frame.anchor];
        anchor.totals.calls += totals.calls;
        anchor.totals.recursive_calls += totals.recursive_calls;
        anchor.totals.inclusive_ticks += totals.inclusive_ticks;
        anchor.totals.exclusive_ticks += totals.exclusive_ticks;

        if (frame.parent) |parent| {
            self.frames.items[parent].child_inclusive_ticks += inclusive_ticks;
        }

        anchor.active_depth -= 1;
        self.current_frame = frame.parent;
        _ = self.frames.pop();

        return totals;
    }
};

pub const Frame = struct {
    anchor: u32,
    parent: ?u32,
    depth: u32,
    recursive_depth: u32,
    start_ticks: u64,
    child_inclusive_ticks: u64 = 0,
    totals: ScopeTotals = .{},
};

pub const Anchor = struct {
    name: []const u8,
    source: std.builtin.SourceLocation,
    parent: ?u32 = null,
    depth: u32 = 0,
    active_depth: u32 = 0,
    totals: ScopeTotals = .{},
};

pub const ScopeTotals = struct {
    calls: u64 = 0,
    recursive_calls: u64 = 0,
    inclusive_ticks: u64 = 0,
    exclusive_ticks: u64 = 0,
};
