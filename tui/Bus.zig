const std = @import("std");
const BlockingQueue = @import("datastruct").BlockingQueue;
const vaxis = @import("vaxis");
const Bus = @This();

pub const EventType = enum(u8) {
    key_down,
    key_up,
    mouse_down,
    mouse_up,
    mouse_move,
    click,
    mouse_enter,
    mouse_leave,
    wheel,
    focus,
    blur,
    resize,
    scheme,
};

pub const KeyData = struct {
    codepoint: u21,
    mods: u8,
    text_len: u8 = 0,
    text: [32]u8 = undefined,

    pub fn fromVaxis(key: vaxis.Key) KeyData {
        var data = KeyData{
            .codepoint = key.codepoint,
            .mods = @bitCast(key.mods),
        };
        if (key.text) |t| {
            const len: u8 = @intCast(@min(t.len, 32));
            @memcpy(data.text[0..len], t[0..len]);
            data.text_len = len;
        }
        return data;
    }
};

pub const MouseData = struct {
    col: u16,
    row: u16,
    button: u8,
};

pub const ResizeData = struct {
    cols: u16,
    rows: u16,
};

pub const SchemeData = struct {
    scheme: u8,
};

pub const Event = struct {
    _type: EventType,
    target: u64,
    data: Data,

    pub const Data = union {
        key: KeyData,
        mouse: MouseData,
        resize: ResizeData,
        scheme: SchemeData,
        none: void,
    };
};

pub const MailBox = BlockingQueue(Event, 64);

pub const Callback = *const fn (event: u8, target: u64, ptr: ?[*]const u8, dataLen: usize) callconv(.c) void;

callback: ?Callback = null,
mailbox: MailBox = .{},

pub fn push(self: *Bus, _type: EventType, target: u64, data: Event.Data) void {
    _ = self.mailbox.push(.{ ._type = _type, .target = target, .data = data }, .instant);
}

pub fn drain(self: *Bus) void {
    const cb = self.callback orelse return;

    var it = self.mailbox.drain();
    defer it.deinit();

    while (it.next()) |ev| {
        const bytes: []const u8 = switch (ev._type) {
            .key_down, .key_up => std.mem.asBytes(&ev.data.key),
            .mouse_down, .mouse_up, .mouse_move, .click, .mouse_enter, .mouse_leave, .wheel => std.mem.asBytes(&ev.data.mouse),
            .resize => std.mem.asBytes(&ev.data.resize),
            .scheme => std.mem.asBytes(&ev.data.scheme),
            .focus, .blur => &.{},
        };

        const ptr: ?[*]const u8 = if (bytes.len > 0) bytes.ptr else null;
        cb(@intFromEnum(ev._type), ev.target, ptr, bytes.len);
    }
}
