const std = @import("std");
const Element = @import("mod.zig");
const Buffer = @import("../../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const Style = @import("Style.zig");
const Allocator = std.mem.Allocator;

pub fn TypedElement(comptime Owner: type) type {
    return struct {
        const Self = @This();

        base: Element,

        pub const Callbacks = struct {
            drawFn: ?*const fn (*Owner, *Element, *Buffer) void = null,
            beforeDrawFn: ?*const fn (*Owner, *Element, *Buffer) void = null,
            afterDrawFn: ?*const fn (*Owner, *Element, *Buffer) void = null,
            hitFn: ?*const fn (*Owner, *Element, *HitGrid) void = null,
            beforeHitFn: ?*const fn (*Owner, *Element, *HitGrid) void = null,
            afterHitFn: ?*const fn (*Owner, *Element, *HitGrid) void = null,
        };

        pub const Options = struct {
            num: ?u64 = null,
            kind: Element.Kind = .raw,
            zIndex: usize = 0,
            style: Style = .{},
        };

        pub fn init(alloc: Allocator, owner: *Owner, comptime cbs: Callbacks, opts: Options) Self {
            return .{
                .base = Element.init(alloc, .{
                    .num = opts.num,
                    .kind = opts.kind,
                    .zIndex = opts.zIndex,
                    .style = opts.style,
                    .userdata = owner,
                    .drawFn = if (cbs.drawFn) |cb| (struct {
                        fn wrapper(element: *Element, buffer: *Buffer) void {
                            @call(
                                .always_inline,
                                cb,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, buffer },
                            );
                        }
                    }.wrapper) else null,
                    .beforeDrawFn = if (cbs.beforeDrawFn) |cb| (struct {
                        fn wrapper(element: *Element, buffer: *Buffer) void {
                            @call(
                                .always_inline,
                                cb,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, buffer },
                            );
                        }
                    }.wrapper) else null,
                    .afterDrawFn = if (cbs.afterDrawFn) |cb| (struct {
                        fn wrapper(element: *Element, buffer: *Buffer) void {
                            @call(
                                .always_inline,
                                cb,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, buffer },
                            );
                        }
                    }.wrapper) else null,
                    .hitFn = if (cbs.hitFn) |cb| (struct {
                        fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                            @call(
                                .always_inline,
                                cb,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, hit_grid },
                            );
                        }
                    }.wrapper) else null,
                    .beforeHitFn = if (cbs.beforeHitFn) |cb| (struct {
                        fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                            @call(
                                .always_inline,
                                cb,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, hit_grid },
                            );
                        }
                    }.wrapper) else null,
                    .afterHitFn = if (cbs.afterHitFn) |cb| (struct {
                        fn wrapper(element: *Element, hit_grid: *HitGrid) void {
                            @call(
                                .always_inline,
                                cb,
                                .{ @as(*Owner, @ptrCast(@alignCast(element.userdata orelse return))), element, hit_grid },
                            );
                        }
                    }.wrapper) else null,
                }),
            };
        }

        pub fn deinit(self: *Self) void {
            self.base.deinit();
        }

        pub inline fn elem(self: *Self) *Element {
            return &self.base;
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
    };
}
