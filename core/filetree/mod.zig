const std = @import("std");
const global = @import("../global.zig");

const worktreepkg = @import("../worktree/mod.zig");
const Worktree = worktreepkg.Worktree;
const Entry = worktreepkg.Entry;
// const Kind = worktreepkg.Kind;
//
const Allocator = std.mem.Allocator;

pub const FileTree = @This();

alloc: Allocator,
mutex: std.Thread.Mutex = .{},
expanded_entries: std.AutoHashMap(u64, void),
visible_entries: std.ArrayList(u64) = .{},
worktree: *Worktree,

listener: global.EventEmitter.Listener,

pub fn create(alloc: Allocator, worktree: *Worktree) !*FileTree {
    const self = try alloc.create(FileTree);
    errdefer alloc.destroy(self);

    var map = std.AutoHashMap(u64, void).init(alloc);
    errdefer map.deinit();

    self.* = .{
        .alloc = alloc,
        .expanded_entries = map,
        .worktree = worktree,
        .listener = .{
            .ctx = self,
            .handle = worktreeUpdateCallback,
        },
    };

    try global.state.events.on(.worktreeUpdate, self.listener);

    return self;
}

fn worktreeUpdateCallback(ctx: *anyopaque) void {
    const self: *FileTree = @ptrCast(@alignCast(ctx));
    self.mutex.lock();
    defer self.mutex.unlock();

    self.rebuildVisibleEntries();
}

pub fn destroy(self: *FileTree) void {
    global.state.events.off(.worktreeUpdate, self.listener);
    self.expanded_entries.deinit();
    self.visible_entries.deinit(self.alloc);
    self.alloc.destroy(self);
}

pub fn clickEntry(self: *FileTree, entry: Entry) void {
    if (entry.kind == .dir) {
        if (self.expanded_entries.contains(entry.id)) {
            _ = self.expanded_entries.remove(entry.id);
        } else {
            self.expanded_entries.put(entry.id, {}) catch {};
        }
        self.rebuildVisibleEntries();
    } else {}
}

fn rebuildVisibleEntries(self: *FileTree) void {
    self.visible_entries.clearRetainingCapacity();

    self.worktree.snapshot.mutex.lock();
    defer self.worktree.snapshot.mutex.unlock();

    var it = self.worktree.snapshot.entries.iter();
    while (it.next()) |entry| {
        if (std.mem.indexOfScalar(u8, entry.key, '/') != null) continue;

        self.visible_entries.append(self.alloc, entry.value.id) catch continue;

        if (entry.value.kind == .dir and self.expanded_entries.contains(entry.value.id)) {
            self.appendDirectChildren(entry.key);
        }
    }
}

fn appendDirectChildren(self: *FileTree, dir_path: []const u8) void {
    var prefix_buf: [std.fs.max_path_bytes]u8 = undefined;
    const prefix = std.fmt.bufPrint(&prefix_buf, "{s}/", .{dir_path}) catch return;

    var dir_it = self.worktree.snapshot.entries.rangeFrom(prefix);
    while (dir_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.key, prefix)) break;
        const rest = entry.key[prefix.len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) continue;
        if (entry.value.kind != .dir) continue;
        self.visible_entries.append(self.alloc, entry.value.id) catch continue;

        if (self.expanded_entries.contains(entry.value.id)) {
            self.appendDirectChildren(entry.key);
        }
    }

    var file_it = self.worktree.snapshot.entries.rangeFrom(prefix);
    while (file_it.next()) |entry| {
        if (!std.mem.startsWith(u8, entry.key, prefix)) break;
        const rest = entry.key[prefix.len..];
        if (std.mem.indexOfScalar(u8, rest, '/') != null) continue;
        if (entry.value.kind != .file) continue;
        self.visible_entries.append(self.alloc, entry.value.id) catch continue;
    }
}
//
// fn draw(element: *Element, buffer: *Buffer) void {
//     const self: *FileTree = @ptrCast(@alignCast(element.userdata));
//
//     const span = self.scrollable.visibleRowSpan(element);
//     const outer_top = self.scrollable.outer.layout.top;
//     const print_base: u16 = outer_top -| element.layout.top;
//
//     self.project.worktree.snapshot.mutex.lock();
//     defer self.project.worktree.snapshot.mutex.unlock();
//
//     const all = self.visible_entries.items;
//     const end = @min(span.end, all.len);
//     for (span.start..end) |abs_i| {
//         const id = all[abs_i];
//         const path = self.project.worktree.snapshot.getPathById(id) orelse continue;
//         const entry = self.project.worktree.snapshot.entries.get(path) catch continue;
//         const vp_row: u16 = @intCast(abs_i - span.start);
//         const print_row = print_base + vp_row;
//
//         const is_selected = self.project.selected_entry != null and self.project.selected_entry.? == id;
//
//         const icon: []const u8 = switch (entry.kind) {
//             .dir => if (self.expanded_entries.contains(entry.id)) " " else "󰉋 ",
//             .file => global.file_icons.get(entry.file_type),
//         };
//
//         if (is_selected) {
//             const screen_y = element.layout.top + print_row;
//             buffer.fillRect(self.scrollable.outer.layout.left, screen_y, element.layout.width, 1, .{ .style = .{ .bg = global.settings.theme.mutedBg } });
//         }
//
//         const display_name = if (std.mem.lastIndexOfScalar(u8, path, '/')) |sep| path[sep + 1 ..] else path;
//         const depth: u16 = @intCast(std.mem.count(u8, path, "/"));
//
//         const guide_fg = global.settings.theme.fg.setAlpha(0.27);
//         const guide_style: vaxis.Cell.Style = .{ .fg = guide_fg, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } };
//         var d: u16 = 0;
//         while (d < depth) : (d += 1) {
//             const guide = "⡇";
//             _ = element.print(
//                 buffer,
//                 &.{.{ .text = guide, .style = guide_style }},
//                 .{ .row_offset = print_row, .col_offset = d * 2 },
//             );
//         }
//
//         const indent: u16 = depth * 2;
//         _ = element.print(
//             buffer,
//             &.{
//                 .{
//                     .text = icon,
//                     .style = .{ .fg = global.settings.theme.fg, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } },
//                 },
//                 .{
//                     .text = display_name,
//                     .style = .{ .fg = global.settings.theme.fg, .bg = .{ .rgba = .{ 0, 0, 0, 0 } } },
//                 },
//             },
//             .{ .row_offset = print_row, .col_offset = indent, .wrap = .none },
//         );
//     }
// }
