const std = @import("std");
const lib = @import("../../lib.zig");

const Element = lib.Element;

const Tabs = @This();

pub const Id = u64;

pub const Tab = struct {
    id: Id,
    content: *Element,
    trigger: *Element,
    tabs: *Tabs,
    userdata: ?*anyopaque,
};

items: std.ArrayListUnmanaged(Tab) = .{},
selected: ?usize = null,
alloc: std.mem.Allocator,
next_id: Id = 1,
container: *Element,

pub fn init(alloc: std.mem.Allocator, opts: Element.Options) !Tabs {
    const container = try alloc.create(Element);
    container.* = Element.init(alloc, opts);
    return .{ .alloc = alloc, .container = container };
}

pub fn createTab(self: *Tabs, opts: Element.Options, trigger_opts: Element.Options, userdata: ?*anyopaque) !*Tab {
    const id = self.next_id;
    self.next_id += 1;
    try self.open(id, opts, trigger_opts, userdata);
    return &self.items.items[self.items.items.len - 1];
}

pub fn closeSelected(self: *Tabs) void {
    const id = self.getSelected() orelse return;
    self.close(id);
}

pub fn deinit(self: *Tabs) void {
    for (self.items.items) |item| {
        item.content.deinit();
        item.trigger.deinit();
    }
    self.container.deinit();
    self.items.deinit(self.alloc);
    self.alloc.destroy(self);
}

pub fn open(self: *Tabs, id: Id, opts: Element.Options, trigger_opts: Element.Options, userdata: ?*anyopaque) !void {
    for (self.items.items) |item| {
        if (item.id == id) {
            self.setSelected(self.indexOf(id));
            return;
        }
    }

    const content = try self.alloc.create(Element);
    content.* = Element.init(self.alloc, opts);
    errdefer content.deinit();

    var overridden_opts = trigger_opts;
    overridden_opts.userdata = self;

    const trigger = try self.alloc.create(Element);
    trigger.* = Element.init(self.alloc, overridden_opts);
    errdefer trigger.deinit();
    try trigger.addEventListener(.click, onTriggerClick);

    try self.items.append(self.alloc, .{
        .id = id,
        .content = content,
        .trigger = trigger,
        .tabs = self,
        .userdata = userdata,
    });
    self.setSelected(self.items.items.len - 1);
}

pub fn close(self: *Tabs, id: Id) void {
    const index = self.indexOf(id) orelse return;
    const tab = self.items.orderedRemove(index);
    tab.content.deinit();
    tab.trigger.deinit();

    if (self.items.items.len == 0) {
        self.setSelected(null);
    } else if (self.selected) |sel| {
        if (sel == index) {
            const new = if (index >= self.items.items.len) self.items.items.len - 1 else index;
            self.setSelected(new);
        } else if (sel > index) {
            self.setSelected(sel - 1);
        }
    }
}

pub fn select(self: *Tabs, index: usize) void {
    if (index < self.items.items.len) {
        self.setSelected(index);
    }
}

pub fn selectById(self: *Tabs, id: Id) void {
    if (self.indexOf(id)) |index| {
        self.setSelected(index);
    }
}

pub fn selectNext(self: *Tabs) void {
    if (self.items.items.len == 0) return;
    const sel = self.selected orelse return;
    self.setSelected((sel + 1) % self.items.items.len);
}

pub fn selectPrev(self: *Tabs) void {
    if (self.items.items.len == 0) return;
    const sel = self.selected orelse return;
    self.setSelected(if (sel == 0) self.items.items.len - 1 else sel - 1);
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
    self.syncChild();
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

fn setSelected(self: *Tabs, index: ?usize) void {
    self.selected = index;
    self.syncChild();
}

fn syncChild(self: *Tabs) void {
    self.container.removeChildrens();
    if (self.selected) |sel| {
        self.container.addChild(self.items.items[sel].content) catch return;
    }
}

fn onTriggerClick(element: *Element, _: Element.EventData) void {
    const self: *Tabs = @ptrCast(@alignCast(element.userdata orelse return));
    for (self.items.items, 0..) |item, i| {
        if (item.trigger == element) {
            self.setSelected(i);
            return;
        }
    }
}
