const builtin = @import("builtin");
const rgfw = @import("rgfw");

pub const Window = if (builtin.is_test) NoopWindow else rgfw.Window;

const NoopWindow = struct {
    pub fn init(
        _: *@This(),
        _: [:0]const u8,
        _: i32,
        _: i32,
        _: i32,
        _: i32,
        _: rgfw.Window.Flags,
    ) !void {}

    pub fn deinit(self: *@This()) void {
        _ = self;
    }
};
