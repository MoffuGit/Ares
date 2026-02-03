const std = @import("std");
const xev = @import("../global.zig").xev;

const Monitor = @import("monitor/mod.zig");
const MonitorThread = @import("monitor/Thread.zig");

const Scanner = @import("scanner/mod.zig");
const ScannerThread = @import("scanner/Thread.zig");

const Snapshot = @import("Snapshot.zig");

pub const FileTree = @import("FileTree.zig");

const BPlusTree = @import("../datastruct/b_plus_tree.zig").BPlusTree;

const Loop = @import("../Loop.zig");
const AppEvent = @import("../AppEvent.zig");

fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

pub const Entries = BPlusTree([]const u8, Entry, entryOrder);

pub const Entry = struct {
    id: u64,
    path: []const u8,
    kind: Kind,
};

pub const Kind = enum { file, dir };

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.worktree);
//TODO:
//add callback to app
//add new types of evnet to Loop
//add a way to send and subscribe to this events
//create structures for app userdata
//improve btree ranges
//add metadata to entries
//send new events from worktree
//consume new events in filetree

//NOTE:
//the app now will not only hanlde the events that are sended to the Loop
//it will have a similar event listener to the one of the elements only that this time
//the evnets would come from other structures, like the worktree, this would notify every time
//the snapshot gets updated or when a entry gets updated, then, an struct can add his callback
//for that specific event, this are not elements, this are any type of structure, if this strucutre
//contains an element or not is not imporant, this will helps us for example:
//for the file tree, when a change happen(updatesEtnriesSet) i can send many event to the mailbox,
//then, the filetree it would be subscribe to this events, it would consume them and update his state,
//then, if this update triggers a new draw we would call element.requestDraw()
//
//NOTE:
//about the app context userdata, i think is a good place to add my Editor state struct
//it should contains things like workspaces, tabs, splits, code editors,
//i need to think what information it will have every struct and what's going to be his view,
//i think the one i can think well what's going to contains the the workspace, the other ones
//i will think them latter, they are not that imporant right now
//the workspace, the file tree sidebar and floating file tree with serach can be the first parts to get
//impl because there are almost done,
//
//NOTE:
//another thing, it should be good to be capable of taking ranges from my b tree,
//and returning a n iterator that move inside this range, it would be better to what
//we do on the diffDirectory function, and it should be nice to add a counter inisde the b tree
//for knowing the ammount of entries,
//
//NOTE:
//another thing, it would be nice to store inside every Entry metadata from every file and directory,
//this could give you better events, things like, file got bigger or smaller, read them again,
//or more things to shod on the file tree, cool shit
pub const Worktree = struct {
    alloc: Allocator,

    snapshot: Snapshot,

    abs_path: []u8,
    root: []u8,

    monitor: Monitor,
    monitor_thread: MonitorThread,
    monitor_thr: std.Thread,

    scanner: Scanner,
    scanner_thread: ScannerThread,
    scanner_thr: std.Thread,

    app_mailbox: ?*Loop.Mailbox = null,
    app_wakeup: ?xev.Async = null,

    pub fn create(abs_path: []const u8, alloc: Allocator, mailbox: *Loop.Mailbox, wakeup: xev.Async) !*Worktree {
        const worktree = try alloc.create(Worktree);
        try worktree.init(abs_path, alloc, mailbox, wakeup);

        return worktree;
    }

    pub fn destroy(self: *Worktree) void {
        self.deinit();
        self.alloc.destroy(self);
    }

    pub fn init(self: *Worktree, abs_path: []const u8, alloc: Allocator, mailbox: *Loop.Mailbox, wakeup: xev.Async) !void {
        const _abs_path = try alloc.dupe(u8, abs_path);
        errdefer alloc.free(_abs_path);

        const root = try alloc.dupe(u8, std.fs.path.basename(_abs_path));
        errdefer alloc.free(root);

        var monitor_thread = try MonitorThread.init(alloc, &self.monitor);
        errdefer monitor_thread.deinit();

        var scanner_thread = try ScannerThread.init(alloc, &self.scanner);
        errdefer scanner_thread.deinit();

        var monitor = try Monitor.init(alloc, self);
        errdefer monitor.deinit();

        var scanner = try Scanner.init(alloc, self, &self.snapshot, _abs_path, root);
        errdefer scanner.deinit();

        var snapshot = try Snapshot.init(alloc);
        errdefer snapshot.deinit();

        self.* = .{
            .alloc = alloc,
            .snapshot = snapshot,
            .root = root,
            .abs_path = _abs_path,
            .scanner = scanner,
            .scanner_thread = scanner_thread,
            .scanner_thr = undefined,
            .monitor = monitor,
            .monitor_thread = monitor_thread,
            .monitor_thr = undefined,
            .app_mailbox = mailbox,
            .app_wakeup = wakeup,
        };

        self.monitor_thr = try std.Thread.spawn(.{}, MonitorThread.threadMain, .{&self.monitor_thread});
        self.scanner_thr = try std.Thread.spawn(.{}, ScannerThread.threadMain, .{&self.scanner_thread});
    }

    pub fn deinit(self: *Worktree) void {
        {
            self.monitor_thread.stop.notify() catch |err| {
                log.err("error notifying monitor thread to stop, may stall err={}", .{err});
            };
            self.monitor_thr.join();
        }

        {
            self.scanner_thread.stop.notify() catch |err| {
                log.err("error notifying scanner thread to stop, may stall err={}", .{err});
            };
            self.scanner_thr.join();
        }

        self.scanner_thread.deinit();
        self.scanner.deinit();

        self.monitor.deinit();
        self.monitor_thread.deinit();

        self.snapshot.deinit();

        self.alloc.free(self.abs_path);
        self.alloc.free(self.root);

        log.info("Worktree closed", .{});
    }

    pub fn initial_scan(self: *Worktree) !void {
        _ = self.scanner_thread.mailbox.push(.initialScan, .instant);
        self.scanner_thread.wakeup.notify() catch |err| {
            log.err("error notifying scanner thread to wakeup, err={}", .{err});
        };
    }

    pub fn notifyAppEvent(self: *Worktree, data: AppEvent.EventData) void {
        const should_destroy = blk: {
            if (self.app_mailbox) |mailbox| {
                if (mailbox.push(.{ .app_event = data }, .instant) != 0) {
                    if (self.app_wakeup) |wakeup| {
                        wakeup.notify() catch {};
                    }
                    break :blk false;
                }
            }
            break :blk true;
        };

        if (should_destroy) {
            switch (data) {
                .worktree_updated => |updated_entries| updated_entries.destroy(),
            }
        }
    }
};
