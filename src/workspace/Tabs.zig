const std = @import("std");

const Tabs = @This();

pub const Id = u64;

pub const Tab = struct {
    id: Id,
    selected_entry: ?u64 = null,
};

items: std.ArrayListUnmanaged(Tab) = .{},
selected: ?usize = null,
alloc: std.mem.Allocator,
next_id: Id = 1,

pub fn init(alloc: std.mem.Allocator) Tabs {
    return .{ .alloc = alloc };
}

pub fn createTab(self: *Tabs) !Id {
    const id = self.next_id;
    self.next_id += 1;
    try self.open(id);
    return id;
}

pub fn closeSelected(self: *Tabs) void {
    const id = self.getSelected() orelse return;
    self.close(id);
}

pub fn deinit(self: *Tabs) void {
    self.items.deinit(self.alloc);
}

pub fn open(self: *Tabs, id: Id) !void {
    for (self.items.items) |item| {
        if (item.id == id) {
            self.selectById(id);
            return;
        }
    }
    try self.items.append(self.alloc, .{ .id = id });
    self.selected = self.items.items.len - 1;
}

pub fn close(self: *Tabs, id: Id) void {
    const index = self.indexOf(id) orelse return;
    _ = self.items.orderedRemove(index);

    if (self.items.items.len == 0) {
        self.selected = null;
    } else if (self.selected) |sel| {
        if (sel == index) {
            self.selected = if (index >= self.items.items.len) self.items.items.len - 1 else index;
        } else if (sel > index) {
            self.selected = sel - 1;
        }
    }
}

pub fn select(self: *Tabs, index: usize) void {
    if (index < self.items.items.len) {
        self.selected = index;
    }
}

pub fn selectById(self: *Tabs, id: Id) void {
    if (self.indexOf(id)) |index| {
        self.selected = index;
    }
}

pub fn selectNext(self: *Tabs) void {
    if (self.items.items.len == 0) return;
    const sel = self.selected orelse return;
    self.selected = (sel + 1) % self.items.items.len;
}

pub fn selectPrev(self: *Tabs) void {
    if (self.items.items.len == 0) return;
    const sel = self.selected orelse return;
    self.selected = if (sel == 0) self.items.items.len - 1 else sel - 1;
}

pub fn move(self: *Tabs, from: usize, to: usize) void {
    if (from >= self.items.items.len or to >= self.items.items.len) return;
    const item = self.items.orderedRemove(from);
    self.items.insert(self.alloc, to, item) catch return;

    if (self.selected) |sel| {
        if (sel == from) {
            self.selected = to;
        } else if (from < sel and to >= sel) {
            self.selected = sel - 1;
        } else if (from > sel and to <= sel) {
            self.selected = sel + 1;
        }
    }
}

pub fn getSelected(self: *const Tabs) ?Id {
    const sel = self.selected orelse return null;
    return self.items.items[sel].id;
}

pub fn getSelectedTab(self: *Tabs) ?*Tab {
    const sel = self.selected orelse return null;
    return &self.items.items[sel];
}

pub fn getTabById(self: *Tabs, id: Id) ?*Tab {
    for (self.items.items) |*item| {
        if (item.id == id) return item;
    }
    return null;
}

pub fn count(self: *const Tabs) usize {
    return self.items.items.len;
}

pub fn indexOf(self: *const Tabs, id: Id) ?usize {
    for (self.items.items, 0..) |item, i| {
        if (item.id == id) return i;
    }
    return null;
}
