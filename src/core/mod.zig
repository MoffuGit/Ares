const global = @import("global.zig");
const alloc = global.state.alloc;

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");

export fn init_state() void {
    global.state.init();
}

export fn createSettings() !*Settings {
    return try Settings.create(alloc);
}

export fn destroySettings(settings: *Settings) void {
    settings.destroy();
}

export fn loadSettings(settings: *Settings, path: []const u8) !void {
    try settings.load(path);
}

export fn createIo() !*Io {
    return try Io.create(alloc);
}

//NOTE:
//this needs to be ffi compatible
// export fn readFile(io: *Io, abs_path, userdata, callback) !void {}

export fn destroyIo(io: *Io) void {
    io.destroy();
}
