const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../lib.zig");
const global = @import("../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Context = lib.App.Context;
const Settings = @import("../settings/mod.zig");
const Animation = Element.Animation;

const TopBar = @This();

const ColorAnimation = Animation.Animation(vaxis.Color);

element: *Element,
settings: *Settings,
workspace: *Workspace,
entry_color: ?vaxis.Color = null,
entry_id: ?u64 = null,
color_anim: ColorAnimation,

fn lerpColor(a: vaxis.Color, b: vaxis.Color, t: f32) vaxis.Color {
    const a_rgba = a.rgba;
    const b_rgba = b.rgba;
    var new: [4]u8 = undefined;
    inline for (0..3) |i| {
        const a_f: f32 = @as(f32, @floatFromInt(a_rgba[i])) / 255.0;
        const b_f: f32 = @as(f32, @floatFromInt(b_rgba[i])) / 255.0;
        new[i] = @intFromFloat((a_f + (b_f - a_f) * t) * 255.0);
    }
    new[3] = a_rgba[3];

    return .{ .rgba = new };
}

fn colorCallback(userdata: ?*anyopaque, state: vaxis.Color, ctx: *Context) void {
    const self: *TopBar = @ptrCast(@alignCast(userdata orelse return));
    self.entry_color = state;
    ctx.requestDraw();
}

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
        .color_anim = ColorAnimation.init(
            .{
                .userdata = self,
                .start = .default,
                .end = .default,
                .duration_us = 150_000,
                .updateFn = lerpColor,
                .callback = colorCallback,
                .easing = .linear,
            },
        ),
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

                    if (self.entry_id != entry.id) {
                        if (self.entry_color) |old| {
                            if (!old.eql(file_color)) {
                                self.color_anim.cancel();
                                self.color_anim.start = old;
                                self.color_anim.end = file_color;
                                self.color_anim.play(element.context.?);
                            }
                        } else {
                            self.entry_color = file_color;
                        }
                        self.entry_id = entry.id;
                    }

                    const fg = self.settings.theme.fg.setAlpha(0.78);

                    _ = element.print(
                        buffer,
                        &.{
                            .{ .text = "▎", .style = .{ .fg = self.entry_color.? } },
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
