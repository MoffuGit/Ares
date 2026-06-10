const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const TypeInfo = struct {
    pub const max_align: std.mem.Alignment = .@"16";

    name: [:0]const u8,
    size: usize,
    alignment: u8,

    pub inline fn init(comptime T: type) *@This() {
        return &struct {
            var info: TypeInfo = .{
                .name = @typeName(T),
                .size = @sizeOf(T),
                .alignment = @alignOf(T),
            };
        }.info;
    }

    pub fn destroyOpaque(self: *const @This(), gpa: Allocator, ptr: *anyopaque) void {
        if (self.size == 0) return;

        gpa.rawFree(
            @as([*]u8, @ptrCast(ptr))[0..self.size],
            .fromByteUnits(self.alignment),
            @returnAddress(),
        );
    }
};

pub const TypeId = *TypeInfo;
