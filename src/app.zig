const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const assert = std.debug.assert;

const ent = @import("entity.zig");
const Entity = ent.Entity;
const EntityStore = ent.EntityStore;
const Workspace = @import("workspace.zig");
const Runtime = @import("runtime.zig");

pub const App = @This();

runtime: Runtime,
entity_store: EntityStore,
peding_updates: u16,
flushing: bool,

gpa: Allocator,

pub fn init(self: *App, gpa: Allocator) !void {
    self.* = .{
        .runtime = undefined,
        .entity_store = undefined,
        .peding_updates = 0,
        .flushing = false,
        .gpa = gpa,
    };

    try self.runtime.init(gpa);
    errdefer self.runtime.deinit();

    try self.entity_store.init(gpa);
    errdefer self.entity_store.deinit(gpa);
}

pub fn deinit(self: *App) void {
    self.entity_store.deinit(self.gpa);
    self.runtime.deinit();
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

    const io = app.runtime.foreground.io();

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
