const std = @import("std");
const vaxis = @import("vaxis");
const GPA = std.heap.GeneralPurposeAllocator(.{});
const App = @import("App.zig");
const Mouse = @import("window/Mouse.zig");

pub const Callback = *const fn (event: u8, target: u64, ptr: ?[*]const u8, dataLen: usize) callconv(.c) void;

pub const xev = @import("xev").Dynamic;

pub var state: GlobalState = undefined;

pub const GlobalState = struct {
    const Self = @This();

    gpa: GPA = .{},
    alloc: std.mem.Allocator,
    callback: ?Callback = null,

    pub fn init(self: *Self, callback: ?Callback) void {
        self.* = .{
            .alloc = self.gpa.allocator(),
            .callback = callback,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.gpa.deinit() == .leak) {
            std.log.debug("WE HAVE LEAKS", .{});
        }
    }

    pub fn notify(self: *Self, evt: Events, target: u64) void {
        const cb = self.callback orelse return;

        const bytes: []const u8 = switch (evt) {
            .key_down, .key_up => |data| std.mem.asBytes(&data),
            .mouse_down, .mouse_up, .mouse_move, .click, .mouse_enter, .mouse_leave, .wheel => |data| std.mem.asBytes(&data),
            .resize => |data| std.mem.asBytes(&data),
            .scheme => |data| std.mem.asBytes(&data),
            .focus, .blur => &.{},
        };

        const ptr: ?[*]const u8 = if (bytes.len > 0) bytes.ptr else null;
        cb(@intFromEnum(evt), target, ptr, bytes.len);
    }
};

pub const KeyEvent = struct {
    codepoint: u21,
    mods: u8,
    text_len: u8 = 0,
    text: [32]u8 = undefined,

    pub fn fromVaxis(key: vaxis.Key) KeyEvent {
        var data = KeyEvent{
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

pub const Resize = struct {
    cols: u16,
    rows: u16,
};
pub const Events = union(enum) {
    key_down: KeyEvent,
    key_up: KeyEvent,
    mouse_down: Mouse,
    mouse_up: Mouse,
    mouse_move: Mouse,
    click: Mouse,
    mouse_enter: Mouse,
    mouse_leave: Mouse,
    wheel: Mouse,
    focus: void,
    blur: void,
    resize: Resize,
    scheme: u8,
};
