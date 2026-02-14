const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../lib.zig");
const global = @import("../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Context = lib.App.Context;
const Settings = @import("../settings/mod.zig");

const TopBar = @This();

const TE = Element.TypedElement(TopBar);
const ColorAnim = TE.Anim(vaxis.Color);

element: TE,
settings: *Settings,
workspace: *Workspace,
entry_color: ?vaxis.Color = null,
entry_id: ?u64 = null,
color_anim: ColorAnim,

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

fn colorCallback(self: *TopBar, state: vaxis.Color, ctx: *Context) void {
    self.entry_color = state;
    ctx.requestDraw();
}

pub fn create(alloc: std.mem.Allocator, workspace: *Workspace) !*TopBar {
    const self = try alloc.create(TopBar);
    errdefer alloc.destroy(self);

    self.* = .{
        .workspace = workspace,
        .settings = global.settings,
        .element = TE.init(alloc, self, .{
            .drawFn = draw,
        }, .{
            .id = "top-bar",
            .style = .{
                .width = .stretch,
                .height = .{ .point = 2 },
                .margin = .{ .horizontal = .{ .point = 1 } },
                .flex_shrink = 0,
            },
        }),
        .color_anim = ColorAnim.init(self, colorCallback, .{
            .start = .default,
            .end = .default,
            .duration_us = 100_000,
            .updateFn = lerpColor,
            .easing = .linear,
        }),
    };

    return self;
}

pub fn destroy(self: *TopBar, alloc: std.mem.Allocator) void {
    self.element.deinit();
    alloc.destroy(self);
}

fn draw(self: *TopBar, element: *Element, buffer: *Buffer) void {
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
                                self.color_anim.inner.start = old;
                                self.color_anim.inner.end = file_color;
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
