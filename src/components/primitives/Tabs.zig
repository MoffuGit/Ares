const std = @import("std");
const lib = @import("../../lib.zig");

const Element = lib.Element;
const Allocator = std.mem.Allocator;

const Tabs = @This();

const Tab = struct {
    id: usize,
    content: *Element,
    trigger: *Element,
    tabs: *Tabs,
    userdata: ?*anyopaque,

    pub fn deinit(self: *Tab, alloc: Allocator) void {
        self.content.deinit();
        self.trigger.deinit();

        alloc.destroy(self.content);
        alloc.destroy(self.trigger);
    }

    pub const Options = struct {
        content: Element.Options,
        trigger: Element.Options,
        userdata: ?*anyopaque,
    };
};

values: std.ArrayListUnmanaged(Tab) = .{},
selected: ?usize = null,
alloc: std.mem.Allocator,
next_id: usize = 1,
container: *Element,
list: *Element,

const Options = struct {
    container: Element.Options = .{},
    list: Element.Options = .{},
};

pub fn init(alloc: std.mem.Allocator, opts: Options) !Tabs {
    const container = try alloc.create(Element);
    container.* = Element.init(alloc, opts.container);
    const list = try alloc.create(Element);
    list.* = Element.init(alloc, opts.list);

    return .{ .alloc = alloc, .container = container, .list = list };
}

pub fn deinit(self: *Tabs) void {
    for (self.values.items) |*tab| {
        tab.deinit(self.alloc);
    }
    self.values.deinit(self.alloc);

    self.container.deinit();
    self.alloc.destroy(self.container);
    self.list.deinit();
    self.alloc.destroy(self.list);
}

pub fn newTab(self: *Tabs, opts: Tab.Options) !*Tab {
    const id = self.next_id;
    self.next_id += 1;
    const content = try self.alloc.create(Element);
    content.* = Element.init(self.alloc, opts.content);
    errdefer content.deinit();

    var trigger_opts = opts.trigger;
    trigger_opts.userdata = self;

    const trigger = try self.alloc.create(Element);
    trigger.* = Element.init(self.alloc, trigger_opts);
    errdefer trigger.deinit();

    try trigger.addEventListener(.click, onTriggerClick);

    try self.list.addChild(trigger);

    try self.values.append(self.alloc, .{
        .id = id,
        .content = content,
        .trigger = trigger,
        .tabs = self,
        .userdata = opts.userdata,
    });

    return &self.values.items[self.values.items.len - 1];
}

pub fn closeTab(self: *Tabs, id: usize) void {
    const index = self.indexOf(id) orelse return;

    var tab = self.values.orderedRemove(index);
    tab.trigger.remove();
    tab.deinit(self.alloc);

    if (self.values.items.len == 0) {
        self.select(null);
    } else if (self.selected) |sel| {
        if (sel == id) {
            const new_idx = if (index >= self.values.items.len) self.values.items.len - 1 else index;
            const new_tab = self.values.items[new_idx];
            self.select(new_tab.id);
        }
    }
}

pub fn select(self: *Tabs, id: ?usize) void {
    if (self.selected == id) return;
    self.selected = id;

    if (self.selected) |sel| {
        const index = self.indexOf(sel) orelse return;
        const tab = self.values.items[index];

        self.container.removeChildrens();

        self.container.addChild(tab.content) catch {};
    }
}

pub fn indexOf(self: *Tabs, id: usize) ?usize {
    for (self.values.items, 0..) |item, i| {
        if (item.id == id) return i;
    }
    return null;
}

fn onTriggerClick(element: *Element, _: Element.EventData) void {
    const self: *Tabs = @ptrCast(@alignCast(element.userdata orelse return));
    for (self.values.items) |tab| {
        if (tab.trigger == element) {
            self.select(tab.id);
            return;
        }
    }
}
