pub const Message = union(enum) {
    /// Add a watcher for a directory by its entry id (lookup path from Snapshot)
    add: u64,
    remove: u64,
};
