const std = @import("std");
const global = @import("../global.zig");
const xev = global.xev;

const Allocator = std.mem.Allocator;
const Thread = @import("Thread.zig");

pub const types = @import("types.zig");
pub const File = types.File;
pub const Stat = types.Stat;

const log = std.log.scoped(.io);

pub const Io = @This();

pub const ReadRequest = struct {
    path: []u8,
    completion: xev.Completion = .{},

    xev_file: xev.File = undefined,
    fd: ?std.fs.File = null,
    buffer: ?[]u8 = null,
    file_stat: Stat = .{},

    alloc: Allocator,

    io: *Io,

    pub fn init(self: *ReadRequest) !void {
        var file = try std.fs.openFileAbsolute(self.path, .{ .mode = .read_only });
        errdefer file.close();

        const stat = try file.stat();

        self.file_stat = Stat{
            .size = stat.size,
            .mtime = stat.mtime,
            .atime = stat.atime,
            .ctime = stat.ctime,
            .mode = @intCast(stat.mode),
        };

        const buffer = try self.alloc.alloc(u8, stat.size);
        errdefer self.alloc.free(buffer);

        const xev_file = try xev.File.init(file);

        self.xev_file = xev_file;
        self.fd = file;
        self.buffer = buffer;
    }

    pub fn deinit(self: *ReadRequest) void {
        if (self.fd) |fd| fd.close();
        if (self.buffer) |buf| self.alloc.free(buf);
        self.alloc.free(self.path);
        self.alloc.destroy(self);
    }
};

pub const WriteRequest = struct {
    path: []u8,
    data: []u8,
    completion: xev.Completion = .{},

    xev_file: xev.File = undefined,
    fd: ?std.fs.File = null,

    alloc: Allocator,

    io: *Io,

    pub fn init(self: *WriteRequest) !void {
        var file = try std.fs.createFileAbsolute(self.path, .{ .truncate = true });
        errdefer file.close();

        const xev_file = try xev.File.init(file);

        self.xev_file = xev_file;
        self.fd = file;
    }

    pub fn deinit(self: *WriteRequest) void {
        if (self.fd) |fd| fd.close();
        self.alloc.free(self.data);
        self.alloc.free(self.path);
        self.alloc.destroy(self);
    }
};

alloc: Allocator,
thread: Thread,
thr: std.Thread,
pending_reads: std.ArrayListUnmanaged(*ReadRequest),
pending_writes: std.ArrayListUnmanaged(*WriteRequest),

pub fn create(alloc: Allocator, thread_pool: *xev.ThreadPool) !*Io {
    var io = try alloc.create(Io);

    io.* = .{
        .alloc = alloc,
        .thread = try Thread.init(alloc, io, thread_pool),
        .thr = undefined,
        .pending_reads = .{},
        .pending_writes = .{},
    };

    io.thr = try std.Thread.spawn(.{}, Thread.threadMain, .{&io.thread});

    return io;
}

pub fn destroy(self: *Io) void {
    {
        self.thread.stop.notify() catch |err| {
            log.err("error notifying io thread to stop, may stall err={}", .{err});
        };
        self.thr.join();
    }

    // Clean up any requests still in the mailbox
    while (self.thread.mailbox.pop()) |message| {
        switch (message) {
            .read => |req| req.deinit(),
            .write => |req| req.deinit(),
        }
    }

    // Clean up any pending reads that were submitted but never completed
    for (self.pending_reads.items) |req| {
        req.deinit();
    }
    self.pending_reads.deinit(self.alloc);

    // Clean up any pending writes that were submitted but never completed
    for (self.pending_writes.items) |req| {
        req.deinit();
    }
    self.pending_writes.deinit(self.alloc);

    self.thread.deinit();
    self.alloc.destroy(self);
}

pub fn readFile(self: *Io, abs_path: []const u8) !void {
    const path = try self.alloc.dupe(u8, abs_path);
    const req = try self.alloc.create(ReadRequest);

    req.* = .{
        .path = path,
        .alloc = self.alloc,
        .io = self,
    };

    if (self.thread.mailbox.push(.{ .read = req }, .instant) != 0) {
        self.thread.wakeup.notify() catch |err| {
            log.err("error notifying io thread to wakeup: {}", .{err});
        };
    } else {
        self.alloc.free(path);
        self.alloc.destroy(req);
    }
}

pub fn addPendingRead(self: *Io, req: *ReadRequest) void {
    self.pending_reads.append(self.alloc, req) catch |err| {
        log.err("failed to track pending read: {}", .{err});
    };
}

pub fn removePendingRead(self: *Io, req: *ReadRequest) void {
    for (self.pending_reads.items, 0..) |item, i| {
        if (item == req) {
            _ = self.pending_reads.swapRemove(i);
            return;
        }
    }
}

pub fn onReadComplete(req: *ReadRequest, bytes_read: usize) void {
    const alloc = req.alloc;
    const path = req.path;
    const buf = req.buffer.?;
    const file_stat = req.file_stat;

    const file_bytes = alloc.dupe(u8, buf[0..bytes_read]) catch {
        log.err("failed to allocate file bytes", .{});
        req.io.removePendingRead(req);
        global.state.emitGlobal(.{ .ioReadComplete = .{ .path = path, .file = null } });
        req.deinit();
        return;
    };

    // Remove from pending and emit before deinit (path is freed in deinit)
    req.io.removePendingRead(req);

    const file = File{
        .bytes = file_bytes,
        .stat = file_stat,
        .alloc = alloc,
    };

    global.state.emitGlobal(.{ .ioReadComplete = .{
        .path = path,
        .file = file,
    } });

    // IO owns the read buffer; consumers must clone what they need.
    file.deinit();

    req.deinit();
}

pub fn onReadError(req: *ReadRequest) void {
    const path = req.path;
    req.io.removePendingRead(req);

    global.state.emitGlobal(.{ .ioReadComplete = .{ .path = path, .file = null } });

    req.deinit();
}

pub fn writeFile(self: *Io, abs_path: []const u8, data: []const u8) !void {
    const path = try self.alloc.dupe(u8, abs_path);
    errdefer self.alloc.free(path);

    const data_copy = try self.alloc.dupe(u8, data);
    errdefer self.alloc.free(data_copy);

    const req = try self.alloc.create(WriteRequest);

    req.* = .{
        .path = path,
        .data = data_copy,
        .alloc = self.alloc,
        .io = self,
    };

    if (self.thread.mailbox.push(.{ .write = req }, .instant) != 0) {
        self.thread.wakeup.notify() catch |err| {
            log.err("error notifying io thread to wakeup: {}", .{err});
        };
    } else {
        self.alloc.free(data_copy);
        self.alloc.free(path);
        self.alloc.destroy(req);
    }
}

pub fn addPendingWrite(self: *Io, req: *WriteRequest) void {
    self.pending_writes.append(self.alloc, req) catch |err| {
        log.err("failed to track pending write: {}", .{err});
    };
}

pub fn removePendingWrite(self: *Io, req: *WriteRequest) void {
    for (self.pending_writes.items, 0..) |item, i| {
        if (item == req) {
            _ = self.pending_writes.swapRemove(i);
            return;
        }
    }
}

pub fn onWriteComplete(req: *WriteRequest, bytes_written: usize) void {
    const path = req.path;

    req.io.removePendingWrite(req);

    global.state.emitGlobal(.{ .ioWriteComplete = .{
        .path = path,
        .bytes_written = bytes_written,
    } });

    req.deinit();
}

pub fn onWriteError(req: *WriteRequest) void {
    const path = req.path;
    req.io.removePendingWrite(req);

    global.state.emitGlobal(.{ .ioWriteComplete = .{ .path = path, .bytes_written = null } });

    req.deinit();
}
