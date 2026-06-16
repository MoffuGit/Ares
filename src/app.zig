const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;
const datastruct = @import("datastruct.zig");

const btree = datastruct.btree;
const ent = @import("entity.zig");
const Entity = ent.Entity;
const EntityId = ent.EntityId;
const EntityStore = ent.EntityStore;
const Subscriptions = @import("subscription.zig").Subscriptions;
const Workspace = @import("workspace.zig");

pub const App = @This();

gpa: Allocator,
entity_store: EntityStore,
observers: Observers,
peding_updates: u16,

notifications: btree.BPlusSet(EntityId, ent.entityOrder),

flushing: bool,

pub fn init(self: *App, gpa: Allocator) !void {
    self.* = .{
        .notifications = undefined,
        .entity_store = undefined,
        .observers = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
    };

    try self.entity_store.init(gpa);
    errdefer self.entity_store.deinit(gpa);

    try self.observers.init(gpa);
    errdefer self.observers.deinit(gpa);

    try self.notifications.init(gpa);
    errdefer self.notifications.deinit(gpa);
}

pub fn deinit(self: *App) void {
    self.notifications.deinit(self.gpa);
    self.observers.deinit(self.gpa);
    self.entity_store.deinit(self.gpa);
}

pub fn new(self: *App, io: Io, comptime T: type, function: anytype, args: anytype) !Entity(T) {
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _io: Io, _args: Args) !Entity(T) {
            const entity = try app.gpa.create(T);
            errdefer app.gpa.destroy(entity);

            try @call(.auto, function, .{entity} ++ _args);

            const id = app.entity_store.reserve(_io);
            return app.entity_store.insert(id, T, entity);
        }
    };

    return try self.update(io, TypeErased.new, .{ self, io, args });
}

pub fn update_entity(self: *App, io: Io, comptime T: type, entity: Entity(T), function: anytype, args: anytype) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _entity: Entity(T), _args: Args) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
            const ptr = app.entity_store.remove(T, _entity);
            defer _ = app.entity_store.insert(_entity.any.id, T, ptr);

            return @call(.auto, function, .{ptr} ++ _args);
        }
    };

    return try self.update(io, TypeErased.new, .{ self, entity, args });
}

pub fn read_entity(self: *App, io: Io, comptime T: type, entity: Entity(T), function: anytype, args: anytype) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _entity: Entity(T), _args: Args) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
            const ptr = app.entity_store.get(T, _entity);

            return @call(.auto, function, .{ptr} ++ _args);
        }
    };

    return try self.update(io, TypeErased.new, .{ self, entity, args });
}

pub fn notify(self: *App, comptime T: type, entity: Entity(T)) !void {
    _ = try self.notifications.insert(self.gpa, entity.id());
}

pub fn update(self: *App, io: Io, function: anytype, args: std.meta.ArgsTuple(@TypeOf(function))) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
    self.start_update();
    defer self.end_update(io);

    return @call(.auto, function, args);
}

pub fn start_update(self: *App) void {
    self.peding_updates += 1;
}

pub fn end_update(self: *App, io: Io) void {
    if (!self.flushing and self.peding_updates == 1) {
        self.flushing = true;
        self.flush(io) catch @panic("Failed to flush app");
        self.flushing = false;
    }
    self.peding_updates += 1;
}

pub fn flush(self: *App, io: Io) !void {
    try self.destroy_dropped_entities(io);
    try self.flush_notifications();
}

pub fn flush_notifications(self: *App) !void {
    var iter = self.notifications.iter();
    while (iter.next()) |id| {
        self.observers.notify(id, .{self}, self.gpa);
    }

    try self.notifications.clear(self.gpa);
}

pub fn destroy_dropped_entities(self: *App, io: Io) !void {
    try self.entity_store.lockRefs(io);
    defer self.entity_store.unlockRefs(io);

    while (self.entity_store.popDrop()) |drop| {
        drop.@"2".destroy(self.gpa, drop.@"0");
    }
}

pub const Observers = Subscriptions(EntityId, &.{*App}, ent.entityOrder);

const Observer = struct {
    any: ent.AnyEntity,
    io: Io,
    userdata: ?*anyopaque,
    callback: *const fn (*App, Observer) bool,
};

pub fn observe(
    self: *App,
    comptime T: type,
    entity: Entity(T),
    context: anytype,
    comptime callback: *const fn (*App, Entity(T), @TypeOf(context)) void,
    io: Io,
) !Observers.Subscription {
    const Context = @TypeOf(context);

    const TypeErased = struct {
        fn _callback(app: *App, observer: Observer) bool {
            return observer.callback(app, observer);
        }

        fn _observe(app: *App, observer: Observer) bool {
            const _entity = observer.any.into(T, observer.io) orelse return false;
            defer _entity.drop(app.gpa, observer.io) catch {};
            const _context: Context = @ptrCast(@alignCast(observer.userdata));
            callback(app, _entity, _context);

            return true;
        }
    };

    return try self.observers.insert(
        entity.id(),
        TypeErased._callback,
        &.{Observer},
        .{
            .{
                .any = entity.any,
                .userdata = @ptrCast(context),
                .callback = TypeErased._observe,
                .io = io,
            },
        },
        self.gpa,
    );
}

test "creates/drops entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;
    const entity_count = 32;

    const TestStruct = struct {
        index: usize,

        pub fn init(self: *@This()) !void {
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
    try app.init(allocator);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities, 0..) |*entity, index| {
        entity.* = try TestEntity.new(&app, io, .{});

        try entity.update(&app, io, TestStruct.set_index, .{index});
        try entity.update(&app, io, TestStruct.inc, .{});
        try testing.expectEqual(index + 1, entity.read(&app, io, TestStruct.get_index, .{}));
    }

    for (entities) |entity| {
        try entity.drop(allocator, io);
    }

    try app.flush(io);
}

test "Observe entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const io = testing.io;
    const entity_count = 32;

    const TestStruct = struct {
        index: usize,

        pub fn init(self: *@This()) !void {
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
    try app.init(allocator);
    defer app.deinit();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities) |*entity| {
        entity.* = try TestEntity.new(&app, io, .{});
    }

    const observed = entities[0];

    var context: bool = false;

    const Observed = struct {
        pub fn callback(_: *App, _: TestEntity, _context: *bool) void {
            _context.* = true;
        }
    };

    var index: usize = 0;

    try observed.update(&app, io, TestStruct.set_index, .{index});
    try observed.update(&app, io, TestStruct.inc, .{});
    try testing.expectEqual(index + 1, observed.read(&app, io, TestStruct.get_index, .{}));
    try observed.notify(&app);

    try testing.expect(!context);

    const sub = try app.observe(TestStruct, observed, &context, Observed.callback, io);
    sub.enable();

    index = 1;

    try observed.update(&app, io, TestStruct.set_index, .{index});
    try observed.update(&app, io, TestStruct.inc, .{});
    try testing.expectEqual(index + 1, observed.read(&app, io, TestStruct.get_index, .{}));
    try observed.notify(&app);

    try app.flush(io);

    try testing.expect(context);

    for (entities) |entity| {
        try entity.drop(allocator, io);
    }

    try app.flush(io);
}
