const std = @import("std");
const Allocator = std.mem.Allocator;
const worktreepkg = @import("../mod.zig");
const Worktree = worktreepkg.Worktree;
const Snapshot = @import("../Snapshot.zig");
const xev = @import("xev").Dynamic;
const Thread = @import("Thread.zig");

const log = std.log.scoped(.worktree_io);

pub const Io = @This();

pub const File = struct {
    bytes: []const u8,
    stat: worktreepkg.Stat,
    alloc: Allocator,

    pub fn deinit(self: File) void {
        self.alloc.free(self.bytes);
    }
};

pub const ReadRequest = struct {
    path: []const u8,
    entry_id: u64,
    completion: xev.Completion = .{},

    xev_file: xev.File,
    fd: std.fs.File,
    buffer: []u8,
    file_stat: worktreepkg.Stat = .{},

    alloc: Allocator,

    io: *Io,

    userdata: ?*anyopaque,
    callback: *const fn (userdata: ?*anyopaque, file: ?File) void,

    pub fn init(self: *ReadRequest) !void {
        var file = try std.fs.openFileAbsolute(self.path, .{ .mode = .read_only });
        errdefer file.close();

        const stat = try file.stat();

        const wt_stat = worktreepkg.Stat{
            .size = stat.size,
            .mtime = stat.mtime,
            .atime = stat.atime,
            .ctime = stat.ctime,
            .mode = @intCast(stat.mode),
        };

        self.io.worktree.scanner.updateEntryStat(self.entry_id, wt_stat);
        self.file_stat = wt_stat;

        const buffer = try self.alloc.alloc(u8, stat.size);
        errdefer self.alloc.free(buffer);

        const xev_file = try xev.File.init(file);
        errdefer xev_file.deinit();

        self.xev_file = xev_file;
        self.fd = file;
        self.buffer = buffer;
    }

    pub fn deinit(self: *ReadRequest) void {
        self.fd.close();
        self.alloc.destroy(self);
    }
};

alloc: Allocator,
worktree: *Worktree,
mailbox: *Thread.Mailbox,

pub fn init(alloc: Allocator, worktree: *Worktree, mailbox: *Thread.Mailbox) Io {
    return .{
        .alloc = alloc,
        .worktree = worktree,
        .mailbox = mailbox,
    };
}

pub fn deinit(self: *Io) void {
    _ = self;
}

pub fn readFile(
    self: *Io,
    entry_id: u64,
    userdata: ?*anyopaque,
    callback: *const fn (userdata: ?*anyopaque, file: ?File) void,
) !void {
    const abs_path = blk: {
        self.worktree.snapshot.mutex.lock();
        defer self.worktree.snapshot.mutex.unlock();
        break :blk self.worktree.snapshot.getAbsPathById(entry_id) orelse {
            log.err("no entry found for id={}", .{entry_id});
            return error.EntryNotFound;
        };
    };

    const req = try self.alloc.create(ReadRequest);
    req.* = .{
        .buffer = undefined,
        .fd = undefined,
        .xev_file = undefined,
        .path = abs_path,
        .entry_id = entry_id,
        .alloc = self.alloc,
        .io = self,
        .userdata = userdata,
        .callback = callback,
    };

    if (self.mailbox.push(.{ .read = req }, .instant) != 0) {
        self.worktree.io_thread.wakeup.notify() catch |err| {
            log.err("error notifying io thread to wakeup: {}", .{err});
        };
    } else {
        self.alloc.destroy(req);
        return error.MailboxFull;
    }
}

pub fn onReadComplete(req: *ReadRequest, bytes_read: usize) void {
    const alloc = req.alloc;
    const callback = req.callback;
    const userdata = req.userdata;
    const buf = req.buffer;
    const file_stat = req.file_stat;

    const file_bytes = alloc.dupe(u8, buf[0..bytes_read]) catch {
        log.err("failed to allocate file bytes", .{});
        alloc.free(buf);
        req.deinit();
        callback(userdata, null);
        return;
    };

    alloc.free(buf);
    req.deinit();

    callback(userdata, File{
        .bytes = file_bytes,
        .stat = file_stat,
        .alloc = alloc,
    });
}

pub fn onReadError(req: *ReadRequest) void {
    const callback = req.callback;
    const userdata = req.userdata;
    req.alloc.free(req.buffer);
    req.deinit();
    callback(userdata, null);
}
