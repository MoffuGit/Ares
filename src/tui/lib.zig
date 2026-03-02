const global = @import("global.zig");
const App = @import("mod.zig");

export fn initState() void {
    global.state.init();
}

export fn deinitState() void {
    global.state.deinit();
}

export fn createApp() ?*App {
    return App.create(global.state.alloc, .{}) catch null;
}

export fn destroyApp(app: *App) void {
    app.destroy();
}
