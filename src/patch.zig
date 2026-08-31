// SOURCE: https://github.com/EpicGames/raddebugger
// LICENSE: [RADDEBUGGER]

const std = @import("std");
const Allocator = std.mem.Allocator;
const testing = std.testing;
const heap = std.heap;

const Buffer = @import("buffer.zig");
const Info = Buffer.Info;
const datastruct = @import("datastruct.zig");
const mem_map = datastruct.mem_map;
const MemMap = mem_map.MemMap;
const SinglyLinkedList = datastruct.SinglyLinkedList;
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
    list: SinglyLinkedList(Patch) = .empty,

    pub fn push(self: *PatchList, range: Rngu64, replace: []u8, alloc: Allocator) !void {
        const patch = try alloc.create(Patch);
        patch.* = .{
            .range = range,
            .replace = replace,
        };
        self.list.append(patch);
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
    lines: SinglyLinkedList(Line) = .empty,
    total: u64 = 0,

    pub fn push(self: *LineMap, line: Line, alloc: Allocator) !void {
        const l = try alloc.create(Line);
        l.* = line;

        self.total += l.range.dim();
        self.lines.append(l);
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

                const dim = n.range.dim();

                const off_range: Rngu64 = .new(
                    delta(n.memmap_ranges[0].min, n.delta),
                    delta(n.memmap_ranges[dim - 1].max, n.delta),
                );

                if (!off_range.contains(off)) continue;

                var min_idx: u64 = 0;
                var max_idx = dim - 1;

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

    pub fn init(buffer: []u8, info: Info, patch_list: PatchList, alloc: Allocator) !Patched {
        var last_memmap: MemMap = .{};
        var last_linemap: LineMap = .{};
        var last_size: u64 = buffer.len;

        try last_memmap.push(.new(0, buffer.len), buffer.ptr, alloc);
        try last_linemap.push(.new(info.line_ranges, .new(1, info.line_count + 1), 0), alloc);

        const patched_buffer = try alloc.alloc(u8, 1024);
        defer alloc.free(patched_buffer);
        var fixed = heap.FixedBufferAllocator.init(patched_buffer);
        const temp = fixed.allocator();

        var patch_node = patch_list.list.head;

        while (patch_node) |patch| : (patch_node = patch.next) {
            var next_memmap: MemMap = .{};
            var next_linemap: LineMap = .{};

            const size_delta = @as(i64, @intCast(patch.replace.len)) - @as(i64, @intCast(patch.range.dim()));
            const pre_range: Rngu64 = .new(0, patch.range.min);
            const post_range: Rngu64 = .new(patch.range.max, last_size);

            var map_node = last_memmap.ranges.head;
            while (map_node) |map| : (map_node = map.next) {
                const range = map.vaddr_range;
                const range_x_pre: Rngu64 = .intersect(pre_range, range);
                const range_x_post: Rngu64 = .intersect(post_range, range);

                if (!range_x_pre.empty()) {
                    try next_memmap.push(range_x_pre, map.base + (range_x_pre.min - range.min), temp);
                }

                if (!range_x_post.empty()) {
                    const range_x_post_shifted: Rngu64 = .new(
                        delta(range_x_post.min, size_delta),
                        delta(range_x_post.max, size_delta),
                    );
                    try next_memmap.push(
                        range_x_post_shifted,
                        map.base + (range_x_post.min - range.min),
                        temp,
                    );
                }
            }

            if (patch.replace.len != 0) {
                try next_memmap.push(
                    .new(patch.range.min, patch.range.min + patch.replace.len),
                    patch.replace.ptr,
                    temp,
                );
            }

            var replaced_lines_range: Rngu64 = .new(
                last_linemap.lineFromOffset(patch.range.min),
                last_linemap.lineFromOffset(patch.range.max),
            );
            const pre_lines_range: Rngu64 = .new(1, replaced_lines_range.min);
            const post_lines_range: Rngu64 = .new(replaced_lines_range.max + 1, last_linemap.total + 1);

            var line_delta: i64 = 0;
            line_delta -= @intCast(replaced_lines_range.dim());

            var replace_line_range: SinglyLinkedList(math.Rngu64Node) = .empty;
            var replaced_lines_count: u64 = 0;
            var last_line_start_off: u64 = 0;

            for (patch.replace, 0..) |c, idx| {
                if (c == '\n') {
                    const new_range_node = try temp.create(math.Rngu64Node);
                    new_range_node.* = .{ .range = .new(last_line_start_off, idx) };
                    replace_line_range.append(new_range_node);

                    line_delta += 1;
                    last_line_start_off += 1;
                    replaced_lines_count += 1;
                }
            }

            const new_range_node = try temp.create(math.Rngu64Node);
            new_range_node.* = .{ .range = .new(last_line_start_off, patch.replace.len) };
            replace_line_range.append(new_range_node);

            replaced_lines_count += 1;

            var line_node = last_linemap.lines.head;
            while (line_node) |line| : (line_node = line.next) {
                const range = line.range;
                const range_x_pre: Rngu64 = .intersect(pre_lines_range, range);
                const range_x_post: Rngu64 = .intersect(post_lines_range, range);

                if (!range_x_pre.empty()) {
                    const off = range_x_pre.min - range.min;
                    try next_linemap.push(
                        .new(
                            line.memmap_ranges[off .. off + (range_x_pre.max - range_x_pre.min)],
                            range_x_pre,
                            line.delta,
                        ),
                        temp,
                    );
                }

                if (!range_x_post.empty()) {
                    const range_x_post_shifted: Rngu64 = .new(
                        delta(range_x_post.min, line_delta),
                        delta(range_x_post.max, line_delta),
                    );
                    const off = range_x_post.min - range.min;
                    try next_linemap.push(
                        .new(
                            line.memmap_ranges[off .. off + (range_x_post.max - range_x_post.min)],
                            range_x_post_shifted,
                            line.delta + size_delta,
                        ),
                        temp,
                    );
                }
            }

            const affected_lines_ranges = try temp.alloc(Rngu64, replaced_lines_count);
            var range_node = replace_line_range.head;
            var affected_idx: u64 = 0;

            while (range_node) |range| {
                var affected_range: Rngu64 = .new(
                    range.range.min + patch.range.min,
                    range.range.max + patch.range.min,
                );

                if (affected_idx == 0) {
                    affected_range.min = last_linemap.rngForLine(replaced_lines_range.min).min;
                }

                if (affected_idx == replaced_lines_count - 1 and affected_idx >= @max(0, line_delta)) {
                    const original_range = last_linemap.rngForLine(replaced_lines_range.max);
                    if (original_range.max > patch.range.max) {
                        affected_range.max += original_range.max - patch.range.max;
                    }
                }

                affected_lines_ranges[affected_idx] = affected_range;
                range_node = range.next;
                affected_idx += 1;
            }

            try next_linemap.push(
                .new(
                    affected_lines_ranges,
                    .new(replaced_lines_range.min, replaced_lines_range.min + replaced_lines_count),
                    0,
                ),
                temp,
            );

            last_memmap = next_memmap;
            last_size = delta(last_size, size_delta);
            last_linemap = next_linemap;
        }

        var res_memmap: MemMap = .{};
        var res_linemap: LineMap = .{};

        var memmap_node = last_memmap.ranges.head;
        while (memmap_node) |map| : (memmap_node = map.next) {
            try res_memmap.push(map.vaddr_range, map.base, alloc);
        }

        var linemap_node = last_linemap.lines.head;
        while (linemap_node) |map| : (linemap_node = map.next) {
            try res_linemap.push(
                .{ .delta = map.delta, .range = map.range, .memmap_ranges = map.memmap_ranges },
                alloc,
            );
        }

        return .{
            .size = last_size,
            .linemap = res_linemap,
            .memmap = res_memmap,
        };
    }
};

test "Patch Buffer" {
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

    var patch_list: PatchList = .{};
    try patch_list.push(.new(51, 56), try arena.dupe(u8, "about"), arena);

    const patched = try Patched.init(buffer, info, patch_list, arena);

    const expected = "This line is about x chars long\nThis other line is about y chars long\nThis line is kinda like z chars long\nThis last line is aboyt z chars long\n\n";
    const result = try patched.memmap.slice(.new(0, @intCast(patched.size)), arena);
    try testing.expectEqualStrings(expected, result);
}
