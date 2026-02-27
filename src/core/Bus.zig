const std = @import("std");
const BlockingQueue = @import("datastruct").BlockingQueue;
const Bus = @This();

pub const EventType = enum {
    settings_update,
};

pub const Event = union(EventType) {
    settings_update: void,
};

pub const AnyEvent = struct {
    const MAX_DATA_SIZE = 256;

    _type: u8,
    len: u8 = 0,
    ptr: ?[MAX_DATA_SIZE]u8 = null,
};

pub const MailBox = BlockingQueue(AnyEvent, 64);

pub const JsCallback = *const fn (event: u8, ptr: ?[*]const u8, dataLen: usize) callconv(.c) void;
callback: ?JsCallback = null,
mailbox: MailBox = .{},

pub fn push(self: *Bus, event: Event) void {
    const any = AnyEvent{ ._type = @intFromEnum(event) };

    switch (event) {
        .settings_update => {},
    }

    _ = self.mailbox.push(any, .instant);
}

pub fn drain(self: *Bus) void {
    const cb = self.callback orelse return;

    var it = self.mailbox.drain();
    defer it.deinit();

    while (it.next()) |ev| {
        cb(ev._type, ev.ptr, ev.len);
    }
}
