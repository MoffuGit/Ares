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

    pub fn reserveMany(self: @This(), buffer: []EntityId, io: Io) !void {
        try self.rwlock.lock(io);
        defer self.rwlock.unlock(io);

        var idx: u64 = 0;
        while (idx < buffer.len) : (idx += 1) {
            buffer[idx] = try self.refs.put(.init(1));
        }
    }
};

pub const AnyEntity = struct {
    refs: *EntityRefs,
    type_id: TypeId,
    id: EntityId,

    pub fn init(refs: *EntityRefs, id: EntityId, type_id: TypeId) @This() {
        return .{ .refs = refs, .id = id, .type_id = type_id };
    }

    pub fn clone(self: @This(), io: Io) !@This() {
        const refs = self.refs;
        try refs.rwlock.lockShared(io);
        defer refs.rwlock.unlockShared(io);

        const ref = refs.refs.get(self.id) orelse @panic("Cloning a released AnyEntity");
        const previous = ref.fetchAdd(1, .acq_rel);
        assert(previous > 0);
        return self;
    }

    pub fn drop(self: @This(), gpa: Allocator, io: Io) !void {
        const refs = self.refs;
        try refs.rwlock.lockShared(io);
        defer refs.rwlock.unlockShared(io);

        const ref = refs.refs.get(self.id) orelse @panic("Dropping a released AnyEntity");
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

        pub fn init(refs: *EntityRefs, id: EntityId) @This() {
            return .{ .any = .init(refs, id, TypeInfo.init(T)) };
        }

        pub fn clone(self: @This(), io: Io) !@This() {
            return .{ .any = try self.any.clone(io) };
        }

        pub fn drop(self: @This(), gpa: Allocator, io: Io) !void {
            try self.any.drop(gpa, io);
        }

        pub fn get(self: @This(), store: *EntityStore) *const T {
            return store.get(T, self.any);
        }

        pub fn getMut(self: @This(), store: *EntityStore) *T {
            return store.getMut(T, self.any);
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

    pub fn reserve(self: *@This(), io: Io) EntityId {
        return self.refs.reserve(io) catch @panic("Entities Overflow");
    }

    pub fn insert(self: *@This(), key: EntityId, comptime T: type, entity: *T) Entity(T) {
        _ = self.entities.put(key, entity) catch @panic("Entities Overflow");
        return .init(&self.refs, key);
    }

    pub fn get(self: *@This(), comptime T: type, entity: AnyEntity) *const T {
        assert(entity.type_id == TypeInfo.init(T));

        const ptr = self.entities.get(entity.id) orelse @panic("Reading non existing entity");
        return @ptrCast(@alignCast(ptr.*));
    }

    pub fn getMut(self: *@This(), comptime T: type, entity: AnyEntity) *T {
        assert(entity.type_id == TypeInfo.init(T));

        const ptr = self.entities.getMut(entity.id) orelse @panic("Reading non existing entity");
        return @ptrCast(@alignCast(ptr.*));
    }

    pub fn lockRefs(self: *@This(), io: Io) !void {
        try self.refs.rwlock.lock(io);
    }

    pub fn unlockRefs(self: *@This(), io: Io) void {
        self.refs.rwlock.unlock(io);
    }

    pub fn popDrop(self: *@This()) ?struct { *anyopaque, EntityId, TypeId } {
        const entity = self.refs.dropped_entities.pop() orelse return null;

        const ptr = self.entities.remove(entity.id) orelse @panic("Dropping non existing entity");
        self.refs.refs.remove(entity.id);

        return .{ ptr, entity.id, entity.type_id };
    }

    pub fn collect(self: *@This(), gpa: Allocator, io: Io) !std.ArrayList(struct { *anyopaque, EntityId, TypeId }) {
        var entities: std.ArrayList(struct { *anyopaque, EntityId, TypeId }) = .empty;
        errdefer entities.deinit(gpa);

        const refs = &self.refs;
        try refs.rwlock.lock(io);
        defer refs.rwlock.unlock(io);

        while (self.refs.dropped_entities.pop()) |entity| {
            const ptr = self.entities.remove(entity.id) orelse continue;
            self.refs.refs.remove(entity.id);
            try entities.append(gpa, .{ ptr, entity.id, entity.type_id });
        }

        return entities;
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

    const id = store.reserve(io);
    const entity = store.insert(id, A, ptr);

    try std.testing.expectEqual(ptr, entity.get(&store));
    try std.testing.expectEqual(@as(u32, 42), entity.get(&store).value);
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

    const id = store.reserve(io);
    const entity = store.insert(id, A, ptr);

    try entity.drop(allocator, io);

    var collected = try store.collect(allocator, io);
    defer collected.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), collected.items.len);
    try std.testing.expectEqual(ptr, @as(*A, @ptrCast(@alignCast(collected.items[0][0]))));
    try std.testing.expect(collected.items[0][1].eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), collected.items[0][2]);
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

    const id = store.reserve(io);
    const entity = store.insert(id, A, ptr);
    const clone = try entity.clone(io);
    const any_clone = try entity.any.clone(io);

    try entity.drop(allocator, io);
    try clone.drop(allocator, io);
    var empty_collected = try store.collect(allocator, io);
    defer empty_collected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty_collected.items.len);

    try any_clone.drop(allocator, io);
    var collected = try store.collect(allocator, io);
    defer collected.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), collected.items.len);
    try std.testing.expectEqual(ptr, @as(*A, @ptrCast(@alignCast(collected.items[0][0]))));
    try std.testing.expect(collected.items[0][1].eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), collected.items[0][2]);
}
