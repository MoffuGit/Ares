const Waker = @This();

callback: ?*const fn (userdata: ?*anyopaque) void = null,
userdata: ?*anyopaque = null,

pub fn wake(self: *const Waker) void {
    if (self.callback) |cb| {
        cb(self.userdata);
    }
}
