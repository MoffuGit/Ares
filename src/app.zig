//This App and many parts/ideas of it came from gpui (https://github.com/zed-industries/zed/tree/main/crates/gpui)
//LICENSE: [ZED]
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;
const heap = std.heap;

const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const constants = @import("contants.zig");
const MAX_SIZE = constants.MAX_SIZE;
const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;
const ent = @import("entity.zig");
pub const Entity = ent.Entity;
const AnyEntity = ent.AnyEntity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const sch = @import("scheduler.zig");
const BackgroundScheduler = sch.BackgroundScheduler;
const Scheduler = sch.Scheduler;
const Waker = sch.Waker;
const Executor = BackgroundScheduler.Executor;
const Subscriptions = @import("subscription.zig").Subscriptions;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;

pub const Options = extern struct {
    userdata: *anyopaque = undefined,
    wakeup_cb: *const fn (*anyopaque) callconv(.c) void = noop,
};

fn noop(_: *anyopaque) callconv(.c) void {}

pub const App = @This();

io: Io,
gpa: Allocator,
alloc: heap.ArenaAllocator,
arena: Allocator,
entities: EntityStore,
observers: Observers,
chunks: ChunkAllocator,
peding_updates: u16,

scheduler: sch.Scheduler,
background_scheduler: BackgroundScheduler,

notifications: btree.BPlusSet(EntityId, ent.entityOrder),

flushing: bool,

options: Options,

pub fn init(self: *App, options: Options, gpa: Allocator, io: Io) !void {
    self.* = .{
        .options = options,
        .scheduler = undefined,
        .notifications = undefined,
        .entities = undefined,
        .observers = undefined,
        .chunks = undefined,
        .background_scheduler = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
        .alloc = .init(gpa),
        .arena = undefined,
        .io = io,
    };
    self.arena = self.alloc.allocator();
    errdefer self.alloc.deinit();

    try self.chunks.init(self.arena, &.{ .{ 50, MAX_SIZE }, .{ 50, Observers.NODE_SIZE } });
    try self.observers.init(self.chunks.allocator());
    try self.entities.init(self.arena, 100);
    try self.notifications.init(self.chunks.allocator());

    try self.background_scheduler.init(options, self.arena, io);
    errdefer self.background_scheduler.deinit();

    try self.scheduler.init(options, self.arena, self.chunks.allocator(), io);
    errdefer self.scheduler.deinit();
}

pub fn deinit(self: *App) void {
    self.scheduler.deinit();
    self.background_scheduler.deinit();
    self.alloc.deinit();
}

pub fn new(self: *App, comptime T: type, function: anytype, args: anytype) !Entity(T) {
    self.start_update();
    defer self.end_update();

    const alloc = self.chunks.allocator();
    const ptr = try alloc.create(T);
    errdefer alloc.destroy(ptr);

    const id = self.entities.insert(ptr);
    errdefer self.entities.recycle(id);

    const entity: Entity(T) = .init(&self.entities, id);
    const ctx: Context(T) = .new(self, entity);

    self.entities.start_update(id);
    defer self.entities.end_update(id);

    try @call(.always_inline, function, .{ ptr, ctx } ++ args);

    return entity;
}

pub fn executor(self: *App, T: type, function: anytype, args: anytype) !Executor(T) {
    return try self.background_scheduler.executor(T, function, args);
}

pub const UpdateFrame = struct {
    app: *App,
    any: AnyEntity,

    pub fn end(self: *const @This(), ptr: anytype) void {
        const T = @TypeOf(ptr);

        assert(self.any.type_id == TypeInfo.init(@typeInfo(T).pointer.child));

        self.app.entities.end_update(self.any.id);
        self.app.end_update();
    }
};

pub fn update_frame(self: *App, comptime T: type, entity: Entity(T)) struct { *T, UpdateFrame } {
    self.start_update();
    self.entities.start_update(entity.any.id);

    const ptr = self.entities.get(T, entity);

    return .{ ptr, .{ .any = entity.any, .app = self } };
}

pub fn read_entity(self: *App, comptime T: type, entity: Entity(T)) *const T {
    return self.entities.get(T, entity);
}

pub fn notify(self: *App, entity: anytype) void {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    _ = self.notifications.insert(self.chunks.allocator(), entity.id()) catch |err| {
        std.log.err("We cannot notify, err: {}", .{err});
    };
}

pub fn start_update(self: *App) void {
    self.peding_updates += 1;
}

pub fn end_update(self: *App) void {
    if (!self.flushing and self.peding_updates == 1) {
        self.flushing = true;
        self.flush();
        self.flushing = false;
    }
    self.peding_updates += 1;
}

pub fn flush(self: *App) void {
    self.scheduler.run() catch @panic("Scheduler run Error");
    self.destroy_dropped_entities();
    self.flush_notifications();
}

pub fn @"defer"(self: *App, function: anytype, args: anytype) Scheduler.Cancelation {
    return self.scheduler.@"defer"(function, args);
}

pub fn await(self: *App, function: anytype, args: anytype) !Waker {
    return try self.scheduler.await(function, args);
}

pub fn flush_notifications(self: *App) void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notify(id, .{self});
    }

    self.notifications.clear(self.chunks.allocator());
}

pub fn destroy_dropped_entities(self: *App) void {
    const alloc = self.chunks.allocator();

    while (self.entities.popDrop()) |drop| {
        const ptr, const key, const type_info = drop;

        self.observers.remove(key);
        type_info.destroy(ptr, alloc);
        self.entities.recycle(key);
    }
}

pub const Observers = Subscriptions(EntityId, &.{*App}, ent.entityOrder);

pub fn observe(
    self: *App,
    entity: anytype,
    function: anytype,
    args: anytype,
) !Observers.Subscription {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const T = _Entity.EntityType;
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn _callback(app: *App, observed: AnyEntity, _args: Args) bool {
            const _entity = observed.into(T) orelse return false;
            return @call(.always_inline, function, .{ app, _entity } ++ _args);
        }

        fn enable(sub: Observers.Subscription, res: anyerror!void) bool {
            res catch @panic("Deferred Subscription Error");
            sub.enable();
            return false;
        }
    };

    const sub = try self.observers.insert(
        entity.id(),
        TypeErased._callback,
        .{ entity.any, args },
    );

    _ = self.@"defer"(TypeErased.enable, .{sub});

    return sub;
}

pub fn Context(comptime T: type) type {
    return struct {
        const _Entity = Entity(T);

        app: *App,
        entity: _Entity,

        pub fn new(app: *App, entity: _Entity) @This() {
            return .{ .app = app, .entity = entity };
        }

        pub fn gpa(self: *const @This()) Allocator {
            return self.app.gpa;
        }

        pub fn arena(self: *const @This()) Allocator {
            return self.app.arena;
        }

        pub fn update(self: *const @This()) struct { *T, UpdateFrame } {
            return self.entity.update(self.app);
        }

        pub fn read(self: *const @This()) *T {
            return self.entity.read(self.app);
        }

        pub fn notify(self: *const @This()) void {
            self.entity.notify(self.app);
        }

        pub fn observe(
            self: *const @This(),
            entity: anytype,
            function: anytype,
            args: anytype,
        ) !Observers.Subscription {
            const Args = @TypeOf(args);
            const Observed = @TypeOf(entity);

            const TypeErased = struct {
                pub fn callback(
                    app: *App,
                    observed: Observed,
                    any: AnyEntity,
                    _args: Args,
                ) bool {
                    const _entity = any.into(T) orelse return false;

                    const ctx: Context(T) = .new(app, _entity);

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    @call(.always_inline, function, .{ ptr, observed, ctx } ++ _args);

                    return true;
                }
            };

            return try self.app.observe(entity, TypeErased.callback, .{ self.entity.any, args });
        }

        pub fn @"defer"(self: *const @This(), function: anytype, args: anytype) Scheduler.Cancelation {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn @"defer"(any: AnyEntity, app: *App, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const _entity = any.into(T) orelse return false;

                    const ctx: Context(T) = .new(app, _entity);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };
            return self.app.@"defer"(TypeErased.@"defer", .{ self.entity.any, self.app, args });
        }

        pub fn await(self: *const @This(), function: anytype, args: anytype) !Waker {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn async(any: AnyEntity, app: *App, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const _entity = any.into(T) orelse return false;

                    const ctx: Context(T) = .new(app, _entity);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };

            return try self.app.await(TypeErased.async, .{ self.entity.any, self.app, args });
        }

        pub fn executor(
            self: *const @This(),
            E: type,
            function: anytype,
            args: anytype,
        ) !Executor(E) {
            return try self
                .app
                .executor(E, function, args);
        }
    };
}

test "creates/drops entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;
    const entity_count = 32;

    const TestStruct = struct {
        index: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .index = 0 };
        }

        pub fn set_index(self: *@This(), index: usize) void {
            self.index = index;
        }

        pub fn inc(self: *@This()) void {
            self.index += 1;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities, 0..) |*entity, index| {
        entity.* = try TestEntity.new(&app, .{});

        {
            const ptr, const update = entity.update(&app);
            defer update.end(ptr);

            ptr.set_index(index);
            ptr.inc();
        }

        try testing.expectEqual(index + 1, entity.read(&app).index);
    }

    for (entities) |entity| {
        entity.drop();
    }

    app.flush();
}

test "Observe entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;
    const entity_count = 32;

    const TestStruct = struct {
        index: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .index = 0 };
        }

        pub fn set_index(self: *@This(), index: usize) void {
            self.index = index;
        }

        pub fn inc(self: *@This()) void {
            self.index += 1;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities) |*entity| {
        entity.* = try TestEntity.new(&app, .{});
    }

    const observed = entities[0];

    var context: bool = false;

    const Observed = struct {
        pub fn callback(_: *App, _: TestEntity, _context: *bool) bool {
            _context.* = true;
            return false;
        }
    };

    var index: usize = 0;

    {
        const ptr, const update = observed.update(&app);
        defer update.end(ptr);

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.read(&app).index);
    observed.notify(&app);

    try testing.expect(!context);

    _ = try app.observe(observed, Observed.callback, .{&context});

    index = 1;

    {
        const ptr, const update = observed.update(&app);
        defer update.end(ptr);

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.read(&app).index);
    observed.notify(&app);

    app.flush();

    try testing.expect(context);

    for (entities) |entity| {
        entity.drop();
    }

    app.flush();
}

test "Context observes entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const Observed = struct {
        index: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .index = 0 };
        }

        pub fn set_index(self: *@This(), index: usize) void {
            self.index = index;
        }
    };

    const ObserverState = struct {
        observed_updates: usize,
        last_observed_index: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .observed_updates = 0, .last_observed_index = 0 };
        }

        pub fn observe(self: *@This(), observed: Entity(Observed), ctx: Context(@This())) void {
            self.observed_updates += 1;
            self.last_observed_index = observed.read(ctx.app).index;
        }

        pub fn get_last_observed_index(self: *const @This()) usize {
            return self.last_observed_index;
        }
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const observer = try Entity(ObserverState).new(&app, .{});
    const observed = try Entity(Observed).new(&app, .{});

    var context = Context(ObserverState).new(&app, observer);
    _ = try context.observe(observed, ObserverState.observe, .{});

    {
        const ptr, const update = observed.update(&app);
        defer update.end(ptr);

        ptr.set_index(42);
    }
    observed.notify(&app);
    app.flush();

    try testing.expectEqual(1, observer.read(&app).observed_updates);
    try testing.expectEqual(42, observer.read(&app).last_observed_index);

    observer.drop();
    observed.drop();
    app.flush();
}

test "Context defer runs on foreground executor with entity context" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const State = struct {
        calls: usize,
        last_value: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .calls = 0, .last_value = 0 };
        }

        pub fn deferred(ctx: Context(@This()), value: usize) bool {
            const ptr, const update = ctx.update();
            defer update.end(ptr);

            ptr.set(value);

            return false;
        }

        pub fn set(self: *@This(), value: usize) void {
            self.calls += 1;
            self.last_value = value;
        }

        pub fn get_last_value(self: *const @This()) usize {
            return self.last_value;
        }
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const entity = try Entity(State).new(&app, .{});

    var context = Context(State).new(&app, entity);
    var handler = context.@"defer"(State.deferred, .{42});

    try testing.expectEqual(0, entity.read(&app).calls);

    app.flush();

    try testing.expectEqual(1, entity.read(&app).calls);
    try testing.expectEqual(42, entity.read(&app).last_value);

    handler.cancel();
    entity.drop();
    app.flush();
}

test "Context async runs on foreground executor with entity context" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const State = struct {
        calls: usize,
        last_value: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .calls = 0, .last_value = 0 };
        }

        pub fn await(ctx: Context(@This()), value: usize) bool {
            const ptr, const update = ctx.update();
            defer update.end(ptr);

            ptr.set(value);
            return false;
        }

        pub fn set(self: *@This(), value: usize) void {
            self.calls += 1;
            self.last_value = value;
        }
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const entity = try Entity(State).new(&app, .{});

    var context = Context(State).new(&app, entity);
    const waker = try context.await(State.await, .{42});

    try testing.expectEqual(0, entity.read(&app).calls);

    try waker.wake();

    app.flush();

    try testing.expectEqual(1, entity.read(&app).calls);
    try testing.expectEqual(42, entity.read(&app).last_value);

    waker.close();
    entity.drop();
    app.flush();
}

test "Context observe removes subscription when observer is dropped" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const Observed = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}
    };

    const ObserverState = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}

        pub fn observe(_: *@This(), _: Entity(Observed), _: Context(@This())) void {}
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const observer = try Entity(ObserverState).new(&app, .{});
    const observed = try Entity(Observed).new(&app, .{});

    var context = Context(ObserverState).new(&app, observer);
    _ = try context.observe(observed, ObserverState.observe, .{});

    observer.drop();
    app.flush();

    try testing.expect(app.observers.subscribers.get(observed.id()) != null);

    observed.notify(&app);
    app.flush();

    try testing.expectEqual(null, app.observers.subscribers.get(observed.id()));

    observed.drop();
    app.flush();
}

test "Context observe removes subscription when observed is dropped" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const Observed = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}
    };

    const ObserverState = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}

        pub fn observe(_: *@This(), _: Entity(Observed), _: Context(@This())) void {}
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const observer = try Entity(ObserverState).new(&app, .{});
    const observed = try Entity(Observed).new(&app, .{});
    const observed_id = observed.id();

    var context = Context(ObserverState).new(&app, observer);
    _ = try context.observe(observed, ObserverState.observe, .{});

    observed.drop();
    app.flush();

    try testing.expectEqual(null, app.observers.subscribers.get(observed_id));

    observer.drop();
    app.flush();
}

test "Observe entities drop before enable" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;
    const entity_count = 32;

    const TestStruct = struct {
        index: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .index = 0 };
        }

        pub fn set_index(self: *@This(), index: usize) void {
            self.index = index;
        }

        pub fn inc(self: *@This()) void {
            self.index += 1;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities) |*entity| {
        entity.* = try TestEntity.new(&app, .{});
    }

    const observed = entities[0];

    var context: bool = false;

    const Observed = struct {
        pub fn callback(_: *App, _: TestEntity, _context: *bool) bool {
            _context.* = true;

            return false;
        }
    };

    var index: usize = 0;

    {
        const ptr, const update = observed.update(&app);
        defer update.end(ptr);

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.read(&app).index);
    observed.notify(&app);

    try testing.expect(!context);

    const sub = try app.observe(observed, Observed.callback, .{&context});
    try sub.unsubscribeApp();

    index = 1;

    {
        const ptr, const update = observed.update(&app);
        defer update.end(ptr);

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.read(&app).index);
    observed.notify(&app);

    app.flush();

    try testing.expect(!context);

    for (entities) |entity| {
        entity.drop();
    }

    app.flush();
}
