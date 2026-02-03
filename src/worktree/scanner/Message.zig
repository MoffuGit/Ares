pub const Message = union(enum) {
    scan: struct { path: []const u8, abs_path: []const u8 },
    initialScan,
    fsEvent: struct { id: u64, events: u32 },
};
