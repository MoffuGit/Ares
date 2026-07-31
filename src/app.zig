//This App and many parts/ideas of it came from gpui (https://github.com/zed-industries/zed/tree/main/crates/gpui)
//LICENSE: [ZED]
const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;
const heap = std.heap;

const chunk_pool = @import("chunk_pool.zig");
const ChunkAllocator = chunk_pool.ChunkAllocator;
const constants = @import("constants.zig");
const MAX_SIZE = constants.MAX_SIZE;
const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;
const ect = @import("executor.zig");
const Executors = ect.Executors;
const Executor = ect.Executor;
const ent = @import("entity.zig");
pub const Entity = ent.Entity;
const AnyEntity = ent.AnyEntity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const Runner = @import("runner.zig");
const TaskId = Runner.TaskId;
const Subscriptions = @import("subscription.zig").Subscriptions;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;

const log = std.log.scoped(.app);
pub const Waker = struct {
    waker: Runner.Waker,
    options: App.Options,
    cancelation: App.Cancelation,

    pub fn wake(self: *const Waker) !void {
        try self.waker.wake();
        self.options.wakeup_cb(self.options.userdata);
    }

    pub fn close(self: *const Waker) void {
        self.cancelation.cancel();
        self.waker.close();
    }
};

pub const Options = struct {
    fn noop(_: *anyopaque) void {}

    userdata: *anyopaque = undefined,
    wakeup_cb: *const fn (*anyopaque) void = noop,
};

pub const App = @This();

gpa: Allocator,
arena: heap.ArenaAllocator,
entities: EntityStore,
events: std.Deque(Event),
listeners: Listeners,
observers: Observers,
chunks: ChunkAllocator,
peding_updates: u16,

runner: Runner,

executors: Executors,

notifications: btree.BPlusSet(EntityId, ent.entityOrder),

flushing: bool,

options: Options,

pub fn init(self: *App, options: Options, gpa: Allocator, io: Io) !void {
    self.* = .{
        .runner = undefined,
        .options = options,
        .notifications = undefined,
        .entities = undefined,
        .observers = undefined,
        .listeners = undefined,
        .chunks = undefined,
        .executors = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
        .arena = .init(gpa),
        .events = .empty,
    };
    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    try self.chunks.init(arena, &.{ .{ 50, MAX_SIZE }, .{ 50, Observers.NODE_SIZE }, .{ 50, 2048 } });
    const chunks = self.chunks.allocator();

    try self.runner.init(arena, chunks, io);
    errdefer self.runner.deinit();
    try self.observers.init(chunks);
    try self.listeners.init(chunks);
    try self.notifications.init(chunks);
    try self.entities.init(arena, 100);
    try self.executors.init(arena, chunks, io);
    errdefer self.executors.deinit();
}

pub fn deinit(self: *App) void {
    self.flush();
    self.runner.deinit();
    self.executors.deinit();
    self.events.deinit(self.gpa);
    self.arena.deinit();
}

pub fn new(self: *App, comptime T: type, function: anytype, args: anytype) !Entity(T) {
    self.startUpdate();
    defer self.endUpdate();

    const alloc = self.chunks.allocator();
    const ptr = try alloc.create(T);
    errdefer alloc.destroy(ptr);

    const id = self.entities.insert(ptr);
    errdefer self.entities.recycle(id);

    const entity: Entity(T) = .init(&self.entities, id);
    const ctx: Context(T) = .new(self, entity);

    self.entities.startUpdate(id);
    defer self.entities.endUpdate(id);

    try @call(.always_inline, function, .{ ptr, ctx } ++ args);

    return entity;
}

pub fn executor(self: *App, comptime T: type, args: anytype) !Executor(T) {
    return try Executor(T).new(&self.executors, args);
}

pub const UpdateFrame = struct {
    app: *App,
    any: AnyEntity,

    pub fn end(self: *const @This(), ptr: anytype) void {
        const T = @TypeOf(ptr);

        assert(self.any.type_id == TypeInfo.init(@typeInfo(T).pointer.child));

        self.app.entities.endUpdate(self.any.id);
        self.app.endUpdate();
    }
};

pub fn updateFrame(self: *App, any: AnyEntity) UpdateFrame {
    self.startUpdate();
    self.entities.startUpdate(any.id);

    return .{ .any = any, .app = self };
}

pub fn notify(self: *App, entity: anytype) void {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    _ = self.notifications.insert(self.chunks.allocator(), entity.id()) catch |err| {
        log.err("We cannot notify, err: {}", .{err});
    };
}

pub fn startUpdate(self: *App) void {
    self.peding_updates += 1;
}

pub fn endUpdate(self: *App) void {
    if (self.peding_updates == 1) {
        self.flush();
    }
    self.peding_updates -= 1;
}

pub fn flush(self: *App) void {
    if (self.flushing) return;

    self.flushing = true;
    defer self.flushing = false;

    self.runner.run(.no_wait) catch @panic("Loop run Error");
    self.destroyDroppedEntities();
    self.flushNotifications();
    self.flushEvents();
}

pub fn flushNotifications(self: *App) void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notify(id, .{ self, id });
    }

    self.notifications.clear(self.chunks.allocator());
}

pub fn flushEvents(self: *App) void {
    const chunk = self.chunks.allocator();
    while (self.events.popFront()) |event| {
        self.listeners.notify(
            event.id,
            .{ self, event.ptr, event.type },
        );

        event.destroy(chunk);
    }
}

pub fn destroyDroppedEntities(self: *App) void {
    const alloc = self.chunks.allocator();

    while (self.entities.popDrop()) |drop| {
        const ptr, const key, const type_info = drop;

        self.listeners.remove(key);
        self.observers.remove(key);

        type_info.deinit(ptr);
        type_info.destroy(ptr, alloc);

        self.entities.recycle(key);
    }
}

pub const Event = struct {
    id: EntityId,
    type: TypeId,
    ptr: *anyopaque,

    pub fn destroy(self: *const Event, chunk: Allocator) void {
        self.type.deinit(self.ptr);
        self.type.destroy(self.ptr, chunk);
    }
};

pub const Listeners = Subscriptions(
    EntityId,
    &.{ *App, *anyopaque, TypeId },
    ent.entityOrder,
);

pub fn listen(
    self: *App,
    entity: anytype,
    comptime E: type,
    function: anytype,
    args: anytype,
) !Listeners.Subscription {
    const _Entity = @TypeOf(entity);

    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn _callback(app: *App, ptr: *anyopaque, _type: TypeId, _args: Args) bool {
            if (TypeInfo.init(E) != _type) return true;
            const event: *E = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, function, .{ app, event } ++ _args);
        }

        fn enable(sub: Listeners.Subscription, res: anyerror!void) bool {
            res catch @panic("Deferred Subscription Error");
            sub.enable();
            return false;
        }
    };

    const sub = try self.listeners.insert(
        entity.id(),
        TypeErased._callback,
        .{args},
    );

    _ = self.@"defer"(TypeErased.enable, .{sub});

    return sub;
}

pub fn nevent(self: *App, entity: anytype, comptime E: type) !*E {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const chunk = self.chunks.allocator();
    const ptr = try chunk.create(E);
    errdefer chunk.destroy(ptr);

    try self.events.pushBack(
        self.gpa,
        .{ .id = entity.id(), .ptr = ptr, .type = TypeInfo.init(E) },
    );

    return ptr;
}

pub const Observers = Subscriptions(EntityId, &.{ *App, EntityId }, ent.entityOrder);

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
        fn _callback(app: *App, id: EntityId, _args: Args) bool {
            const observed = AnyEntity.init(&app.entities, id, TypeInfo.init(T));
            const _entity = _Entity.from(observed) orelse return false;
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
        .{args},
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

        pub fn drop(self: *const @This()) void {
            self.entity.drop();
        }

        pub fn gpa(self: *const @This()) Allocator {
            return self.app.gpa;
        }

        pub fn arena(self: *const @This()) Allocator {
            return self.app.arena.allocator();
        }

        pub fn update(self: *const @This()) struct { *T, UpdateFrame } {
            return self.entity.update(self.app);
        }

        pub fn read(self: *const @This()) *const T {
            return self.entity.read();
        }

        pub fn tryRead(self: *const @This()) ?*const T {
            return self.entity.tryRead();
        }

        pub fn notify(self: *const @This()) void {
            self.entity.notify(self.app);
        }

        pub fn nevent(self: *const @This(), comptime E: type) !*E {
            return try self.entity.nevent(self.app, E);
        }

        pub fn listen(self: *const @This(), comptime E: type, entity: anytype, function: anytype, args: anytype) !Listeners.Subscription {
            const Args = @TypeOf(args);

            const TypeErased = struct {
                pub fn callback(
                    app: *App,
                    event: *E,
                    any: AnyEntity,
                    _args: Args,
                ) bool {
                    const _entity = _Entity.from(any) orelse return false;

                    const ctx: Context(T) = .new(app, _entity);

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    @call(.always_inline, function, .{ ptr, event, ctx } ++ _args);

                    return true;
                }
            };

            return try self.app.listen(entity, E, TypeErased.callback, .{ self.entity.any, args });
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
                    const _entity = _Entity.from(any) orelse return false;

                    const ctx: Context(T) = .new(app, _entity);

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    @call(.always_inline, function, .{ ptr, observed, ctx } ++ _args);

                    return true;
                }
            };

            return try self.app.observe(entity, TypeErased.callback, .{ self.entity.any, args });
        }

        pub fn @"defer"(self: *const @This(), function: anytype, args: anytype) App.Cancelation {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn @"defer"(any: AnyEntity, app: *App, _args: Args, res: anyerror!void) bool {
                    res catch return false;
                    const _entity = _Entity.from(any) orelse return false;

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
                    const _entity = _Entity.from(any) orelse return false;

                    const ctx: Context(T) = .new(app, _entity);

                    return @call(.always_inline, function, .{ctx} ++ _args);
                }
            };

            return try self.app.await(TypeErased.async, .{ self.entity.any, self.app, args });
        }

        pub fn executor(
            self: *const @This(),
            E: type,
            args: anytype,
        ) !Executor(E) {
            return try self
                .app
                .executor(E, args);
        }
    };
}

pub fn @"defer"(
    self: *App,
    function: anytype,
    context: anytype,
) Cancelation {
    const task = self.runner.create();
    task.@"defer"(function, context);

    self.runner.complete(task);

    return .{ .id = task.id, .app = self };
}

pub fn await(
    self: *App,
    function: anytype,
    context: anytype,
) !Waker {
    const task = self.runner.create();
    errdefer self.runner.destroyUnregistered(task);
    const waker = try task.await(function, context);

    self.runner.submit(task);

    return .{
        .waker = waker,
        .options = self.options,
        .cancelation = .{
            .id = task.id,
            .app = self,
        },
    };
}

pub const Cancelation = struct {
    id: TaskId,
    app: *App,

    pub fn cancel(self: *const Cancelation) void {
        const cancelation = self.app.runner.createCancelation(self.id);
        self.app.runner.cancel(cancelation);
    }
};

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

        try testing.expectEqual(index + 1, entity.read().index);
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
    try testing.expectEqual(index + 1, observed.read().index);
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
    try testing.expectEqual(index + 1, observed.read().index);
    observed.notify(&app);

    app.flush();

    try testing.expect(context);

    for (entities) |entity| {
        entity.drop();
    }

    app.flush();
}

test "Listen entities events" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        id: usize,
    };

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

    const listened = try TestEntity.new(&app, .{});

    var context: usize = 0;

    const Listened = struct {
        pub fn callback(_: *App, evt: *TestEvent, _context: *usize) bool {
            _context.* = evt.id;
            return false;
        }
    };

    _ = try app.listen(listened, TestEvent, Listened.callback, .{&context});

    const evt = try listened.nevent(&app, TestEvent);
    evt.* = .{
        .id = 35,
    };

    app.flush();

    try testing.expectEqual(context, 35);

    listened.drop();
    app.flush();
}

test "Context listen entities events" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        id: usize,
    };

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

    const listened = try TestEntity.new(&app, .{});
    const listener = try TestEntity.new(&app, .{});
    const context = listener.ctx(&app);

    const Listened = struct {
        pub fn callback(ptr: *TestStruct, evt: *TestEvent, _: Context(TestStruct)) void {
            ptr.index = evt.id;
        }
    };

    _ = try context.listen(TestEvent, listened, Listened.callback, .{});

    const evt = try listened.nevent(&app, TestEvent);
    evt.* = .{
        .id = 35,
    };

    app.flush();

    try testing.expectEqual(listener.read().index, 35);

    listened.drop();
    listener.drop();
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

        pub fn observe(self: *@This(), observed: Entity(Observed), _: Context(@This())) void {
            self.observed_updates += 1;
            self.last_observed_index = observed.read().index;
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

    try testing.expectEqual(1, observer.read().observed_updates);
    try testing.expectEqual(42, observer.read().last_observed_index);

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

    try testing.expectEqual(0, entity.read().calls);

    app.flush();

    try testing.expectEqual(1, entity.read().calls);
    try testing.expectEqual(42, entity.read().last_value);

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

    try testing.expectEqual(0, entity.read().calls);

    try waker.wake();

    app.flush();

    try testing.expectEqual(1, entity.read().calls);
    try testing.expectEqual(42, entity.read().last_value);

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
    try testing.expectEqual(index + 1, observed.read().index);
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
    try testing.expectEqual(index + 1, observed.read().index);
    observed.notify(&app);

    app.flush();

    try testing.expect(!context);

    for (entities) |entity| {
        entity.drop();
    }

    app.flush();
}
