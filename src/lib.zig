const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const heap = std.heap;
const builtin = @import("builtin");

const App = @import("app.zig");
const Runtime = App.Runtime;
const db = @import("db.zig");
const ent = @import("entity.zig");
const global = @import("global.zig");
const os = @import("os.zig");
const Session = @import("session.zig");
const uuid = @import("uuid.zig");
const Workspace = @import("workspace.zig");
const Observer = App.Observer;

const log = std.log.scoped(.lib);

const state = &@import("global.zig").state;

fn Slice(T: type) type {
    return extern struct {
        ptr: ?[*]const T,
        len: usize,

        const empty: @This() = .{ .ptr = null, .len = 0 };

        fn init(bytes: []const T) @This() {
            return .{ .ptr = bytes.ptr, .len = bytes.len };
        }

        pub fn slice(self: @This()) ?[]const T {
            const ptr = self.ptr orelse return null;
            return ptr[0..self.len];
        }
    };
}

pub fn Option(T: type) type {
    return extern struct {
        value: T,
        valid: bool,

        const none: @This() = .{
            .value = undefined,
            .valid = false,
        };

        fn some(val: T) @This() {
            return .{ .value = val, .valid = true };
        }

        fn maybe(val: ?T) @This() {
            if (val) |s| return some(s);
            return .none;
        }

        fn into(self: @This()) ?T {
            return if (self.valid) self.value else null;
        }
    };
}

const String = Slice(u8);

pub export fn odyssey_init(c_argc: c_int, c_argv: [*][*:0]c_char) c_int {
    assert(builtin.link_libc);
    os.raiseFdLimit();

    const argv = @as([*][*:0]u8, @ptrCast(c_argv))[0..@intCast(c_argc)];
    const environ: std.process.Environ.Block = if (@hasField(std.process.Environ.Block, "slice")) environ: {
        const c_environ = std.c.environ;
        var env_count: usize = 0;
        while (c_environ[env_count] != null) : (env_count += 1) {}
        break :environ .{ .slice = c_environ[0..env_count :null] };
    } else .global;

    global.state.init(argv, environ) catch |err| {
        log.err("Global state err={}", .{err});
        return 1;
    };

    return 0;
}

pub export fn odyssey_deinit() void {
    global.state.deinit();
}

pub export fn odyssey_app_new(runtime: *const Runtime) ?*App {
    return app_new(runtime) catch |err| {
        log.err("error initializing app: {}", .{err});
        return null;
    };
}

fn app_new(runtime: *const Runtime) !*App {
    var app = try state.gpa.create(App);
    errdefer state.gpa.destroy(app);

    try app.init(
        state.gpa,
        state.threaded.io(),
        runtime.*,
    );

    return app;
}

pub export fn odyssey_app_run(app: *App) void {
    app.submitTick();

    app.run(.until_done);
}

pub export fn odyssey_app_free(app: *App) void {
    app.deinit();
    state.gpa.destroy(app);
}
