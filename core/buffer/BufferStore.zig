const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Io = @import("../io/mod.zig");
const Worktree = @import("../worktree/mod.zig").Worktree;
const global = @import("../global.zig");
const zintect = @import("zintect");

const log = std.log.scoped(.buffer_store);

pub const BufferStore = @This();

alloc: Allocator,
instance: zintect.Instance,
buffers: std.AutoHashMap(u64, Buffer),
io: *Io,
worktree: *Worktree,
listener: global.EventEmitter.Listener = undefined,

pub fn init(alloc: Allocator, io: *Io, worktree: *Worktree) BufferStore {
    return .{
        .instance = zintect.Instance.init() catch @panic("fuck"),
        .alloc = alloc,
        .buffers = std.AutoHashMap(u64, Buffer).init(alloc),
        .io = io,
        .worktree = worktree,
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

    var it = self.buffers.valueIterator();
    while (it.next()) |buf| {
        buf.deinit();
    }
    self.instance.deinit();
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
        } else {
            buf.applyError();
        }

        global.state.emitGlobal(.{ .bufferUpdate = entry_id });

        return;
    }
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
