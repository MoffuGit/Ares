pub const Element = @This();

const std = @import("std");
const vaxis = @import("vaxis");

const Loop = @import("../Loop.zig");
pub const Tick = Loop.Tick;
pub const Timer = @import("Timer.zig");
const AnimationMod = @import("Animation.zig");
pub const Animation = AnimationMod.Animation;
pub const BaseAnimation = AnimationMod.BaseAnimation;
const Buffer = @import("../Buffer.zig");

pub const AppContext = @import("../AppContext.zig");

pub const Childrens = std.ArrayListUnmanaged(*Element);

alloc: std.mem.Allocator,
id: []const u8,
visible: bool = true,
zIndex: usize = 0,
removed: bool = false,
opacity: f32 = 1.0,
childrens: ?Childrens = null,
parent: ?*Element = null,
buffer: ?Buffer = null,
x: u16 = 0,
y: u16 = 0,
width: u16 = 0,
height: u16 = 0,
context: ?AppContext = null,

userdata: ?*anyopaque = null,
updateFn: ?*const fn (element: *Element, time: std.time.Instant) void = null,
drawFn: ?*const fn (element: *Element, buffer: *Buffer) void = null,
removeFn: ?*const fn (element: *Element) void = null,
//MouseHandler, KeyHanlder...

pub fn draw(self: *Element, buffer: *Buffer) void {
    if (!self.visible) return;

    const writeBuffer = if (self.buffer) |*buf| buf else buffer;

    if (self.drawFn) |callback| {
        callback(self, writeBuffer);
    }

    if (self.childrens) |*children| {
        std.mem.sort(*Element, children.items, {}, zIndexLessThanValue);
        for (children.items) |child| {
            child.draw(writeBuffer);
        }
    }

    if (self.buffer) |*buf| {
        self.blitToBuffer(buf, buffer);
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
        callback(self, try std.time.Instant.now());
    }

    if (self.childrens) |*childrens| {
        for (childrens.items) |child| {
            try child.update();
        }
    }
}

pub fn getContext(self: *Element) ?AppContext {
    return self.context;
}

pub fn setContext(self: *Element, ctx: AppContext) void {
    self.context = ctx;

    if (self.childrens) |*childrens| {
        for (childrens.items) |child| {
            child.setContext(ctx);
        }
    }
}

pub const Opts = struct {
    id: []const u8,
    visible: bool = true,
    zIndex: usize = 0,
    opacity: f32 = 1.0,
    x: u16 = 0,
    y: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    ownBuffer: bool = false,
    userdata: ?*anyopaque = null,
    updateFn: ?*const fn (element: *Element, time: std.time.Instant) void = null,
    drawFn: ?*const fn (element: *Element, buffer: *Buffer) void = null,
    removeFn: ?*const fn (element: *Element) void = null,
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
        .updateFn = opts.updateFn,
        .drawFn = opts.drawFn,
        .removeFn = opts.removeFn,
    };
}

pub fn remove(self: *Element) void {
    if (self.removed) return;
    self.removed = true;

    if (self.parent) |parent| {
        if (parent.childrens) |*siblings| {
            for (siblings.items, 0..) |child, i| {
                if (std.mem.eql(u8, child.id, self.id)) {
                    _ = siblings.orderedRemove(i);
                    break;
                }
            }
        }
        self.parent = null;
    }

    if (self.childrens) |*children| {
        for (children.items) |child| {
            child.parent = null;
            child.remove();
        }
        children.deinit(self.alloc);
        self.childrens = null;
    }

    if (self.buffer) |*buf| {
        buf.deinit(self.alloc);
        self.buffer = null;
    }

    if (self.removeFn) |removeFn| {
        removeFn(self);
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

    if (self.context) |ctx| {
        child.setContext(ctx);
    }

    try self.childrens.?.append(self.alloc, child);
}

pub fn removeChild(self: *Element, id: []const u8) void {
    if (self.childrens) |*children| {
        for (children.items) |child| {
            if (std.mem.eql(u8, child.id, id)) {
                child.remove();
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
