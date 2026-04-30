const xev = @import("../../global.zig").xev;

pub fn Callback(comptime T: type) type {
    return *const fn (
        userdata: ?*anyopaque,
        watcher: *T.Watcher,
        path: []const u8,
        result: u32,
    ) xev.CallbackAction;
}

pub fn NoopCallback(comptime T: type) Callback(xev, T) {
    return (struct {
        pub fn noopCallback(
            _: ?*anyopaque,
            _: *T.Watcher,
            _: []const u8,
            _: u32,
        ) xev.CallbackAction {
            return .disarm;
        }
    }).noopCallback;
}

pub const State = enum(u1) {
    dead = 0,
    active = 1,
};

pub const Completion = struct {
    next: ?Completion = null,
    userdata: ?*anyopaque = null,
    callback: Callback = NoopCallback,
    flags: packed struct {
        state: State = .dead,
    } = .{},
};
