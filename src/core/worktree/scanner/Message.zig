pub const Message = union(enum) {
    scan_dir: u64,
    initialScan,
    // fsEvent: struct { id: u64, events: u32 },
};
