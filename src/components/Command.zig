const std = @import("std");
const vaxis = @import("vaxis");
const unicode = vaxis.unicode;
const gwidth = vaxis.gwidth.gwidth;
const lib = @import("../lib.zig");
const global = @import("../global.zig");
const keymapspkg = @import("../keymaps/mod.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Context = lib.App.Context;
const Dialog = @import("styled/Dialog.zig");
const Input = @import("../app/window/element/Input.zig");
const CommandList = @import("CommandList.zig");
const Allocator = std.mem.Allocator;
const Action = keymapspkg.Action;

const App = lib.App;

const Command = @This();

pub const CommandId = u64;

pub const Execute = union(enum) {
    dispatch: Action,
    callback: struct {
        userdata: *anyopaque,
        cb: *const fn (userdata: *anyopaque) void,
    },
};

pub const CommandEntry = struct {
    id: CommandId,
    owner: *anyopaque,
    owner_name: []const u8,
    title: []const u8,
    execute: Execute,
    binding: ?[]const u8 = null,
};

alloc: Allocator,
ctx: *Context,
dialog: *Dialog,
input: *Input,
list: *CommandList,
prev_focused: ?*Element.Element = null,
keymap_sub_id: ?u64 = null,

entries: std.ArrayListUnmanaged(CommandEntry) = .{},
next_id: CommandId = 1,

pub fn create(alloc: Allocator, ctx: *Context) !*Command {
    const self = try alloc.create(Command);
    errdefer alloc.destroy(self);

    const theme = global.settings.theme;

    const dialog = try Dialog.create(
        alloc,
        ctx,
        .{
            .box = .{
                .style = .{
                    .width = .{ .point = 75 },
                    .height = .{ .point = 25 },
                    .position = .{
                        .top = .{ .point = 2 },
                    },
                    .align_items = .center,
                },
                .border = .{
                    .kind = .thin_block,
                    .color = .{ .axes = .{ .vertical = .{
                        .bg = &theme.mutedBg,
                        .fg = &theme.border,
                    }, .horizontal = .{
                        .bg = &theme.bg,
                        .fg = &theme.border,
                    } } },
                },
                .bg = &theme.bg,
                .fg = &theme.fg,
            },
        },
    );
    errdefer dialog.destroy();

    const input = try Input.create(alloc, .{ .drawFn = drawInput }, .{
        .element = .{
            .id = "command-input",
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .point = 1 },
            },
        },
    });
    errdefer input.destroy();

    const list = try CommandList.create(alloc);
    errdefer list.destroy();

    try dialog.box.element.childs(.{ input, list.container });

    self.* = .{
        .alloc = alloc,
        .ctx = ctx,
        .dialog = dialog,
        .input = input,
        .list = list,
    };

    return self;
}

pub fn register(
    self: *Command,
    owner: *anyopaque,
    owner_name: []const u8,
    title: []const u8,
    execute: Execute,
) !CommandId {
    const id = self.next_id;
    self.next_id += 1;

    try self.entries.append(self.alloc, .{
        .id = id,
        .owner = owner,
        .owner_name = owner_name,
        .title = try self.alloc.dupe(u8, title),
        .execute = execute,
    });
    return id;
}

pub fn unregister(self: *Command, id: CommandId) void {
    for (self.entries.items, 0..) |e, i| {
        if (e.id == id) {
            self.alloc.free(e.title);
            if (e.binding) |b| self.alloc.free(b);
            _ = self.entries.orderedRemove(i);
            return;
        }
    }
}

pub fn unregisterOwner(self: *Command, owner: *anyopaque) void {
    var i: usize = 0;
    while (i < self.entries.items.len) {
        const e = self.entries.items[i];
        if (e.owner == owner) {
            self.alloc.free(e.title);
            if (e.binding) |b| self.alloc.free(b);
            _ = self.entries.orderedRemove(i);
        } else {
            i += 1;
        }
    }
}

fn refreshBindings(self: *Command) void {
    const settings = global.settings;
    for (self.entries.items) |*e| {
        if (e.binding) |b| self.alloc.free(b);
        e.binding = null;

        switch (e.execute) {
            .dispatch => |action| {
                if (settings.keymapBindingString(action)) |s| {
                    e.binding = self.alloc.dupe(u8, s) catch null;
                }
            },
            .callback => {},
        }
    }
}

fn executeEntry(self: *Command, id: CommandId) void {
    const entry = for (self.entries.items) |e| {
        if (e.id == id) break e;
    } else return;

    self.toggleShow();

    switch (entry.execute) {
        .dispatch => |action| {
            self.ctx.app.dispatchKeymapActions(&.{action});
        },
        .callback => |cb| cb.cb(cb.userdata),
    }
}

pub fn toggleShow(self: *Command) void {
    const is_visible = self.dialog.portal.element.elem().visible;

    if (!is_visible) {
        self.prev_focused = self.ctx.app.window.getFocus();
        self.ctx.app.window.setFocus(self.input.elem());
        self.keymap_sub_id = self.ctx.app.subscribe(.keymap_action, Command, self, onKeyAction) catch null;
        self.refreshBindings();
        self.list.setEntries(self.entries.items);
    } else {
        if (self.keymap_sub_id) |id| {
            self.ctx.app.unsubscribe(.keymap_action, id);
            self.keymap_sub_id = null;
        }
        self.ctx.app.window.setFocus(self.prev_focused);
        self.prev_focused = null;
    }

    self.dialog.toggleShow();
}

fn onKeyAction(self: *Command, data: App.EventData) void {
    const key_data = data.keymap_action;

    switch (key_data.action) {
        .command => |cmd| {
            switch (cmd) {
                .up => self.list.moveSelection(-1),
                .down => self.list.moveSelection(1),
                .select => {
                    if (self.list.selectedId()) |id| {
                        self.executeEntry(id);
                    }
                },
                .scroll_up => self.list.scrollPage(-1),
                .scroll_down => self.list.scrollPage(1),
                .top => self.list.moveToTop(),
                .bottom => self.list.moveToBottom(),
            }
            key_data.consume();
        },
        else => {},
    }

    self.ctx.requestDraw();
}

fn drawInput(input: *Input, element: *Element, buffer: *Buffer) void {
    const layout = element.layout;
    const theme = global.settings.theme;

    element.fill(buffer, .{ .style = .{ .bg = theme.bg } });

    const base_x = layout.left;
    const base_y = layout.top;
    const width = layout.width;

    var col: u16 = 0;

    const before = input.buf.items;
    var iter_before = unicode.graphemeIterator(before);
    while (iter_before.next()) |grapheme| {
        const s = grapheme.bytes(before);
        const w: u16 = @intCast(gwidth(s, .unicode));
        if (col + w > width) break;
        buffer.writeCell(base_x + col, base_y, .{
            .char = .{ .grapheme = s, .width = @intCast(w) },
            .style = .{ .fg = theme.fg, .bg = theme.bg },
        });
        col += w;
    }

    const cursor_col = col;
    const second = input.buf.secondHalf();
    const cursor_char = blk: {
        var it = unicode.graphemeIterator(second);
        if (it.next()) |g| break :blk g.bytes(second);
        break :blk " ";
    };
    const cursor_w: u16 = @intCast(@max(1, gwidth(cursor_char, .unicode)));
    if (cursor_col + cursor_w <= width) {
        buffer.writeCell(base_x + cursor_col, base_y, .{
            .char = .{ .grapheme = cursor_char, .width = @intCast(cursor_w) },
            .style = .{ .fg = theme.bg, .bg = theme.fg },
        });
    }

    col = cursor_col + cursor_w;
    var iter_after = unicode.graphemeIterator(second);
    _ = iter_after.next();
    while (iter_after.next()) |grapheme| {
        const s = grapheme.bytes(second);
        const w: u16 = @intCast(gwidth(s, .unicode));
        if (col + w > width) break;
        buffer.writeCell(base_x + col, base_y, .{
            .char = .{ .grapheme = s, .width = @intCast(w) },
            .style = .{ .fg = theme.fg, .bg = theme.bg },
        });
        col += w;
    }
}

pub fn destroy(self: *Command) void {
    for (self.entries.items) |e| {
        self.alloc.free(e.title);
        if (e.binding) |b| self.alloc.free(b);
    }
    self.entries.deinit(self.alloc);
    self.input.destroy();
    self.dialog.destroy();
    self.alloc.destroy(self);
}
