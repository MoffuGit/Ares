pub const Message = union(enum) {
    scan: struct { path: []const u8, abs_path: []const u8 },
    initialScan,
};
