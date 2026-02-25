const global = @import("global.zig");

export fn init_state() void {
    global.state.init();
}
