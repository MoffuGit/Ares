const std = @import("std");
const vaxis = @import("vaxis");
const lib = @import("../../lib.zig");
const global = @import("../../global.zig");

const Element = lib.Element;
const Buffer = lib.Buffer;
const Workspace = lib.Workspace;
const Context = lib.App.Context;
const Portal = @import("../primitives/Portal.zig");
const Box = Element.Box;
const AnimationPkg = Element.Animation;
const Allocator = std.mem.Allocator;

const Dialog = @This();

const OpacityAnim = AnimationPkg.Animation(f32);

alloc: Allocator,
box: *Box,
portal: *Portal,
ctx: *Context,
opacity: f32 = 0.0,
opacity_anim: OpacityAnim,

const Options = struct {
    portal: Portal.Options = .{},
    box: Box.Options = .{},
    style: Element.Style = .{},
};

fn lerpF32(start: f32, end: f32, progress: f32) f32 {
    return start + (end - start) * progress;
}

fn onOpacityUpdate(userdata: ?*anyopaque, state: f32, ctx: *Context) void {
    const self: *Dialog = @ptrCast(@alignCast(userdata orelse return));
    // if (self.opacity_anim.end == 0.0) {
    //     if (self.box.border) |*border| {
    //         border.color = border.color.setAlpha(0);
    //     }
    // }
    self.opacity = state;
    self.box.opacity = state;
    // self.box.bg = self.box.bg.setAlpha(state);
    ctx.requestDraw();
}

fn onCloseComplete(userdata: ?*anyopaque, _: *Context) void {
    const self: *Dialog = @ptrCast(@alignCast(userdata orelse return));
    self.portal.element.elem().hide();
}

pub fn create(alloc: Allocator, ctx: *Context, opts: Options) !*Dialog {
    var portal_opts = opts.portal;
    portal_opts.parent = ctx.app.root();

    const portal = try Portal.create(alloc, portal_opts);
    errdefer portal.destroy();

    const box = try Box.init(alloc, opts.box);
    errdefer box.deinit(alloc);

    try portal.element.childs(.{&box.element});

    const dialog = try alloc.create(Dialog);
    errdefer alloc.destroy(dialog);

    dialog.* = .{
        .alloc = alloc,
        .box = box,
        .portal = portal,
        .ctx = ctx,
        .opacity_anim = OpacityAnim.init(.{
            .start = 0.0,
            .end = 1.0,
            .duration_us = 100_000,
            .updateFn = lerpF32,
            .callback = onOpacityUpdate,
            .userdata = dialog,
            .easing = .ease_out_expo,
        }),
    };

    dialog.portal.element.elem().hide();

    return dialog;
}

pub fn toggleShow(self: *Dialog) void {
    const elem = self.portal.element.elem();
    self.opacity_anim.cancel();

    if (elem.visible) {
        self.opacity_anim.start = self.opacity;
        self.opacity_anim.end = 0.0;
        self.opacity_anim.on_complete = onCloseComplete;
        self.opacity_anim.play(self.ctx);
    } else {
        elem.show();
        self.opacity_anim.start = self.opacity;
        self.opacity_anim.end = 1.0;
        self.opacity_anim.on_complete = null;
        self.opacity_anim.play(self.ctx);
    }
}

pub fn destroy(self: *Dialog) void {
    self.opacity_anim.cancel();
    self.portal.destroy();
    self.box.deinit(self.alloc);
    self.alloc.destroy(self);
}
