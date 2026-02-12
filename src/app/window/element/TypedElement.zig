const std = @import("std");
const Element = @import("mod.zig");
const AnimationPkg = @import("Animation.zig");
const BaseAnimation = AnimationPkg.BaseAnimation;
const Buffer = @import("../../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const Easing = @import("Easing.zig").Type;
const apppkg = @import("../../mod.zig");
const Context = apppkg.Context;
const Allocator = std.mem.Allocator;

//NOTE:
//i hate calling setSomething after creating an element,
//and there is no need to store the owner in here, we should
//be capable of storing the owner pointer as the userdata
//for that we should create a comptime Options struct,
//it would provide the same options that Element Options, only that
//they would be aware of the Owner Type, then we should make them type erased,
pub fn TypedElement(comptime Owner: type) type {
    return struct {
        const Self = @This();

        base: Element,
        owner: *Owner,

        pub fn init(alloc: Allocator, owner: *Owner, opts: Element.Options) Self {
            var o = opts;
            o.userdata = null;
            o.drawFn = null;
            o.hitFn = null;
            o.updateFn = null;
            o.beforeDrawFn = null;
            o.afterDrawFn = null;
            o.beforeHitFn = null;
            o.afterHitFn = null;

            return .{
                .base = Element.init(alloc, o),
                .owner = owner,
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        pub inline fn elem(self: *Self) *Element {
            return &self.base;
        }

        // ---- Typed callback setters ----

        pub fn setDrawFn(self: *Self, comptime cb: *const fn (*Owner, *Element, *Buffer) void) void {
            self.base.drawFn = struct {
                fn wrapper(element: *Element, buffer: *Buffer) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, buffer);
                }
            }.wrapper;
        }

        pub fn setBeforeDrawFn(self: *Self, comptime cb: *const fn (*Owner, *Element, *Buffer) void) void {
            self.base.beforeDrawFn = struct {
                fn wrapper(element: *Element, buffer: *Buffer) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, buffer);
                }
            }.wrapper;
        }

        pub fn setAfterDrawFn(self: *Self, comptime cb: *const fn (*Owner, *Element, *Buffer) void) void {
            self.base.afterDrawFn = struct {
                fn wrapper(element: *Element, buffer: *Buffer) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, buffer);
                }
            }.wrapper;
        }

        pub fn setHitFn(self: *Self, comptime cb: *const fn (*Owner, *Element, *HitGrid) void) void {
            self.base.hitFn = struct {
                fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, hit_grid);
                }
            }.wrapper;
        }

        pub fn setBeforeHitFn(self: *Self, comptime cb: *const fn (*Owner, *Element, *HitGrid) void) void {
            self.base.beforeHitFn = struct {
                fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, hit_grid);
                }
            }.wrapper;
        }

        pub fn setAfterHitFn(self: *Self, comptime cb: *const fn (*Owner, *Element, *HitGrid) void) void {
            self.base.afterHitFn = struct {
                fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, hit_grid);
                }
            }.wrapper;
        }

        pub fn setUpdateFn(self: *Self, comptime cb: *const fn (*Owner, *Element) void) void {
            self.base.updateFn = struct {
                fn wrapper(element: *Element) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element);
                }
            }.wrapper;
        }

        // ---- Event listeners ----

        pub fn on(self: *Self, event_type: Element.EventType, comptime cb: *const fn (*Owner, *Element, Element.EventData) void) !void {
            try self.base.addEventListener(event_type, struct {
                fn wrapper(element: *Element, data: Element.EventData) void {
                    const te: *Self = @fieldParentPtr("base", element);
                    cb(te.owner, element, data);
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
