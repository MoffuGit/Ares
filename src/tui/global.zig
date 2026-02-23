const std = @import("std");
const core = @import("core");
const FileType = core.worktree.FileType;

pub const file_icons = std.EnumArray(FileType, []const u8).init(.{
    .zig = " ",
    .c = " ",
    .cpp = " ",
    .h = " ",
    .py = " ",
    .js = " ",
    .ts = " ",
    .json = " ",
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

pub var engine: *core.Engine = undefined;
