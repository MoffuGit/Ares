const global = @import("global.zig");

const Settings = @import("settings/mod.zig");
const Io = @import("io/mod.zig");

export fn init_state() void {
    global.state.init();
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

//NOTE:
//this needs to be ffi compatible, maybe i will not use it,
//in teory almost all the io should happen using the project
//but is not bad having this function avaiable
// export fn readFile(io: *Io, abs_path, userdata, callback) !void {}

export fn destroyIo(io: *Io) void {
    io.destroy();
}

test {
    _ = @import("keymaps/mod.zig");
}
