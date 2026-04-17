const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Io = @import("../io/mod.zig");
const Worktree = @import("../worktree/mod.zig").Worktree;
const global = @import("../global.zig");
const Zinio = @import("../Zinio.zig");
const xev_pkg = @import("xev");

const log = std.log.scoped(.buffer_store);

pub const BufferStore = @This();

alloc: Allocator,
buffers: std.AutoHashMap(u64, Buffer),
io: *Io,
worktree: *Worktree,
listener: global.EventEmitter.Listener = undefined,
zinio: Zinio,

pub fn init(alloc: Allocator, io: *Io, worktree: *Worktree, thread_pool: *xev_pkg.ThreadPool) !BufferStore {
    return .{
        .alloc = alloc,
        .buffers = std.AutoHashMap(u64, Buffer).init(alloc),
        .io = io,
        .worktree = worktree,
        .zinio = try Zinio.init(alloc, thread_pool),
    };
}

pub fn start(self: *BufferStore) !void {
    self.listener = .{
        .ctx = self,
        .handle = handleIoReadComplete,
    };
    try global.state.events.on(.ioReadComplete, self.listener);
}

pub fn deinit(self: *BufferStore) void {
    global.state.events.off(.ioReadComplete, self.listener);

    self.zinio.deinit();

    var it = self.buffers.valueIterator();
    while (it.next()) |buf| {
        buf.deinit();
    }
    self.buffers.deinit();
}

pub fn open(self: *BufferStore, entry_id: u64) ?*Buffer {
    if (self.get(entry_id)) |buf| return buf;

    const abs_path = self.worktree.getAbsPath(entry_id) orelse return null;
    self.buffers.put(entry_id, Buffer.init(self.alloc, entry_id)) catch |err| {
        log.err("failed to create buffer for entry_id={}: {}", .{ entry_id, err });
        return null;
    };

    self.io.readFile(abs_path) catch return null;

    return self.get(entry_id);
}

fn handleIoReadComplete(ctx: *anyopaque, event: global.GlobalEvents) void {
    const self: *BufferStore = @ptrCast(@alignCast(ctx));
    const payload = event.ioReadComplete;

    var it = self.buffers.iterator();
    while (it.next()) |entry| {
        const entry_id = entry.key_ptr.*;
        const buf = entry.value_ptr;

        const abs_path = self.worktree.getAbsPath(entry_id) orelse continue;
        if (!std.mem.eql(u8, abs_path, payload.path)) continue;

        if (payload.file) |f| {
            buf.applyFile(f);
            self.requestHighlight(entry_id, buf, abs_path);
        } else {
            buf.applyError();
        }

        global.state.emitGlobal(.{ .bufferUpdate = entry_id });

        return;
    }
}

fn requestHighlight(self: *BufferStore, entry_id: u64, buf: *Buffer, abs_path: []const u8) void {
    buf.mutex.lock();
    defer buf.mutex.unlock();

    const file = buf.file orelse return;
    const text_snapshot = self.alloc.dupe(u8, file.bytes) catch return;

    const ext = fileExtension(abs_path);
    const ext_owned = self.alloc.dupe(u8, ext) catch {
        self.alloc.free(text_snapshot);
        return;
    };

    self.zinio.schedule(.{
        .entry_id = entry_id,
        .version = buf.text.version,
        .text = text_snapshot,
        .extension = ext_owned,
        .buffer = buf,
    });
}

fn fileExtension(path: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| {
        return path[dot + 1 ..];
    }
    return "";
}

pub fn get(self: *BufferStore, entry_id: u64) ?*Buffer {
    return self.buffers.getPtr(entry_id);
}

pub fn close(self: *BufferStore, entry_id: u64) void {
    if (self.buffers.fetchRemove(entry_id)) |kv| {
        var buf = kv.value;
        buf.deinit();
    }
}
