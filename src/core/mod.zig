const std = @import("std");
const global = @import("global.zig");
const Bus = @import("Bus.zig");

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");
const Monitor = @import("monitor/mod.zig");

export fn initState(callback: ?Bus.JsCallback) void {
    global.state.init(callback);
}

export fn deinitState() void {
    global.state.deinit();
}

export fn drainEvents() void {
    global.state.bus.drain();
}
export fn createSettings() ?*Settings {
    return Settings.create(global.state.alloc) catch null;
}

export fn destroySettings(settings: *Settings) void {
    settings.destroy();
}

//TODO:
//update the ts bindings
// export fn loadSettings(settings: *Settings, path: [*]const u8, len: u64, monitor: *Monitor) void {
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
