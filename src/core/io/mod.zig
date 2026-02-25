const std = @import("std");
const global = @import("../global.zig");
const xev = global.xev;

const Allocator = std.mem.Allocator;
const Thread = @import("Thread.zig");

const log = std.log.scoped(.io);

pub const Io = @This();

pub const File = struct {
    bytes: []const u8,
    stat: Stat,
    alloc: Allocator,

    pub fn deinit(self: File) void {
        self.alloc.free(self.bytes);
    }
};

pub const Stat = struct {
    size: u64 = 0,
    mtime: i128 = 0,
    atime: i128 = 0,
    ctime: i128 = 0,
    mode: u32 = 0,
};

pub const ReadRequest = struct {
    path: []u8,
    completion: xev.Completion = .{},

    xev_file: xev.File,
    fd: std.fs.File,
    buffer: []u8,
    file_stat: Stat = .{},

    alloc: Allocator,

    io: *Io,

    userdata: ?*anyopaque,
    callback: *const fn (userdata: ?*anyopaque, file: ?File) void,

    pub fn init(self: *ReadRequest) !void {
        var file = try std.fs.openFileAbsolute(self.path, .{ .mode = .read_only });
        errdefer file.close();

        const stat = try file.stat();

        const file_stat = Stat{
            .size = stat.size,
            .mtime = stat.mtime,
            .atime = stat.atime,
            .ctime = stat.ctime,
            .mode = @intCast(stat.mode),
        };

        self.file_stat = file_stat;

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
        self.alloc.destroy(self.path);
        self.alloc.destroy(self);
    }
};

alloc: Allocator,
thread: *Thread,

pub fn create(alloc: Allocator, thread: *Thread.Mailbox) !Io {
    const io = try alloc.create(Io);

    io.* = .{
        .alloc = alloc,
        .thread = thread,
    };
    return io;
}

pub fn destroy(self: *Io) void {
    self.alloc.destroy(self);
}

pub fn readFile(
    self: *Io,
    abs_path: []const u8,
    comptime Userdata: type,
    userdata: ?*Userdata,
    callback: *const fn (userdata: ?*Userdata, file: ?File) void,
) !void {
    const path = try self.alloc.dupe(u8, abs_path);
    const req = try self.alloc.create(ReadRequest);

    req.* = .{
        .buffer = undefined,
        .fd = undefined,
        .xev_file = undefined,
        .path = path,
        .alloc = self.alloc,
        .io = self,
        .userdata = userdata,
        .callback = callback,
    };
    if (self.thread.mailbox.push(.{ .read = req }, .instant) != 0) {
        self.thread.wakeup.notify() catch |err| {
            log.err("error notifying io thread to wakeup: {}", .{err});
        };
    } else {
        req.deinit();
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
//
// pub fn onReadError(req: *ReadRequest) void {
//     const callback = req.callback;
//     const userdata = req.userdata;
//     req.alloc.free(req.buffer);
//     req.deinit();
//     callback(userdata, null);
// }
