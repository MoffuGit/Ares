const std = @import("std");
const atomic = std.atomic;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const Io = std.Io;

const App = @import("app.zig");
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

pub const EntityRefs = struct {
    const Refs = slotmap.SlotMap(atomic.Value(u8));

    refs: Refs,
    gpa: Allocator,
    io: Io,
    dropped_entities: std.ArrayList(AnyEntity),
    rwlock: Io.RwLock,

    pub fn init(gpa: Allocator, io: Io, capacity: usize) !@This() {
        return .{
            .gpa = gpa,
            .io = io,
            .refs = try .init(gpa, capacity),
            .dropped_entities = try .initCapacity(gpa, capacity),
            .rwlock = .init,
        };
    }

    pub fn deinit(self: *@This()) void {
        assert(self.dropped_entities.items.len == 0);
        self.refs.deinit(self.gpa);
        self.dropped_entities.deinit(self.gpa);
    }

    pub fn reserve(self: *@This()) !EntityId {
        try self.rwlock.lock(self.io);
        defer self.rwlock.unlock(self.io);

        return try self.refs.put(.init(1));
    }

    pub fn reserveMany(self: @This(), buffer: []EntityId) !void {
        try self.rwlock.lock(self.io);
        defer self.rwlock.unlock(self.io);

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

    pub fn into(self: @This(), T: type) ?Entity(T) {
        const refs = self.refs;
        refs.rwlock.lockSharedUncancelable(refs.io);
        defer refs.rwlock.unlockShared(refs.io);

        const ref = refs.refs.get(self.id) orelse return null;
        const previous = ref.fetchAdd(1, .acq_rel);
        assert(previous > 0);
        return .{
            .any = self,
        };
    }

    pub fn clone(self: @This()) @This() {
        const refs = self.refs;
        refs.rwlock.lockSharedUncancelable(refs.io);
        defer refs.rwlock.unlockShared(refs.io);

        const ref = refs.refs.get(self.id) orelse @panic("Cloning a released AnyEntity");
        const previous = ref.fetchAdd(1, .acq_rel);
        assert(previous > 0);
        return self;
    }

    pub fn drop(self: @This()) void {
        const refs = self.refs;
        refs.rwlock.lockSharedUncancelable(refs.io);
        defer refs.rwlock.unlockShared(refs.io);

        const ref = refs.refs.get(self.id) orelse @panic("Dropping a released AnyEntity");
        const previous = ref.fetchSub(1, .acq_rel);
        assert(previous > 0);
        if (previous == 1) {
            self.refs.dropped_entities.appendAssumeCapacity(self);
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

        pub fn update(self: @This(), app: *App, function: anytype, args: anytype) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
            return app.update_entity(self, function, args);
        }

        pub fn read(self: @This(), app: *App, function: anytype, args: anytype) @typeInfo(@TypeOf(function)).@"fn".return_type.? {
            return app.read_entity(self, function, args);
        }

        pub fn notify(self: @This(), app: *App) !void {
            try app.notify(self);
        }

        pub fn init(store: *EntityStore, new_id: EntityId) @This() {
            return .{ .any = .init(&store.refs, new_id, TypeInfo.init(T)) };
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
    const Entities = slotmap.SecondaryMap(*anyopaque);

    entities: Entities,
    refs: EntityRefs,

    pub fn init(self: *@This(), gpa: Allocator, io: Io) !void {
        var refs = try EntityRefs.init(gpa, io, 100);
        errdefer refs.deinit();

        const entities = try Entities.init(gpa, refs.refs.capacity);
        errdefer entities.deinit(gpa);

        self.* = .{
            .entities = entities,
            .refs = refs,
        };
    }

    pub fn deinit(self: *@This(), gpa: Allocator) void {
        self.entities.deinit(gpa);
        self.refs.deinit();
    }

    pub fn reserve(self: *@This()) EntityId {
        return self.refs.reserve() catch @panic("Entities Overflow");
    }

    pub fn insert(self: *@This(), key: EntityId, entity: *anyopaque) void {
        _ = self.entities.put(key, entity);
    }

    pub fn get(self: *@This(), comptime T: type, entity: Entity(T)) *const T {
        const ptr = self.entities.get(entity.id()) orelse @panic("Reading non existing entity");
        return @ptrCast(@alignCast(ptr.*));
    }

    pub fn getMut(self: *@This(), comptime T: type, entity: Entity(T)) *T {
        const ptr = self.entities.getMut(entity.id()) orelse @panic("Reading non existing entity");
        return @ptrCast(@alignCast(ptr.*));
    }

    pub fn remove(self: *@This(), comptime T: type, entity: Entity(T)) *T {
        const ptr = self.entities.remove(entity.id()) orelse @panic("Updating non existing Entity");

        return @as(*T, @ptrCast(@alignCast(ptr)));
    }

    pub fn lockRefs(self: *@This()) !void {
        try self.refs.rwlock.lock(self.refs.io);
    }

    pub fn unlockRefs(self: *@This()) void {
        self.refs.rwlock.unlock(self.refs.io);
    }

    pub fn popDrop(self: *@This()) ?struct { *anyopaque, EntityId, TypeId } {
        const entity = self.refs.dropped_entities.pop() orelse return null;

        const ptr = self.entities.remove(entity.id) orelse @panic("Dropping non existing entity");
        self.refs.refs.remove(entity.id);

        return .{ ptr, entity.id, entity.type_id };
    }

    pub fn recycle(self: *@This(), id: EntityId) void {
        self.refs.refs.recycle(id);
    }

    pub fn collect(self: *@This(), gpa: Allocator) !std.ArrayList(struct { *anyopaque, EntityId, TypeId }) {
        var entities: std.ArrayList(struct { *anyopaque, EntityId, TypeId }) = .empty;
        errdefer entities.deinit(gpa);

        const refs = &self.refs;
        try refs.rwlock.lock(refs.io);
        defer refs.rwlock.unlock(refs.io);

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
    try store.init(allocator, io);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 42 };

    const id = store.reserve();
    const entity: Entity(A) = .init(&store, id);
    store.insert(id, ptr);

    try std.testing.expectEqual(ptr, store.getMut(A, entity));
    try std.testing.expectEqual(@as(u32, 42), store.get(A, entity).value);
}

test "closing entity records id and type when ref count reaches zero" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator, io);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 7 };

    const id = store.reserve();
    const entity: Entity(A) = .init(&store, id);
    store.insert(id, ptr);

    entity.drop();

    var collected = try store.collect(allocator);
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
    try store.init(allocator, io);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 9 };

    const id = store.reserve();
    const entity: Entity(A) = .init(&store, id);
    store.insert(id, ptr);
    const clone = entity.clone();
    const any_clone = entity.any.clone();

    entity.drop();
    clone.drop();
    var empty_collected = try store.collect(allocator);
    defer empty_collected.deinit(allocator);
    try std.testing.expectEqual(@as(usize, 0), empty_collected.items.len);

    any_clone.drop();
    var collected = try store.collect(allocator);
    defer collected.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), collected.items.len);
    try std.testing.expectEqual(ptr, @as(*A, @ptrCast(@alignCast(collected.items[0][0]))));
    try std.testing.expect(collected.items[0][1].eql(id));
    try std.testing.expectEqual(TypeInfo.init(A), collected.items[0][2]);
}

test "dropping arena-backed entity calls optional deinit" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;

    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();

    const A = struct {
        deinit_called: *bool,

        pub fn deinit(self: *@This()) void {
            self.deinit_called.* = true;
        }
    };

    var store: EntityStore = undefined;
    try store.init(allocator, io);
    defer store.deinit(allocator);

    var deinit_called = false;
    const ptr = try arena.allocator().create(A);
    ptr.* = .{ .deinit_called = &deinit_called };

    const id = store.reserve();
    const entity: Entity(A) = .init(&store, id);
    store.insert(id, ptr);

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
    const io = std.testing.io;

    const A = struct { value: u32 };

    var store: EntityStore = undefined;
    try store.init(allocator, io);
    defer store.deinit(allocator);

    const ptr = try allocator.create(A);
    defer allocator.destroy(ptr);
    ptr.* = .{ .value = 1 };

    const id = store.reserve();
    const entity: Entity(A) = .init(&store, id);
    store.insert(id, ptr);

    entity.drop();
    const drop = store.popDrop().?;
    try std.testing.expect(drop.@"1".eql(id));
    store.recycle(drop.@"1");

    const recycled = store.reserve();
    try std.testing.expectEqual(id.index, recycled.index);
}
