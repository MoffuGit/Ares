const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Io = @import("../worktree/io/mod.zig");
const EventQueue = @import("../EventQueue.zig");

const log = std.log.scoped(.buffer_store);

pub const BufferStore = @This();

const ReadContext = struct {
    store: *BufferStore,
    entry_id: u64,
};

alloc: Allocator,
buffers: std.AutoHashMap(u64, Buffer),
io: *Io,
events: *EventQueue,

pub fn init(alloc: Allocator, io: *Io, events: *EventQueue) BufferStore {
    return .{
        .alloc = alloc,
        .buffers = std.AutoHashMap(u64, Buffer).init(alloc),
        .io = io,
        .events = events,
    };
}

pub fn deinit(self: *BufferStore) void {
    var it = self.buffers.valueIterator();
    while (it.next()) |buf| {
        buf.deinit();
    }
    self.buffers.deinit();
}

pub fn open(self: *BufferStore, entry_id: u64) ?*Buffer {
    if (self.buffers.getPtr(entry_id)) |buf| return buf;

    self.buffers.put(entry_id, Buffer.initLoading(entry_id)) catch |err| {
        log.err("failed to create buffer for entry_id={}: {}", .{ entry_id, err });
        return null;
    };

    const ctx = self.alloc.create(ReadContext) catch |err| {
        log.err("failed to alloc read context for entry_id={}: {}", .{ entry_id, err });
        if (self.buffers.getPtr(entry_id)) |buf| buf.applyError();
        return self.buffers.getPtr(entry_id);
    };
    ctx.* = .{ .store = self, .entry_id = entry_id };

    self.io.readFile(entry_id, @ptrCast(ctx), onReadComplete) catch |err| {
        log.err("failed to request read for entry_id={}: {}", .{ entry_id, err });
        self.alloc.destroy(ctx);
        if (self.buffers.getPtr(entry_id)) |buf| buf.applyError();
        return self.buffers.getPtr(entry_id);
    };

    return self.buffers.getPtr(entry_id);
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

fn onReadComplete(userdata: ?*anyopaque, file: ?Io.File) void {
    const ctx: *ReadContext = @ptrCast(@alignCast(userdata));
    const self = ctx.store;
    const entry_id = ctx.entry_id;
    self.alloc.destroy(ctx);

    if (self.buffers.getPtr(entry_id)) |buf| {
        if (file) |f| {
            buf.applyFile(f);
        } else {
            buf.applyError();
            log.err("read failed for entry_id={}", .{entry_id});
        }
    } else {
        if (file) |f| {
            var tmp = f;
            tmp.deinit();
        }
    }

    self.events.push(.{ .buffer_updated = entry_id });
}
