const std = @import("std");
const posix = std.posix;
const linux = std.os.linux;
const Fnv1a_32 = std.hash.Fnv1a_32;
const datastruct = @import("datastruct");
const Allocator = std.mem.Allocator;

const Tree = datastruct.RBTree(Watcher, Watcher.compare);

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

alloc: Allocator,
tree: Tree,
loop: *xev.Loop,
active: usize = 0,

pub const Watcher = struct {
    completions: Completions = .{},

    wd: u32 = 0,
    path: []u8 = &.{},

    flags: packed struct {
        state: State = .dead,
    } = .{},

    fd: i32 = -1,
    c: xev.Completion = .{},

    pub fn init(alloc: Allocator, path: []const u8) !Watcher {
        const wd = Fnv1a_32.hash(path);
        return .{
            .wd = wd,
            .path = try alloc.dupe(u8, path),
        };
    }

    pub fn deinit(self: *Watcher, alloc: Allocator) void {
        if (self.fd != -1) posix.close(self.fd);
        alloc.free(self.path);
        self.path = &.{};
        self.fd = -1;
        self.flags.state = .dead;
    }

    pub fn state(self: Watcher) State {
        return switch (self.flags.state) {
            .dead => .dead,
            .active => .active,
        };
    }

    pub fn invoke(self: *Watcher, res: u32) void {
        var comps = self.completions;

        self.completions = .{};

        while (comps.pop()) |comp| {
            switch (comp.invoke(self.path, res)) {
                .rearm => {
                    self.completions.push(comp);
                },
                .disarm => {
                    comp.flags.state = .dead;
                },
            }
        }
    }

    pub fn compare(a: Watcher, b: Watcher) std.math.Order {
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
            .callback = callback,
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
    fn callback(
        ud: ?*anyopaque,
        _: *xev.Loop,
        _: *xev.Completion,
        res: xev.Result,
    ) xev.CallbackAction {
        const watcher: *Watcher = @ptrCast(@alignCast(ud.?));

        const flags = res.vnode catch {
            return .disarm;
        };

        watcher.invoke(flags);

        if (watcher.completions.empty()) {
            watcher.flags.state = .dead;
            return .disarm;
        }

        return .rearm;
    }
};

pub fn init(loop: *xev.Loop, alloc: Allocator) !Watchers {
    const tree = Tree.init(alloc);
    return .{
        .loop = loop,
        .tree = tree,
        .alloc = alloc,
    };
}

pub fn deinit(self: *Watchers) void {
    var it = self.tree.iter();
    while (it.next()) |w| {
        w.deinit(self.alloc);
    }
    self.tree.deinit();
}

pub fn watch(self: *Watchers, path: []const u8, comp: *Completion, comptime Userdata: type, userdata: ?*Userdata, comptime cb: *const fn (
    ud: ?*Userdata,
    comp: *Completion,
    path: []const u8,
    result: u32,
) xev.CallbackAction) !void {
    if (comp.flags.state != .dead) {
        return;
    }

    comp.* = .{
        .callback = (struct {
            fn callback(
                ud: ?*anyopaque,
                _comp: *Completion,
                _path: []const u8,
                result: u32,
            ) xev.CallbackAction {
                return @call(.always_inline, cb, .{ shared.userdataValue(Userdata, ud), _comp, _path, result });
            }
        }).callback,
        .userdata = userdata,
        .flags = .{ .state = .active },
    };

    // Probe by hash without allocating a path.
    const probe: Watcher = .{ .wd = Fnv1a_32.hash(path) };

    if (self.tree.find(probe)) |w| {
        w.completions.push(comp);
        self.active += 1;
        return;
    }

    const watcher = try Watcher.init(self.alloc, path);
    errdefer self.alloc.free(watcher.path);

    _ = try self.tree.insert(watcher);

    const w = self.tree.find(watcher).?;
    w.completions.push(comp);
    try w.start(self.loop);
    self.active += 1;
}
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
