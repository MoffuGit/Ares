const std = @import("std");
const atomic = std.atomic;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const App = @import("app.zig");
const UpdateFrame = App.UpdateFrame;
const datastruct = @import("datastruct.zig");
const slotmap = datastruct.slotmap;
pub const EntityId = slotmap.Key;
const typeId = @import("typeId.zig");
const TypeId = typeId.TypeId;
const TypeInfo = typeId.TypeInfo;

pub fn entityOrder(a: EntityId, b: EntityId) std.math.Order {
    const index_order = std.math.order(a.index, b.index);
    if (index_order != .eq) return index_order;

    return std.math.order(@intFromEnum(a.generation), @intFromEnum(b.generation));
}

pub const AnyEntity = struct {
    store: *EntityStore,
    type_id: TypeId,
    id: EntityId,

    pub fn init(store: *EntityStore, id: EntityId, type_id: TypeId) @This() {
        return .{ .store = store, .id = id, .type_id = type_id };
    }

    pub fn get(self: *const @This()) *anyopaque {
        return self.store.get(self.id);
    }

    pub fn tryGet(self: *const @This()) ?*anyopaque {
        return self.store.tryGet(self.id);
    }

    pub fn drop(self: @This()) void {
        if (self.store.entities.get(self.id)) |ptr| {
            self.type_id.drop(ptr.*);
            self.store.dropped.appendAssumeCapacity(self);
        }
    }
};

pub fn Entity(comptime T: type) type {
    return struct {
        pub const EntityType = T;

        any: AnyEntity,

        pub fn new(app: *App, args: anytype) !@This() {
            return try app.new(T, T.init, args);
        }

        pub fn from(any: AnyEntity) ?@This() {
            assert(any.type_id == TypeInfo.init(T));
            if (!any.store.entities.contains(any.id)) return null;

            return .{
                .any = any,
            };
        }

        pub fn update(self: @This(), app: *App) struct { *T, UpdateFrame } {
            const frame = app.updateFrame(self.any);
            const ptr = self.any.get();

            return .{ @ptrCast(@alignCast(ptr)), frame };
        }

        pub fn read(self: @This()) *const T {
            const ptr = self.any.get();
            return @ptrCast(@alignCast(ptr));
        }

        pub fn tryRead(self: @This()) ?*const T {
            const ptr = self.any.tryGet() orelse return null;
            return @ptrCast(@alignCast(ptr));
        }

        pub fn notify(self: @This(), app: *App) void {
            app.notify(self);
        }

        pub fn nevent(self: @This(), app: *App, comptime E: type) !*E {
            return try app.nevent(self, E);
        }

        pub fn init(store: *EntityStore, new_id: EntityId) @This() {
            return .{ .any = .init(store, new_id, TypeInfo.init(T)) };
        }

        pub fn id(self: *const @This()) EntityId {
            return self.any.id;
        }

        pub fn drop(self: @This()) void {
            self.any.drop();
        }

        pub fn ctx(self: *const @This(), app: *App) App.Context(T) {
            return .new(app, self.*);
        }
    };
}

pub const EntityStore = struct {
    const Entities = slotmap.SlotMap(*anyopaque);
    const Updates = slotmap.SecondaryMap(bool);

    entities: Entities,
    updates: Updates,
    dropped: std.ArrayList(AnyEntity),

    pub fn init(self: *@This(), arena: Allocator, capacity: usize) !void {
        var entities = try Entities.init(arena, capacity);
        errdefer entities.deinit(arena);

        var updates = try Updates.init(arena, capacity);
        errdefer updates.deinit(arena);

        self.* = .{
            .entities = entities,
            .updates = updates,
            .dropped = try .initCapacity(arena, capacity),
        };
    }

    pub fn insert(self: *@This(), ptr: *anyopaque) EntityId {
        return self.entities.put(ptr) catch @panic("Entities Overflow");
    }

    pub fn get(self: *@This(), id: EntityId) *anyopaque {
        const ptr = self.entities.get(id) orelse @panic("Reading non existing entity");
        return ptr.*;
    }

    pub fn tryGet(self: *@This(), id: EntityId) ?*anyopaque {
        const ptr = self.entities.get(id) orelse return null;
        return ptr.*;
    }

    pub fn startUpdate(self: *@This(), id: EntityId) void {
        if (self.updates.put(id, true) orelse false) @panic("Double Started Update");
    }

    pub fn endUpdate(self: *@This(), id: EntityId) void {
        if (!(self.updates.put(id, false) orelse true)) @panic("Double Ended Update");
    }

    pub fn popDrop(self: *@This()) ?struct { *anyopaque, EntityId, TypeId } {
        const entity = self.dropped.pop() orelse return null;

        const ptr = self.entities.remove(entity.id) orelse @panic("Dropping non existing entity");
        _ = self.updates.remove(entity.id);

        return .{ ptr, entity.id, entity.type_id };
    }

    pub fn recycle(self: *@This(), id: EntityId) void {
        self.entities.recycle(id);
    }

    pub fn collect(self: *@This(), gpa: Allocator) !std.ArrayList(struct { *anyopaque, EntityId, TypeId }) {
        var entities: std.ArrayList(struct { *anyopaque, EntityId, TypeId }) = .empty;
        errdefer entities.deinit(gpa);

        while (self.dropped.pop()) |entity| {
            const ptr = self.entities.remove(entity.id) orelse continue;
            _ = self.updates.remove(entity.id);
            try entities.append(gpa, .{ ptr, entity.id, entity.type_id });
        }

        return entities;
    }
};

test "entity store returns inserted data and rejects wrong type" {
    const allocator = std.testing.allocator;
    var alloc = std.heap.ArenaAllocator.init(allocator);
    defer alloc.deinit();

    const arena = alloc.allocator();

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(arena, 10);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 42 };

    const id = store.insert(ptr);
    const entity: Entity(A) = .init(&store, id);

    try std.testing.expectEqualDeep(@intFromPtr(ptr), @intFromPtr(store.get(entity.id())));
    try std.testing.expectEqual(@as(u32, 42), entity.read().value);
}

test "closing entity records id and type when ref count reaches zero" {
    const allocator = std.testing.allocator;
    var alloc = std.heap.ArenaAllocator.init(allocator);
    defer alloc.deinit();

    const arena = alloc.allocator();

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(arena, 10);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 7 };

    const id = store.insert(ptr);
    const entity: Entity(A) = .init(&store, id);

    entity.drop();

    var collected = try store.collect(allocator);
    defer collected.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), collected.items.len);
    try std.testing.expectEqual(ptr, @as(*A, @ptrCast(@alignCast(collected.items[0][0]))));
    try std.testing.expect(collected.items[0][1].eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), collected.items[0][2]);
}

test "dropping arena-backed entity calls optional deinit" {
    const allocator = std.testing.allocator;

    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const A = struct {
        deinit_called: *bool,

        pub fn deinit(self: *@This()) void {
            self.deinit_called.* = true;
        }
    };

    var store: EntityStore = undefined;
    try store.init(arena.allocator(), 10);

    var deinit_called = false;
    const ptr = try arena.allocator().create(A);
    ptr.* = .{ .deinit_called = &deinit_called };

    const id = store.insert(ptr);
    const entity: Entity(A) = .init(&store, id);

    entity.drop();

    const drop = store.popDrop().?;
    try std.testing.expectEqual(ptr, @as(*A, @ptrCast(@alignCast(drop.@"0"))));
    try std.testing.expect(drop.@"1".eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), drop.@"2");

    drop.@"2".deinit(drop.@"0");
    try std.testing.expect(deinit_called);
}

test "destroyed entities recycle ids" {
    const allocator = std.testing.allocator;
    var alloc = std.heap.ArenaAllocator.init(allocator);
    defer alloc.deinit();

    const arena = alloc.allocator();

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(arena, 10);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 1 };

    const id = store.insert(ptr);
    const entity: Entity(A) = .init(&store, id);

    entity.drop();
    const drop = store.popDrop().?;
    try std.testing.expect(drop.@"1".eql(id));
    store.recycle(drop.@"1");

    const recycled = store.insert(ptr);
    try std.testing.expectEqual(id.index, recycled.index);
}
