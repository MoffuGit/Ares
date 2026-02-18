const std = @import("std");
const triepkg = @import("../datastruct/trie.zig");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;

const Allocator = std.mem.Allocator;
const KeyStrokeActions = triepkg.Trie(KeyStroke, Action, KeyStrokeContext);

pub const Action = enum {
    enter_insert,
    enter_visual,
    enter_normal,

    toggle_left_dock,
    toggle_right_dock,
    toggle_command_palette,

    new_tab,
    close_active_tab,
    next_tab,
    prev_tab,
};

pub const Mode = enum { normal, insert, visual };

pub const Keymaps = struct {
    normal: KeyStrokeActions,
    insert: KeyStrokeActions,
    visual: KeyStrokeActions,

    pub fn init(alloc: std.mem.Allocator) !Keymaps {
        return .{
            .normal = try KeyStrokeActions.init(alloc),
            .insert = try KeyStrokeActions.init(alloc),
            .visual = try KeyStrokeActions.init(alloc),
        };
    }

    pub fn deinit(self: *Keymaps) void {
        self.normal.deinit();
        self.insert.deinit();
        self.visual.deinit();
    }

    pub fn actions(self: *Keymaps, mode: Mode) *KeyStrokeActions {
        return switch (mode) {
            .normal => &self.normal,
            .insert => &self.insert,
            .visual => &self.visual,
        };
    }
};

test {
    _ = keystrokepkg;
}
