const xev = @import("../../global.zig").xev;

pub const Callback = *const fn (
    userdata: ?*anyopaque,
    comp: *Completion,
    path: []const u8,
    result: u32,
) xev.CallbackAction;

pub fn NoopCallback(
    _: ?*anyopaque,
    _: *Completion,
    _: []const u8,
    _: u32,
) xev.CallbackAction {
    return .disarm;
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

    pub fn invoke(self: *Completion, path: []const u8, res: u32) xev.CallbackAction {
        self.callback(self.userdata, self, path, res);
    }
};
