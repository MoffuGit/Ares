const global = @import("global.zig");
const App = @import("mod.zig");
const Bus = @import("Bus.zig");

export fn initState(callback: ?Bus.Callback) void {
    global.state.init(callback);
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
