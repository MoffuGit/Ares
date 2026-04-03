const std = @import("std");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;
pub const parseSequence = keystrokepkg.parseSequence;

const Allocator = std.mem.Allocator;

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
    bindings: [scope_count][mode_count]EntryList,

    pub fn init(alloc: Allocator) !Keymaps {
        var bindings: [scope_count][mode_count]EntryList = undefined;
        for (&bindings) |*per_scope| {
            for (per_scope) |*list| list.* = .{};
        }

        return .{
            .alloc = alloc,
            .bindings = bindings,
        };
    }

    pub fn deinit(self: *Keymaps) void {
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

    pub fn entries(self: *const Keymaps, scope: Scope, mode: Mode) []const KeymapEntry {
        return self.bindings[@intFromEnum(scope)][@intFromEnum(mode)].items;
    }

    pub fn insert(self: *Keymaps, scope: Scope, mode: Mode, sequence_str: []const u8, action_str: []const u8) !void {
        const seq = try parseSequence(self.alloc, sequence_str);
        defer self.alloc.free(seq);

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
