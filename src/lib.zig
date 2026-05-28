const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const CoreApp = @import("app.zig");
const global = @import("global.zig");

const state = &@import("global.zig").state;

pub export fn odyssey_init(c_argc: c_int, c_argv: [*][*:0]c_char) c_int {
    assert(builtin.link_libc);
    const argv = @as([*][*:0]u8, @ptrCast(c_argv))[0..@intCast(c_argc)];
    const environ: std.process.Environ.Block = if (@hasField(std.process.Environ.Block, "slice")) environ: {
        const c_environ = std.c.environ;
        var env_count: usize = 0;
        while (c_environ[env_count] != null) : (env_count += 1) {}
        break :environ .{ .slice = c_environ[0..env_count :null] };
    } else .global;

    global.state.init(argv, environ) catch return 1;
    return 0;
}

pub export fn odyssey_deinit() void {
    global.state.deinit();
}

pub const App = extern struct {
    core_app: *CoreApp,

    pub fn init(self: *App, core_app: *CoreApp) !void {
        self.* = .{
            .core_app = core_app,
        };
    }
};

pub export fn odyssey_app_new() ?*App {
    return app_new() catch |err| {
        std.log.err("error initializing app: {}", .{err});
        return null;
    };
}

fn app_new() !*App {
    var app = try state.gpa.create(App);
    errdefer state.gpa.destroy(app);

    const core_app = try state.gpa.create(CoreApp);
    errdefer state.gpa.destroy(core_app);

    try core_app.init(state.gpa, state.threaded.io());
    try app.init(core_app);

    return app;
}

pub export fn odyssey_app_free(app: *App) void {
    const core_app = app.core_app;
    core_app.deinit();

    state.gpa.destroy(app);
    state.gpa.destroy(core_app);
}
