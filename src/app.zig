const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;

const zio = @import("zio");
const Runtime = zio.Runtime;

const ent = @import("entity.zig");
const Entity = ent.Entity;
const EntityStore = ent.EntityStore;
const Workspace = @import("workspace.zig");

pub const App = @This();

foreground_runtime: *Runtime,
background_runtime: *Runtime,

entity_store: EntityStore,
peding_updates: u16,
flushing: bool,

gpa: Allocator,

pub fn init(self: *App, gpa: Allocator) !void {
    const foreground_runtime = try Runtime.init(gpa, .{
        .executors = .auto,
        .enable_main_executor = false,
    });
    errdefer foreground_runtime.deinit();

    const background_runtime = try Runtime.init(gpa, .{
        .executors = .exact(1),
        .enable_main_executor = true,
        .enable_task_migration = false,
    });
    errdefer background_runtime.deinit();

    self.* = .{
        .entity_store = undefined,
        .foreground_runtime = foreground_runtime,
        .background_runtime = background_runtime,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
    };

    try self.entity_store.init(gpa);
}

pub fn new(self: *App, io: Io, comptime T: type, function: anytype) !Entity(T) {
    const TypeErased = struct {
        fn new(app: *App, _io: Io) !Entity(T) {
            const entity = try app.gpa.create(T);
            errdefer app.gpa.destroy(entity);

            try @call(.auto, function, .{entity});

            const id = app.entity_store.reserve(_io);
            return app.entity_store.insert(id, T, entity);
        }
    };

    return try self.update(io, TypeErased.new, .{ self, io });
}

pub fn update_entity(self: *App, io: Io, comptime T: type, entity: *Entity(T), function: anytype, args: anytype) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
    const Args = @TypeOf(args);

    const TypeErased = struct {
        fn new(app: *App, _entity: *Entity(T), _args: Args) !@typeInfo(@TypeOf(function)).@"fn".return_type.? {
            const ptr = app.entity_store.entities.remove(_entity.any.id) orelse @panic("Updating non existing Entity");
            defer _ = app.entity_store.entities.put(_entity.any.id, ptr);

            return @call(.auto, function, .{@as(*T, @ptrCast(@alignCast(ptr)))} ++ _args);
        }
    };

    return try self.update(io, TypeErased.new, .{ self, entity, args });
}
//
// pub fn read_entity(self: *App, comptime T: type, entity: Entity(T), function: anytype) !void {}

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
}

pub fn destroy_dropped_entities(self: *App, io: Io) !void {
    try self.entity_store.lockRefs(io);
    defer self.entity_store.unlockRefs(io);

    while (self.entity_store.popDrop()) |drop| {
        drop.@"2".destroyOpaque(self.gpa, drop.@"0");
    }
}

pub fn deinit(self: *App) void {
    self.entity_store.deinit(self.gpa);
    self.background_runtime.deinit();
    self.foreground_runtime.deinit();
}

test "app creates and drops many struct entities" {
    const testing = std.testing;
    const allocator = testing.allocator;
    const entity_count = 32;

    const TestStruct = struct {
        index: usize,

        pub fn init(self: *@This()) !void {
            self.* = .{ .index = 0 };
        }

        pub fn set_index(self: *@This(), index: usize) void {
            self.index = index;
        }
    };

    const TestEntity = Entity(TestStruct);

    var app: App = undefined;
    try app.init(allocator);
    defer app.deinit();

    const io = app.foreground_runtime.io();

    var entities: [entity_count]TestEntity = undefined;
    for (&entities, 0..) |*entity, index| {
        entity.* = try TestEntity.new(&app, io);

        try entity.update(&app, io, TestStruct.set_index, .{index});
        try testing.expectEqual(index, entity.get(&app.entity_store).index);
    }

    for (entities) |entity| {
        try entity.drop(allocator, io);
    }

    try app.flush(io);
}
