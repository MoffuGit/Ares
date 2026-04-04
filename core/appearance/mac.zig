const objc = @import("objc");
const std = @import("std");
const Allocator = std.mem.Allocator;
const EventEmitter = @import("../EventEmitter.zig").EventEmitter(ObserverEvents);
const c = @cImport({
    @cInclude("dispatch/dispatch.h");
});

const Appearance = @This();

const ObserverBlock = objc.Block(struct { observer: *Observer }, .{}, void);

pub const ObserverEvents = union(enum) {
    Change: void,
};

fn emitColorChange(target: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const self = objc.Object.fromId(target);
    const ivar_obj = self.getInstanceVariable("colorChangeBlock");
    const ctx: *const ObserverBlock.Context = @ptrCast(@alignCast(ivar_obj.value));
    ObserverBlock.invoke(ctx, .{});
}

fn getOrCreateObserverClass() !objc.Class {
    if (objc.getClass("NSColorChangesObserver")) |cls| return cls;

    const NSObject = objc.getClass("NSObject").?;
    const cls = objc.allocateClassPair(NSObject, "NSColorChangesObserver") orelse
        return error.ClassAllocationFailed;

    _ = cls.addIvar("colorChangeBlock");
    _ = cls.addMethod("emitColorChange", emitColorChange);
    objc.registerClassPair(cls);
    return cls;
}

pub const Observer = struct {
    pub const Tag = EventEmitter.Tag;
    pub const Listener = EventEmitter.Listener;

    const Self = @This();

    alloc: Allocator,
    mutex: std.Thread.Mutex = .{},
    events: EventEmitter,

    instance: objc.Object,
    heap_block: *const ObserverBlock.Context,

    pub fn create(alloc: Allocator) !*Self {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const observer = try alloc.create(Self);
        errdefer alloc.destroy(observer);

        const ObserverClass = try getOrCreateObserverClass();

        observer.* = .{
            .alloc = alloc,
            .events = EventEmitter.init(alloc),
            .heap_block = undefined,
            .instance = undefined,
        };
        errdefer observer.events.deinit();

        var block: ObserverBlock.Context = ObserverBlock.init(.{
            .observer = observer,
        }, (struct {
            fn emit(ctx: *const ObserverBlock.Context) callconv(.c) void {
                const _observer = ctx.observer;
                _observer.mutex.lock();
                _observer.mutex.unlock();

                _observer.events.emit(.Change);
            }
        }).emit);

        const heap_block = try ObserverBlock.copy(&block);
        observer.heap_block = heap_block;
        errdefer ObserverBlock.release(heap_block);

        const instance = ObserverClass.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "init", .{});
        observer.instance = instance;

        const block_as_obj: objc.Object = .{ .value = @ptrCast(@alignCast(heap_block)) };
        instance.setInstanceVariable("colorChangeBlock", block_as_obj);

        const NSDistributedNotificationCenter = objc.getClass("NSDistributedNotificationCenter").?;
        const defaultCenter = NSDistributedNotificationCenter.msgSend(objc.Object, "defaultCenter", .{});

        const NSString = objc.getClass("NSString").?;
        const notificationName = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"AppleInterfaceThemeChangedNotification"});

        defaultCenter.msgSend(
            void,
            "addObserver:selector:name:object:",
            .{ instance, objc.sel("emitColorChange"), notificationName, @as(objc.c.id, null) },
        );

        return observer;
    }

    pub fn observe(self: *Self, event: Tag, listener: Listener) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        try self.events.on(event, listener);
    }

    pub fn destroy(self: *Self) void {
        const pool = objc.AutoreleasePool.init();
        defer pool.deinit();

        const NSDistributedNotificationCenter = objc.getClass("NSDistributedNotificationCenter").?;
        const defaultCenter = NSDistributedNotificationCenter.msgSend(objc.Object, "defaultCenter", .{});

        defaultCenter.msgSend(
            void,
            "removeObserver:",
            .{self.instance},
        );

        self.instance.msgSend(void, "release", .{});
        ObserverBlock.release(self.heap_block);
        self.events.deinit();
        self.alloc.destroy(self);
    }
};

const NSPoint = extern struct {
    x: f64,
    y: f64,
};

const NSSize = extern struct {
    width: f64,
    height: f64,
};

const NSRect = extern struct {
    origin: NSPoint,
    size: NSSize,
};

const TrafficLightsContext = struct {
    window_ptr: *anyopaque,
    x: f64,
    y_from_top: f64,
    success: bool,
};

fn trafficLightsWork(ctx_ptr: ?*anyopaque) callconv(.c) void {
    const ctx: *TrafficLightsContext = @ptrCast(@alignCast(ctx_ptr));

    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const window: objc.Object = .{ .value = @ptrCast(@alignCast(ctx.window_ptr)) };

    const NSWindow = objc.getClass("NSWindow") orelse return;
    if (!window.msgSend(bool, "isKindOfClass:", .{NSWindow})) return;

    const close_button = window.msgSend(objc.Object, "standardWindowButton:", .{@as(u64, 0)});
    const minimize_button = window.msgSend(objc.Object, "standardWindowButton:", .{@as(u64, 1)});
    const zoom_button = window.msgSend(objc.Object, "standardWindowButton:", .{@as(u64, 2)});

    if (close_button.value == null or minimize_button.value == null or zoom_button.value == null) return;

    const button_container = close_button.msgSend(objc.Object, "superview", .{});
    if (button_container.value == null) return;

    const close_frame = close_button.msgSend(NSRect, "frame", .{});
    const minimize_frame = minimize_button.msgSend(NSRect, "frame", .{});

    var spacing = minimize_frame.origin.x - close_frame.origin.x;
    if (spacing <= 0) {
        spacing = close_frame.size.width + 6.0;
    }

    const flipped = button_container.msgSend(bool, "isFlipped", .{});
    const container_frame = button_container.msgSend(NSRect, "frame", .{});

    var target_y = ctx.y_from_top;
    if (!flipped) {
        target_y = container_frame.size.height - ctx.y_from_top - close_frame.size.height;
    }
    target_y = @max(0.0, target_y);

    const buttons = [_]objc.Object{ close_button, minimize_button, zoom_button };
    var current_x = ctx.x;
    for (buttons) |button| {
        button.msgSend(void, "setFrameOrigin:", .{NSPoint{ .x = current_x, .y = target_y }});
        current_x += spacing;
    }

    button_container.msgSend(void, "setNeedsLayout:", .{@as(bool, true)});
    button_container.msgSend(void, "layoutSubtreeIfNeeded", .{});

    ctx.success = true;
}

pub fn isDark() bool {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const NSString = objc.getClass("NSString").?;
    const keyString = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"AppleInterfaceStyle"});

    const NSUserDefaults = objc.getClass("NSUserDefaults").?;

    const standardUserDefaults = NSUserDefaults.msgSend(objc.Object, "standardUserDefaults", .{});

    const interfaceObject = standardUserDefaults.msgSend(objc.Object, "objectForKey:", .{keyString});

    const darkString = NSString.msgSend(objc.Object, "stringWithUTF8String:", .{"Dark"});

    return interfaceObject.msgSend(bool, "isEqualToString:", .{darkString});
}
