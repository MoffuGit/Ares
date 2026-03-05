const global = @import("global.zig");
const App = @import("App.zig");
const Bus = @import("Bus.zig");
const MutationQueue = @import("mutations/Queue.zig");

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

export fn drainEvents() void {
    global.state.bus.drain();
}

export fn postBatch(app: *App, ptr: [*]const u8, len: usize) void {
    MutationQueue.processBatch(app, ptr[0..len]);
}
