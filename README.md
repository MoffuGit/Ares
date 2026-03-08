Two things now

the Appearance Observer
create the ObserverDelegate class,
find a way to add our block to the methods of this class
create the class and add it to the notification center
for theme changes notifications
then, we notify our own strucutres for this events
they choose if they check the theme again or not
this is used for the desktop app only,

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
//     //NOTE:
//     in here we add our block
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
