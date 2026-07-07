const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

const App = @import("app.zig");
const Options = App.Options;
const Observers = App.Observers;
const db = @import("db.zig");
const ent = @import("entity.zig");
const global = @import("global.zig");
const Session = @import("session.zig");
const uuid = @import("uuid.zig");
const Workspace = @import("workspace.zig");

const state = &@import("global.zig").state;

fn Slice(T: type) type {
    return extern struct {
        ptr: ?[*]const T,
        len: usize,

        const empty: @This() = .{ .ptr = null, .len = 0 };

        fn init(bytes: []const T) @This() {
            return .{ .ptr = bytes.ptr, .len = bytes.len };
        }
    };
}

fn Option(T: type) type {
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
    };
}

const String = Slice(u8);

pub export fn odyssey_init(c_argc: c_int, c_argv: [*][*:0]c_char) c_int {
    assert(builtin.link_libc);
    const argv = @as([*][*:0]u8, @ptrCast(c_argv))[0..@intCast(c_argc)];
    const environ: std.process.Environ.Block = if (@hasField(std.process.Environ.Block, "slice")) environ: {
        const c_environ = std.c.environ;
        var env_count: usize = 0;
        while (c_environ[env_count] != null) : (env_count += 1) {}
        break :environ .{ .slice = c_environ[0..env_count :null] };
    } else .global;

    global.state.init(argv, environ) catch |err| {
        std.log.err("Global state err={}", .{err});
        return 1;
    };

    return 0;
}

pub export fn odyssey_deinit() void {
    global.state.deinit();
}

pub export fn odyssey_db_start() c_int {
    db_start() catch |err| {
        std.log.err("error starting zqlite pool: {}", .{err});
        return 1;
    };
    return 0;
}

pub export fn odyssey_db_stop() void {
    db.deinit();
}

fn db_start() !void {
    try db.init(global.state.gpa);
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

pub export fn odyssey_workspace_new(app: *App) MaybeEntity {
    const workspace = workspace_new(app) catch |err| {
        std.log.err("error creating workspace={}", .{err});
        return .none;
    };

    return .some(.init(workspace.any));
}

fn workspace_new(app: *App) !ent.Entity(Workspace) {
    const workspace: ent.Entity(Workspace) = try .new(app, .{});
    errdefer workspace.drop();

    return workspace;
}

pub export fn odyssey_remove_observer(observer: ExternObserver) void {
    const sub = observer.subscription();
    sub.unsubscribe() catch |err| {
        std.log.err("unsubscribe err={}", .{err});
    };
}

pub export fn odyssey_session_new(app: *App) MaybeEntity {
    const session = session_new(app) catch |err| {
        std.log.err("error creating session={}", .{err});
        return .none;
    };

    return .some(.init(session.any));
}

fn session_new(app: *App) !ent.Entity(Session) {
    const io = state.threaded.io();
    const gpa = state.gpa;
    const conn = try db.acquire(io);
    defer db.release(io, conn);

    const session: ent.Entity(Session) = try .new(app, .{
        gpa,
        &conn,
        io,
    });

    return session;
}

const MaybeEntity = Option(ExternEntity);

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

const MaybeObserver = Option(ExternObserver);

const ExternSerializedWindowBounds = extern struct {
    x: f64,
    y: f64,
    width: f64,
    height: f64,

    fn init(bounds: Workspace.persistence.SerializedWindowBounds) @This() {
        return .{
            .x = bounds.x,
            .y = bounds.y,
            .width = bounds.width,
            .height = bounds.height,
        };
    }
};

const ExternSerializedWorkspace = extern struct {
    paths: Slice(String),
    session: Option(u128),
    window: Option(ExternSerializedWindowBounds),
    has_window: bool,
    timestamp: i64,
    has_timestamp: bool,
    id: i64,

    fn init(workspace: Workspace.SerializedWorkspace, paths: []String) @This() {
        return .{
            .paths = .init(paths),
            .session = if (workspace.session) |session| .some(session) else .none,
            .window = if (workspace.window) |window| .some(.init(window)) else .none,
            .has_window = workspace.window != null,
            .timestamp = workspace.timestamp orelse 0,
            .has_timestamp = workspace.timestamp != null,
            .id = workspace.id,
        };
    }
};

const ExternSerializedWorkspaces = extern struct {
    ptr: ?[*]ExternSerializedWorkspace,
    len: usize,

    const empty: @This() = .{ .ptr = null, .len = 0 };

    fn init(workspaces: []Workspace.SerializedWorkspace) !@This() {
        const serialized = try state.gpa.alloc(ExternSerializedWorkspace, workspaces.len);
        errdefer state.gpa.free(serialized);

        var workspace_index: usize = 0;
        errdefer {
            for (serialized[0..workspace_index]) |workspace| {
                if (workspace.paths.ptr) |paths| state.gpa.free(paths[0..workspace.paths.len]);
            }
        }

        for (workspaces, serialized) |workspace, *out| {
            const paths = try state.gpa.alloc(String, workspace.paths.len);
            errdefer state.gpa.free(paths);

            for (workspace.paths, paths) |path, *out_path| {
                out_path.* = .init(path);
            }

            out.* = .init(workspace, paths);
            workspace_index += 1;
        }

        return .{ .ptr = serialized.ptr, .len = serialized.len };
    }
};

fn free_workspace_slice(workspaces: []Workspace.SerializedWorkspace) void {
    for (workspaces) |workspace| workspace.deinit(state.gpa);
    state.gpa.free(workspaces);
}

pub export fn odyssey_workspace_get_all_metadata_and_validate() ExternSerializedWorkspaces {
    return workspace_get_all_metadata_and_validate() catch |err| {
        std.log.err("error getting workspace metadata={}", .{err});
        return .empty;
    };
}

fn workspace_get_all_metadata_and_validate() !ExternSerializedWorkspaces {
    const io = state.threaded.io();
    const gpa = state.gpa;
    const conn = try db.acquire(io);
    defer db.release(io, conn);

    const workspaces = try Workspace.persistence.getAllMetadataAndValidate(conn, gpa, io);
    defer free_workspace_slice(workspaces);

    return try ExternSerializedWorkspaces.init(workspaces);
}

pub export fn odyssey_workspace_get_by_session(app: *App, session_entity: ExternEntity) ExternSerializedWorkspaces {
    return workspace_get_by_session(app, session_entity) catch |err| {
        std.log.err("error getting workspaces by session={}", .{err});
        return .empty;
    };
}

fn workspace_get_by_session(app: *App, session_entity: ExternEntity) !ExternSerializedWorkspaces {
    const session = session_entity.any().into(Session) orelse return error.InvalidSessionEntity;
    const old_id = session.read(app).old_id orelse return .empty;

    const io = state.threaded.io();
    const gpa = state.gpa;
    const conn = try db.acquire(io);
    defer db.release(io, conn);

    const workspaces = try Workspace.persistence.getBySession(conn, gpa, old_id);
    defer free_workspace_slice(workspaces);

    return try ExternSerializedWorkspaces.init(workspaces);
}

pub export fn odyssey_workspace_list_free(list: ExternSerializedWorkspaces) void {
    const list_ptr = list.ptr orelse return;
    for (list_ptr[0..list.len]) |workspace| {
        if (workspace.paths.ptr) |paths| state.gpa.free(paths[0..workspace.paths.len]);
    }
    state.gpa.free(list_ptr[0..list.len]);
}
