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
const MAX_CONTEXT_SIZE = constants.MAX_CONTEXT_SIZE;
const MAX_CONTEXT_ALIGN = constants.MAX_CONTEXT_ALIGN;
const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;
const SinglyLinkedList = datastruct.SinglyLinkedList;
const ent = @import("entity.zig");
const Entity = ent.Entity;
const AnyEntity = ent.AnyEntity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const Waker = Loop.Waker;
const subs = @import("subscription.zig");
const Subscriptions = subs.Subscriptions;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;
const Scheduler = @import("scheduler.zig");

const CHUNK_SIZES: []const chunk_pool.PoolConfig = &.{
    .{ 50, 128 },
    .{ 50, 256 },
    .{ 50, 512 },
    .{ 50, 2048 },
};

const log = std.log.scoped(.app);

pub const Options = struct {
    fn noop(_: *anyopaque) void {}

    userdata: *anyopaque = undefined,
    wakeup_cb: *const fn (*anyopaque) void = noop,
};

pub const App = @This();

io: Io,
gpa: Allocator,
arena: heap.ArenaAllocator,
entities: EntityStore,
events: SinglyLinkedList(Event),
dispatched: SinglyLinkedList(Dispatched),
deferred: SinglyLinkedList(Deferred),
listeners: Listeners,
receivers: Receivers,
observers: Observers,
chunks: ChunkAllocator,
peding_updates: u16,
scheduler: Scheduler,

loop: Loop,

notifications: btree.BPlusSet(EntityId, ent.entityOrder),

flushing: bool,

options: Options,

pub fn init(self: *App, options: Options, gpa: Allocator, io: Io) !void {
    self.* = .{
        .io = io,
        .options = options,
        .notifications = undefined,
        .entities = undefined,
        .observers = undefined,
        .listeners = undefined,
        .receivers = undefined,
        .chunks = undefined,
        .loop = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
        .arena = .init(gpa),
        .events = .{},
        .dispatched = .{},
        .deferred = .{},
        .scheduler = undefined,
    };

    try self.loop.init(self.io);
    errdefer self.loop.deinit();

    const arena = self.arena.allocator();
    errdefer self.arena.deinit();

    try self.entities.init(arena, 100);
    try self.chunks.init(arena, CHUNK_SIZES);

    const chunks = self.chunks.allocator();

    try self.observers.init(chunks);
    try self.listeners.init(chunks);
    try self.receivers.init(chunks);
    try self.notifications.init(chunks);

    try self.scheduler.init(arena, self.io);
}

pub fn deinit(self: *App) void {
    self.scheduler.deinit();
    self.flush(.until_done);
    self.receivers.deinit();
    self.arena.deinit();
    self.loop.deinit();
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
        self.flush(.no_wait);
    }
    self.peding_updates -= 1;
}

pub fn flush(self: *App, mode: Loop.RunMode) void {
    if (self.flushing) return;

    self.flushing = true;
    defer self.flushing = false;

    self.loop.run(mode) catch |err| {
        log.err("Event Loop err={}", .{err});
    };
    self.destroyDroppedEntities();
    self.flushDeferred();
    self.flushNotifications();
    self.flushEvents();
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
        deferred.callback(&deferred.context);
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
            const reach = self.receivers.notify(
                event.subscription,
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

pub const Deferred = struct {
    callback: *const fn (*anyopaque) void,
    context: [MAX_CONTEXT_SIZE]u8 align(MAX_CONTEXT_ALIGN.toByteUnits()),

    next: ?*Deferred = null,
};

pub const Listeners = Subscriptions(
    EntityId,
    @Tuple(&.{ *App, *anyopaque, TypeId }),
    ent.entityOrder,
);

pub const Listener = Listeners.Subscription;

pub const Receivers = Subscriptions(
    EntityId,
    @Tuple(&.{ *App, *anyopaque, TypeId }),
    ent.entityOrder,
);

pub const Receiver = Receivers.Subscription;

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

pub fn receive(
    self: *App,
    receiver: anytype,
    comptime E: type,
    function: anytype,
    args: anytype,
) !Receiver {
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

        fn enable(app: *App, sub: Receiver) void {
            app.receivers.enable(sub);
        }
    };

    const sub = try self.receivers.insert(
        receiver.id(),
        TypeErased._callback,
        .{args},
    );

    _ = self.@"defer"(TypeErased.enable, .{ self, sub });

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

        fn enable(app: *App, sub: Listener) void {
            app.listeners.enable(sub);
        }
    };

    const sub = try self.listeners.insert(
        entity.id(),
        TypeErased._callback,
        .{args},
    );

    _ = self.@"defer"(TypeErased.enable, .{ self, sub });

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

    self.events.append(event);

    return ptr;
}

pub fn dispatch(self: *App, subscription: Receiver, comptime E: type) !*E {
    const chunk = self.chunks.allocator();
    const ptr = try chunk.create(E);
    errdefer chunk.destroy(ptr);

    const _dispatch = try chunk.create(Dispatched);

    _dispatch.* = .{
        .subscription = subscription,
        .ptr = ptr,
        .type = TypeInfo.init(E),
    };

    self.dispatched.append(_dispatch);

    return ptr;
}

pub const Observers = Subscriptions(
    EntityId,
    @Tuple(&.{ *App, EntityId }),
    ent.entityOrder,
);

pub const Observer = Observers.Subscription;

pub fn observe(
    self: *App,
    entity: anytype,
    function: anytype,
    args: anytype,
) !Observer {
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

        fn enable(app: *App, sub: Observer) void {
            app.observers.enable(sub);
        }
    };

    const sub = try self.observers.insert(
        entity.id(),
        TypeErased._callback,
        .{args},
    );

    _ = self.@"defer"(TypeErased.enable, .{ self, sub });

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

        pub fn receive(
            self: *const @This(),
            comptime E: type,
            function: anytype,
            args: anytype,
        ) !Receiver {
            const Args = @TypeOf(args);

            const TypeErased = struct {
                pub fn callback(
                    app: *App,
                    event: *E,
                    any: AnyEntity,
                    _args: Args,
                ) bool {
                    const _entity = _Entity.from(any) orelse unreachable;

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    return @call(.always_inline, function, .{ ptr, event } ++ _args);
                }
            };

            return try self.app.receive(self.entity, E, TypeErased.callback, .{ self.entity.any, args });
        }

        pub fn listen(
            self: *const @This(),
            comptime E: type,
            entity: anytype,
            function: anytype,
            args: anytype,
        ) !Listener {
            const Args = @TypeOf(args);

            const TypeErased = struct {
                pub fn callback(
                    app: *App,
                    event: *E,
                    any: AnyEntity,
                    _args: Args,
                ) bool {
                    const _entity = _Entity.from(any) orelse unreachable;

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    @call(.always_inline, function, .{ ptr, event } ++ _args);

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
        ) !Observer {
            const Args = @TypeOf(args);
            const Observed = @TypeOf(entity);

            const TypeErased = struct {
                pub fn callback(
                    app: *App,
                    observed: Observed,
                    any: AnyEntity,
                    _args: Args,
                ) bool {
                    const _entity = _Entity.from(any) orelse unreachable;

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    @call(.always_inline, function, .{ ptr, observed } ++ _args);

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

                    const ptr, const _update = _entity.update(app);
                    defer _update.end(ptr);

                    @call(.always_inline, function, .{ptr} ++ _args);
                }
            };
            self.app.@"defer"(TypeErased.@"defer", .{ self.entity.any, self.app, args });
        }

        pub fn await(self: *const @This(), c: *Completion, function: anytype, args: anytype) !Waker {
            return try self.app.await(c, function, args);
        }

        pub fn timer(self: *const @This(), c: *Completion, function: anytype, context: anytype, ms: u64) void {
            self.app.timer(c, function, context, ms);
        }

        pub fn cancel(self: *const @This(), completion: *Completion, target: *Completion) void {
            self.app.cancel(completion, target);
        }
        pub fn scheduler(self: *const @This()) *Scheduler {
            return &self.app.scheduler;
        }
    };
}

pub fn await(self: *App, c: *Completion, function: anytype, args: anytype) !Waker {
    return try self.loop.await(c, function, args);
}

pub fn timer(self: *App, c: *Completion, function: anytype, context: anytype, ms: u64) void {
    self.loop.timer(c, function, context, ms);
}

pub fn cancel(self: *App, completion: *Completion, target: *Completion) void {
    completion.cancel(target);
    self.loop.cancel(completion);
}

pub fn @"defer"(
    self: *App,
    function: anytype,
    args: anytype,
) void {
    const Args = @TypeOf(args);
    assert(@sizeOf(Args) <= MAX_CONTEXT_SIZE);
    assert(@alignOf(Args) <= MAX_CONTEXT_ALIGN.toByteUnits());

    const chunks = self.chunks.allocator();
    const deferred = chunks.create(Deferred) catch @panic("Deferred Overflow");

    const TypeErased = struct {
        fn complete(ptr: *anyopaque) void {
            const _args: *Args = @ptrCast(@alignCast(ptr));

            @call(.always_inline, function, _args.*);
        }
    };

    deferred.* = .{ .callback = TypeErased.complete, .context = undefined };

    const clone: *Args = @ptrCast(@alignCast(&deferred.context));
    clone.* = args;

    self.deferred.append(deferred);
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

    app.flush(.no_wait);
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

    app.flush(.no_wait);

    try testing.expect(context);

    for (entities) |entity| {
        entity.drop();
    }

    app.flush(.no_wait);
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

    app.flush(.no_wait);

    try testing.expectEqual(context, 35);

    listened.drop();
    app.flush(.no_wait);
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

    const TestReceiver = struct {
        pub fn callback(_: *App, event: *TestEvent, value: *usize) bool {
            value.* = event.value;
            return false;
        }
    };

    const sub = try app.receive(receiver, TestEvent, TestReceiver.callback, .{&received});
    app.flush(.no_wait);

    const event = try app.dispatch(sub, TestEvent);
    event.* = .{ .value = 35 };
    app.flush(.no_wait);

    try testing.expectEqual(@as(usize, 35), received);
    try testing.expectEqual(null, app.receivers.subscribers.get_mut(receiver.id()));

    receiver.drop();
    app.flush(.no_wait);
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

        pub fn receive(self: *@This(), event: *TestEvent) bool {
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
    app.flush(.no_wait);

    const first = try app.dispatch(sub, TestEvent);
    first.* = .{ .value = 35 };
    app.flush(.no_wait);

    try testing.expectEqual(@as(usize, 35), receiver.read().value);
    try testing.expect(app.receivers.subscribers.get_mut(receiver.id()).?.get(sub.id) != null);

    const second = try app.dispatch(sub, TestEvent);
    second.* = .{ .value = 70 };
    app.flush(.no_wait);

    try testing.expectEqual(@as(usize, 70), receiver.read().value);
    app.receivers.unsubscribe(sub);

    receiver.drop();
    app.flush(.no_wait);
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

    const TestReceiver = struct {
        pub fn callback(_: *App, _: *TestEvent, called: *bool) bool {
            called.* = true;
            return true;
        }
    };

    const sub = try app.receive(receiver, TestEvent, TestReceiver.callback, .{&callback_called});
    app.flush(.no_wait);

    const event = try app.dispatch(sub, TestEvent);
    event.* = .{ .deinit_called = &deinit_called };

    const receiver_id = receiver.id();
    receiver.drop();
    app.flush(.no_wait);

    try testing.expect(!callback_called);
    try testing.expect(deinit_called);
    try testing.expectEqual(null, app.receivers.subscribers.get_mut(receiver_id));
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
        pub fn callback(ptr: *TestStruct, evt: *TestEvent) void {
            ptr.index = evt.id;
        }
    };

    _ = try context.listen(TestEvent, listened, Listened.callback, .{});

    const evt = try listened.nevent(&app, TestEvent);
    evt.* = .{
        .id = 35,
    };

    app.flush(.no_wait);

    try testing.expectEqual(listener.read().index, 35);

    listened.drop();
    listener.drop();
    app.flush(.no_wait);
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

        pub fn observe(self: *@This(), observed: Entity(Observed)) void {
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
    app.flush(.no_wait);

    try testing.expectEqual(1, observer.read().observed_updates);
    try testing.expectEqual(42, observer.read().last_observed_index);

    observer.drop();
    observed.drop();
    app.flush(.no_wait);
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

        pub fn deferred(ptr: *@This(), value: usize) void {
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

    app.flush(.no_wait);

    try testing.expectEqual(1, entity.read().calls);
    try testing.expectEqual(42, entity.read().last_value);

    entity.drop();
    app.flush(.no_wait);
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

        pub fn observe(_: *@This(), _: Entity(Observed)) void {}
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
    app.flush(.no_wait);

    try testing.expectEqual(null, app.observers.subscribers.get(observed_id));

    observer.drop();
    app.flush(.no_wait);
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
    app.observers.unsubscribe(sub);

    index = 1;

    {
        const ptr, const update = observed.update(&app);
        defer update.end(ptr);

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.read().index);
    observed.notify(&app);

    app.flush(.no_wait);

    try testing.expect(!context);

    for (entities) |entity| {
        entity.drop();
    }

    app.flush(.no_wait);
}
