const objc = @import("objc");
const std = @import("std");
const Allocator = std.mem.Allocator;
const EventEmitter = @import("../../EventEmitter.zig").EventEmitter(ObserverEvents);

const Appearance = @This();

const ObserverBlock = objc.Block(struct { observer: *Observer }, .{}, void);

const ObserverEvents = union(enum) {
    Change: void,
};

fn emitColorChange(target: objc.c.id, _: objc.c.SEL) callconv(.c) void {
    const self = objc.Object.fromId(target);
    const ivar_obj = self.getInstanceVariable("colorChangeBlock");
    const ctx: *const ObserverBlock.Context = @ptrCast(@alignCast(ivar_obj.value));
    ObserverBlock.invoke(ctx, .{});
}

pub const Observer = struct {
    pub const Tag = EventEmitter.Tag;
    pub const Listener = EventEmitter.Listener;

    const Self = @This();

    alloc: Allocator,
    mutex: std.Thread.Mutex = .{},
    events: EventEmitter,

    autorelase_pool: *objc.AutoreleasePool,
    heap_block: *const ObserverBlock.Context,

    pub fn create(alloc: Allocator) !*Self {
        const observer = try alloc.create(Self);
        errdefer alloc.destroy(observer);

        const pool = objc.AutoreleasePool.init();
        errdefer pool.deinit();

        const NSObject = objc.getClass("NSObject").?;

        const ObserverClass = objc.allocateClassPair(NSObject, "NSColorChangesObserver");
        if (ObserverClass == null) {
            return error.ClassAllocationFailed;
        }

        _ = ObserverClass.?.addIvar("colorChangeBlock");
        _ = ObserverClass.?.addMethod("emitColorChange", emitColorChange);

        objc.registerClassPair(ObserverClass.?);

        observer.* = .{
            .alloc = alloc,
            .events = EventEmitter.init(alloc),
            .autorelase_pool = pool,
            .heap_block = undefined,
        };

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

        const instance = ObserverClass.?.msgSend(objc.Object, "alloc", .{})
            .msgSend(objc.Object, "init", .{});

        const block_as_obj: objc.Object = .{ .value = @ptrCast(@alignCast(heap_block)) };
        instance.setInstanceVariable("colorChangeBlock", block_as_obj);

        instance.msgSend(void, "emitColorChange", .{});

        return observer;
    }

    pub fn observe(self: *Self, event: Tag, listener: Listener) !void {
        try self.events.on(event, listener);
    }

    pub fn destroy(self: *Self) void {
        ObserverBlock.release(self.heap_block);
        self.autorelase_pool.deinit();
        self.events.deinit();
        self.alloc.destroy(self);
    }
};

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
