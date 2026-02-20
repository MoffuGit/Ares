const vaxis = @import("vaxis");
const Action = @import("../keymaps/mod.zig").Action;
const UpdatedEntriesSet = @import("../worktree/scanner/mod.zig").UpdatedEntriesSet;

pub const Message = union(enum) {
    scheme: vaxis.Color.Scheme,
    worktreeUpdatedEntries: *UpdatedEntriesSet,
    bufferUpdated: u64,
    keymapAction: []const Action,
};
