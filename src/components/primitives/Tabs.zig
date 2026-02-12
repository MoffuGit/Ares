const std = @import("std");
const lib = @import("../../lib.zig");

const Element = lib.Element;
const Allocator = std.mem.Allocator;

const Tabs = @This();

pub const Tab = struct {
    id: usize,
    content: *Element,
    trigger: *Element,
    tabs: *Tabs,
    userdata: ?*anyopaque,

    pub const Options = struct {
        content: Element.Options = .{},
        trigger: Element.Options = .{},
        userdata: ?*anyopaque = null,
    };

    pub fn create(alloc: Allocator, id: usize, tabs: *Tabs, opts: Tab.Options) !*Tab {
        const tab = try alloc.create(Tab);

        var content_opts = opts.content;
        content_opts.userdata = tab;

        const content = try alloc.create(Element);
        content.* = Element.init(alloc, opts.content);
        errdefer content.deinit();

        var trigger_opts = opts.trigger;
        trigger_opts.userdata = tab;

        const trigger = try alloc.create(Element);
        trigger.* = Element.init(alloc, trigger_opts);
        errdefer trigger.deinit();

        try trigger.addEventListener(.click, onTriggerClick);

        tab.* = .{
            .id = id,
            .content = content,
            .trigger = trigger,
            .tabs = tabs,
            .userdata = opts.userdata,
        };

        return tab;
    }

    pub fn destroy(self: *Tab) void {
        const alloc = self.tabs.alloc;
        self.content.deinit();
        self.trigger.deinit();

        alloc.destroy(self.content);
        alloc.destroy(self.trigger);

        alloc.destroy(self);
    }

    fn onTriggerClick(element: *Element, _: Element.EventData) void {
        const self: *Tab = @ptrCast(@alignCast(element.userdata orelse return));
        self.tabs.select(self.id);
        element.context.?.requestDraw();
    }
};

pub const OnSelectCallback = *const fn (tabs: *Tabs, id: ?usize, userdata: ?*anyopaque) void;

alloc: std.mem.Allocator,

values: std.ArrayList(*Tab) = .{},
selected: ?usize = null,

next_id: usize = 1,

on_select: ?OnSelectCallback = null,
on_select_userdata: ?*anyopaque = null,

container: *Element,
list: *Element,
indicator: *Element,

const Options = struct {
    container: Element.Options = .{},
    list: Element.Options = .{},
    indicator: Element.Options = .{},
    on_select: ?OnSelectCallback = null,
    on_select_userdata: ?*anyopaque = null,
};

pub fn create(alloc: std.mem.Allocator, opts: Options) !*Tabs {
    const tabs = try alloc.create(Tabs);
    errdefer alloc.destroy(tabs);

    const container = try alloc.create(Element);
    container.* = Element.init(alloc, opts.container);

    const list = try alloc.create(Element);
    list.* = Element.init(alloc, opts.list);

    var indicator_opts = opts.indicator;
    indicator_opts.userdata = tabs;

    const indicator = try alloc.create(Element);
    indicator.* = Element.init(alloc, indicator_opts);

    try list.addChild(indicator);

    tabs.* = .{
        .alloc = alloc,
        .container = container,
        .list = list,
        .indicator = indicator,
        .on_select = opts.on_select,
        .on_select_userdata = opts.on_select_userdata,
    };

    return tabs;
}

pub fn destroy(self: *Tabs) void {
    for (self.values.items) |tab| {
        tab.destroy();
    }
    self.values.deinit(self.alloc);

    self.container.deinit();
    self.alloc.destroy(self.container);

    self.indicator.deinit();
    self.alloc.destroy(self.indicator);

    self.list.deinit();
    self.alloc.destroy(self.list);

    self.alloc.destroy(self);
}

pub fn newTab(self: *Tabs, opts: Tab.Options) !*Tab {
    const id = self.next_id;
    self.next_id += 1;

    const tab = try Tab.create(self.alloc, id, self, opts);

    try self.values.append(self.alloc, tab);
    try self.list.addChild(tab.trigger);

    return tab;
}

pub fn closeTab(self: *Tabs, id: usize) void {
    const index = self.indexOf(id) orelse return;

    var tab = self.values.orderedRemove(index);
    tab.trigger.remove();
    tab.destroy();

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

    self.container.removeChildrens();

    if (self.selected) |sel| {
        const index = self.indexOf(sel) orelse return;
        const tab = self.values.items[index];

        self.container.addChild(tab.content) catch {};
    }

    if (self.on_select) |cb| {
        cb(self, id, self.on_select_userdata);
    }
}

pub fn selectNext(self: *Tabs) void {
    if (self.values.items.len == 0) return;
    const index = if (self.selected) |sel| self.indexOf(sel) orelse 0 else 0;
    const next = (index + 1) % self.values.items.len;
    self.select(self.values.items[next].id);
}

pub fn selectPrev(self: *Tabs) void {
    if (self.values.items.len == 0) return;
    const index = if (self.selected) |sel| self.indexOf(sel) orelse 0 else 0;
    const prev = if (index == 0) self.values.items.len - 1 else index - 1;
    self.select(self.values.items[prev].id);
}

pub fn selectedTrigger(self: *Tabs) ?*Element {
    const sel = self.selected orelse return null;
    const index = self.indexOf(sel) orelse return null;
    return self.values.items[index].trigger;
}

pub fn indexOf(self: *Tabs, id: usize) ?usize {
    for (self.values.items, 0..) |item, i| {
        if (item.id == id) return i;
    }
    return null;
}
