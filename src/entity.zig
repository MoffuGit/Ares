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

    pub fn into(self: @This(), T: type) ?Entity(T) {
        if (!self.store.entities.contains(self.id)) return null;

        return .{
            .any = self,
        };
    }

    pub fn drop(self: @This()) void {
        self.store.dropped.appendAssumeCapacity(self);
    }
};

pub fn Entity(comptime T: type) type {
    return struct {
        pub const EntityType = T;

        any: AnyEntity,

        pub fn new(app: *App, args: anytype) !@This() {
            return try app.new(T, T.init, args);
        }

        pub fn update(self: @This(), app: *App) struct { *T, UpdateFrame } {
            return app.update_frame(T, self);
        }

        pub fn read(self: @This(), app: *App) *const T {
            return app.read_entity(T, self);
        }

        pub fn notify(self: @This(), app: *App) void {
            app.notify(self);
        }

        pub fn init(store: *EntityStore, new_id: EntityId) @This() {
            return .{ .any = .init(store, new_id, TypeInfo.init(T)) };
        }

        pub fn clone(self: @This()) @This() {
            return .{ .any = self.any.clone() };
        }

        pub fn id(self: *const @This()) EntityId {
            return self.any.id;
        }

        pub fn drop(self: @This()) void {
            self.any.drop();
        }
    };
}

pub const EntityStore = struct {
    const Entities = slotmap.SlotMap(*anyopaque);
    const Updates = slotmap.SecondaryMap(bool);

    entities: Entities,
    updates: Updates,
    dropped: std.ArrayList(AnyEntity),

    pub fn init(self: *@This(), fixed: Allocator, capacity: usize) !void {
        var entities = try Entities.init(fixed, capacity);
        errdefer entities.deinit(fixed);

        var updates = try Updates.init(fixed, capacity);
        errdefer updates.deinit(fixed);

        self.* = .{
            .entities = entities,
            .updates = updates,
            .dropped = try .initCapacity(fixed, capacity),
        };
    }

    pub fn deinit(self: *@This(), fixed: Allocator) void {
        self.entities.deinit(fixed);
        self.updates.deinit(fixed);
        self.dropped.deinit(fixed);
    }

    pub fn insert(self: *@This(), ptr: *anyopaque) EntityId {
        return self.entities.put(ptr) catch @panic("Entities Overflow");
    }

    pub fn get(self: *@This(), comptime T: type, entity: Entity(T)) *T {
        const ptr = self.entities.get(entity.id()) orelse @panic("Reading non existing entity");
        return @ptrCast(@alignCast(ptr.*));
    }

    pub fn start_update(self: *@This(), id: EntityId) void {
        if (self.updates.put(id, true) orelse false) @panic("Double Started Update");
    }

    pub fn end_update(self: *@This(), id: EntityId) void {
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

    pub fn collect(self: *@This(), fixed: Allocator) !std.ArrayList(struct { *anyopaque, EntityId, TypeId }) {
        var entities: std.ArrayList(struct { *anyopaque, EntityId, TypeId }) = .empty;
        errdefer entities.deinit(fixed);

        while (self.dropped.pop()) |entity| {
            const ptr = self.entities.remove(entity.id) orelse continue;
            _ = self.updates.remove(entity.id);
            try entities.append(fixed, .{ ptr, entity.id, entity.type_id });
        }

        return entities;
    }
};

test "entity store returns inserted data and rejects wrong type" {
    const allocator = std.testing.allocator;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator, 10);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 42 };

    const id = store.insert(ptr);
    const entity: Entity(A) = .init(&store, id);

    try std.testing.expectEqual(ptr, store.get(A, entity));
    try std.testing.expectEqual(@as(u32, 42), store.get(A, entity).value);
}

test "closing entity records id and type when ref count reaches zero" {
    const allocator = std.testing.allocator;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator, 10);
    defer store.deinit(allocator);

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
    try store.init(allocator, 10);
    defer store.deinit(allocator);

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

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator, 10);
    defer store.deinit(allocator);

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
