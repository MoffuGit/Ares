const std = @import("std");
const triepkg = @import("../datastruct/trie.zig");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;

const Allocator = std.mem.Allocator;
const KeyStrokeActions = triepkg.Trie(KeyStroke, Action, KeyStrokeContext);

pub const Action = union(enum) {
    workspace: Workspace,
    editor: Editor,

    pub const Workspace = enum {
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

    pub const Editor = enum {
        placeholder,
    };

    /// Parses a "structure:action" string like "workspace:new_tab".
    pub fn parse(s: []const u8) ?Action {
        const sep = std.mem.indexOfScalar(u8, s, ':') orelse return null;
        const structure = s[0..sep];
        const action_name = s[sep + 1 ..];
        if (action_name.len == 0) return null;

        if (asciiEqlIgnoreCase(structure, "workspace")) {
            const a = std.meta.stringToEnum(Workspace, action_name) orelse return null;
            return .{ .workspace = a };
        } else if (asciiEqlIgnoreCase(structure, "editor")) {
            const a = std.meta.stringToEnum(Editor, action_name) orelse return null;
            return .{ .editor = a };
        }
        return null;
    }

    pub fn eql(a: Action, b: Action) bool {
        const tag_a = std.meta.activeTag(a);
        const tag_b = std.meta.activeTag(b);
        if (tag_a != tag_b) return false;
        return switch (a) {
            .workspace => |wa| wa == b.workspace,
            .editor => |ea| ea == b.editor,
        };
    }

    fn asciiEqlIgnoreCase(a_str: []const u8, comptime b_str: []const u8) bool {
        if (a_str.len != b_str.len) return false;
        for (a_str, b_str) |ac, bc| {
            if (std.ascii.toLower(ac) != bc) return false;
        }
        return true;
    }
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
