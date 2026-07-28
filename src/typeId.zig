const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const constants = @import("constants.zig");
const MAX_ALIGN = constants.MAX_ALIGN;

pub const TypeInfo = struct {
    deinit_fn: ?*const fn (*anyopaque) void,
    drop_fn: ?*const fn (*anyopaque) void,
    size: usize,
    alignment: u8,

    pub inline fn init(comptime T: type) *@This() {
        comptime assert(@alignOf(T) <= MAX_ALIGN.toByteUnits());
        return &struct {
            fn deinit(ptr: *anyopaque) void {
                @as(*T, @ptrCast(@alignCast(ptr))).deinit();
            }

            fn drop(ptr: *anyopaque) void {
                @as(*T, @ptrCast(@alignCast(ptr))).drop();
            }

            var info: TypeInfo = .{
                .size = @sizeOf(T),
                .alignment = @alignOf(T),
                .deinit_fn = if (@hasDecl(T, "deinit")) @This().deinit else null,
                .drop_fn = if (@hasDecl(T, "drop")) @This().drop else null,
            };
        }.info;
    }

    pub fn deinit(self: *const @This(), ptr: *anyopaque) void {
        if (self.deinit_fn) |deinit_fn| deinit_fn(ptr);
    }

    pub fn drop(self: *const @This(), ptr: *anyopaque) void {
        if (self.drop_fn) |drop_fn| drop_fn(ptr);
    }

    pub fn destroy(self: *const @This(), ptr: *anyopaque, alloc: Allocator) void {
        if (self.size == 0) return;
        const non_const_ptr = @as([*]u8, @ptrCast(ptr));
        alloc.rawFree(non_const_ptr[0..self.size], .fromByteUnits(self.alignment), @returnAddress());
    }
};

pub const TypeId = *TypeInfo;

test "type info stores optional deinit function" {
    const WithDeinit = struct {
        deinit_called: *bool,

        pub fn deinit(self: *@This()) void {
            self.deinit_called.* = true;
        }
    };
    const WithoutDeinit = struct { value: u32 };

    var deinit_called = false;
    var value = WithDeinit{ .deinit_called = &deinit_called };

    const with_deinit = TypeInfo.init(WithDeinit);
    const without_deinit = TypeInfo.init(WithoutDeinit);

    try std.testing.expect(with_deinit.deinit_fn != null);
    try std.testing.expect(without_deinit.deinit_fn == null);

    with_deinit.deinit_fn.?(&value);
    try std.testing.expect(deinit_called);
}
