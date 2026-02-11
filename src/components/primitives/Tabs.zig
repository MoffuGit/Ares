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
    }
};

alloc: std.mem.Allocator,

values: std.ArrayList(*Tab) = .{},
selected: ?usize = null,

next_id: usize = 1,

container: *Element,
list: *Element,

const Options = struct {
    container: Element.Options = .{},
    list: Element.Options = .{},
};

pub fn create(alloc: std.mem.Allocator, opts: Options) !*Tabs {
    const tabs = try alloc.create(Tabs);
    errdefer alloc.destroy(tabs);

    const container = try alloc.create(Element);
    container.* = Element.init(alloc, opts.container);

    const list = try alloc.create(Element);
    list.* = Element.init(alloc, opts.list);

    tabs.* = .{
        .alloc = alloc,
        .container = container,
        .list = list,
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
}

pub fn indexOf(self: *Tabs, id: usize) ?usize {
    for (self.values.items, 0..) |item, i| {
        if (item.id == id) return i;
    }
    return null;
}
