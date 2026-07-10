const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");

const App = @import("app.zig");
const heap = std.heap;
const db = @import("db.zig");
const ent = @import("entity.zig");
const global = @import("global.zig");
const Session = @import("session.zig");
const uuid = @import("uuid.zig");
const Workspace = @import("workspace.zig");

const state = &@import("global.zig").state;

const ExternAppOptions = extern struct {
    userdata: *anyopaque = undefined,
    wakeup_cb: *const fn (*anyopaque) callconv(.c) void,
};

const ExternAppCallback = struct {
    userdata: *anyopaque,
    wakeup_cb: *const fn (*anyopaque) callconv(.c) void,

    fn wakeup(userdata: *anyopaque) void {
        const callback: *ExternAppCallback = @ptrCast(@alignCast(userdata));
        callback.wakeup_cb(callback.userdata);
    }
};

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
    };
}

const String = Slice(u8);

const MaybeEntity = Option(ExternEntity);

const ExternEntity = extern struct {
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
    const Observers = App.Observers;

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
    timestamp: i64,
    id: i64,

    fn init(workspace: Workspace.SerializedWorkspace, gpa: Allocator) !@This() {
        const paths = try gpa.alloc(String, workspace.paths.len);
        errdefer gpa.free(paths);

        for (workspace.paths, paths) |path, *out_path| {
            out_path.* = .init(path);
        }

        return .{
            .paths = .init(paths),
            .session = if (workspace.session) |session| .some(session) else .none,
            .window = if (workspace.window) |window| .some(.init(window)) else .none,
            .timestamp = workspace.timestamp,
            .id = workspace.id,
        };
    }
};

const ExternSerializedWorkspaces = extern struct {
    ptr: ?[*]ExternSerializedWorkspace,
    len: usize,

    const empty: @This() = .{ .ptr = null, .len = 0 };

    fn init(workspaces: []Workspace.SerializedWorkspace, gpa: Allocator) !@This() {
        const serialized = try gpa.alloc(ExternSerializedWorkspace, workspaces.len);
        errdefer gpa.free(serialized);

        var workspace_index: usize = 0;
        errdefer {
            for (serialized[0..workspace_index]) |workspace| {
                if (workspace.paths.ptr) |paths| gpa.free(paths[0..workspace.paths.len]);
            }
        }

        for (workspaces, serialized) |workspace, *out| {
            out.* = try .init(workspace, gpa);
            workspace_index += 1;
        }

        return .{ .ptr = serialized.ptr, .len = serialized.len };
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
    db.init(global.state.gpa) catch |err| {
        std.log.err("error starting zqlite pool: {}", .{err});
        return 1;
    };
    return 0;
}

pub export fn odyssey_db_stop() void {
    db.deinit();
}

pub export fn odyssey_app_new(options: *const ExternAppOptions) ?*App {
    return app_new(options) catch |err| {
        std.log.err("error initializing app: {}", .{err});
        return null;
    };
}

fn app_new(options: *const ExternAppOptions) !*App {
    var app = try state.gpa.create(App);
    errdefer state.gpa.destroy(app);

    const callback = try state.gpa.create(ExternAppCallback);
    errdefer state.gpa.destroy(callback);

    callback.* = .{
        .userdata = options.userdata,
        .wakeup_cb = options.wakeup_cb,
    };

    try app.init(
        .{
            .userdata = callback,
            .wakeup_cb = ExternAppCallback.wakeup,
        },
        state.gpa,
        state.threaded.io(),
    );

    return app;
}

pub export fn odyssey_app_free(app: *App) void {
    const callback: *ExternAppCallback = @ptrCast(@alignCast(app.options.userdata));
    app.deinit();
    state.gpa.destroy(callback);
    state.gpa.destroy(app);
}

pub export fn odyssey_app_flush(app: *App) void {
    app.flush();
}

pub export fn odyssey_drop_entity(entity: ExternEntity) void {
    entity.any().drop();
}

pub export fn odyssey_workspace_new(app: *App, extern_entity: ExternEntity, paths: Slice(String)) MaybeEntity {
    const session = extern_entity.any().into(Session) orelse @panic("Missing Session Entity");

    const workspace = workspace_new(app, session, paths) catch |err| {
        std.log.err("error creating workspace={}", .{err});
        return .none;
    };

    return .some(.init(workspace.any));
}

fn workspace_new(app: *App, session: ent.Entity(Session), extern_paths: Slice(String)) !ent.Entity(Workspace) {
    const id = session.read(app).id;

    var buffer: [1024][]const u8 = undefined;

    const string_slices = extern_paths.slice() orelse
        return error.PathsAreRequired;

    for (
        string_slices,
        0..,
    ) |slice, idx| {
        if (idx == buffer.len) break;
        buffer[idx] = slice.slice() orelse return error.EmptyPath;
    }

    const paths = buffer[0..string_slices.len];

    const workspace: ent.Entity(Workspace) = try .new(
        app,
        .{
            Workspace.Options{
                .paths = paths,
                .session = id,
            },
            state.threaded.io(),
        },
    );
    errdefer workspace.drop();

    return workspace;
}

pub export fn odyssey_workspace_mark_for_restoration(app: *App, extern_entity: ExternEntity) void {
    const workspace = extern_entity.any().into(Workspace) orelse @panic("Missing Workspace Entity");
    const ptr, const update = workspace.update(app);
    defer update.end(ptr);

    ptr.markForRestoration() catch |err| {
        std.log.warn("Workspace would not restore={}", .{err});
    };
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
    defer gpa.free(workspaces);

    return try ExternSerializedWorkspaces.init(workspaces, gpa);
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
    defer gpa.free(workspaces);

    return try ExternSerializedWorkspaces.init(workspaces, gpa);
}

pub export fn odyssey_workspace_list_free(list: ExternSerializedWorkspaces) void {
    const list_ptr = list.ptr orelse return;
    const workspaces = list_ptr[0..list.len];
    for (workspaces) |workspace| {
        if (workspace.paths.ptr) |paths| state.gpa.free(paths[0..workspace.paths.len]);
    }
    state.gpa.free(workspaces);
}

pub export fn odyssey_workspace_delete_by_id(id: i64) c_int {
    workspace_delete_by_id(id) catch |err| {
        std.log.err("error deleting workspace by id={}", .{err});
        return 1;
    };
    return 0;
}

fn workspace_delete_by_id(id: i64) !void {
    const io = state.threaded.io();
    const conn = try db.acquire(io);
    defer db.release(io, conn);

    try Workspace.persistence.deleteById(conn, id);
}
