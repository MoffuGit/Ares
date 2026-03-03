const std = @import("std");
const BlockingQueue = @import("datastruct").BlockingQueue;
const Bus = @This();

pub const EventType = enum {
    settings_update,
    theme_update,
    worktree_update,
};

pub const Event = union(EventType) {
    settings_update: void,
    theme_update: void,
    worktree_update: void,
};

pub const AnyEvent = struct {
    const MAX_DATA_SIZE = 256;

    _type: u8,
    len: u8 = 0,
    data: [MAX_DATA_SIZE]u8 = undefined,
};

pub const MailBox = BlockingQueue(AnyEvent, 64);

pub const Callback = *const fn (event: u8, ptr: ?[*]const u8, dataLen: usize) callconv(.c) void;
callback: ?Callback = null,
mailbox: MailBox = .{},

drain_mutex: std.Thread.Mutex = .{},
drain_cond: std.Thread.Condition = .{},
drain_pending: bool = false,
drain_running: bool = false,
drain_thread: ?std.Thread = null,

pub fn startDrain(self: *Bus) void {
    self.drain_running = true;
    self.drain_thread = std.Thread.spawn(.{}, drainLoop, .{self}) catch null;
}

pub fn stopDrain(self: *Bus) void {
    self.drain_mutex.lock();
    self.drain_running = false;
    self.drain_mutex.unlock();
    self.drain_cond.signal();
    if (self.drain_thread) |t| t.join();
    self.drain_thread = null;
}

fn drainLoop(self: *Bus) void {
    while (true) {
        self.drain_mutex.lock();
        while (!self.drain_pending and self.drain_running) {
            self.drain_cond.wait(&self.drain_mutex);
        }
        if (!self.drain_running) {
            self.drain_mutex.unlock();
            return;
        }
        self.drain_pending = false;
        self.drain_mutex.unlock();

        self.drain();
    }
}

pub fn push(self: *Bus, event: Event) void {
    const any = AnyEvent{ ._type = @intFromEnum(event) };

    switch (event) {
        else => {},
    }

    _ = self.mailbox.push(any, .instant);

    self.drain_mutex.lock();
    self.drain_pending = true;
    self.drain_mutex.unlock();
    self.drain_cond.signal();
}

pub fn drain(self: *Bus) void {
    const cb = self.callback orelse return;

    var it = self.mailbox.drain();
    defer it.deinit();

    while (it.next()) |ev| {
        const ptr: ?[*]const u8 = if (ev.len > 0) &ev.data else null;
        cb(ev._type, ptr, ev.len);
    }
}
