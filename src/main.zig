const std = @import("std");
const datastruct = @import("datastruct/mod.zig");
const log = std.log.scoped(.main);
const global = @import("global.zig");
const lib = @import("lib.zig");

const App = lib.App;
const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = @import("workspace/mod.zig").Workspace;
const FileTree = @import("components/app/FileTree.zig");

const GPA = std.heap.GeneralPurposeAllocator(.{});

//TODO:
//create structures for app userdata(workspace, worktree)
//update the filetree
//
//NOTE:
//about the app context userdata, i think is a good place to add my Editor state struct
//it should contains things like workspaces, tabs, splits, code editors,
//i need to think what information it will have every struct and what's going to be his view,
//i think the one i can think well what's going to contains the the workspace, the other ones
//i will think them latter, they are not that imporant right now
//the workspace, the file tree sidebar and floating file tree with serach can be the first parts to get
//impl because there are almost done,

pub fn keyPressFn(element: *Element, data: Element.EventData) void {
    const key_data = data.key_press;
    if (key_data.key.matches('c', .{ .ctrl = true })) {
        if (element.context) |ctx| {
            ctx.stop() catch {};
        }
        key_data.ctx.stopPropagation();
    }
}

pub fn schemeFn(app: *App) void {
    if (global.settings.scheme == .system) {
        global.settings.updateSystemScheme(app.scheme orelse return);
        app.window.requestDraw();
    }
}

pub fn drawFn(element: *Element, buffer: *Buffer) void {
    element.fill(buffer, .{ .style = .{ .bg = global.settings.theme.bg } });
}

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    var app = try App.create(alloc, .{ .root = .{ .drawFn = drawFn } });
    defer app.destroy();

    try global.init(alloc, &app.context);
    defer global.deinit();

    const settings = global.settings;

    settings.load("./settings/") catch {
        log.warn("Using default settings", .{});
    };

    const cwd = std.fs.cwd();
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_path = try cwd.realpath(".", &path_buf);

    var workspace = try Workspace.create(alloc, &app.context);
    defer workspace.destroy();

    try workspace.openProject(cwd_path);

    const file_tree = try FileTree.create(alloc, workspace.project.?.worktree);
    defer file_tree.destroy(alloc);

    try app.root().addEventListener(.key_press, keyPressFn);

    try app.window.root.addChild(file_tree.getElement());

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
