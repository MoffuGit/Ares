const std = @import("std");
const BlockingQueue = @import("datastruct").BlockingQueue;
const Bus = @This();

pub const EventType = enum {
    settings_update,
};

pub const Event = union(EventType) { settings_update: null };

pub const AnyEvent = struct {
    _type: u8,
    //data: bytes
    //len: len of the bytes
};

pub const MailBox = BlockingQueue(AnyEvent, 64);

pub const JsCallback = *const fn (event: u8, ptr: ?[*]const u8, dataLen: usize) callconv(.c) void;
callback: ?JsCallback = null,
mailbox: MailBox = .{},

pub fn push(self: *Bus, event: Event) void {
    const any = AnyEvent{ ._type = @intFromEnum(event) };
    // var ev: Event = .{
    //     .event_type = event,
    //     .data_len = @intCast(data.len),
    // };
    // @memcpy(ev.data[0..data.len], data);
    //
    _ = self.mailbox.push(any, .instant);
}
//
pub fn drain(self: *Bus) void {
    const cb = self.callback orelse return;

    var it = self.mailbox.drain();
    defer it.deinit();

    while (it.next()) |ev| {
        cb(@intFromEnum(ev.event_type), null, 0);
    }
}
