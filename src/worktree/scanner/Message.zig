pub const Message = union(enum) {
    /// Scan a directory by its entry id (lookup path from Snapshot)
    scan_dir: u64,
    initialScan,
    fsEvent: struct { id: u64, events: u32 },
};
