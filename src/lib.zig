const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const App = @import("app.zig");
const Options = App.Options;
const Observers = App.Observers;
const ent = @import("entity.zig");
const global = @import("global.zig");
const Workspace = @import("workspace.zig");

const state = &@import("global.zig").state;

const WorkspaceCallback = *const fn (*anyopaque, ExternWorkspace) callconv(.c) bool;

const Entity = extern struct {
    entity: ExternEntity,
    valid: bool,

    const err: @This() = .{
        .entity = undefined,
        .valid = false,
    };

    fn ok(entity: ent.AnyEntity) @This() {
        return .{ .entity = .init(entity), .valid = true };
    }
};

pub const ExternEntity = extern struct {
    store: *anyopaque,
    type_id: *anyopaque,
    id: u64,

    pub fn init(entity: ent.AnyEntity) @This() {
        return .{
            .store = entity.store,
            .type_id = entity.type_id,
            .id = @bitCast(entity.id),
        };
    }

    pub fn any(self: @This()) ent.AnyEntity {
        return .{
            .store = @ptrCast(@alignCast(self.store)),
            .type_id = @ptrCast(@alignCast(self.type_id)),
            .id = @bitCast(self.id),
        };
    }
};

const ExternObserver = extern struct {
    ptr: *anyopaque,
    key: u64,
    id: u32,

    fn init(sub: *const Observers.Subscription) @This() {
        return .{
            .key = @bitCast(sub.key),
            .id = sub.id,
            .ptr = sub.subscriptions,
        };
    }

    pub fn subscription(self: *const @This()) Observers.Subscription {
        return .{
            .id = self.id,
            .key = @bitCast(self.key),
            .subscriptions = @ptrCast(@alignCast(self.ptr)),
        };
    }
};

const Observer = extern struct {
    observer: ExternObserver,
    valid: bool,

    const err: @This() = .{
        .observer = undefined,
        .valid = false,
    };

    fn ok(observer: *const Observers.Subscription) @This() {
        return .{
            .valid = true,
            .observer = .init(observer),
        };
    }
};

const ExternWorkspace = extern struct {
    count: usize,

    pub fn init(w: *const Workspace) @This() {
        return .{
            .count = w.count,
        };
    }
};

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

pub export fn odyssey_app_new(options: *const Options) ?*App {
    return app_new(options) catch |err| {
        std.log.err("error initializing app: {}", .{err});
        return null;
    };
}

fn app_new(options: *const Options) !*App {
    var app = try state.gpa.create(App);
    errdefer state.gpa.destroy(app);

    try app.init(options.*, state.gpa, state.threaded.io());

    return app;
}

pub export fn odyssey_app_free(app: *App) void {
    app.deinit();
    state.gpa.destroy(app);
}

pub export fn odyssey_app_flush(app: *App) void {
    app.flush();
}

pub export fn odyssey_drop_entity(entity: ExternEntity) void {
    entity.any().drop();
}

pub export fn odyssey_workspace_new(app: *App) Entity {
    const workspace = workspace_new(app) catch |err| {
        std.log.err("error creating workspace={}", .{err});
        return .err;
    };

    return .ok(workspace.any);
}

fn workspace_new(app: *App) !ent.Entity(Workspace) {
    const workspace: ent.Entity(Workspace) = try .new(app, .{});
    errdefer workspace.drop();

    return workspace;
}

pub export fn odyssey_workspace_observe(
    app: *App,
    workspace: ExternEntity,
    function: WorkspaceCallback,
    userdata: *anyopaque,
) Observer {
    const entity = workspace.any().into(Workspace) orelse return .err;
    const TypeErased = struct {
        fn callback(_app: *App, _workspace: ent.Entity(Workspace), _userdata: *anyopaque, _function: WorkspaceCallback) bool {
            return _function(_userdata, .init(_workspace.read(_app)));
        }
    };
    const subscription = app.observe(entity, TypeErased.callback, .{ userdata, function }) catch |err| {
        std.log.err("error observing workspace={}", .{err});
        return .err;
    };

    return .ok(&subscription);
}

pub export fn odyssey_workspace_unobserve(observer: ExternObserver) void {
    const sub = observer.subscription();
    sub.unsubscribe() catch |err| {
        std.log.err("unsubscribe err={}", .{err});
    };
}
