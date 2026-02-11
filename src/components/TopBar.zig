const std = @import("std");
const lib = @import("../lib.zig");
const global = @import("../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Settings = @import("../settings/mod.zig");

const TopBar = @This();

element: *Element,
settings: *Settings,
workspace: *Workspace,

pub fn create(alloc: std.mem.Allocator, workspace: *Workspace) !*TopBar {
    const self = try alloc.create(TopBar);
    errdefer alloc.destroy(self);

    const element = try alloc.create(Element);
    errdefer alloc.destroy(element);

    element.* = Element.init(alloc, .{
        .id = "top-bar",
        .drawFn = draw,
        .userdata = self,
        .style = .{
            .width = .stretch,
            .height = .{ .point = 2 },
            .margin = .{ .horizontal = .{ .point = 1 } },
            .flex_shrink = 0,
        },
    });

    self.* = .{
        .workspace = workspace,
        .element = element,
        .settings = global.settings,
    };

    return self;
}

pub fn destroy(self: *TopBar, alloc: std.mem.Allocator) void {
    self.element.deinit();
    alloc.destroy(self.element);
    alloc.destroy(self);
}

pub fn getElement(self: *TopBar) *Element {
    return self.element;
}

fn draw(element: *Element, buffer: *Buffer) void {
    const self: *TopBar = @ptrCast(@alignCast(element.userdata));
    element.fill(buffer, .{ .style = .{
        .bg = self.settings.theme.bg,
    } });

    if (self.workspace.project) |project| {
        if (project.selected_entry) |id| {
            const snapshot = &project.worktree.snapshot;

            if (snapshot.getEntryById(id)) |entry| {
                if (snapshot.getPathById(id)) |path| {
                    const file_color = self.settings.theme.getFileTypeColor(entry.file_type.toString());

                    const fg = self.settings.theme.fg.setAlpha(0.78);

                    _ = element.print(
                        buffer,
                        &.{
                            .{ .text = "▎", .style = .{ .fg = file_color } },
                            .{ .text = path, .style = .{ .fg = fg } },
                        },
                        .{},
                    );
                }
            }
        }
    }
    buffer.fillRect(element.layout.left -| 1, element.layout.top + 1, element.layout.width + 2, 1, .{ .char = .{
        .grapheme = "▀",
    }, .style = .{ .bg = self.settings.theme.mutedBg, .fg = self.settings.theme.bg } });
}
