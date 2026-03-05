const std = @import("std");
const global = @import("global.zig");
const Monitor = @import("monitor/mod.zig");
const Settings = @import("settings/mod.zig");

test {
    _ = @import("datastruct");
    _ = @import("lib.zig");
}

test {
    const testings = std.testing;
    const alloc = testings.allocator;
    global.state.init(null);
    defer global.state.deinit();

    const monitor = try Monitor.create(alloc);
    defer monitor.destroy();

    const settings = try Settings.create(alloc);
    defer settings.destroy();

    const abs_path = try std.fs.cwd().realpathAlloc(alloc, "settings");
    defer alloc.free(abs_path);

    try settings.load(abs_path, monitor);
}
