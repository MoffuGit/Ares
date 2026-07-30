// SOURCE: https://github.com/EpicGames/raddebugger
// LICENSE: [RADDEBUGGER]

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;

const Buffer = @import("buffer.zig");
const Info = Buffer.Info;
const datastruct = @import("datastruct.zig");
const mem_map = datastruct.mem_map;
const MemMap = mem_map.MemMap;
const Queue = datastruct.Queue;
const math = @import("math.zig");
const Rngu64 = math.Rngu64;

const log = std.log.scoped(.patch);

pub inline fn delta(a: u64, d: i64) u64 {
    return @intCast(@as(i64, @intCast(a)) + d);
}

pub const Patch = struct {
    replace: []u8,
    range: Rngu64,

    next: ?*Patch = null,
};

pub const PatchList = struct {
    list: Queue(Patch) = .{},

    pub fn push(self: *PatchList, range: Rngu64, replace: []u8, alloc: Allocator) !void {
        const patch = try alloc.create(Patch);
        patch.* = .{
            .range = range,
            .replace = replace,
        };
        self.list.push(patch);
    }
};

pub const Line = struct {
    memmap_ranges: []Rngu64,
    range: Rngu64,
    delta: i64,

    next: ?*Line = null,

    pub fn new(ranges: []Rngu64, range: Rngu64, d: i64) Line {
        return .{ .memmap_ranges = ranges, .range = range, .delta = d };
    }
};

pub const LineMap = struct {
    lines: Queue(Line) = .{},
    total: u64 = 0,

    pub fn push(
        self: *LineMap,
        line: Line,
        arena: Allocator,
    ) !void {
        const l = try arena.create(Line);
        l.* = line;

        self.total += l.range.dim();
        self.lines.push(l);
    }

    pub fn rngForLine(self: *const LineMap, line: u64) Rngu64 {
        var res: Rngu64 = undefined;
        var node = self.lines.head;
        while (node) |n| : (node = n.next) {
            if (n.range.contains(line)) {
                res = n.memmap_ranges[line - n.range.min];
                res.min = delta(res.min, n.delta);
                res.max = delta(res.max, n.delta);
                break;
            }
        }

        return res;
    }

    pub fn lineFromOffset(self: *const LineMap, off: u64) u64 {
        var res: u64 = 0;

        bkl: {
            var node = self.lines.head;
            while (node) |n| : (node = n.next) {
                if (n.range.empty()) continue;

                const off_range: Rngu64 = .new(
                    delta(n.memmap_ranges[0].min, n.delta),
                    delta(n.memmap_ranges[n.range.max - n.range.min - 1].max, n.delta),
                );

                if (!off_range.contains(off)) continue;

                var min_idx: u64 = 0;
                var max_idx = n.range.dim() - 1;

                while (min_idx <= max_idx) {
                    const mid_idx = (max_idx + min_idx) / 2;

                    const memmap_range = n.memmap_ranges[mid_idx];
                    const max_range = delta(memmap_range.max, n.delta);
                    const min_range = delta(memmap_range.min, n.delta);

                    if (max_range < off) min_idx = mid_idx + 1;
                    if (off < min_range) max_idx = mid_idx - 1;
                    if (min_range <= off and off <= max_range) {
                        res = n.range.min + mid_idx;
                        break :bkl;
                    }
                }
            }
        }

        return res;
    }
};

pub const Patched = struct {
    linemap: LineMap,
    memmap: MemMap,
    size: u64,

    pub fn init(buffer: []u8, info: Info, patch_list: PatchList, arena: Allocator) !Patched {
        var last_memmap: MemMap = .{};
        var last_linemap: LineMap = .{};
        var last_size: usize = buffer.len;

        try last_memmap.push(.new(0, buffer.len), buffer.ptr, arena);
        try last_linemap.push(.new(info.line_ranges, .new(1, info.line_count + 1), 0), arena);

        var node = patch_list.list.head;

        while (node) |n| : (node = n.next) {
            var next_memory_map: MemMap = .{};
            var next_line_map: LineMap = .{};

            const pre_range: Rngu64 = .new(0, n.range.min);
            const post_range: Rngu64 = .new(n.range.max, last_size);

            var replace_line_num_range: Rngu64 = .new(
                last_linemap.lineFromOffset(n.range.min),
                last_linemap.lineFromOffset(n.range.max),
            );

            const pre_line_num_range: Rngu64 = .new(1, replace_line_num_range.min);
            const post_line_num_range: Rngu64 = .new(replace_line_num_range.max + 1, last_linemap.total + 1);
            const size_delta: i64 = @as(i64, @intCast(n.replace.len)) - @as(i64, @intCast(n.range.dim()));
            const next_size: usize = @intCast(@as(i64, @intCast(last_size)) + size_delta);

            var line_delta: i64 = 0;
            var replace_line_range: Queue(math.Rngu64Node) = .{};
            var replaced_lines_count: u64 = 0;
            var last_line_start_off: u64 = 0;
            line_delta -= @intCast(replace_line_num_range.dim());
            for (n.replace, 0..) |c, idx| {
                if (c == '\n') {
                    line_delta += 1;
                    const line_range: Rngu64 = .new(last_line_start_off, idx);
                    const new_range_node = try arena.create(math.Rngu64Node);
                    new_range_node.range = line_range;
                    last_line_start_off += 1;
                    replace_line_range.push(new_range_node);
                    replaced_lines_count += 1;
                }
            }
            const new_range_node = try arena.create(math.Rngu64Node);
            new_range_node.* = .{ .range = .new(last_line_start_off, n.replace.len) };

            replace_line_range.push(new_range_node);
            replaced_lines_count += 1;

            var map_node = last_memmap.ranges.head;
            while (map_node) |map_n| : (map_node = map_n.next) {
                const range_x_pre: Rngu64 = .intersect(pre_range, map_n.vaddr_range);
                const range_x_post: Rngu64 = .intersect(post_range, map_n.vaddr_range);

                if (range_x_pre.max > range_x_pre.min) {
                    const off: usize = @intCast(range_x_pre.min - map_n.vaddr_range.min);
                    try next_memory_map.push(range_x_pre, map_n.base + off, arena);
                }

                if (range_x_post.max > range_x_post.min) {
                    const range_x_post_shifted: Rngu64 = .new(
                        delta(range_x_post.min, size_delta),
                        delta(range_x_post.max, size_delta),
                    );
                    const off: usize = @intCast(range_x_post.min - map_n.vaddr_range.min);
                    try next_memory_map.push(range_x_post_shifted, map_n.base + off, arena);
                }
            }

            if (n.replace.len != 0) {
                try next_memory_map.push(.new(n.range.min, n.range.min + n.replace.len), n.replace.ptr, arena);
            }

            {
                var line_map_node = last_linemap.lines.head;
                while (line_map_node) |line_map_n| : (line_map_node = line_map_n.next) {
                    const num_range = line_map_n.range;
                    const range_x_pre: Rngu64 = .intersect(pre_line_num_range, num_range);
                    const range_x_post: Rngu64 = .intersect(post_line_num_range, num_range);

                    if (!range_x_pre.empty()) {
                        const off: usize = @intCast(range_x_pre.min - num_range.min);
                        const dim: usize = @intCast(range_x_pre.max - range_x_pre.min);
                        try next_line_map.push(
                            .new(line_map_n.memmap_ranges[off .. off + dim], range_x_pre, line_map_n.delta),
                            arena,
                        );
                    }

                    if (!range_x_post.empty()) {
                        const range_x_post_shifted: Rngu64 = .new(
                            delta(range_x_post.min, line_delta),
                            delta(range_x_post.max, line_delta),
                        );
                        const off: usize = @intCast(range_x_post.min - num_range.min);
                        const dim: usize = @intCast(range_x_post.max - range_x_post.min);
                        try next_line_map.push(
                            .new(line_map_n.memmap_ranges[off .. off + dim], range_x_post_shifted, line_map_n.delta + size_delta),
                            arena,
                        );
                    }
                }
            }

            const affected_lines_ranges = try arena.alloc(Rngu64, replaced_lines_count);
            var line_node = replace_line_range.head;

            var affected_line_idx: u64 = 0;
            while (line_node) |line_n| : ({
                line_node = line_n.next;
                affected_line_idx += 1;
            }) {
                var affected_line_range: Rngu64 = .new(
                    line_n.range.min + n.range.min,
                    line_n.range.max + n.range.min,
                );

                // first line in the range -> take min from original line map
                if (affected_line_idx == 0) {
                    const og_line_range = last_linemap.rngForLine(replace_line_num_range.min);
                    affected_line_range.min = og_line_range.min;
                }

                // last line in the range -> take remaining suffix from original line map
                const clamped_line_delta: u64 = @intCast(@max(@as(i64, 0), line_delta));
                if (affected_line_idx == replaced_lines_count - 1 and affected_line_idx >= clamped_line_delta) {
                    const og_line_range = last_linemap.rngForLine(replace_line_num_range.max);
                    if (og_line_range.max > n.range.max) {
                        affected_line_range.max += og_line_range.max - n.range.max;
                    }
                }

                affected_lines_ranges[@intCast(affected_line_idx)] = affected_line_range;
            }

            try next_line_map.push(
                .new(affected_lines_ranges, .new(replace_line_num_range.min, replace_line_num_range.min + replaced_lines_count), 0),
                arena,
            );

            last_memmap = next_memory_map;
            last_size = next_size;
            last_linemap = next_line_map;
        }

        return .{
            .size = last_size,
            .linemap = last_linemap,
            .memmap = last_memmap,
        };
    }
};

test "Basic Patch Operations" {
    const gpa = testing.allocator;

    const line1 = "This line is about x chars long\n";
    const line2 = "This other line is aboyt y chars long\n";
    const line3 = "This line is kinda like z chars long\n";
    const line4 = "This last line is aboyt z chars long\n";
    const line5 = "\n";

    const text = line1 ++ line2 ++ line3 ++ line4 ++ line5;

    var a: std.heap.ArenaAllocator = .init(gpa);
    defer a.deinit();

    const arena = a.allocator();

    const buffer = try arena.dupe(u8, text);

    var info: Info = undefined;
    try info.init(buffer, arena);

    const path_list: PatchList = .{};
    const patched = try Patched.init(buffer, info, path_list, arena);

    try testing.expectEqual(3, patched.linemap.lineFromOffset(70));
    try testing.expectEqual(2, patched.linemap.lineFromOffset(69));

    const src_range = patched.linemap.rngForLine(2);
    const slice_line_2 = try patched.memmap.slice(src_range, arena);
    try testing.expectEqualStrings(line2[0 .. line2.len - 1], slice_line_2);
}

test "Patch Replace Same Size" {
    const gpa = testing.allocator;

    const line1 = "This line is about x chars long\n";
    const line2 = "This other line is aboyt y chars long\n";
    const line3 = "This line is kinda like z chars long\n";
    const line4 = "This last line is aboyt z chars long\n";
    const line5 = "\n";

    const text = line1 ++ line2 ++ line3 ++ line4 ++ line5;

    var a: std.heap.ArenaAllocator = .init(gpa);
    defer a.deinit();

    const arena = a.allocator();

    const buffer = try arena.dupe(u8, text);
    var info: Info = undefined;
    try info.init(buffer, arena);

    // Replace "aboyt" (5 chars) with "about" (5 chars) in line 2 at offset 51
    var patch_list: PatchList = .{};
    try patch_list.push(.new(51, 56), try arena.dupe(u8, "about"), arena);

    const patched = try Patched.init(buffer, info, patch_list, arena);

    const expected = "This line is about x chars long\nThis other line is about y chars long\nThis line is kinda like z chars long\nThis last line is aboyt z chars long\n\n";
    const result = try patched.memmap.slice(.new(0, @intCast(patched.size)), arena);
    try testing.expectEqualStrings(expected, result);
}

test "Patch Replace Different Size" {
    const gpa = testing.allocator;

    const line1 = "This line is about x chars long\n";
    const line2 = "This other line is aboyt y chars long\n";
    const line3 = "This line is kinda like z chars long\n";
    const line4 = "This last line is aboyt z chars long\n";
    const line5 = "\n";

    const text = line1 ++ line2 ++ line3 ++ line4 ++ line5;

    var a: std.heap.ArenaAllocator = .init(gpa);
    defer a.deinit();

    const arena = a.allocator();

    const buffer = try arena.dupe(u8, text);
    var info: Info = undefined;
    try info.init(buffer, arena);

    // Replace "x" (1 char) at offset 22 in line 1 with "LOTS OF " (8 chars)
    var patch_list: PatchList = .{};
    try patch_list.push(.new(19, 20), try arena.dupe(u8, "LOTS OF "), arena);

    const patched = try Patched.init(buffer, info, patch_list, arena);

    const expected = "This line is about LOTS OF  chars long\nThis other line is aboyt y chars long\nThis line is kinda like z chars long\nThis last line is aboyt z chars long\n\n";
    const result = try patched.memmap.slice(.new(0, @intCast(patched.size)), arena);
    try testing.expectEqualStrings(expected, result);
}

test "Patch Overlapping Twice" {
    const gpa = testing.allocator;

    const text = "normal test\n";

    var a: std.heap.ArenaAllocator = .init(gpa);
    defer a.deinit();

    const arena = a.allocator();

    const buffer = try arena.dupe(u8, text);
    var info: Info = undefined;
    try info.init(buffer, arena);

    // Patch 1: replace "normal" (offset 0-6) with "patched"
    //   -> "patched test\n"
    // Patch 2: replace "patched" (offset 0-7 in post-patch-1 state) with "normal patched twice"
    //   -> "normal patched twice test\n"
    // The two patches overlap: patch 2's range covers the area patch 1 just modified.
    var patch_list: PatchList = .{};
    try patch_list.push(.new(0, 6), try arena.dupe(u8, "patched"), arena);
    try patch_list.push(.new(0, 7), try arena.dupe(u8, "normal patched twice"), arena);

    const patched = try Patched.init(buffer, info, patch_list, arena);

    const expected = "normal patched twice test\n";
    const result = try patched.memmap.slice(.new(0, @intCast(patched.size)), arena);
    try testing.expectEqualStrings(expected, result);
}
