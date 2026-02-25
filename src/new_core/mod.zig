const global = @import("global.zig");

pub fn init_state() void {
    global.state.init();
}

pub fn deinit_state() void {
    global.state.deinit();
}
