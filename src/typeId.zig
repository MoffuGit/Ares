const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

pub const TypeInfo = struct {
    name: [:0]const u8,
    size: usize,
    alignment: u8,
    deinit_fn: ?*const fn (*anyopaque) void,

    pub inline fn init(comptime T: type) *@This() {
        return &struct {
            fn deinit(ptr: *anyopaque) void {
                @as(*T, @ptrCast(@alignCast(ptr))).deinit();
            }

            var info: TypeInfo = .{
                .name = @typeName(T),
                .size = @sizeOf(T),
                .alignment = @alignOf(T),
                .deinit_fn = if (@hasDecl(T, "deinit")) deinit else null,
            };
        }.info;
    }

    pub fn destroy(self: *const @This(), gpa: Allocator, ptr: *anyopaque) void {
        if (self.deinit_fn) |deinit| deinit(ptr);
        if (self.size == 0) return;

        gpa.rawFree(
            @as([*]u8, @ptrCast(ptr))[0..self.size],
            .fromByteUnits(self.alignment),
            @returnAddress(),
        );
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
