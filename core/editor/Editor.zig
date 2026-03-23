const Editor = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const SharedState = @import("../SharedState.zig");
const sizepkg = @import("../size.zig");

const log = std.log.scoped(.screen);

alloc: Allocator,
shared_state: *SharedState,

pub fn init(alloc: Allocator, shared_state: *SharedState) !Editor {
    return .{
        .alloc = alloc,
        .shared_state = shared_state,
    };
}

pub fn deinit(self: *Editor) void {
    _ = self;
}

pub fn resize(self: *Editor, size: sizepkg.Size) void {
    self.shared_state.mutex.lock();
    defer self.shared_state.mutex.unlock();

    self.shared_state.screen.resize(size);
}
