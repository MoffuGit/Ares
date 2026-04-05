const std = @import("std");
const triepkg = @import("datastruct");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
pub const parseSequence = keystrokepkg.parseSequence;

const Allocator = std.mem.Allocator;
const KeySequenceTrie = triepkg.Trie(KeyStroke, u8, KeyStrokeContext);

pub const Mode = enum { normal, insert, visual };
pub const Scope = enum { global, editor, command_palette };

pub const KeymapEntry = struct {
    sequence: []const u8,
    action: []const u8,
};

const EntryList = std.ArrayListUnmanaged(KeymapEntry);

pub const Keymaps = struct {
    const scope_count = @typeInfo(Scope).@"enum".fields.len;
    const mode_count = @typeInfo(Mode).@"enum".fields.len;

    alloc: Allocator,
    tries: [mode_count]KeySequenceTrie,
    bindings: [scope_count][mode_count]EntryList,

    pub fn init(alloc: Allocator) !Keymaps {
        var tries: [mode_count]KeySequenceTrie = undefined;
        var initialized: usize = 0;
        errdefer for (tries[0..initialized]) |*t| t.deinit();

        for (&tries) |*t| {
            t.* = try KeySequenceTrie.init(alloc);
            initialized += 1;
        }

        var bindings: [scope_count][mode_count]EntryList = undefined;
        for (&bindings) |*per_scope| {
            for (per_scope) |*list| list.* = .{};
        }

        return .{
            .alloc = alloc,
            .tries = tries,
            .bindings = bindings,
        };
    }

    pub fn deinit(self: *Keymaps) void {
        for (&self.tries) |*t| t.deinit();

        for (&self.bindings) |*per_scope| {
            for (per_scope) |*list| {
                for (list.items) |entry| {
                    self.alloc.free(entry.sequence);
                    self.alloc.free(entry.action);
                }
                list.deinit(self.alloc);
            }
        }
    }

    pub fn trie(self: *Keymaps, mode: Mode) *KeySequenceTrie {
        return &self.tries[@intFromEnum(mode)];
    }

    pub fn entries(self: *const Keymaps, scope: Scope, mode: Mode) []const KeymapEntry {
        return self.bindings[@intFromEnum(scope)][@intFromEnum(mode)].items;
    }

    pub fn insert(self: *Keymaps, scope: Scope, mode: Mode, sequence_str: []const u8, action_str: []const u8) !void {
        const seq = try parseSequence(self.alloc, sequence_str);
        defer self.alloc.free(seq);

        const t = self.trie(mode);
        if (t.get(seq) == null) {
            try t.insert(seq, 1);
        }

        const owned_seq = try self.alloc.dupe(u8, sequence_str);
        errdefer self.alloc.free(owned_seq);

        const owned_action = try self.alloc.dupe(u8, action_str);
        errdefer self.alloc.free(owned_action);

        try self.bindings[@intFromEnum(scope)][@intFromEnum(mode)].append(self.alloc, .{
            .sequence = owned_seq,
            .action = owned_action,
        });
    }
};

test {
    _ = keystrokepkg;
}
