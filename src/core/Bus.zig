const std = @import("std");
const BlockingQueue = @import("datastruct").BlockingQueue;
// const EventType = @import("events.zig").EventType;
//
const Bus = @This();
//
// pub const MAX_EVENT_DATA = 128;
//
// pub const Event = struct {
//     event_type: EventType,
//     data: [MAX_EVENT_DATA]u8 = undefined,
//     data_len: u8 = 0,
// };
//
// pub const Queue = BlockingQueue(Event, 64);

pub const JsCallback = *const fn (event: u8, dataPtr: [*]const u8, dataLen: usize) callconv(.c) void;
callback: ?JsCallback = null,
// queue: Queue = .{},

//
// pub fn emit(self: *Bus, event: EventType, data: []const u8) void {
//     std.debug.assert(data.len <= MAX_EVENT_DATA);
//
//     var ev: Event = .{
//         .event_type = event,
//         .data_len = @intCast(data.len),
//     };
//     @memcpy(ev.data[0..data.len], data);
//
//     _ = self.queue.push(ev, .instant);
// }
//
// pub fn poll(self: *Bus) void {
//     const cb = self.callback orelse return;
//
//     var it = self.queue.drain();
//     defer it.deinit();
//
//     while (it.next()) |ev| {
//         cb(@intFromEnum(ev.event_type), @as([*]const u8, &ev.data), ev.data_len);
//     }
// }
