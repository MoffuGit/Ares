const std = @import("std");
const xev = @import("../global.zig").xev;

const Monitor = @import("monitor/mod.zig");
const MonitorThread = @import("monitor/Thread.zig");

const Scanner = @import("scanner/mod.zig");
const ScannerThread = @import("scanner/Thread.zig");
pub const UpdatedEntriesSet = Scanner.UpdatedEntriesSet;

const Snapshot = @import("Snapshot.zig");

const BPlusTree = @import("../datastruct/b_plus_tree.zig").BPlusTree;

const Loop = @import("../app/Loop.zig");

fn entryOrder(a: []const u8, b: []const u8) std.math.Order {
    return std.mem.order(u8, a, b);
}

pub const Entries = BPlusTree([]const u8, Entry, entryOrder);

pub const Stat = struct {
    /// File size in bytes (0 for directories)
    size: u64 = 0,
    /// Last modification time (nanoseconds since epoch)
    mtime: i128 = 0,
    /// Last access time (nanoseconds since epoch)
    atime: i128 = 0,
    /// Creation time (nanoseconds since epoch, if available)
    ctime: i128 = 0,
    /// File mode/permissions
    mode: u32 = 0,
};

pub const Entry = struct {
    id: u64,
    kind: Kind,
    file_type: FileType = .unknown,
    stat: Stat = .{},
};

pub const Kind = enum { file, dir };

pub const FileType = enum {
    zig,
    c,
    cpp,
    h,
    py,
    js,
    ts,
    json,
    xml,
    yaml,
    toml,
    md,
    txt,
    html,
    css,
    sh,
    go,
    rs,
    java,
    rb,
    lua,
    makefile,
    dockerfile,
    gitignore,
    license,
    unknown,

    pub fn fromName(name: []const u8) FileType {
        if (std.mem.eql(u8, name, "Makefile") or std.mem.eql(u8, name, "makefile") or std.mem.eql(u8, name, "GNUmakefile")) return .makefile;
        if (std.mem.eql(u8, name, "Dockerfile") or std.mem.startsWith(u8, name, "Dockerfile.")) return .dockerfile;
        if (std.mem.eql(u8, name, ".gitignore")) return .gitignore;
        if (std.mem.eql(u8, name, "LICENSE") or std.mem.eql(u8, name, "LICENSE.md") or std.mem.eql(u8, name, "LICENSE.txt")) return .license;

        const ext = std.fs.path.extension(name);
        if (ext.len == 0) return .unknown;
        const e = ext[1..];

        if (std.mem.eql(u8, e, "zig")) return .zig;
        if (std.mem.eql(u8, e, "c")) return .c;
        if (std.mem.eql(u8, e, "cpp") or std.mem.eql(u8, e, "cc") or std.mem.eql(u8, e, "cxx")) return .cpp;
        if (std.mem.eql(u8, e, "h") or std.mem.eql(u8, e, "hpp") or std.mem.eql(u8, e, "hxx")) return .h;
        if (std.mem.eql(u8, e, "py")) return .py;
        if (std.mem.eql(u8, e, "js") or std.mem.eql(u8, e, "mjs") or std.mem.eql(u8, e, "cjs")) return .js;
        if (std.mem.eql(u8, e, "ts") or std.mem.eql(u8, e, "mts") or std.mem.eql(u8, e, "cts")) return .ts;
        if (std.mem.eql(u8, e, "json")) return .json;
        if (std.mem.eql(u8, e, "xml")) return .xml;
        if (std.mem.eql(u8, e, "yaml") or std.mem.eql(u8, e, "yml")) return .yaml;
        if (std.mem.eql(u8, e, "toml")) return .toml;
        if (std.mem.eql(u8, e, "md") or std.mem.eql(u8, e, "markdown")) return .md;
        if (std.mem.eql(u8, e, "txt")) return .txt;
        if (std.mem.eql(u8, e, "html") or std.mem.eql(u8, e, "htm")) return .html;
        if (std.mem.eql(u8, e, "css")) return .css;
        if (std.mem.eql(u8, e, "sh") or std.mem.eql(u8, e, "bash") or std.mem.eql(u8, e, "zsh")) return .sh;
        if (std.mem.eql(u8, e, "go")) return .go;
        if (std.mem.eql(u8, e, "rs")) return .rs;
        if (std.mem.eql(u8, e, "java")) return .java;
        if (std.mem.eql(u8, e, "rb")) return .rb;
        if (std.mem.eql(u8, e, "lua")) return .lua;
        return .unknown;
    }

    pub fn toString(self: FileType) []const u8 {
        return switch (self) {
            .zig => "zig",
            .c => "c",
            .cpp => "cpp",
            .h => "h",
            .py => "py",
            .js => "js",
            .ts => "ts",
            .json => "json",
            .xml => "xml",
            .yaml => "yaml",
            .toml => "toml",
            .md => "md",
            .txt => "txt",
            .html => "html",
            .css => "css",
            .sh => "sh",
            .go => "go",
            .rs => "rs",
            .java => "java",
            .rb => "rb",
            .lua => "lua",
            .makefile => "makefile",
            .dockerfile => "dockerfile",
            .gitignore => "gitignore",
            .license => "license",
            .unknown => "unknown",
        };
    }
};

const Allocator = std.mem.Allocator;

const log = std.log.scoped(.worktree);

pub const Worktree = struct {
    alloc: Allocator,

    snapshot: Snapshot,

    abs_path: []u8,

    app_loop: ?*Loop,

    monitor: Monitor,
    monitor_thread: MonitorThread,
    monitor_thr: std.Thread,

    scanner: Scanner,
    scanner_thread: ScannerThread,
    scanner_thr: std.Thread,

    pub fn create(abs_path: []const u8, alloc: Allocator, app_loop: ?*Loop) !*Worktree {
        const worktree = try alloc.create(Worktree);
        try worktree.init(abs_path, alloc, app_loop);

        return worktree;
    }

    pub fn destroy(self: *Worktree) void {
        self.deinit();
        self.alloc.destroy(self);
    }

    pub fn init(self: *Worktree, abs_path: []const u8, alloc: Allocator, app_loop: ?*Loop) !void {
        const _abs_path = try alloc.dupe(u8, abs_path);
        errdefer alloc.free(_abs_path);

        var snapshot = try Snapshot.init(alloc);
        errdefer snapshot.deinit();

        var monitor_thread = try MonitorThread.init(alloc, &self.monitor);
        errdefer monitor_thread.deinit();

        var scanner_thread = try ScannerThread.init(alloc, &self.scanner);
        errdefer scanner_thread.deinit();

        var monitor = try Monitor.init(alloc, self);
        errdefer monitor.deinit();

        var scanner = try Scanner.init(alloc, self, &self.snapshot, _abs_path);
        errdefer scanner.deinit();

        self.* = .{
            .alloc = alloc,
            .snapshot = snapshot,
            .abs_path = _abs_path,
            .app_loop = app_loop,
            .scanner = scanner,
            .scanner_thread = scanner_thread,
            .scanner_thr = undefined,
            .monitor = monitor,
            .monitor_thread = monitor_thread,
            .monitor_thr = undefined,
        };

        self.monitor_thr = try std.Thread.spawn(.{}, MonitorThread.threadMain, .{&self.monitor_thread});
        self.scanner_thr = try std.Thread.spawn(.{}, ScannerThread.threadMain, .{&self.scanner_thread});

        _ = self.scanner_thread.mailbox.push(.initialScan, .instant);
        self.scanner_thread.wakeup.notify() catch |err| {
            log.err("error notifying scanner thread to wakeup, err={}", .{err});
        };
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

        log.info("Worktree closed", .{});
    }

    /// Send updated entries to the app loop. Returns true if successfully sent.
    pub fn notifyUpdatedEntries(self: *Worktree, entries: *UpdatedEntriesSet) bool {
        if (self.app_loop) |loop| {
            if (loop.mailbox.push(.{ .app = .{ .worktreeUpdatedEntries = entries } }, .instant) != 0) {
                loop.wakeup.notify() catch |err| {
                    log.err("error notifying app loop: {}", .{err});
                };
                return true;
            }
        }
        return false;
    }
};
