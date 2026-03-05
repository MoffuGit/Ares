pub const Message = union(enum) {
    scan_dir: u64,
    initialScan,
};
