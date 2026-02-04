const std = @import("std");
const datastruct = @import("datastruct/mod.zig");
const log = std.log.scoped(.main);
const global = @import("global.zig");
const lib = @import("lib.zig");

const App = lib.App;
const Element = lib.Element;
const Buffer = lib.Buffer;
const worktreepkg = @import("worktree/mod.zig");
const Worktree = worktreepkg.Worktree;
const FileTree = worktreepkg.FileTree;

const GPA = std.heap.GeneralPurposeAllocator(.{});

//TODO:
//create structures for app userdata(workspace, worktree)
//add metadata to entries
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
//
//NOTE:
//another thing, it would be nice to store inside every Entry metadata from every file and directory,
//this could give you better events, things like, file got bigger or smaller, read them again,
//or more things to shod on the file tree, cool shit
//NOTE:
//every directory is collapsed by default,
//because of that out initla size is for every
//entry that is at the first level:
//src/file1
//src/file2
//src/directory1
//then, we can track when a directory gets open,
//to add more height to the scroll,
//we would draw only the element that can be in the outer view,
//but we should keep track of the size of all expanded directories and files
//probably we can iter over all worktree files and then
//only update in base of the snapshot version and entry snapshot version
//you only update the values that have a new snapshot value

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

    var worktree = try Worktree.create(
        cwd_path,
        alloc,
        &app.loop,
    );
    defer worktree.destroy();

    const file_tree = try FileTree.create(alloc, worktree);
    defer file_tree.destroy(alloc);

    try app.root().addEventListener(.key_press, keyPressFn);

    try app.window.root.addChild(file_tree.getElement());

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
