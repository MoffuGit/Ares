//This App and many parts/ideas of it came from gpui (https://github.com/zed-industries/zed/tree/main/crates/gpui)
//LICENSE: [ZED]

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;

const datastruct = @import("datastruct.zig");
const btree = datastruct.btree;
const ent = @import("entity.zig");
pub const Entity = ent.Entity;
const AnyEntity = ent.AnyEntity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const executor = @import("executor.zig");
const Subscriptions = @import("subscription.zig").Subscriptions;

pub const App = @This();

gpa: Allocator,
io: Io,
entity_store: EntityStore,
observers: Observers,
peding_updates: u16,

foreground_executor: executor.ForegroundExecutor,
background_executor: executor.BackgroundExecutor,

notifications: btree.BPlusSet(EntityId, ent.entityOrder),

flushing: bool,

pub fn init(self: *App, gpa: Allocator, io: Io) !void {
    self.* = .{
        .notifications = undefined,
        .entity_store = undefined,
        .observers = undefined,
        .foreground_executor = undefined,
        .background_executor = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
        .io = io,
    };

    try self.foreground_executor.init(self.gpa, io);
    errdefer self.foreground_executor.deinit();

    try self.background_executor.init(gpa, io);
    errdefer self.background_executor.deinit(gpa, io);

    try self.entity_store.init(gpa, io);
    errdefer self.entity_store.deinit(gpa);

    try self.observers.init(gpa);
    errdefer self.observers.deinit(gpa);

    try self.notifications.init(gpa);
    errdefer self.notifications.deinit(gpa);
}

pub fn deinit(self: *App) void {
    self.background_executor.deinit(self.gpa, self.io);
    self.foreground_executor.deinit();
    self.notifications.deinit(self.gpa);
    self.observers.deinit(self.gpa);
    self.entity_store.deinit(self.gpa);
}

pub fn new(self: *App, comptime T: type, function: anytype, args: anytype) !Entity(T) {
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _args: Args) !Entity(T) {
            const prt = try app.gpa.create(T);
            errdefer app.gpa.destroy(prt);

            const id = app.entity_store.reserve();
            const entity: Entity(T) = .init(&app.entity_store, id);
            const ctx: Context(T) = .new(app, entity);

            try @call(.auto, function, .{ prt, ctx } ++ _args);

            app.entity_store.insert(id, prt);

            return entity;
        }
    };

    return try self.update(TypeErased.new, .{ self, args });
}

pub fn update_entity(self: *App, entity: anytype, function: anytype, args: anytype) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const T = _Entity.EntityType;
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _entity: Entity(T), _args: Args) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
            const ptr = app.entity_store.remove(T, _entity);
            defer app.entity_store.insert(_entity.any.id, ptr);

            return @call(.auto, function, .{ptr} ++ _args);
        }
    };

    return self.update(TypeErased.new, .{ self, entity, args });
}

pub fn read_entity(self: *App, entity: anytype, function: anytype, args: anytype) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    const T = _Entity.EntityType;
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _entity: Entity(T), _args: Args) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
            const ptr = app.entity_store.get(T, _entity);

            return @call(.auto, function, .{ptr} ++ _args);
        }
    };

    return self.update(TypeErased.new, .{ self, entity, args });
}

pub fn notify(self: *App, entity: anytype) !void {
    const _Entity = @TypeOf(entity);
    if (!@hasDecl(_Entity, "EntityType") or !@hasField(_Entity, "any") or !@hasDecl(_Entity, "id")) {
        @compileError("entity must be an Entity(T)");
    }

    _ = try self.notifications.insert(self.gpa, entity.id());
}

pub fn update(
    self: *App,
    function: anytype,
    args: std.meta.ArgsTuple(@TypeOf(function)),
) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
    self.start_update();
    defer self.end_update();

    return @call(.auto, function, args);
}

pub fn start_update(self: *App) void {
    self.peding_updates += 1;
}

pub fn end_update(self: *App) void {
    if (!self.flushing and self.peding_updates == 1) {
        self.flushing = true;
        self.flush() catch @panic("Failed to flush app");
        self.flushing = false;
    }
    self.peding_updates += 1;
}

pub fn flush(self: *App) !void {
    self.foreground_executor.run();
    try self.destroy_dropped_entities();
    try self.flush_notifications();
}

pub fn flush_notifications(self: *App) !void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notify(id, .{self}, self.gpa);
    }

    try self.notifications.clear(self.gpa);
}

pub fn destroy_dropped_entities(self: *App) !void {
    try self.entity_store.lockRefs();
    defer self.entity_store.unlockRefs();

    while (self.entity_store.popDrop()) |drop| {
        self.observers.remove(drop.@"1", self.gpa);
        drop.@"2".destroy(self.gpa, drop.@"0");
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
        fn _callback(app: *App, observer: AnyEntity, _args: Args) bool {
            const _entity = observer.into(T) orelse return false;
            defer _entity.drop();
            return @call(.auto, function, .{ app, _entity } ++ _args);
        }
        fn enable(sub: Observers.Subscription) executor.Action {
            sub.enable();
            return .disarm;
        }
    };

    const sub = try self.observers.insert(
        entity.id(),
        TypeErased._callback,
        .{ entity.any, args },
        self.gpa,
    );

    const handler = try self.foreground_executor.@"defer"(TypeErased.enable, .{sub});
    handler.detach();

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
                    defer _entity.drop();

                    const ctx: Context(T) = .new(app, _entity);
                    _entity.update(app, function, .{ observed, ctx } ++ _args);

                    return true;
                }
            };

            return try self.app.observe(entity, TypeErased.callback, .{ self.entity.any, args });
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

        pub fn get_index(self: *const @This()) usize {
            return self.index;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(allocator, io);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities, 0..) |*entity, index| {
        entity.* = try TestEntity.new(&app, .{});

        entity.update(&app, TestStruct.set_index, .{index});
        entity.update(&app, TestStruct.inc, .{});
        try testing.expectEqual(index + 1, entity.read(&app, TestStruct.get_index, .{}));
    }

    for (entities) |entity| {
        entity.drop();
    }

    try app.flush();
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

        pub fn get_index(self: *const @This()) usize {
            return self.index;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(allocator, io);
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

    observed.update(&app, TestStruct.set_index, .{index});
    observed.update(&app, TestStruct.inc, .{});
    try testing.expectEqual(index + 1, observed.read(&app, TestStruct.get_index, .{}));
    try observed.notify(&app);

    try testing.expect(!context);

    _ = try app.observe(observed, Observed.callback, .{&context});

    index = 1;

    observed.update(&app, TestStruct.set_index, .{index});
    observed.update(&app, TestStruct.inc, .{});
    try testing.expectEqual(index + 1, observed.read(&app, TestStruct.get_index, .{}));
    try observed.notify(&app);

    try app.flush();

    try testing.expect(context);

    for (entities) |entity| {
        entity.drop();
    }

    try app.flush();
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

        pub fn get_index(self: *const @This()) usize {
            return self.index;
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
            self.last_observed_index = observed.read(ctx.app, Observed.get_index, .{});
        }

        pub fn get_observed_updates(self: *const @This()) usize {
            return self.observed_updates;
        }

        pub fn get_last_observed_index(self: *const @This()) usize {
            return self.last_observed_index;
        }
    };

    var app: App = undefined;
    try app.init(allocator, io);
    defer app.deinit();

    const observer = try Entity(ObserverState).new(&app, .{});
    const observed = try Entity(Observed).new(&app, .{});

    var context = Context(ObserverState).new(&app, observer);
    _ = try context.observe(observed, ObserverState.observe, .{});

    observed.update(&app, Observed.set_index, .{42});
    try observed.notify(&app);
    try app.flush();

    try testing.expectEqual(1, observer.read(&app, ObserverState.get_observed_updates, .{}));
    try testing.expectEqual(42, observer.read(&app, ObserverState.get_last_observed_index, .{}));

    observer.drop();
    observed.drop();
    try app.flush();
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
    try app.init(allocator, io);
    defer app.deinit();

    const observer = try Entity(ObserverState).new(&app, .{});
    const observed = try Entity(Observed).new(&app, .{});

    var context = Context(ObserverState).new(&app, observer);
    _ = try context.observe(observed, ObserverState.observe, .{});

    observer.drop();
    try app.flush();

    try testing.expect(app.observers.subscribers.get(observed.id()) != null);

    try observed.notify(&app);
    try app.flush();

    try testing.expectEqual(null, app.observers.subscribers.get(observed.id()));

    observed.drop();
    try app.flush();
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
    try app.init(allocator, io);
    defer app.deinit();

    const observer = try Entity(ObserverState).new(&app, .{});
    const observed = try Entity(Observed).new(&app, .{});
    const observed_id = observed.id();

    var context = Context(ObserverState).new(&app, observer);
    _ = try context.observe(observed, ObserverState.observe, .{});

    observed.drop();
    try app.flush();

    try testing.expectEqual(null, app.observers.subscribers.get(observed_id));

    observer.drop();
    try app.flush();
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

        pub fn get_index(self: *const @This()) usize {
            return self.index;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(allocator, io);
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

    observed.update(&app, TestStruct.set_index, .{index});
    observed.update(&app, TestStruct.inc, .{});
    try testing.expectEqual(index + 1, observed.read(&app, TestStruct.get_index, .{}));
    try observed.notify(&app);

    try testing.expect(!context);

    const sub = try app.observe(observed, Observed.callback, .{&context});
    try sub.unsubscribe(allocator);

    index = 1;

    observed.update(&app, TestStruct.set_index, .{index});
    observed.update(&app, TestStruct.inc, .{});
    try testing.expectEqual(index + 1, observed.read(&app, TestStruct.get_index, .{}));
    try observed.notify(&app);

    try app.flush();

    try testing.expect(!context);

    for (entities) |entity| {
        entity.drop();
    }

    try app.flush();
}
