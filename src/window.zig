const builtin = @import("builtin");
const rgfw = @import("rgfw");

pub const Window = window: {
    if (!builtin.is_test) break :window rgfw.Window;

    break :window struct {
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
};
