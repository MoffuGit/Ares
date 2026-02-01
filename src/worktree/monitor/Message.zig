pub const Message = union(enum) {
    add: struct { path: []u8, id: u64 },
    remove: u64,
};
