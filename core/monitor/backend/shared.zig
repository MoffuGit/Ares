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
    next: ?*Completion = null,
    userdata: ?*anyopaque = null,
    callback: Callback = NoopCallback,
    flags: packed struct {
        state: State = .dead,
    } = .{},

    pub fn invoke(self: *Completion, path: []const u8, res: u32) xev.CallbackAction {
        return self.callback(self.userdata, self, path, res);
    }
};

/// Convert the callback value with an opaque pointer into the userdata type
/// that we can pass to our higher level callback types.
pub fn userdataValue(comptime Userdata: type, v: ?*anyopaque) ?*Userdata {
    // Void userdata is always a null pointer.
    if (Userdata == void) return null;
    return @ptrCast(@alignCast(v));
}
