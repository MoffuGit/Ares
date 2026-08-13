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
const Scheduler = @import("scheduler.zig");
const subs = @import("subscription.zig");
const Subscriptions = subs.Subscriptions;
const typeId = @import("typeId.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;

const CHUNK_SIZES: []const chunk_pool.PoolConfig = &.{
    .{ 50, 128 },
    .{ 50, 256 },
    .{ 50, 512 },
    .{ 50, 2048 },
};

const log = std.log.scoped(.app);

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

pub fn init(self: *App, gpa: Allocator, io: Io) !void {
    self.* = .{
        .io = io,
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
    errdefer self.scheduler.deinit();

    try self.loop.init(&self.scheduler, self.io);
    errdefer self.loop.deinit();
}

pub fn deinit(self: *App) void {
    self.flush(.until_done);
    self.scheduler.deinit();
    self.receivers.deinit();
    self.arena.deinit();
    self.loop.deinit();
}

pub fn new(self: *App, comptime T: type, function: anytype, args: anytype) !Entity(T) {
    const alloc = self.chunks.allocator();
    const ptr = try alloc.create(T);
    errdefer alloc.destroy(ptr);

    const id = self.entities.insert(ptr);
    errdefer self.entities.recycle(id);

    const entity: Entity(T) = .new(&self.entities, id);
    const ctx: Context(T) = .new(self, entity);

    const update = ctx.update();
    defer update.end();

    try @call(.always_inline, function, .{ ptr, ctx } ++ args);

    return entity;
}

pub const Update = struct {
    any: AnyEntity,
    app: *App,

    pub fn end(self: *const @This()) void {
        self.app.entities.endUpdate(self.any.id);
        if (self.app.peding_updates == 1) {
            self.app.flush(.no_wait);
        }
        self.app.peding_updates -= 1;
    }
};

pub fn startUpdate(self: *App, entity: anytype) Update {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    self.peding_updates += 1;
    self.entities.startUpdate(entity.any.id);

    return .{ .any = entity.any, .app = self };
}

pub fn flush(self: *App, mode: Loop.RunMode) void {
    if (self.flushing) return;

    self.flushing = true;
    defer self.flushing = false;

    self.loop.run(mode) catch |err| {
        log.err("Event Loop err={}", .{err});
    };
    self.flushDeferred();
    self.destroyDroppedEntities();
    self.flushNotifications();
    self.flushEvents();
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

pub fn flushNotifications(self: *App) void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notifyAll(id, .{ self, id });
    }

    self.notifications.clear(self.chunks.allocator());
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
    observer: *Observer,
) !void {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const T = _Entity.EntityType;

    const TypeErased = struct {
        fn _callback(sub: *Observer, app: *App, id: EntityId) bool {
            const observed = AnyEntity.init(&app.entities, id, TypeInfo.init(T));
            const _entity = _Entity.from(observed) orelse return false;
            return @call(.always_inline, function, .{ sub, app, _entity });
        }
    };

    try self.observers.insert(
        entity.id(),
        TypeErased._callback,
        observer,
    );

    self.@"defer"(Observer, Observer.enable, observer);
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

pub fn flushDeferred(self: *App) void {
    const chunks = self.chunks.allocator();

    while (self.deferred.pop()) |deferred| {
        deferred.callback(deferred.context);
        chunks.destroy(deferred);
    }
}

pub fn @"defer"(
    self: *App,
    comptime T: type,
    comptime function: *const fn (*T) void,
    data: *T,
) void {
    const chunks = self.chunks.allocator();
    const deferred = chunks.create(Deferred) catch @panic("Deferred Overflow");

    const TypeErased = struct {
        fn callback(ptr: *anyopaque) void {
            const d: *T = @ptrCast(@alignCast(ptr));

            @call(.always_inline, function, .{d});
        }
    };

    deferred.* = .{ .callback = TypeErased.callback, .context = data };

    self.deferred.append(deferred);
}

pub const Deferred = struct {
    callback: *const fn (*anyopaque) void,
    context: *anyopaque,

    next: ?*Deferred = null,
};

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
                event.key,
                event.id,
                .{ self, event.ptr, event.type },
            );

            if (!reach) event.deinit();

            event.destroy(chunk);
            chunk.destroy(event);
        }
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
    key: Receivers.Key,
    id: u32,
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

pub fn receive(
    self: *App,
    entity: anytype,
    comptime E: type,
    function: anytype,
    receiver: *Receiver,
) !void {
    const _Entity = @TypeOf(entity);

    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("receiver must be an Entity(T)");
    }

    const TypeErased = struct {
        fn _callback(sub: *Receiver, app: *App, ptr: *anyopaque, _type: TypeId) bool {
            if (TypeInfo.init(E) != _type) @panic("Receiver subscription event type mismatch");
            const event: *E = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, function, .{ sub, app, event });
        }
    };

    try self.receivers.insert(
        entity.id(),
        TypeErased._callback,
        receiver,
    );

    self.@"defer"(Receiver, Receiver.enable, receiver);
}

pub fn listen(
    self: *App,
    entity: anytype,
    comptime E: type,
    function: anytype,
    listener: *Listener,
) !void {
    const _Entity = @TypeOf(entity);

    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const TypeErased = struct {
        fn _callback(sub: *Listener, app: *App, ptr: *anyopaque, _type: TypeId) bool {
            if (TypeInfo.init(E) != _type) return true;
            const event: *E = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, function, .{ sub, app, event });
        }

        fn enable(app: *App, sub: Listener) void {
            app.listeners.enable(sub);
        }
    };

    try self.listeners.insert(
        entity.id(),
        TypeErased._callback,
        listener,
    );

    self.@"defer"(Listener, Listener.enable, listener);
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

pub fn dispatch(self: *App, key: Receivers.Key, id: u32, comptime E: type) !*E {
    const chunk = self.chunks.allocator();
    const ptr = try chunk.create(E);
    errdefer chunk.destroy(ptr);

    const dispatched = try chunk.create(Dispatched);

    dispatched.* = .{
        .key = key,
        .id = id,
        .ptr = ptr,
        .type = TypeInfo.init(E),
    };

    self.dispatched.append(dispatched);

    return ptr;
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

        pub fn update(self: *const @This()) Update {
            return self.app.startUpdate(self.entity);
        }

        pub fn notify(self: *const @This()) void {
            self.app.notify(self.entity);
        }

        pub fn nevent(self: *const @This(), comptime E: type) !*E {
            return try self.entity.nevent(self.app, E);
        }

        pub fn receive(
            self: *const @This(),
            comptime E: type,
            function: anytype,
            receiver: *Receiver,
        ) !void {
            return try self.app.receive(
                self.entity,
                E,
                function,
                receiver,
            );
        }

        pub fn listen(
            self: *const @This(),
            entity: anytype,
            comptime E: type,
            function: anytype,
            listener: *Listener,
        ) !void {
            return try self.app.listen(
                entity,
                E,
                function,
                listener,
            );
        }

        pub fn observe(
            self: *const @This(),
            entity: anytype,
            function: anytype,
            observer: *Observer,
        ) !void {
            return try self.app.observe(
                entity,
                function,
                observer,
            );
        }

        pub fn @"defer"(
            self: *const @This(),
            comptime D: type,
            function: *const fn (*D) void,
            data: *D,
        ) void {
            self.app.@"defer"(
                D,
                function,
                data,
            );
        }

        pub fn await(self: *const @This(), c: *Completion, function: anytype) !Waker {
            return try self.app.await(c, function);
        }

        pub fn timer(self: *const @This(), c: *Completion, function: anytype, ms: u64) void {
            self.app.timer(c, function, ms);
        }

        pub fn cancel(self: *const @This(), completion: *Completion, target: *Completion) void {
            self.app.cancel(completion, struct {
                fn cancel(_: *Completion, _: void) bool {
                    return false;
                }
            }.cancel, target);
        }

        pub fn scheduler(self: *const @This()) *Scheduler {
            return &self.app.scheduler;
        }
    };
}

pub fn await(self: *App, c: *Completion, function: anytype) !Waker {
    return try self.loop.await(c, function);
}

pub fn timer(self: *App, c: *Completion, function: anytype, ms: u64) void {
    self.loop.timer(c, function, ms);
}

pub fn cancel(self: *App, completion: *Completion, function: anytype, target: *Completion) void {
    self.loop.cancel(completion, function, target);
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
    try app.init(allocator, io);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities, 0..) |*entity, index| {
        entity.* = try app.new(TestStruct, TestStruct.init, .{});

        {
            const ptr = entity.mut();
            const update = app.startUpdate(entity.*);
            defer update.end();

            ptr.set_index(index);
            ptr.inc();
        }

        try testing.expectEqual(index + 1, entity.get().?.index);
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
    try app.init(allocator, io);
    defer app.deinit();

    const observed = try app.new(TestStruct, TestStruct.init, .{});
    defer observed.drop();

    const TestObserver = struct {
        run: bool = false,
        observer: Observer = .noop,

        pub fn callback(observer: *Observer, _: *App, _: TestEntity) bool {
            const parent: *@This() = @fieldParentPtr("observer", observer);
            parent.run = true;
            return false;
        }
    };

    var observer: TestObserver = .{};

    var index: usize = 0;

    {
        const ptr = observed.mut();
        const update = app.startUpdate(observed);
        defer update.end();

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.get().?.index);
    app.notify(observed);

    try testing.expect(!observer.run);

    _ = try app.observe(observed, TestObserver.callback, &observer.observer);

    index = 1;

    {
        const ptr = observed.mut();
        const update = app.startUpdate(observed);
        defer update.end();

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.get().?.index);
    app.notify(observed);

    app.flush(.no_wait);

    try testing.expect(observer.run);

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

    var app: App = undefined;
    try app.init(allocator, io);
    defer app.deinit();

    const listened = try app.new(TestStruct, TestStruct.init, .{});

    const TestListener = struct {
        id: usize = 0,
        listener: Listener = .noop,

        pub fn callback(listener: *Listener, _: *App, evt: *TestEvent) bool {
            const parent: *@This() = @fieldParentPtr("listener", listener);
            parent.id = evt.id;
            return false;
        }
    };

    var listener: TestListener = .{};

    _ = try app.listen(listened, TestEvent, TestListener.callback, &listener.listener);

    const evt = try app.nevent(listened, TestEvent);
    evt.* = .{
        .id = 35,
    };

    app.flush(.no_wait);

    try testing.expectEqual(listener.id, 35);

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

    const TestReceiver = struct {
        received: usize = 0,
        receiver: Receiver = .noop,

        pub fn callback(receiver: *Receiver, _: *App, evt: *TestEvent) bool {
            const parent: *@This() = @fieldParentPtr("receiver", receiver);
            parent.received = evt.value;
            return false;
        }
    };

    var app: App = undefined;
    try app.init(allocator, io);
    defer app.deinit();

    const dispatcher = try app.new(TestStruct, TestStruct.init, .{});

    var receiver: TestReceiver = .{};

    try app.receive(dispatcher, TestEvent, TestReceiver.callback, &receiver.receiver);
    app.flush(.no_wait);

    const event = try app.dispatch(dispatcher.id(), receiver.receiver.id, TestEvent);
    event.* = .{ .value = 35 };
    app.flush(.no_wait);

    try testing.expectEqual(@as(usize, 35), receiver.received);
    try testing.expectEqual(null, app.receivers.subscribers.get_mut(dispatcher.id()));

    dispatcher.drop();
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

    const TestReceiver = struct {
        received: bool = false,
        receiver: Receiver = .noop,

        pub fn callback(receiver: *Receiver, _: *App, evt: *TestEvent) bool {
            const parent: *@This() = @fieldParentPtr("receiver", receiver);
            parent.received = evt.deinit_called.*;
            return false;
        }
    };

    var app: App = undefined;
    try app.init(allocator, io);
    defer app.deinit();

    const dispatcher = try app.new(TestStruct, TestStruct.init, .{});
    var deinit_called = false;

    var receiver: TestReceiver = .{};

    try app.receive(dispatcher, TestEvent, TestReceiver.callback, &receiver.receiver);
    app.flush(.no_wait);

    const event = try app.dispatch(dispatcher.id(), receiver.receiver.id, TestEvent);
    event.* = .{ .deinit_called = &deinit_called };

    const receiver_id = dispatcher.id();
    dispatcher.drop();
    app.flush(.no_wait);

    try testing.expect(!receiver.received);
    try testing.expect(deinit_called);
    try testing.expectEqual(null, app.receivers.subscribers.get_mut(receiver_id));
}

test "Observe entities drop before enable" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

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

    const TestObserver = struct {
        run: bool = false,
        observer: Observer = .noop,

        pub fn callback(observer: *Observer, _: *App, _: TestEntity) bool {
            const parent: *@This() = @fieldParentPtr("observer", observer);
            parent.run = true;
            return false;
        }
    };

    var app: App = undefined;
    try app.init(allocator, io);
    defer app.deinit();

    const observed = try app.new(TestStruct, TestStruct.init, .{});

    var observer: TestObserver = .{};

    var index: usize = 0;

    {
        const ptr = observed.mut();
        const update = app.startUpdate(observed);
        defer update.end();

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.get().?.index);
    app.notify(observed);

    try testing.expect(!observer.run);

    try app.observe(observed, TestObserver.callback, &observer.observer);
    app.observers.unsubscribe(observed.id(), observer.observer.id);

    index = 1;

    {
        const ptr = observed.mut();
        const update = app.startUpdate(observed);
        defer update.end();

        ptr.set_index(index);
        ptr.inc();
    }
    try testing.expectEqual(index + 1, observed.get().?.index);
    app.notify(observed);

    app.flush(.no_wait);

    try testing.expect(!observer.run);

    observed.drop();

    app.flush(.no_wait);
}
