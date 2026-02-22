// Core
comptime {
    _ = @import("core/keymaps/KeyStroke.zig");
    _ = @import("core/keymaps/mod.zig");
    _ = @import("core/settings/theme/mod.zig");
    _ = @import("core/settings/mod.zig");
}

// Datastruct
comptime {
    _ = @import("datastruct/b_plus_tree.zig");
    _ = @import("datastruct/blocking_queue.zig");
    _ = @import("datastruct/gap_buffer.zig");
    _ = @import("datastruct/trie.zig");
}
