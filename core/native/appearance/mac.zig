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
    events: EventEmitter,
    observerDelegate: objc.Class,

    pub fn create(alloc: Allocator) !*Self {
        const observer = try alloc.create(Self);

        //NOTE:
        //we need to create our class,
        // Create a new class declaration
        // const class = objc.allocateClassPair(objc.getClass("NSObject"), "MyDelegate").?;
        // Register a method conforming to the protocol
        // _ = class.addMethod("foo:bar:", myHandlerFn);
        // Optionally, explicitly mark the new class for conformance
        // const protocol = objc.getProtocol("SomeDelegateProtocol").?;
        // _ = objc.c.class_addProtocol(self.class.value, protocol.value);
        // Finalize the class declaration
        // objc.registerClassPair(class);
        //
        //the detail is how we can access to the observer events for emitting the change

        observer.* = .{
            .alloc = alloc,
            .events = EventEmitter.init(alloc),
        };

        return observer;
    }

    pub fn observe(self: *Self, event: Tag, listener: Listener) !void {
        try self.events.on(event, listener);
    }

    pub fn destroy(self: *Self) void {
        self.events.deinit();
        self.alloc.destroy(self);
    }
};

// fn themeChangedCallback(self: objc.Object, _cmd: objc.Selector, notification: objc.Object) void {
//     _ = self; // self is the instance of NSColorChangesObserver
//     _ = _cmd; // _cmd is the selector for the method, "handleAppleThemeChanged:"
//     _ = notification; // notification is the NSDistributedNotification object
//
//     // In a real application, you would put your theme change handling logic here.
//     // For now, let's just print something.
//     std.debug.print("Theme changed notification received!\n", .{});
//
//     // You could inspect the notification object if needed:
//     // const userInfo = notification.msgSend(objc.Object, "userInfo");
//     // if (userInfo != null) {
//     //     // ... process userInfo
//     // }
// }

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
