const global = @import("global.zig");

pub fn init_state() void {
    global.state.init();
}
