pub const c = @cImport(@cInclude("zintect.h"));

pub const Instance = struct {
    const Self = @This();

    handler: *anyopaque,

    pub fn init() !Instance {
        const inst = c.zintect_create_instance() orelse return error.MMM;

        return .{ .handler = inst };
    }

    pub fn deinit(self: *Self) void {
        c.zintect_destroy_instace(self.handler);
    }
};
