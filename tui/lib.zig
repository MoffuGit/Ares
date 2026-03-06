const global = @import("global.zig");
const App = @import("App.zig");
const Window = @import("window/mod.zig");
const Bus = @import("Bus.zig");
const Mutations = @import("mutations/mod.zig");

export fn initState(callback: ?Bus.Callback) void {
    global.state.init(callback);
}

export fn deinitState() void {
    global.state.deinit();
}

export fn createApp() ?*App {
    return App.create(
        global.state.alloc,
    ) catch null;
}

export fn destroyApp(app: *App) void {
    app.destroy();
}

export fn getWindow(app: *App) *Window {
    return &app.window;
}

export fn createMutations(window: *Window) ?*Mutations {
    return Mutations.create(global.state.alloc, window) catch null;
}

export fn processMutations(mutations: *Mutations, ptr: [*]const u8, len: u64) void {
    mutations.processMutations(ptr[0..len]);
}

export fn drainEvents() void {
    global.state.bus.drain();
}
