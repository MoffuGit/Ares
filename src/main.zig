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
const Workspace = @import("workspace/mod.zig").Workspace;

const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn keyPressFn(_: *Element, data: Element.EventData) void {
    const key_data = data.key_press;
    if (key_data.key.matches('c', .{ .ctrl = true })) {
        if (key_data.element.context) |ctx| {
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

//NOTE:
//Command palette:
//  Keymaps settings,
//  Trie,
//  Input,
//  Resolver,
//
//EditorView
//  rowLines,
//  Input
//
//TextInput
//  GapBuffer,
//
//because of that the first thing i should do is impl the
//text input, once this part is done i can choose if i do the EditorView
//first or the Command Palette, i think i will go with the Command Palette
//because is more fresh on my head, after the input i would to the trie,
//the keymaps settings and the resolver,
//the resolver wuld connect to the workspace and this let me handle the keympas,
//and because i havbe connected the command palette to the workspace, i can access al the
//Actions that my app have and show them as part of the Command palette,
//the trie would help for searching as well,
//
//then i could work with the Editor View, i would work more on the view more than other thing
//because is not there that much to do
//
//and then i can work on my floatinf file tree, because by now i would have my
//text input and my trie, i can add search into the entries

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
