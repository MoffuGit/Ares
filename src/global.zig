const std = @import("std");

const Settings = @import("settings/mod.zig");
const Allocator = std.mem.Allocator;
const Context = @import("app/mod.zig").Context;
const FileType = @import("worktree/mod.zig").FileType;

pub const xev = @import("xev").Dynamic;

pub const Mode = enum {
    normal,
    insert,
    visual,
};

pub const file_icons = std.EnumArray(FileType, []const u8).init(.{
    .zig = " ",
    .c = " ",
    .cpp = " ",
    .h = " ",
    .py = " ",
    .js = " ",
    .ts = " ",
    .json = " ",
    .xml = "󰗀 ",
    .yaml = " ",
    .toml = " ",
    .md = "󰈙 ",
    .txt = "󰈙 ",
    .html = " ",
    .css = " ",
    .sh = " ",
    .go = " ",
    .rs = " ",
    .java = " ",
    .rb = " ",
    .lua = " ",
    .makefile = " ",
    .dockerfile = "󰡨 ",
    .gitignore = " ",
    .license = " ",
    .unknown = " ",
});

pub var mode: Mode = .normal;
pub var settings: *Settings = undefined;

pub fn init(alloc: Allocator, context: *Context) !void {
    settings = try Settings.create(alloc, context);
}

pub fn deinit() void {
    settings.destroy();
}
