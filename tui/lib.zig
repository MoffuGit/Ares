const std = @import("std");
const global = @import("global.zig");
const App = @import("App.zig");
const Window = @import("window/mod.zig");
const Element = Window.Element;
const Screen = @import("Screen.zig");
const Box = @import("window/element/Box.zig");
const Scrollable = @import("window/element/Scrollable.zig").Scrollable;
const Mutations = @import("mutations/mod.zig");

export fn initState(callback: ?global.Callback) void {
    global.state.init(callback);
    Scrollable.initRegistry(global.state.alloc);
}

export fn deinitState() void {
    Scrollable.deinitRegistry();
    global.state.deinit();
}

export fn createApp() ?*App {
    return App.create(
        global.state.alloc,
    ) catch null;
}

export fn destroyApp(app: *App) void {
    app.destroy();
}

export fn getWindow(app: *App) *Window {
    return &app.window;
}

export fn createTestWindow() ?*Window {
    const alloc = global.state.alloc;
    const screen = alloc.create(Screen) catch return null;
    screen.* = Screen.init(alloc, .{ .cols = 80, .rows = 24, .x_pixel = 0, .y_pixel = 0 }) catch {
        alloc.destroy(screen);
        return null;
    };
    const window = alloc.create(Window) catch {
        screen.deinit();
        alloc.destroy(screen);
        return null;
    };
    window.* = Window.init(alloc, screen) catch {
        screen.deinit();
        alloc.destroy(screen);
        alloc.destroy(window);
        return null;
    };
    return window;
}

export fn drainMailbox(app: *App) void {
    app.drainMailbox();
}

export fn destroyTestWindow(window: *Window) void {
    const alloc = global.state.alloc;
    const screen = window.screen;

    window.deinit();
    alloc.destroy(window);
    screen.deinit();
    alloc.destroy(screen);
}

export fn createMutations(window: *Window) ?*Mutations {
    return Mutations.create(global.state.alloc, window) catch null;
}

export fn destroyMutations(mutations: *Mutations) void {
    mutations.destroy();
}

export fn processMutations(mutations: *Mutations, ptr: [*]const u8, len: u64) void {
    mutations.processMutations(ptr[0..len]);
}

var dump_buf: std.ArrayList(u8) = .{};

export fn dumpTree(window: *Window) u64 {
    const alloc = global.state.alloc;
    dump_buf.clearRetainingCapacity();

    const root = window.root orelse return 0;

    writeElementJson(root, alloc, &dump_buf) catch return 0;

    return dump_buf.items.len;
}

export fn getDumpPtr() [*]const u8 {
    return dump_buf.items.ptr;
}

export fn freeDumpTree() void {
    dump_buf.clearAndFree(global.state.alloc);
}

export fn drawWindow(app: *App) void {
    app.drawWindow() catch {};
}

export fn scrollableScrollBy(id: u64, dx: i32, dy: i32) bool {
    const scrollable = Scrollable.lookup(id) orelse return false;
    scrollable.scrollBy(dx, dy);
    return true;
}

export fn scrollableScrollTo(id: u64, x: i32, y: i32) bool {
    const scrollable = Scrollable.lookup(id) orelse return false;
    scrollable.scrollTo(x, y);
    return true;
}

export fn scrollableContainsPoint(id: u64, col: u16, row: u16) bool {
    const scrollable = Scrollable.lookup(id) orelse return false;
    return scrollable.containsPoint(col, row);
}

export fn scrollableBarPress(id: u64, col: u16, row: u16) bool {
    const scrollable = Scrollable.lookup(id) orelse return false;
    return scrollable.barPress(col, row);
}

export fn scrollableBarDrag(id: u64, col: u16, row: u16) bool {
    const scrollable = Scrollable.lookup(id) orelse return false;
    return scrollable.barDrag(col, row);
}

export fn scrollableBarRelease(id: u64) bool {
    const scrollable = Scrollable.lookup(id) orelse return false;
    return scrollable.barRelease();
}

fn writeElementJson(elem: *Element, alloc: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
    try appendSlice(alloc, buf, "{\"id\":");
    try appendInt(alloc, buf, elem.num);
    try appendSlice(alloc, buf, ",\"kind\":\"");
    try appendSlice(alloc, buf, @tagName(elem.kind));
    try appendSlice(alloc, buf, "\",\"zIndex\":");
    try appendInt(alloc, buf, elem.zIndex);

    if (childrenForDump(elem)) |children| {
        try appendSlice(alloc, buf, ",\"children\":[");
        for (children, 0..) |child, i| {
            if (i > 0) try buf.append(alloc, ',');
            try writeElementJson(child, alloc, buf);
        }
        try buf.append(alloc, ']');
    }

    try buf.append(alloc, '}');
}

fn childrenForDump(elem: *Element) ?[]const *Element {
    if (elem.kind == .scrollable) {
        const scrollable: *Scrollable = @ptrCast(@alignCast(elem.userdata orelse return null));
        if (scrollable.inner.childrens) |*childrens| {
            return childrens.by_order.items;
        }
        return null;
    }

    if (elem.childrens) |*childrens| {
        return childrens.by_order.items;
    }

    return null;
}

fn appendSlice(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.appendSlice(alloc, s);
}

fn appendInt(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), val: u64) !void {
    var tmp: [20]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{val}) catch return;
    try buf.appendSlice(alloc, s);
}
