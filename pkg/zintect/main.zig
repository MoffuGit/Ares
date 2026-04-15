const std = @import("std");

pub const c = @cImport(@cInclude("zintect.h"));

pub const Runtime = struct {
    const Self = @This();

    handler: *anyopaque,

    pub fn init() !Self {
        const inst = c.zintect_create_runtime() orelse return error.CreateRuntimeFailed;

        return .{ .handler = inst };
    }

    pub fn deinit(self: *Self) void {
        c.zintect_destroy_runtime(self.handler);
    }
};

pub const Instance = struct {
    const Self = @This();

    handler: *anyopaque,

    pub fn init() !Self {
        const inst = c.zintect_create_instance() orelse return error.CreateInstanceFailed;

        return .{ .handler = inst };
    }

    pub fn deinit(self: *Self) void {
        c.zintect_destroy_instance(self.handler);
    }

    pub fn initialParse(self: *const Self, runtime: *const Runtime, buffer: [:0]const u8, extension: [:0]const u8) void {
        c.zintect_initial_parse(runtime.handler, self.handler, buffer.ptr, extension.ptr);
    }
};

test "initial parse rust source buffer" {
    var runtime = try Runtime.init();
    defer runtime.deinit();

    var instance = try Instance.init();
    defer instance.deinit();

    instance.initialParse(
        &runtime,
        "pub struct Wow { hi: u64 }\nfn blah() -> u64 {}",
        "rs",
    );

    try std.testing.expect(true);
}
