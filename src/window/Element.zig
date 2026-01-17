pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

pub const Timer = @import("mod.zig").Timer;
const Buffer = @import("../Buffer.zig");
pub const Childrens = std.ArrayList(Element);
const Mailbox = @import("Thread.zig").Mailbox;
const xev = @import("../global.zig").xev;

pub const Context = struct {
    mailbox: *Mailbox,
    wakeup: xev.Async,
    needs_draw: *bool,
};

alloc: std.mem.Allocator,
id: []const u8 = "",
visible: bool = true,
zIndex: usize = 0,
destroyed: bool = false,
opacity: f32 = 1.0,
childrens: ?Childrens = null,
buffer: ?Buffer = null,
x: u16 = 0,
y: u16 = 0,
width: u16 = 0,
height: u16 = 0,

userdata: ?*anyopaque = null,
context: ?Context = null,
//Callbacks for different events
updateFn: ?*const fn (userdata: ?*anyopaque, time: std.time.Instant) void = null,
drawFn: ?*const fn (userdata: ?*anyopaque, buffer: *Buffer) void = null,
//MouseHandler, KeyHanlder...

pub fn draw(self: *Element, buffer: *Buffer) !void {
    if (!self.visible) return;

    if (self.drawFn) |callback| {
        callback(self.userdata, buffer);
    }

    if (self.childrens) |*children| {
        std.mem.sort(Element, children.items, {}, zIndexLessThanValue);
        for (children.items) |*child| {
            try child.draw(buffer);
        }
    }
}

fn zIndexLessThanValue(_: void, a: Element, b: Element) bool {
    return a.zIndex < b.zIndex;
}

pub fn update(self: *Element) !void {
    if (self.updateFn) |callback| {
        callback(self.userdata, try std.time.Instant.now());
    }

    if (self.childrens) |*childrens| {
        for (childrens.items) |*child| {
            try child.update();
        }
    }
}

pub fn addTimer(self: *Element, timer: Timer) !void {
    if (self.context) |ctx| {
        _ = ctx.mailbox.push(.{ .timer = timer }, .instant);
        try ctx.wakeup.notify();
    }
}

pub fn requestDraw(self: *Element) !void {
    if (self.context) |ctx| {
        if (ctx.needs_draw.*) return;
        ctx.needs_draw.* = true;
        try ctx.wakeup.notify();
    }
}

pub fn init(alloc: std.mem.Allocator) Element {
    return .{
        .alloc = alloc,
    };
}

pub fn deinit(self: *Element) void {
    if (self.childrens) |*children| {
        for (children.items) |*child| {
            child.deinit();
        }
        children.deinit();
        self.childrens = null;
    }
    if (self.buffer) |*buf| {
        buf.deinit(self.alloc);
        self.buffer = null;
    }
}

pub fn createBuffer(self: *Element, width: u16, height: u16) !void {
    if (self.buffer) |*buf| {
        buf.deinit(self.alloc);
    }
    self.buffer = try Buffer.init(self.alloc, width, height);
    self.width = width;
    self.height = height;
}

pub fn addChild(self: *Element, child: Element) !*Element {
    if (self.childrens == null) {
        self.childrens = Childrens.init(self.alloc);
    }
    var new_child = child;
    new_child.context = self.context;
    try self.childrens.?.append(new_child);
    return &self.childrens.?.items[self.childrens.?.items.len - 1];
}

pub fn removeChild(self: *Element, id: []const u8) void {
    if (self.childrens) |*children| {
        for (children.items, 0..) |*child, i| {
            if (std.mem.eql(u8, child.id, id)) {
                var removed = children.orderedRemove(i);
                removed.deinit();
                return;
            }
        }
    }
}

pub fn getChildById(self: *Element, id: []const u8) ?*Element {
    if (self.childrens) |*children| {
        for (children.items) |*child| {
            if (std.mem.eql(u8, child.id, id)) {
                return child;
            }
        }
    }
    return null;
}

pub fn getChildrenSortedByZIndex(self: *Element, result: *std.ArrayList(*Element)) !void {
    if (self.childrens) |*children| {
        result.clearRetainingCapacity();
        try result.ensureTotalCapacity(children.items.len);
        for (children.items) |*child| {
            try result.append(child);
        }
        std.mem.sort(*Element, result.items, {}, zIndexLessThan);
    }
}

fn zIndexLessThan(_: void, a: *Element, b: *Element) bool {
    return a.zIndex < b.zIndex;
}
