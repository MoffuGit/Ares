pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

const Window = @import("mod.zig");
pub const Tick = Window.Tick;
pub const Timer = Window.Timer;
pub const Animation = Window.Animation;
pub const BaseAnimation = Window.BaseAnimation;
pub const TimerContext = Window.TimerContext;
const Buffer = @import("../Buffer.zig");
const Mailbox = @import("Thread.zig").Mailbox;
const xev = @import("../global.zig").xev;

pub const Childrens = std.ArrayListUnmanaged(*Element);

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
parent: ?*Element = null,
buffer: ?Buffer = null,
x: u16 = 0,
y: u16 = 0,
width: u16 = 0,
height: u16 = 0,

userdata: ?*anyopaque = null,
setupFn: ?*const fn (userdata: ?*anyopaque, ctx: Context) void = null,
updateFn: ?*const fn (userdata: ?*anyopaque, time: std.time.Instant) void = null,
drawFn: ?*const fn (userdata: ?*anyopaque, buffer: *Buffer) void = null,
destroyFn: ?*const fn (userdata: ?*anyopaque, alloc: std.mem.Allocator) void = null,
//MouseHandler, KeyHanlder...

pub fn setup(self: *Element, ctx: Context) void {
    if (self.setupFn) |callback| {
        callback(self.userdata, ctx);
    }

    if (self.childrens) |*children| {
        for (children.items) |child| {
            child.setup(ctx);
        }
    }
}

pub fn draw(self: *Element, buffer: *Buffer) void {
    if (!self.visible) return;

    if (self.buffer) |*localBuffer| {
        localBuffer.clear();

        if (self.drawFn) |callback| {
            callback(self.userdata, localBuffer);
        }

        if (self.childrens) |*children| {
            std.mem.sort(*Element, children.items, {}, zIndexLessThanValue);
            for (children.items) |child| {
                child.draw(localBuffer);
            }
        }

        self.blitToBuffer(buffer, localBuffer);
    } else {
        if (self.drawFn) |callback| {
            callback(self.userdata, buffer);
        }

        if (self.childrens) |*children| {
            std.mem.sort(*Element, children.items, {}, zIndexLessThanValue);
            for (children.items) |child| {
                child.draw(buffer);
            }
        }
    }
}

fn blitToBuffer(self: *Element, dest: *Buffer, src: *Buffer) void {
    var row: u16 = 0;
    while (row < src.height) : (row += 1) {
        var col: u16 = 0;
        while (col < src.width) : (col += 1) {
            if (src.readCell(col, row)) |cell| {
                const destX = self.x + col;
                const destY = self.y + row;
                dest.writeCell(destX, destY, cell);
            }
        }
    }
}

fn zIndexLessThanValue(_: void, a: *Element, b: *Element) bool {
    return a.zIndex < b.zIndex;
}

pub fn update(self: *Element) !void {
    if (self.updateFn) |callback| {
        callback(self.userdata, try std.time.Instant.now());
    }

    if (self.childrens) |*childrens| {
        for (childrens.items) |child| {
            try child.update();
        }
    }
}

pub fn addTick(ctx: Context, tick: Tick) !void {
    _ = ctx.mailbox.push(.{ .tick = tick }, .instant);
    try ctx.wakeup.notify();
}

pub fn startTimer(ctx: Context, timer: *Timer) !void {
    timer.context = .{ .mailbox = ctx.mailbox, .wakeup = ctx.wakeup, .needs_draw = ctx.needs_draw };
    _ = ctx.mailbox.push(.{ .timer_start = timer }, .instant);
    try ctx.wakeup.notify();
}

pub fn startAnimation(ctx: Context, animation: *BaseAnimation) !void {
    animation.context = .{ .mailbox = ctx.mailbox, .wakeup = ctx.wakeup, .needs_draw = ctx.needs_draw };
    _ = ctx.mailbox.push(.{ .animation_start = animation }, .instant);
    try ctx.wakeup.notify();
}

pub fn requestDraw(ctx: Context) !void {
    if (ctx.needs_draw.*) return;
    ctx.needs_draw.* = true;
    try ctx.wakeup.notify();
}

pub const Opts = struct {
    id: []const u8 = "",
    visible: bool = true,
    zIndex: usize = 0,
    opacity: f32 = 1.0,
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    ownBuffer: bool = false,
    userdata: ?*anyopaque = null,
    setupFn: ?*const fn (userdata: ?*anyopaque, ctx: Context) void = null,
    updateFn: ?*const fn (userdata: ?*anyopaque, time: std.time.Instant) void = null,
    drawFn: ?*const fn (userdata: ?*anyopaque, buffer: *Buffer) void = null,
    destroyFn: ?*const fn (userdata: ?*anyopaque, alloc: std.mem.Allocator) void = null,
};

pub fn init(alloc: std.mem.Allocator, opts: Opts) !Element {
    const buffer: ?Buffer = if (opts.ownBuffer and opts.width > 0 and opts.height > 0)
        try Buffer.init(alloc, opts.width, opts.height)
    else
        null;

    return .{
        .alloc = alloc,
        .id = opts.id,
        .visible = opts.visible,
        .zIndex = opts.zIndex,
        .opacity = opts.opacity,
        .x = opts.x,
        .y = opts.y,
        .width = opts.width,
        .height = opts.height,
        .buffer = buffer,
        .userdata = opts.userdata,
        .setupFn = opts.setupFn,
        .updateFn = opts.updateFn,
        .drawFn = opts.drawFn,
        .destroyFn = opts.destroyFn,
    };
}

pub fn deinit(self: *Element) void {
    if (self.childrens) |*children| {
        for (children.items) |child| {
            child.destroy();
        }
        children.deinit(self.alloc);
        self.childrens = null;
    }
    if (self.buffer) |*buf| {
        buf.deinit(self.alloc);
        self.buffer = null;
    }
}

pub fn destroy(self: *Element) void {
    self.deinit();
    if (self.destroyFn) |destroyFn| {
        destroyFn(self.userdata, self.alloc);
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

pub fn addChild(self: *Element, child: *Element) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }
    child.parent = self;
    try self.childrens.?.append(self.alloc, child);
}

pub fn removeChild(self: *Element, id: []const u8) void {
    if (self.childrens) |*children| {
        for (children.items, 0..) |child, i| {
            if (std.mem.eql(u8, child.id, id)) {
                const removed = children.orderedRemove(i);
                removed.destroy();
                return;
            }
        }
    }
}

pub fn getChildById(self: *Element, id: []const u8) ?*Element {
    if (self.childrens) |*children| {
        for (children.items) |child| {
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
        for (children.items) |child| {
            try result.append(child);
        }
        std.mem.sort(*Element, result.items, {}, zIndexLessThan);
    }
}

fn zIndexLessThan(_: void, a: *Element, b: *Element) bool {
    return a.zIndex < b.zIndex;
}
