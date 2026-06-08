const std = @import("std");
const atomic = std.atomic;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const datastruct = @import("datastruct.zig");
const slotmap = datastruct.slotmap;
const typeId = @import("typeId.zig");
const TypeId = typeId.TypeId;
const TypeInfo = typeId.TypeInfo;

pub const EntityId = slotmap.Key;

pub const EntityRefs = struct {
    const Refs = slotmap.SlotMap(atomic.Value(u8));

    refs: Refs,
    dropped_entities: std.ArrayList(AnyEntity),
    rwlock: Io.RwLock,

    pub fn init(gpa: Allocator, capacity: usize) !@This() {
        return .{
            .refs = try Refs.init(gpa, capacity),
            .dropped_entities = .empty,
            .rwlock = .init,
        };
    }

    pub fn deinit(self: *@This(), gpa: Allocator) void {
        assert(self.dropped_entities.items.len == 0);
        self.refs.deinit(gpa);
        self.dropped_entities.deinit(gpa);
    }

    pub fn reserve(self: *@This(), io: Io) !EntityId {
        try self.rwlock.lock(io);
        defer self.rwlock.unlock(io);

        return try self.refs.put(.init(1));
    }
};

pub const AnyEntity = struct {
    refs: *EntityRefs,
    entity_id: EntityId,
    type_id: TypeId,

    pub fn init(refs: *EntityRefs, entity_id: EntityId, type_id: TypeId) @This() {
        return .{ .refs = refs, .entity_id = entity_id, .type_id = type_id };
    }

    pub fn clone(self: @This()) @This() {
        const ref = self.refs.refs.get(self.entity_id) orelse return self;
        const previous = ref.fetchAdd(1, .acq_rel);
        assert(previous > 0);
        return self;
    }

    pub fn close(self: @This(), gpa: Allocator) !void {
        const ref = self.refs.refs.get(self.entity_id) orelse return;
        const previous = ref.fetchSub(1, .acq_rel);
        assert(previous > 0);
        if (previous == 1) {
            try self.refs.dropped_entities.append(gpa, self);
        }
    }
};

pub fn Entity(comptime T: type) type {
    return struct {
        any: AnyEntity,

        pub fn init(refs: *EntityRefs, entity_id: EntityId) @This() {
            return .{ .any = .init(refs, entity_id, TypeInfo.init(T)) };
        }

        pub fn clone(self: @This()) @This() {
            return .{ .any = self.any.clone() };
        }

        pub fn close(self: @This(), gpa: Allocator) !void {
            try self.any.close(gpa);
        }

        pub fn get(self: @This(), store: *EntityStore) ?*T {
            return store.get(T, self.any);
        }
    };
}

pub const EntityStore = struct {
    const Entities = slotmap.SecondaryMap(*anyopaque);

    entities: Entities,
    refs: EntityRefs,

    pub fn init(self: *@This(), gpa: Allocator) !void {
        var refs = try EntityRefs.init(gpa, 100);
        errdefer refs.deinit(gpa);

        const entities = try Entities.init(gpa, refs.refs.capacity);
        errdefer entities.deinit(gpa);

        self.* = .{
            .entities = entities,
            .refs = refs,
        };
    }

    pub fn deinit(self: *@This(), gpa: Allocator) void {
        self.entities.deinit(gpa);
        self.refs.deinit(gpa);
    }

    pub fn reserve(self: *@This(), io: Io) !EntityId {
        return try self.refs.reserve(io);
    }

    pub fn insert(self: *@This(), key: EntityId, comptime T: type, entity: *T) !Entity(T) {
        _ = try self.entities.put(key, entity);
        return .init(&self.refs, key);
    }

    pub fn get(self: *@This(), comptime T: type, entity: AnyEntity) ?*T {
        assert(entity.type_id == TypeInfo.init(T));

        const ptr = self.entities.get(entity.entity_id) orelse return null;
        return @ptrCast(@alignCast(ptr.*));
    }

    pub fn collectDropped(self: *@This(), gpa: Allocator) void {
        while (self.refs.dropped_entities.pop()) |entity| {
            const ptr = self.entities.remove(entity.entity_id) orelse continue;
            entity.type_id.destroyOpaque(gpa, ptr);
            self.refs.refs.remove(entity.entity_id);
        }
    }
};

test "entity store returns inserted data and rejects wrong type" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 42 };

    const id = try store.reserve(io);
    const entity = try store.insert(id, A, ptr);

    try std.testing.expectEqual(ptr, entity.get(&store).?);
    try std.testing.expectEqual(@as(u32, 42), entity.get(&store).?.value);
}

test "closing entity records id and type when ref count reaches zero" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 7 };

    const id = try store.reserve(io);
    const entity = try store.insert(id, A, ptr);

    try entity.close(allocator);

    try std.testing.expectEqual(@as(usize, 1), store.refs.dropped_entities.items.len);
    try std.testing.expect(store.refs.dropped_entities.items[0].entity_id.eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), store.refs.dropped_entities.items[0].type_id);

    _ = store.refs.dropped_entities.pop();
}

test "cloning entity increments ref count" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 9 };

    const id = try store.reserve(io);
    const entity = try store.insert(id, A, ptr);
    const clone = entity.clone();
    const any_clone = entity.any.clone();

    try entity.close(allocator);
    try clone.close(allocator);
    try std.testing.expectEqual(@as(usize, 0), store.refs.dropped_entities.items.len);

    try any_clone.close(allocator);
    try std.testing.expectEqual(@as(usize, 1), store.refs.dropped_entities.items.len);
    try std.testing.expect(store.refs.dropped_entities.items[0].entity_id.eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), store.refs.dropped_entities.items[0].type_id);

    _ = store.refs.dropped_entities.pop();
}

test "collect dropped entities destroys pointers" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    ptr.* = .{ .value = 11 };

    const id = try store.reserve(io);
    const entity = try store.insert(id, A, ptr);

    try entity.close(allocator);
    store.collectDropped(allocator);

    try std.testing.expectEqual(@as(usize, 0), store.refs.dropped_entities.items.len);
    try std.testing.expectEqual(@as(?*A, null), entity.get(&store));
}
