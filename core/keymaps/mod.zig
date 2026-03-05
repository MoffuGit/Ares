const std = @import("std");
const triepkg = @import("datastruct");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;

const Allocator = std.mem.Allocator;
const KeyStrokeActions = triepkg.Trie(KeyStroke, Action, KeyStrokeContext);

pub const Action = union(enum) {
    workspace: Workspace,
    editor: Editor,
    command: Command,

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

    pub const Command = enum {
        up,
        down,
        select,
        scroll_up,
        scroll_down,
        top,
        bottom,
    };

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
        } else if (asciiEqlIgnoreCase(structure, "command")) {
            const a = std.meta.stringToEnum(Command, action_name) orelse return null;
            return .{ .command = a };
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
            .command => |ca| ca == b.command,
        };
    }

    pub fn key(self: Action) u32 {
        return switch (self) {
            .workspace => |w| (@as(u32, 0) << 16) | @intFromEnum(w),
            .editor => |e| (@as(u32, 1) << 16) | @intFromEnum(e),
            .command => |c| (@as(u32, 2) << 16) | @intFromEnum(c),
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
pub const Scope = enum { global, editor, command_palette };

pub const Keymaps = struct {
    const scope_count = @typeInfo(Scope).@"enum".fields.len;
    const mode_count = @typeInfo(Mode).@"enum".fields.len;
    const total = scope_count * mode_count;

    tries: [total]KeyStrokeActions,

    pub fn init(alloc: std.mem.Allocator) !Keymaps {
        var tries: [total]KeyStrokeActions = undefined;
        var initialized: usize = 0;
        errdefer for (tries[0..initialized]) |*t| t.deinit();
        for (&tries) |*t| {
            t.* = try KeyStrokeActions.init(alloc);
            initialized += 1;
        }
        return .{ .tries = tries };
    }

    pub fn deinit(self: *Keymaps) void {
        for (&self.tries) |*t| t.deinit();
    }

    pub fn actions(self: *Keymaps, scope: Scope, mode: Mode) *KeyStrokeActions {
        const idx = @intFromEnum(scope) * mode_count + @intFromEnum(mode);
        return &self.tries[idx];
    }
};

test {
    _ = keystrokepkg;
}
