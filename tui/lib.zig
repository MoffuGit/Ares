const std = @import("std");
const global = @import("global.zig");
const App = @import("App.zig");
const Window = @import("window/mod.zig");
const Element = Window.Element;
const Screen = @import("Screen.zig");
const Box = @import("window/element/Box.zig");
const Bus = @import("Bus.zig");
const Mutations = @import("mutations/mod.zig");

export fn initState(callback: ?Bus.Callback) void {
    global.state.init(callback);
}

export fn deinitState() void {
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

/// Create a headless window for testing (no TTY required).
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

/// Destroy a headless test window created by `createTestWindow`.
export fn destroyTestWindow(window: *Window) void {
    const alloc = global.state.alloc;
    const screen = window.screen;

    // Clean up all elements
    var it = window.elements.valueIterator();
    while (it.next()) |entry| {
        const elem = entry.*;
        switch (elem.kind) {
            .box => {
                const box: *Box = @ptrCast(@alignCast(elem.userdata orelse continue));
                box.deinit(alloc);
            },
            .raw => {
                elem.deinit();
                alloc.destroy(elem);
            },
        }
    }

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

export fn drainEvents() void {
    global.state.bus.drain();
}

var dump_buf: std.ArrayList(u8) = .{};

/// Serializes the element tree as JSON into an internal buffer.
/// Returns the byte length; use `getDumpPtr` to read the data.
export fn dumpTree(window: *Window) u64 {
    const alloc = global.state.alloc;
    dump_buf.clearRetainingCapacity();

    const root = window.root orelse return 0;

    writeElementJson(root, alloc, &dump_buf) catch return 0;

    return dump_buf.items.len;
}

/// Returns a pointer to the internal dump buffer populated by `dumpTree`.
export fn getDumpPtr() [*]const u8 {
    return dump_buf.items.ptr;
}

export fn freeDumpTree() void {
    dump_buf.clearAndFree(global.state.alloc);
}

fn writeElementJson(elem: *Element, alloc: std.mem.Allocator, buf: *std.ArrayList(u8)) !void {
    try appendSlice(alloc, buf, "{\"id\":");
    try appendInt(alloc, buf, elem.num);
    try appendSlice(alloc, buf, ",\"kind\":\"");
    try appendSlice(alloc, buf, @tagName(elem.kind));
    try appendSlice(alloc, buf, "\",\"zIndex\":");
    try appendInt(alloc, buf, elem.zIndex);

    if (elem.childrens) |*childrens| {
        try appendSlice(alloc, buf, ",\"children\":[");
        for (childrens.by_order.items, 0..) |child, i| {
            if (i > 0) try buf.append(alloc, ',');
            try writeElementJson(child, alloc, buf);
        }
        try buf.append(alloc, ']');
    }

    try buf.append(alloc, '}');
}

fn appendSlice(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    try buf.appendSlice(alloc, s);
}

fn appendInt(alloc: std.mem.Allocator, buf: *std.ArrayList(u8), val: u64) !void {
    var tmp: [20]u8 = undefined;
    const s = std.fmt.bufPrint(&tmp, "{d}", .{val}) catch return;
    try buf.appendSlice(alloc, s);
}
