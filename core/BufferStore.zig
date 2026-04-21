const std = @import("std");
const Allocator = std.mem.Allocator;
const Buffer = @import("Buffer.zig");
const Io = @import("io/mod.zig");
const Settings = @import("settings/mod.zig");
const Worktree = @import("worktree/mod.zig").Worktree;
const global = @import("global.zig");
const xev_pkg = @import("xev");

const log = std.log.scoped(.buffer_store);

pub const BufferStore = @This();

alloc: Allocator,
buffers: std.AutoHashMap(u64, Buffer),
io: *Io,
worktree: *Worktree,
settings: *Settings,

pub fn init(alloc: Allocator, io: *Io, settings: *Settings, worktree: *Worktree, _: *xev_pkg.ThreadPool) !BufferStore {
    settings.rwlock.lockShared();
    defer settings.rwlock.unlockShared();

    return .{
        .alloc = alloc,
        .buffers = std.AutoHashMap(u64, Buffer).init(alloc),
        .io = io,
        .worktree = worktree,
        .settings = settings,
    };
}

pub fn start(self: *BufferStore) !void {
    try global.state.events.on(.ioReadComplete, .{
        .ctx = self,
        .handle = handleIoReadComplete,
    });

    try global.state.events.on(.themeUpdate, .{
        .ctx = self,
        .handle = handleThemeUpdate,
    });
}

pub fn deinit(self: *BufferStore) void {
    global.state.events.off(.ioReadComplete, .{
        .ctx = self,
        .handle = handleIoReadComplete,
    });
    global.state.events.off(.themeUpdate, .{
        .ctx = self,
        .handle = handleThemeUpdate,
    });

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
        } else {
            buf.applyError();
        }

        global.state.emitGlobal(.{ .bufferUpdate = entry_id });

        return;
    }
}

fn handleThemeUpdate(ctx: *anyopaque, _: global.GlobalEvents) void {
    const self: *BufferStore = @ptrCast(@alignCast(ctx));
    _ = self;

    // {
    //     self.settings.rwlock.lockShared();
    //     defer self.settings.rwlock.unlockShared();
    //
    //     _ = self.zinio.runtime.setTheme(self.settings.theme_json);
    // }
    //
    // var it = self.buffers.iterator();
    // while (it.next()) |entry| {
    //     const entry_id = entry.key_ptr.*;
    //     const buf = entry.value_ptr;
    //     const abs_path = self.worktree.getAbsPath(entry_id) orelse continue;
    //     self.requestHighlight(entry_id, buf, abs_path);
    // }
}

// fn requestHighlight(self: *BufferStore, entry_id: u64, buf: *Buffer, abs_path: []const u8) void {
//     buf.mutex.lock();
//     defer buf.mutex.unlock();
//
//     const file = buf.file orelse return;
//     const text_snapshot = self.alloc.dupe(u8, file.bytes) catch return;
//     errdefer self.alloc.free(text_snapshot);
//
//     const ext = fileExtension(abs_path);
//     const ext_owned = self.alloc.dupe(u8, ext) catch {
//         return;
//     };
//     errdefer self.alloc.free(ext_owned);
//
//     self.zinio.schedule(.{
//         .entry_id = entry_id,
//         .version = buf.text.version,
//         .text = text_snapshot,
//         .extension = ext_owned,
//         .buffer = buf,
//     });
// }

// fn fileExtension(path: []const u8) []const u8 {
//     if (std.mem.lastIndexOfScalar(u8, path, '.')) |dot| {
//         return path[dot + 1 ..];
//     }
//     return "";
// }

pub fn get(self: *BufferStore, entry_id: u64) ?*Buffer {
    return self.buffers.getPtr(entry_id);
}

pub fn close(self: *BufferStore, entry_id: u64) void {
    if (self.buffers.fetchRemove(entry_id)) |kv| {
        var buf = kv.value;
        buf.deinit();
    }
}
