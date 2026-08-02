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
const MAX_ALIGN = constants.MAX_ALIGN;
const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;
const Queue = datastruct.Queue;
const ent = @import("entity.zig");
const Entity = ent.Entity;
const AnyEntity = ent.AnyEntity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const Runner = @import("runner.zig");
const subs = @import("subscription.zig");
const Subscriptions = subs.Subscriptions;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;

const log = std.log.scoped(.app);

pub const Options = struct {
    fn noop(_: *anyopaque) void {}

    userdata: *anyopaque = undefined,
    wakeup_cb: *const fn (*anyopaque) void = noop,
};

pub const App = @This();

gpa: Allocator,
arena: heap.ArenaAllocator,
entities: EntityStore,
events: Queue(Event),
dispatched: Queue(Dispatched),
deferred: Queue(Deferred),
listeners: Listeners,
receivers: Receivers,
observers: Observers,
chunks: ChunkAllocator,
peding_updates: u16,

runner: Runner,

notifications: btree.BPlusSet(EntityId, ent.entityOrder),

flushing: bool,

options: Options,

pub fn init(self: *App, options: Options, gpa: Allocator, io: Io) !void {
    self.* = .{
        .options = options,
        .notifications = undefined,
        .entities = undefined,
        .observers = undefined,
        .listeners = undefined,
        .receivers = undefined,
        .chunks = undefined,
        .runner = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
        .arena = .init(gpa),
        .events = .{},
        .dispatched = .{},
        .deferred = .{},
    };
    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    try self.chunks.init(arena, &.{
        .{ 50, MAX_SIZE },
        .{ 50, @max(Observers.NODE_SIZE, Receivers.NODE_SIZE, Listeners.NODE_SIZE) },
        .{ 50, 2048 },
    });

    const chunks = self.chunks.allocator();

    try self.observers.init(chunks);
    try self.listeners.init(chunks);
    try self.receivers.init(chunks);
    try self.notifications.init(chunks);
    try self.entities.init(arena, 100);

    try self.runner.init(arena, chunks, io, options);
    errdefer self.runner.deinit();
}

pub fn deinit(self: *App) void {
    self.flush();
    self.receivers.deinit();
    self.runner.deinit();
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

    self.destroyDroppedEntities();
    self.flushDeferred();
    self.flushNotifications();
    self.flushEvents();
    self.flushBatched();
}

fn flushBatched(self: *App) void {
    const chunks = self.chunks.allocator();
    var batch: Runner.Batch = .{};
    {
        self.runner.batcher.lock(self.runner.io) catch return;
        defer self.runner.batcher.unlock(self.runner.io);

        while (self.runner.batcher.batches.popFront()) |b| {
            var other = b;
            batch.concat(&other);
        }
    }

    while (batch.pop()) |b| {
        const reach = b.subscription.notify(.{ self, b.ptr, b.type });
        if (!reach) b.deinit();
        b.destroy(chunks);
        chunks.destroy(b);
    }
}

pub fn flushNotifications(self: *App) void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notifyAll(id, .{ self, id });
    }

    self.notifications.clear(self.chunks.allocator());
}

pub fn flushDeferred(self: *App) void {
    const chunks = self.chunks.allocator();
    while (self.deferred.pop()) |deferred| {
        deferred.callback(deferred.ptr);
        chunks.rawFree(
            @as([*]u8, @ptrCast(deferred.ptr))[0..MAX_SIZE],
            MAX_ALIGN,
            @returnAddress(),
        );
        chunks.destroy(deferred);
    }
}

pub fn flushEvents(self: *App) void {
    const chunk = self.chunks.allocator();
    while (!self.events.empty() or !self.dispatched.empty()) {
        while (self.events.pop()) |event| {
            self.listeners.notifyAll(
                event.id,
                .{ self, event.ptr, event.type },
            );

            event.destroy(chunk);
            chunk.destroy(event);
        }

        while (self.dispatched.pop()) |event| {
            const reach = event.subscription.notify(
                .{ self, event.ptr, event.type },
            );

            if (!reach) event.deinit();

            event.destroy(chunk);
            chunk.destroy(event);
        }
    }
}

pub fn destroyDroppedEntities(self: *App) void {
    const alloc = self.chunks.allocator();

    while (self.entities.popDrop()) |drop| {
        const ptr, const key, const type_info = drop;

        self.listeners.remove(key);
        self.receivers.remove(key);
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

    next: ?*Event = null,

    pub fn destroy(self: *const Event, chunk: Allocator) void {
        self.type.deinit(self.ptr);
        self.type.destroy(self.ptr, chunk);
    }
};

pub const Dispatched = struct {
    subscription: Receivers.Subscription,
    type: TypeId,
    ptr: *anyopaque,

    next: ?*Dispatched = null,

    pub fn deinit(self: *const Dispatched) void {
        self.type.deinit(self.ptr);
    }

    pub fn destroy(self: *const Dispatched, chunk: Allocator) void {
        self.type.destroy(self.ptr, chunk);
    }
};

pub const Deferred = struct {
    ptr: *anyopaque,
    callback: *const fn (*anyopaque) void,

    next: ?*Deferred = null,
};

pub const Listeners = Subscriptions(
    EntityId,
    @Tuple(&.{ *App, *anyopaque, TypeId }),
    ent.entityOrder,
);

pub const Receivers = Subscriptions(
    EntityId,
    @Tuple(&.{ *App, *anyopaque, TypeId }),
    ent.entityOrder,
);

pub fn receive(
    self: *App,
    receiver: anytype,
    comptime E: type,
    function: anytype,
    args: anytype,
) !Receivers.Subscription {
    const _Entity = @TypeOf(receiver);

    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("receiver must be an Entity(T)");
    }

    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn _callback(app: *App, ptr: *anyopaque, _type: TypeId, _args: Args) bool {
            if (TypeInfo.init(E) != _type) @panic("Receiver subscription event type mismatch");
            const event: *E = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, function, .{ app, event } ++ _args);
        }

        fn enable(sub: Receivers.Subscription) void {
            sub.enable();
        }
    };

    const sub = try self.receivers.insert(
        receiver.id(),
        TypeErased._callback,
        .{args},
    );

    _ = self.@"defer"(TypeErased.enable, .{sub});

    return sub;
}

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

        fn enable(sub: Listeners.Subscription) void {
            sub.enable();
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

    const event = try chunk.create(Event);
    event.* = .{
        .id = entity.id(),
        .ptr = ptr,
        .type = TypeInfo.init(E),
    };

    self.events.push(event);

    return ptr;
}

pub fn dispatch(self: *App, subscription: Receivers.Subscription, comptime E: type) !*E {
    const chunk = self.chunks.allocator();
    const ptr = try chunk.create(E);
    errdefer chunk.destroy(ptr);

    const _dispatch = try chunk.create(Dispatched);

    _dispatch.* = .{
        .subscription = subscription,
        .ptr = ptr,
        .type = TypeInfo.init(E),
    };

    self.dispatched.push(_dispatch);

    return ptr;
}

pub const Observers = Subscriptions(
    EntityId,
    @Tuple(&.{ *App, EntityId }),
    ent.entityOrder,
);

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

        fn enable(sub: Observers.Subscription) void {
            sub.enable();
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

        pub fn chunks(self: *const @This()) Allocator {
            return self.app.chunks.allocator();
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

        pub fn receive(self: *const @This(), comptime E: type, function: anytype, args: anytype) !Receivers.Subscription {
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

                    return @call(.always_inline, function, .{ ptr, event, ctx } ++ _args);
                }
            };

            return try self.app.receive(self.entity, E, TypeErased.callback, .{ self.entity.any, args });
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

        pub fn @"defer"(self: *const @This(), function: anytype, args: anytype) void {
            const Args = @TypeOf(args);
            const TypeErased = struct {
                pub fn @"defer"(any: AnyEntity, app: *App, _args: Args) void {
                    const _entity = _Entity.from(any) orelse return;

                    const ctx: Context(T) = .new(app, _entity);

                    @call(.always_inline, function, .{ctx} ++ _args);
                }
            };
            self.app.@"defer"(TypeErased.@"defer", .{ self.entity.any, self.app, args });
        }

        pub fn runner(self: *const @This()) *Runner {
            return &self.app.runner;
        }
    };
}

pub fn @"defer"(
    self: *App,
    function: anytype,
    args: anytype,
) void {
    const Args = @TypeOf(args);

    const chunks = self.chunks.allocator();
    const deferred = chunks.create(Deferred) catch @panic("Deferred Overflow");

    const TypeErased = struct {
        fn complete(ptr: *anyopaque) void {
            const _args: *Args = @ptrCast(@alignCast(ptr));

            @call(.always_inline, function, _args.*);
        }
    };

    const ptr = chunks.rawAlloc(MAX_SIZE, MAX_ALIGN, @returnAddress()) orelse
        @panic("Deferred Context Overflow");

    const clone: *Args = @ptrCast(@alignCast(ptr));
    clone.* = args;
    deferred.* = .{ .ptr = clone, .callback = TypeErased.complete };

    self.deferred.push(deferred);
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

test "Queued receiver event targets a typed subscription" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        value: usize,
    };

    const TestStruct = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const receiver = try Entity(TestStruct).new(&app, .{});
    var received: usize = 0;

    const Receiver = struct {
        pub fn callback(_: *App, event: *TestEvent, value: *usize) bool {
            value.* = event.value;
            return false;
        }
    };

    const sub = try app.receive(receiver, TestEvent, Receiver.callback, .{&received});
    app.flush();

    const event = try app.dispatch(sub, TestEvent);
    event.* = .{ .value = 35 };
    app.flush();

    try testing.expectEqual(@as(usize, 35), received);
    try testing.expectEqual(null, app.receivers.subscribers.get_ref(receiver.id()));

    receiver.drop();
    app.flush();
}

test "Context receive updates the receiver entity" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        value: usize,
    };

    const TestStruct = struct {
        value: usize,

        pub fn init(self: *@This(), _: Context(@This())) !void {
            self.* = .{ .value = 0 };
        }

        pub fn receive(self: *@This(), event: *TestEvent, _: Context(@This())) bool {
            self.value = event.value;
            return true;
        }
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const receiver = try Entity(TestStruct).new(&app, .{});
    const ctx = receiver.ctx(&app);
    const sub = try ctx.receive(TestEvent, TestStruct.receive, .{});
    app.flush();

    const first = try app.dispatch(sub, TestEvent);
    first.* = .{ .value = 35 };
    app.flush();

    try testing.expectEqual(@as(usize, 35), receiver.read().value);
    try testing.expect(app.receivers.subscribers.get_ref(receiver.id()).?.*.?.get(sub.id) != null);

    const second = try app.dispatch(sub, TestEvent);
    second.* = .{ .value = 70 };
    app.flush();

    try testing.expectEqual(@as(usize, 70), receiver.read().value);
    try sub.unsubscribe();

    receiver.drop();
    app.flush();
}

test "Dropping a receiver removes subscriptions before queued delivery" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        deinit_called: *bool,

        pub fn deinit(self: *@This()) void {
            self.deinit_called.* = true;
        }
    };

    const TestStruct = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}
    };

    var app: App = undefined;
    try app.init(.{}, allocator, io);
    defer app.deinit();

    const receiver = try Entity(TestStruct).new(&app, .{});
    var callback_called = false;
    var deinit_called = false;

    const Receiver = struct {
        pub fn callback(_: *App, _: *TestEvent, called: *bool) bool {
            called.* = true;
            return true;
        }
    };

    const sub = try app.receive(receiver, TestEvent, Receiver.callback, .{&callback_called});
    app.flush();

    const event = try app.dispatch(sub, TestEvent);
    event.* = .{ .deinit_called = &deinit_called };

    const receiver_id = receiver.id();
    receiver.drop();
    app.flush();

    try testing.expect(!callback_called);
    try testing.expect(deinit_called);
    try testing.expectEqual(null, app.receivers.subscribers.get_ref(receiver_id));
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

        pub fn deferred(ctx: Context(@This()), value: usize) void {
            const ptr, const update = ctx.update();
            defer update.end(ptr);

            ptr.set(value);
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
    context.@"defer"(State.deferred, .{42});

    try testing.expectEqual(0, entity.read().calls);

    app.flush();

    try testing.expectEqual(1, entity.read().calls);
    try testing.expectEqual(42, entity.read().last_value);

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

test "Batch wakes the app" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        value: usize,
    };

    const TestEntity = struct {
        pub fn init(_: *@This(), _: Context(@This())) !void {}
    };

    const Wakeup = struct {
        fn callback(userdata: *anyopaque) void {
            const count: *std.atomic.Value(usize) = @ptrCast(@alignCast(userdata));
            _ = count.fetchAdd(1, .release);
        }
    };

    var wakeups: std.atomic.Value(usize) = .init(0);
    var app: App = undefined;
    try app.init(.{ .userdata = &wakeups, .wakeup_cb = Wakeup.callback }, allocator, io);
    defer app.deinit();

    const receiver = try Entity(TestEntity).new(&app, .{});
    var received: usize = 0;

    const Receiver = struct {
        fn callback(_: *App, event: *TestEvent, value: *usize) bool {
            value.* = event.value;
            return true;
        }
    };

    const subscription = try app.receive(receiver, TestEvent, Receiver.callback, .{&received});
    app.flush();

    const TestExecutor = struct {
        initialized: bool,

        pub fn init(self: *@This(), runner: *Runner, sub: Receivers.Subscription) !void {
            self.* = .{ .initialized = true };
            _ = try runner.@"defer"(sendEvent, .{ self, runner, sub });
        }

        fn sendEvent(_: *@This(), runner: *Runner, sub: Receivers.Subscription, res: anyerror!void) bool {
            res catch return false;
            const event = runner.dispatch(sub, TestEvent) catch return false;
            event.* = .{ .value = 35 };
            return false;
        }
    };

    const test_executor = try app.runner.create(TestExecutor);
    try test_executor.init(&app.runner, subscription);
    defer app.runner.drop(test_executor);

    for (0..1000) |_| {
        if (wakeups.load(.acquire) != 0) break;
        io.sleep(.fromMilliseconds(1), .real) catch {};
    }

    try testing.expectEqual(@as(usize, 1), wakeups.load(.acquire));

    app.flush();
    try testing.expectEqual(@as(usize, 35), received);

    receiver.drop();
    app.flush();
}
