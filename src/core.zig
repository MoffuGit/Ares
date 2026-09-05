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
const AnyEntity = ent.AnyEntity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const Loop = @import("loop.zig");
const Completion = Loop.Completion;
const Waker = Loop.Waker;
const Scheduler = @import("scheduler.zig");
const subs = @import("subscription.zig");
const Subscriptions = subs.Subscriptions;
const typeId = @import("type_id.zig");
const TypeInfo = typeId.TypeInfo;
const TypeId = typeId.TypeId;

const CHUNK_SIZES: []const chunk_pool.Options = &.{
    .{ .capacity = 50, .chunk_size = 128 },
    .{ .capacity = 50, .chunk_size = 256 },
    .{ .capacity = 50, .chunk_size = 512 },
    .{ .capacity = 50, .chunk_size = 2048 },
};

const log = std.log.scoped(.core);

pub const Core = @This();

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
scheduler: Scheduler,

flushing: bool,
pending_updates: u8,

loop: Loop,
notifications: btree.BPlusSet(EntityId, ent.entityOrder),

const Options = struct {};

pub fn init(self: *Core, gpa: Allocator, io: Io, _: Options) !void {
    self.* = .{
        .flushing = false,
        .pending_updates = 0,
        .io = io,
        .notifications = undefined,
        .entities = undefined,
        .observers = undefined,
        .listeners = undefined,
        .receivers = undefined,
        .chunks = undefined,
        .loop = undefined,
        .gpa = gpa,
        .arena = .init(gpa),
        .events = .empty,
        .dispatched = .empty,
        .deferred = .empty,
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

pub fn deinit(self: *Core) void {
    self.run(.until_done);
    self.flush();
    self.scheduler.deinit();
    self.receivers.deinit();
    self.arena.deinit();
    self.loop.deinit();
}

pub fn new(self: *Core, comptime T: type, function: anytype, args: anytype) !*T {
    const alloc = self.chunks.allocator();
    const ptr = try alloc.create(T);
    errdefer alloc.destroy(ptr);

    const id = self.entities.insert(ptr);
    errdefer self.entities.recycle(id);

    self.update();
    defer self.endUpdate();

    const any: AnyEntity = .init(&self.entities, id, TypeInfo.init(T));

    try @call(.always_inline, function, .{ ptr, any, self } ++ args);

    return ptr;
}

pub fn update(self: *Core) void {
    self.pending_updates += 1;
}

pub fn endUpdate(self: *Core) void {
    self.pending_updates -= 1;
    if (self.pending_updates == 0) self.flush();
}

pub fn run(self: *Core, mode: Loop.RunMode) void {
    self.loop.run(mode) catch |err| log.err("Loop err={}", .{err});
}

pub fn stop(self: *Core) void {
    self.loop.stop();
}

pub fn flush(self: *Core) void {
    if (self.flushing) return;

    self.flushing = true;
    defer self.flushing = false;

    self.flushDeferred();
    self.destroyDroppedEntities();
    self.flushNotifications();
    self.flushEvents();
}

pub fn destroyDroppedEntities(self: *Core) void {
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

pub fn flushNotifications(self: *Core) void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notifyAll(id, .{ self, id });
    }

    self.notifications.clear(self.chunks.allocator());
}

pub const Observers = Subscriptions(
    EntityId,
    @Tuple(&.{ *Core, EntityId }),
    ent.entityOrder,
);

pub const Observer = Observers.Subscription;

pub fn observe(
    self: *Core,
    entity: anytype,
    function: anytype,
    observer: *Observer,
) !void {
    const T = @typeInfo(@TypeOf(entity)).pointer.child;

    const TypeErased = struct {
        fn _callback(sub: *Observer, core: *Core, id: EntityId) bool {
            const observed = AnyEntity.init(&core.entities, id, TypeInfo.init(T));
            const ptr = observed.into(T) orelse return false;
            return @call(
                .always_inline,
                function,
                .{ sub, core, ptr },
            );
        }
    };

    try self.observers.insert(
        entity.any.id,
        TypeErased._callback,
        observer,
    );

    self.@"defer"(Observer, Observer.enable, observer);
}

pub fn notify(self: *Core, entity: anytype) void {
    _ = self.notifications.insert(self.chunks.allocator(), entity.any.id) catch |err| {
        log.err("We cannot notify, err: {}", .{err});
    };
}

pub fn flushDeferred(self: *Core) void {
    const chunks = self.chunks.allocator();

    while (self.deferred.pop()) |deferred| {
        deferred.callback(deferred.context);
        chunks.destroy(deferred);
    }
}

pub fn @"defer"(
    self: *Core,
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

pub fn flushEvents(self: *Core) void {
    const chunk = self.chunks.allocator();
    while (!self.events.is_empty() or !self.dispatched.is_empty()) {
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
    @Tuple(&.{ *Core, *anyopaque, TypeId }),
    ent.entityOrder,
);

pub const Listener = Listeners.Subscription;

pub const Receivers = Subscriptions(
    EntityId,
    @Tuple(&.{ *Core, *anyopaque, TypeId }),
    ent.entityOrder,
);

pub const Receiver = Receivers.Subscription;

pub fn receive(
    self: *Core,
    entity: anytype,
    comptime E: type,
    function: anytype,
    receiver: *Receiver,
) !void {
    const TypeErased = struct {
        fn _callback(sub: *Receiver, core: *Core, ptr: *anyopaque, _type: TypeId) bool {
            if (TypeInfo.init(E) != _type) @panic("Receiver subscription event type mismatch");
            const event: *E = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, function, .{ sub, core, event });
        }
    };

    try self.receivers.insert(
        entity.any.id,
        TypeErased._callback,
        receiver,
    );

    self.@"defer"(Receiver, Receiver.enable, receiver);
}

pub fn listen(
    self: *Core,
    entity: anytype,
    comptime E: type,
    function: anytype,
    listener: *Listener,
) !void {
    const TypeErased = struct {
        fn _callback(sub: *Listener, core: *Core, ptr: *anyopaque, _type: TypeId) bool {
            if (TypeInfo.init(E) != _type) return true;
            const event: *E = @ptrCast(@alignCast(ptr));
            return @call(.always_inline, function, .{ sub, core, event });
        }

        fn enable(core: *Core, sub: Listener) void {
            core.listeners.enable(sub);
        }
    };

    try self.listeners.insert(
        entity.any.id,
        TypeErased._callback,
        listener,
    );

    self.@"defer"(Listener, Listener.enable, listener);
}

pub fn nevent(self: *Core, entity: anytype, comptime E: type) !*E {
    const chunk = self.chunks.allocator();
    const ptr = try chunk.create(E);
    errdefer chunk.destroy(ptr);

    const event = try chunk.create(Event);
    event.* = .{
        .id = entity.any.id,
        .ptr = ptr,
        .type = TypeInfo.init(E),
    };

    self.events.append(event);

    return ptr;
}

pub fn dispatch(self: *Core, entity: anytype, id: u32, comptime E: type) !*E {
    const chunk = self.chunks.allocator();
    const ptr = try chunk.create(E);
    errdefer chunk.destroy(ptr);

    const dispatched = try chunk.create(Dispatched);

    dispatched.* = .{
        .key = entity.any.id,
        .id = id,
        .ptr = ptr,
        .type = TypeInfo.init(E),
    };

    self.dispatched.append(dispatched);

    return ptr;
}

pub fn await(self: *Core, completion: *Completion, function: anytype) !Waker {
    return try self.loop.await(completion, function);
}

pub fn timer(self: *Core, completion: *Completion, function: anytype, ms: u64) void {
    self.loop.timer(completion, function, ms);
}

pub fn cancel(self: *Core, completion: *Completion, function: anytype, target: *Completion) void {
    self.loop.cancel(completion, function, target);
}

const TestStruct = struct {
    index: usize,
    any: AnyEntity,

    pub fn init(self: *@This(), any: AnyEntity, _: *Core) !void {
        self.* = .{ .index = 0, .any = any };
    }

    pub fn set_index(self: *@This(), index: usize) void {
        self.index = index;
    }

    pub fn inc(self: *@This()) void {
        self.index += 1;
    }

    pub fn drop(self: *@This()) void {
        self.any.drop();
    }
};

test "creates/drops entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;
    const entity_count = 32;

    var core: Core = undefined;
    try core.init(allocator, io, .{});
    defer core.deinit();

    var entities: [entity_count]AnyEntity = undefined;
    for (&entities, 0..) |*entity, index| {
        const ptr = try core.new(TestStruct, TestStruct.init, .{});
        entity.* = ptr.any;

        ptr.set_index(index);
        ptr.inc();
    }

    for (entities, 0..) |entity, index| {
        try testing.expectEqual(index + 1, entity.into(TestStruct).?.index);
        entity.drop();
    }

    core.flush();
}

test "Observe entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    var core: Core = undefined;
    try core.init(allocator, io, .{});
    defer core.deinit();

    const observed = try core.new(TestStruct, TestStruct.init, .{});
    defer observed.drop();

    const TestObserver = struct {
        run: bool = false,
        observer: Observer = .noop,

        pub fn callback(observer: *Observer, _: *Core, _: *TestStruct) bool {
            const parent: *@This() = @fieldParentPtr("observer", observer);
            parent.run = true;
            return false;
        }
    };

    var observer: TestObserver = .{};

    var index: usize = 0;

    observed.set_index(index);
    observed.inc();
    core.notify(observed);

    try testing.expect(!observer.run);

    _ = try core.observe(observed, TestObserver.callback, &observer.observer);

    index = 1;

    observed.set_index(index);
    observed.inc();
    core.notify(observed);

    core.flush();

    try testing.expect(observer.run);

    core.flush();
}

test "Listen entities events" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        id: usize,
    };

    var core: Core = undefined;
    try core.init(allocator, io, .{});
    defer core.deinit();

    const listened = try core.new(TestStruct, TestStruct.init, .{});
    defer listened.drop();

    const TestListener = struct {
        id: usize = 0,
        listener: Listener = .noop,

        pub fn callback(listener: *Listener, _: *Core, evt: *TestEvent) bool {
            const parent: *@This() = @fieldParentPtr("listener", listener);
            parent.id = evt.id;
            return false;
        }
    };

    var listener: TestListener = .{};

    _ = try core.listen(listened, TestEvent, TestListener.callback, &listener.listener);

    const evt = try core.nevent(listened, TestEvent);
    evt.* = .{
        .id = 35,
    };

    core.flush();

    try testing.expectEqual(listener.id, 35);

    core.flush();
}

test "Queued receiver event targets a typed subscription" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestEvent = struct {
        value: usize,
    };

    const TestReceiver = struct {
        received: usize = 0,
        receiver: Receiver = .noop,

        pub fn callback(receiver: *Receiver, _: *Core, evt: *TestEvent) bool {
            const parent: *@This() = @fieldParentPtr("receiver", receiver);
            parent.received = evt.value;
            return false;
        }
    };

    var core: Core = undefined;
    try core.init(allocator, io, .{});
    defer core.deinit();

    const dispatcher = try core.new(TestStruct, TestStruct.init, .{});
    defer dispatcher.drop();

    var receiver: TestReceiver = .{};

    try core.receive(dispatcher, TestEvent, TestReceiver.callback, &receiver.receiver);
    core.flush();

    const event = try core.dispatch(dispatcher, receiver.receiver.id, TestEvent);
    event.* = .{ .value = 35 };
    core.flush();

    try testing.expectEqual(@as(usize, 35), receiver.received);
    try testing.expectEqual(null, core.receivers.subscribers.get_mut(dispatcher.any.id));

    core.flush();
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

    const TestReceiver = struct {
        received: bool = false,
        receiver: Receiver = .noop,

        pub fn callback(receiver: *Receiver, _: *Core, evt: *TestEvent) bool {
            const parent: *@This() = @fieldParentPtr("receiver", receiver);
            parent.received = evt.deinit_called.*;
            return false;
        }
    };

    var core: Core = undefined;
    try core.init(allocator, io, .{});
    defer core.deinit();

    const dispatcher = try core.new(TestStruct, TestStruct.init, .{});
    var deinit_called = false;

    var receiver: TestReceiver = .{};

    try core.receive(dispatcher, TestEvent, TestReceiver.callback, &receiver.receiver);
    core.flush();

    const event = try core.dispatch(dispatcher, receiver.receiver.id, TestEvent);
    event.* = .{ .deinit_called = &deinit_called };

    const receiver_id = dispatcher.any.id;
    dispatcher.drop();
    core.flush();

    try testing.expect(!receiver.received);
    try testing.expect(deinit_called);
    try testing.expectEqual(null, core.receivers.subscribers.get_mut(receiver_id));
}

test "Observe entities drop before enable" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;

    const TestObserver = struct {
        run: bool = false,
        observer: Observer = .noop,

        pub fn callback(observer: *Observer, _: *Core, _: *TestStruct) bool {
            const parent: *@This() = @fieldParentPtr("observer", observer);
            parent.run = true;
            return false;
        }
    };

    var core: Core = undefined;
    try core.init(allocator, io, .{});
    defer core.deinit();

    const observed = try core.new(TestStruct, TestStruct.init, .{});

    var observer: TestObserver = .{};

    var index: usize = 0;

    observed.set_index(index);
    observed.inc();

    core.notify(observed);

    try testing.expect(!observer.run);

    try core.observe(observed, TestObserver.callback, &observer.observer);
    core.observers.unsubscribe(observed.any.id, observer.observer.id);

    index = 1;

    observed.set_index(index);
    observed.inc();

    core.notify(observed);

    core.flush();

    try testing.expect(!observer.run);

    observed.drop();

    core.flush();
}
