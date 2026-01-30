const std = @import("std");
const datastruct = @import("datastruct/mod.zig");
const yoga = @import("yoga");

const Element = @import("element/mod.zig").Element;
const Debug = @import("Debug.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const App = @import("App.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;
const worktreepkg = @import("worktree/mod.zig");
const Worktree = worktreepkg.Worktree;
const FileTree = worktreepkg.FileTree;

const split = @import("split/mod.zig");
const SplitTree = split.Tree;

const log = std.log.scoped(.main);

const global = @import("global.zig");

pub fn keyPressFn(element: *Element, data: Element.EventData) void {
    const key_data = data.key_press;
    if (key_data.key.matches('c', .{ .ctrl = true })) {
        if (element.context) |app_ctx| {
            app_ctx.stopApp() catch {};
        }
        key_data.ctx.stopPropagation();
    }
    if (key_data.key.matches('d', .{ .ctrl = true })) {
        Debug.dumpToFile(element.context.?.window, "debugWindow.txt") catch {};
    }
}

pub fn schemeFn(app: *App) void {
    if (global.settings.scheme == .system) {
        global.settings.updateSystemScheme(app.scheme orelse return);
        app.window.requestDraw();
    }
}

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    var app = try App.create(alloc, .{
        .root = .{
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
            },
        },
        .schemeFn = schemeFn,
    });
    defer app.destroy();

    try global.init(alloc, &app.context);
    defer global.deinit();

    const settings = global.settings;

    settings.load("./settings/") catch {
        log.warn("Using default settings", .{});
    };

    settings.watch(&app.loop.loop);

    try app.root().addEventListener(.key_press, keyPressFn);

    // const cwd = std.fs.cwd();
    // var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    // const cwd_path = try cwd.realpath(".", &path_buf);
    //
    // var worktree = try Worktree.create(cwd_path, alloc);
    // defer worktree.destroy();
    //
    // try worktree.initial_scan();
    //
    // const file_tree = try FileTree.create(alloc, worktree);
    // defer file_tree.destroy(alloc);
    //
    // try app.window.root.addChild(file_tree.getElement());

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
