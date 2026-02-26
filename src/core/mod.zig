const std = @import("std");
const global = @import("global.zig");
const Bus = @import("Bus.zig");

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");
const Monitor = @import("monitor/mod.zig");

pub const Allocated = struct {
    @"test": u64,
};

const TestData = extern struct {
    id: u64,
    allocated: *Allocated,
};

export fn initState(callback: ?Bus.JsCallback) void {
    global.state.init(callback);
}

export fn pollEvents() void {
    global.state.bus.poll();
}

export fn startLoop() void {
    const thread = std.Thread.spawn(.{}, loopFn, .{}) catch return;
    thread.detach();
}

fn loopFn() void {
    while (true) {
        const allocated = global.state.alloc.create(Allocated) catch return;
        allocated.* = .{ .@"test" = 456 };

        const data = TestData{ .id = 42, .allocated = allocated };
        global.state.bus.emit(.test_data, std.mem.asBytes(&data));
        std.Thread.sleep(2 * std.time.ns_per_s);
    }
}

export fn destroyAllocated(allocated: *Allocated) void {
    global.state.alloc.destroy(allocated);
}

export fn createSettings() ?*Settings {
    return Settings.create(global.state.alloc) catch null;
}

export fn destroySettings(settings: *Settings) void {
    settings.destroy();
}

// export fn loadSettings(settings: *Settings, path: [*]const u8) void {
//     settings.load(path) catch {};
// }

export fn createIo() ?*Io {
    return Io.create(global.state.alloc) catch null;
}

export fn destroyIo(io: *Io) void {
    io.destroy();
}

export fn createMonitor() ?*Monitor {
    return Monitor.create(global.state.alloc) catch null;
}

export fn destroyMonitor(monitor: *Monitor) void {
    monitor.destroy();
}

test {
    _ = @import("keymaps/mod.zig");
    _ = @import("monitor/mod.zig");
    _ = @import("worktree/mod.zig");
}
