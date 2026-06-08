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
        if (entity.type_id != TypeInfo.init(T)) return null;
        const ptr = self.entities.get(entity.entity_id) orelse return null;
        return @ptrCast(@alignCast(ptr.*));
    }
};
