const objc = @import("objc");
const std = @import("std");
const Allocator = std.mem.Allocator;
const EventEmitter = @import("../../EventEmitter.zig").EventEmitter(ObserverEvents);

const Appearance = @This();

const ObserverEvents = union(enum) {
    Change: void,
};

pub const Observer = struct {
    pub const Tag = EventEmitter.Tag;
    pub const Listener = EventEmitter.Listener;

    const Self = @This();

    alloc: Allocator,
    mutex: std.Thread.Mutex = .{},
    events: EventEmitter,

    autorelase_pool: *objc.AutoreleasePool,
    // observerDelegate: objc.Class,

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

        observer.* = .{
            .alloc = alloc,
            .events = EventEmitter.init(alloc),
            .autorelase_pool = pool,
        };

        //NOTE:
        //I don't think it's going to be that much issue with the emit call,
        //i will only use it for adding an Event to the queue of the application,
        //this Block should then get set as part of the observerDelegate class
        //then invoked when a change happens

        const ObserverBlock = objc.Block(struct { observer: *Observer }, .{}, void);

        const ObserverCapture: ObserverBlock.Captures = .{
            .observer = observer,
        };

        var Block: ObserverBlock.Context = ObserverBlock.init(ObserverCapture, (struct {
            fn emit(block: *const ObserverBlock.Context) callconv(.c) void {
                const _observer = block.observer;
                _observer.mutex.lock();
                _observer.mutex.unlock();

                _observer.events.emit(.Change);
            }
        }).emit);

        ObserverBlock.invoke(&Block, .{});

        return observer;
    }

    pub fn observe(self: *Self, event: Tag, listener: Listener) !void {
        try self.events.on(event, listener);
    }

    pub fn destroy(self: *Self) void {
        self.autorelase_pool.deinit();
        self.events.deinit();
        self.alloc.destroy(self);
    }
};

// pub fn setupThemeObserver() !void {
//     const pool = objc.AutoreleasePool.init();
//     defer pool.deinit();
//
//     const NSObject = objc.getClass("NSObject").?;
//
//     const ObserverClass = objc.allocateClassPair(NSObject, "NSColorChangesObserver");
//     if (ObserverClass == null) {
//         return error.ClassAllocationFailed;
//     }
//
//     const handleSelector = objc.selector("handleAppleThemeChanged:");
//     if (!ObserverClass.?.addMethod(handleSelector, themeChangedCallback, "v@:@")) {
//         return error.MethodAdditionFailed;
//     }
//     objc.registerClassPair(ObserverClass.?);
//
//     const observerDelegate = ObserverClass.?.msgSend(objc.Object, "new");
//     if (observerDelegate == null) {
//         return error.ObserverInstanceCreationFailed;
//     }
//
//     const NSDistributedNotificationCenter = objc.getClass("NSDistributedNotificationCenter").?;
//     const defaultCenter = NSDistributedNotificationCenter.msgSend(
//         objc.Object,
//         "defaultCenter"
//     );
//
//     const notificationName = objc.nsString("AppleInterfaceThemeChangedNotification");
//
//     defaultCenter.msgSend(
//         void,
//         "addObserver:selector:name:object:",
//         .{
//             observerDelegate,
//             handleSelector,
//             notificationName,
//             objc.nil,
//         }
//     );
//
//     std.debug.print("NSColorChangesObserver setup complete. Observing 'AppleInterfaceThemeChangedNotification'.\n", .{});
// }

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
