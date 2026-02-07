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
            .width = .{ .percent = 100 },
            .height = .{ .point = 2 },
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
    element.fill(buffer, .{ .style = .{ .bg = self.settings.theme.bg } });

    if (self.workspace.project) |project| {
        const root_name = std.fs.path.basename(project.worktree.abs_path);
        _ = element.print(buffer, &.{.{ .text = root_name, .style = .{ .fg = self.settings.theme.fg } }}, .{ .text_align = .center });

        if (project.selected_entry) |id| {
            var snapshot = project.worktree.snapshot;

            snapshot.mutex.lock();
            defer snapshot.mutex.unlock();

            if (snapshot.getPathById(id)) |path| {
                var fg = self.settings.theme.fg.rgba;
                fg[3] = 200;
                _ = element.print(buffer, &.{.{ .text = path, .style = .{ .fg = .{ .rgba = fg } } }}, .{ .col_offset = 1 });
            }
        }
    }
}
