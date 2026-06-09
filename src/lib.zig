const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const App = @import("app.zig");
const Workspace = @import("workspace.zig");
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

pub export fn odyssey_app_new() ?*App {
    return app_new() catch |err| {
        std.log.err("error initializing app: {}", .{err});
        return null;
    };
}

fn app_new() !*App {
    var app = try state.gpa.create(App);
    errdefer state.gpa.destroy(app);

    try app.init(state.gpa);

    return app;
}

pub export fn odyssey_app_free(app: *App) void {
    app.deinit(state.gpa);
    state.gpa.destroy(app);
}

pub export fn odyssey_workspace_new() ?*Workspace {
    return workspace_new() catch |err| {
        std.log.err("error initializing workspace: {}", .{err});
        return null;
    };
}

fn workspace_new() !*Workspace {
    const workspace = try state.gpa.create(Workspace);
    errdefer state.gpa.destroy(workspace);

    try workspace.init();
    errdefer workspace.deinit(state.gpa);

    return workspace;
}

pub export fn odyssey_workspace_free(workspace: *Workspace) void {
    workspace.deinit(state.gpa);
    state.gpa.destroy(workspace);
}
