const std = @import("std");
const ltf = @import("log_to_file");
const datastruct = @import("datastruct/mod.zig");
const log = std.log.scoped(.main);
const global = @import("global.zig");
const lib = @import("lib.zig");

pub const std_options: std.Options = .{
    .logFn = ltf.log_to_file,
};

const App = lib.App;
const Element = lib.Element;
const Buffer = lib.Buffer;
const Resolver = @import("keymaps/Resolver.zig");
const Workspace = @import("workspace/mod.zig").Workspace;

const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn keyPressFn(_: *Element, data: Element.ElementEvent) void {
    const key = data.event.key_press;
    if (key.matches('c', .{ .ctrl = true })) {
        if (data.element.context) |ctx| {
            ctx.stop() catch {};
        }
        data.ctx.stopPropagation();
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

    // Clear log file from previous run.
    if (std.fs.cwd().openDir("logs", .{})) |dir| {
        dir.deleteFile("ares.log") catch {};
    } else |_| {}

    var app = try App.create(alloc, .{});
    defer app.destroy();

    try app.root().addEventListener(.key_press, Element, app.root(), keyPressFn);

    try global.init(alloc, &app.context);
    defer global.deinit();

    const settings = global.settings;

    settings.load("./settings/") catch {
        log.warn("Using default settings", .{});
    };

    const resolver = try Resolver.create(alloc, app);
    defer resolver.destroy();

    const cwd = std.fs.cwd();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = try cwd.realpath(".", &path_buf);

    var workspace = try Workspace.create(alloc, &app.context);
    defer workspace.destroy();

    try workspace.openProject(cwd_path);

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
