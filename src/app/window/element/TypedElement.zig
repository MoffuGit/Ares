const std = @import("std");
const Element = @import("mod.zig");
const AnimationPkg = @import("Animation.zig");
const BaseAnimation = AnimationPkg.BaseAnimation;
const Buffer = @import("../../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const Style = @import("Style.zig");
const Easing = @import("Easing.zig").Type;
const apppkg = @import("../../mod.zig");
const Context = apppkg.Context;
const Allocator = std.mem.Allocator;

pub fn TypedElement(comptime Owner: type) type {
    return struct {
        const Self = @This();

        base: Element,

        pub const Options = struct {
            id: ?[]const u8 = null,
            visible: bool = true,
            zIndex: usize = 0,
            style: Style = .{},
            drawFn: ?*const fn (*Owner, *Element, *Buffer) void = null,
            beforeDrawFn: ?*const fn (*Owner, *Element, *Buffer) void = null,
            afterDrawFn: ?*const fn (*Owner, *Element, *Buffer) void = null,
            hitFn: ?*const fn (*Owner, *Element, *HitGrid) void = null,
            beforeHitFn: ?*const fn (*Owner, *Element, *HitGrid) void = null,
            afterHitFn: ?*const fn (*Owner, *Element, *HitGrid) void = null,
            updateFn: ?*const fn (*Owner, *Element) void = null,
        };

        pub fn init(alloc: Allocator, owner: *Owner, comptime opts: Options) Self {
            return .{
                .base = Element.init(alloc, .{
                    .id = opts.id,
                    .visible = opts.visible,
                    .zIndex = opts.zIndex,
                    .style = opts.style,
                    .userdata = owner,
                    .drawFn = if (opts.drawFn) |draw| struct {
                        fn wrapper(element: *Element, buffer: *Buffer) void {
                            @call(
                                .always_inline,
                                draw,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, buffer },
                            );
                        }
                    }.wrapper else null,
                    .beforeDrawFn = if (opts.beforeDrawFn) |_| struct {
                        fn wrapper(element: *Element, buffer: *Buffer) void {
                            const self: *Owner = @ptrCast(@alignCast(element.userdata));
                            opts.beforeDrawFn.?(self, element, buffer);
                        }
                    }.wrapper else null,
                    .afterDrawFn = if (opts.afterDrawFn) |_| struct {
                        fn wrapper(element: *Element, buffer: *Buffer) void {
                            const self: *Owner = @ptrCast(@alignCast(element.userdata));
                            opts.afterDrawFn.?(self, element, buffer);
                        }
                    }.wrapper else null,
                    .hitFn = if (opts.hitFn) |_| struct {
                        fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                            const self: *Owner = @ptrCast(@alignCast(element.userdata));
                            opts.hitFn.?(self, element, hit_grid);
                        }
                    }.wrapper else null,
                    .beforeHitFn = if (opts.beforeHitFn) |_| struct {
                        fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                            const self: *Owner = @ptrCast(@alignCast(element.userdata));
                            opts.beforeHitFn.?(self, element, hit_grid);
                        }
                    }.wrapper else null,
                    .afterHitFn = if (opts.afterHitFn) |_| struct {
                        fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                            const self: *Owner = @ptrCast(@alignCast(element.userdata));
                            opts.afterHitFn.?(self, element, hit_grid);
                        }
                    }.wrapper else null,
                    .updateFn = if (opts.updateFn) |_| struct {
                        fn wrapper(element: *Element) void {
                            const self: *Owner = @ptrCast(@alignCast(element.userdata));
                            opts.updateFn.?(self, element);
                        }
                    }.wrapper else null,
                }),
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        pub inline fn elem(self: *Self) *Element {
            return &self.base;
        }

        // ---- Event listeners ----

        pub fn on(self: *Self, event_type: Element.EventType, comptime cb: *const fn (*Owner, *Element, Element.EventData) void) !void {
            try self.base.addEventListener(event_type, struct {
                fn wrapper(element: *Element, data: Element.EventData) void {
                    const o: *Owner = @ptrCast(@alignCast(element.userdata));
                    cb(o, element, data);
                }
            }.wrapper);
        }

        // ---- Children ----

        pub fn childs(self: *Self, children: anytype) !void {
            inline for (children) |child| {
                const ptr = if (@hasDecl(@TypeOf(child.*), "elem"))
                    child.elem()
                else
                    child;
                try self.base.addChild(ptr);
            }
        }

        // ---- Typed Animation ----

        pub fn Anim(comptime State: type) type {
            return TypedAnimation(Owner, State);
        }
    };
}

pub fn TypedAnimation(comptime Owner: type, comptime State: type) type {
    return struct {
        const AnimSelf = @This();
        const Inner = AnimationPkg.Animation(State);

        pub const UpdateFn = *const fn (start: State, end: State, progress: f32) State;

        inner: Inner,

        pub const Opts = struct {
            start: State,
            end: State,
            duration_us: i64,
            updateFn: UpdateFn,
            easing: Easing = .linear,
            repeat: bool = false,
            tick_interval_us: i64 = 16_667,
        };

        pub fn init(
            owner: *Owner,
            comptime cb: *const fn (*Owner, State, *Context) void,
            opts: Opts,
        ) AnimSelf {
            return initWithComplete(owner, cb, null, opts);
        }

        pub fn initWithComplete(
            owner: *Owner,
            comptime cb: *const fn (*Owner, State, *Context) void,
            comptime on_complete: ?*const fn (*Owner, *Context) void,
            opts: Opts,
        ) AnimSelf {
            return .{
                .inner = Inner.init(.{
                    .start = opts.start,
                    .end = opts.end,
                    .duration_us = opts.duration_us,
                    .updateFn = opts.updateFn,
                    .easing = opts.easing,
                    .repeat = opts.repeat,
                    .tick_interval_us = opts.tick_interval_us,
                    .userdata = owner,
                    .callback = struct {
                        fn wrapper(userdata: ?*anyopaque, state: State, ctx: *Context) void {
                            const o: *Owner = @ptrCast(@alignCast(userdata orelse return));
                            cb(o, state, ctx);
                        }
                    }.wrapper,
                    .on_complete = if (on_complete) |complete_cb| struct {
                        fn wrapper(userdata: ?*anyopaque, ctx: *Context) void {
                            const o: *Owner = @ptrCast(@alignCast(userdata orelse return));
                            complete_cb(o, ctx);
                        }
                    }.wrapper else null,
                }),
            };
        }

        pub fn play(self: *AnimSelf, ctx: *Context) void {
            self.inner.play(ctx);
        }

        pub fn cancel(self: *AnimSelf) void {
            self.inner.cancel();
        }

        pub fn pause(self: *AnimSelf) void {
            self.inner.pause();
        }

        pub fn @"resume"(self: *AnimSelf) void {
            self.inner.@"resume"();
        }
    };
}
