const std = @import("std");
const objc = @import("objc");
const global = @import("../global.zig");
const MacAppearance = @import("./appearance/mac.zig");
const Allocator = std.mem.Allocator;

pub const Observer = MacAppearance.Observer;

const Appearance = @This();

alloc: Allocator,
observer: *Observer,

pub fn create(alloc: Allocator) !*Appearance {
    const appearance = try alloc.create(Appearance);
    errdefer alloc.destroy(appearance);

    const observer = try Observer.create(alloc);

    appearance.* = .{ .observer = observer, .alloc = alloc };

    return appearance;
}

pub fn destroy(self: *Appearance) void {
    self.observer.destroy();
    self.alloc.destroy(self);
}

pub fn isDark(_: *Appearance) bool {
    return MacAppearance.isDark();
}

test "blocks until appearance change" {
    const testing = std.testing;
    const alloc = testing.allocator;

    const observer = try Observer.create(alloc);
    defer observer.destroy();

    const State = struct {
        changed: bool = false,
        mutex: std.Thread.Mutex = .{},
        cond: std.Thread.Condition = .{},

        fn handle(ctx: *anyopaque) void {
            const self: *@This() = @ptrCast(@alignCast(ctx));
            self.mutex.lock();
            defer self.mutex.unlock();
            self.changed = true;
            self.cond.signal();
        }
    };

    var state = State{};

    try observer.observe(.Change, .{
        .ctx = @ptrCast(&state),
        .handle = State.handle,
    });

    const NSRunLoop = objc.getClass("NSRunLoop").?;
    const currentRunLoop = NSRunLoop.msgSend(objc.Object, "currentRunLoop", .{});
    const NSDate = objc.getClass("NSDate").?;

    while (!state.changed) {
        const date = NSDate.msgSend(objc.Object, "dateWithTimeIntervalSinceNow:", .{@as(f64, 0.1)});
        currentRunLoop.msgSend(void, "runUntilDate:", .{date});
    }

    try testing.expect(state.changed);
}
