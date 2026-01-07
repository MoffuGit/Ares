pub const Message = union(enum) {
    add: struct { path: []u8, id: usize },
    remove: usize,
};
