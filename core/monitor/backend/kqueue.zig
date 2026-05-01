const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const Fnv1a_32 = std.hash.Fnv1a_32;
const datastruct = @import("datastruct");
const Allocator = std.mem.Allocator;

const Tree = datastruct.RBTree;

const xev = @import("../../global.zig").xev;
const shared = @import("shared.zig");
const Callback = shared.Callback;
const NoopCallback = shared.NoopCallback;
const State = shared.State;
const Completion = shared.Completion;
const queue = datastruct.queue;

const Completions = queue.Intrusive(Completion);

const FLAGS =
    std.c.NOTE.WRITE |
    std.c.NOTE.DELETE |
    std.c.NOTE.ATTRIB |
    std.c.NOTE.EXTEND |
    std.c.NOTE.LINK |
    std.c.NOTE.RENAME;

pub const Watchers = @This();
const log = std.log.scoped(.watchers);

tree: Tree(Watcher, Watcher.compare) = .{},
loop: *xev.Loop,
active: usize = 0,

pub const Watcher = struct {
    completions: Completions = .{},

    wd: u32 = 0,
    path: []u8 = .{},

    flags: packed struct {
        state: State = .dead,
    } = .{},

    fd: i32 = -1,
    c: xev.Completion = .{},

    pub fn init(alloc: Allocator, path: []const u8) !void {
        const wd = Fnv1a_32.hash(path);
        return .{
            .wd = wd,
            .path = try alloc.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Watcher, alloc: Allocator) void {
        posix.close(self.fd);
        alloc.free(self.path);
        self.path = .{};
        self.fd = -1;
        self.flags.state = .dead;
    }

    pub fn state(self: Watcher) State {
        return switch (self.flags.state) {
            .dead => .dead,
            .active => .active,
        };
    }

    // pub fn invoke(self: *Watcher, path: []const u8, res: u32) xev.CallbackAction {
    //     return self.callback(self.userdata, self, path, res);
    // }

    pub fn compare(a: *Watcher, b: *Watcher) std.math.Order {
        if (a.wd > b.wd) return .gt;
        if (a.wd < b.wd) return .lt;
        return .eq;
    }

    pub fn start(self: *Watcher, loop: *xev.Loop) !void {
        const fd = try posix.open(self.path, .{}, 0);
        self.fd = fd;
        self.flags.state = .active;

        self.c = .{
            .op = .{
                .vnode = .{
                    .fd = self.fd,
                    .flags = FLAGS,
                },
            },
            .userdata = self,
            .callback = vnode_callback,
        };

        loop.add(&self.c);
    }
    //
    //             pub fn cancel(self: *Monitor, loop: *xev.Loop, w: *Watcher) void {
    //                 self.cancelation.c =
    //                     .{ .op = .{ .cancel = .{ .c = &self.c } }, .userdata = w, .callback = cancel_callback };
    //                 loop.add(&self.cancelation.c);
    //             }
    //
    fn vnode_callback(
        _: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        _: xev.Result,
    ) xev.CallbackAction {
        // const watcher: *Watcher = @ptrCast(@alignCast(ud.?));
        //
        // const vnode_flags = result.vnode catch {
        //     return .disarm;
        // };
        //
        // var watchers = watcher.monitor.watchers;
        // watcher.monitor.watchers = .{};
        //
        // const action = watcher.invoke(watcher.path, vnode_flags);
        //
        // var curr = watchers.pop();
        // while (curr) |w| {
        //     switch (w.invoke(watcher.path, vnode_flags)) {
        //         .disarm => {
        //             w.flags.state = .dead;
        //             w.fs.?.active -= 1;
        //         },
        //         .rearm => {
        //             watcher.monitor.watchers.push(w);
        //         },
        //     }
        //     curr = watchers.pop();
        // }
        //
        // if (action == .disarm) {
        //     if (watcher.monitor.watchers.pop()) |replace| {
        //         replace.monitor = Monitor.init(replace.path) catch {
        //             return action;
        //         };
        //
        //         replace.monitor.start(loop, replace);
        //
        //         watcher.fs.?.tree.replace(watcher, replace) catch {};
        //     } else {
        //         _ = watcher.fs.?.tree.remove(watcher);
        //     }
        //
        //     watcher.monitor.cancel(loop, watcher);
        // }
        //
        // return action;
    }
};

pub fn init(loop: *xev.Loop) Watchers {
    return .{
        .loop = loop,
    };
}

pub fn deinit(self: *Watchers, alloc: Allocator) void {
    var it = self.tree.iter();
    while (it.next()) |w| {
        w.deinit(alloc);
        alloc.destroy(w);
    }
}

//         pub fn watch(self: *Self, path: []const u8, watcher: *Watcher, comptime Userdata: type, userdata: ?*Userdata, comptime cb: *const fn (
//             ud: ?*Userdata,
//             watcher: *Watcher,
//             path: []const u8,
//             result: u32,
//         ) xev.CallbackAction) !void {
//             if (watcher.state() != .dead) {
//                 return;
//             }
//
//
//             watcher.* = .{ .callback = (struct {
//                 fn callback(
//                     ud: ?*anyopaque,
//                     _watcher: *Watcher,
//                     _path: []const u8,
//                     result: u32,
//                 ) xev.CallbackAction {
//                     return @call(.always_inline, cb, .{ common.userdataValue(Userdata, ud), _watcher, _path, result });
//                 }
//             }).callback, .userdata = userdata, .wd = wd, .path = path, .fs = self };
//
//             if (self.tree.find(watcher)) |w| {
//                 w.monitor.watchers.push(watcher);
//             } else {
//                 watcher.monitor = try Monitor.init(path);
//
//                 watcher.monitor.start(self.loop, watcher);
//
//                 self.tree.insert(watcher);
//             }
//
//             watcher.flags.state = .active;
//             self.active += 1;
//         }
//
//         pub fn cancel(self: *Self, watcher: *Watcher) void {
//             if (self.tree.find(watcher)) |w| {
//                 const m = &w.monitor;
//
//                 if (watcher != w) {
//                     watcher.*.flags.state = .dead;
//                     self.active -= 1;
//                     m.watchers.remove(watcher);
//                     return;
//                 }
//
//                 if (m.watchers.pop()) |replace| {
//                     replace.monitor = Monitor.init(replace.path) catch {
//                         return;
//                     };
//
//                     replace.monitor.start(self.loop, replace);
//
//                     self.tree.replace(w, replace) catch {};
//                 } else {
//                     _ = self.tree.remove(w);
//                 }
//
//                 m.cancel(self.loop, w);
//             }
//         }
//
//         pub fn cancelWithCallback(self: *Self, watcher: *Watcher, comptime Userdata: type, userdata: ?*Userdata, comptime cb: *const fn (ud: ?*Userdata, w: *Watcher) void) void {
//             if (self.tree.find(watcher)) |w| {
//                 const m = &w.monitor;
//
//                 m.cancelation = .{ .userdata = userdata, .callback = (struct {
//                     pub fn callback(ud: ?*anyopaque, inner_w: *Watcher) void {
//                         @call(.always_inline, cb, .{ common.userdataValue(Userdata, ud), inner_w });
//                     }
//                 }.callback) };
//
//                 if (watcher != w) {
//                     watcher.flags.state = .dead;
//                     self.active -= 1;
//                     m.watchers.remove(watcher);
//                     m.cancelation.invoke(w);
//                     return;
//                 }
//
//                 m.cancel(self.loop, w);
//
//                 if (m.watchers.pop()) |replace| {
//                     replace.monitor = Monitor.init(replace.path) catch {
//                         return;
//                     };
//
//                     replace.monitor.start(self.loop, replace);
//
//                     self.tree.replace(w, replace) catch {};
//                 } else {
//                     _ = self.tree.remove(w);
//                 }
//             }
//         }
//
//         fn cancel_callback(ud: ?*anyopaque, _: *xev.Loop, _: *xev.Completion, _: xev.Result) xev.CallbackAction {
//             const watcher: *Watcher = @ptrCast(@alignCast(ud.?));
//
//             watcher.*.flags.state = .dead;
//             watcher.fs.?.active -= 1;
//             posix.close(watcher.monitor.fd);
//             watcher.monitor.fd = -1;
//
//             watcher.monitor.cancelation.invoke(watcher);
//
//             return .disarm;
//         }
