const std = @import("std");
const ares = @import("ares");

const App = ares.App;
const Element = ares.Element;
const Animation = Element.Animation;
const AppContext = Element.AppContext;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const BoxState = struct {
    scale: f32,
    r: f32,
    g: f32,
    b: f32,

    fn lerp(start: BoxState, end: BoxState, t: f32) BoxState {
        return .{
            .scale = start.scale + (end.scale - start.scale) * t,
            .r = start.r + (end.r - start.r) * t,
            .g = start.g + (end.g - start.g) * t,
            .b = start.b + (end.b - start.b) * t,
        };
    }
};

const base_color: BoxState = .{ .scale = 1.0, .r = 0x44, .g = 0x88, .b = 0xff };
const hover_color: BoxState = .{ .scale = 1.5, .r = 0x66, .g = 0xcc, .b = 0xff };

const BoxData = struct {
    base_radius: f32,
    state: BoxState = base_color,
    hover_anim: Animation.Animation(BoxState),
    unhover_anim: Animation.Animation(BoxState),

    fn animCallback(userdata: ?*anyopaque, state: BoxState, ctx: *AppContext) void {
        const self: *BoxData = @ptrCast(@alignCast(userdata orelse return));
        self.state = state;
        ctx.requestDraw();
    }
};

pub fn keyPressFn(element: *Element, data: Element.EventData) void {
    const key_data = data.key_press;
    if (key_data.key.matches('c', .{ .ctrl = true })) {
        if (element.context) |app_ctx| {
            app_ctx.stopApp() catch {};
        }
        key_data.ctx.stopPropagation();
    }
    if (key_data.key.matches('d', .{ .ctrl = true })) {
        ares.Debug.dumpToFile(element.context.?.window, "debugWindow.txt") catch {};
    }
}

pub fn drawRoundedBox(element: *Element, buffer: *ares.Buffer) void {
    const box_data: *BoxData = @ptrCast(@alignCast(element.userdata));
    const state = box_data.state;
    const radius: f32 = box_data.base_radius * state.scale;
    element.fillRounded(buffer, .{ .rgb = .{
        @intFromFloat(state.r),
        @intFromFloat(state.g),
        @intFromFloat(state.b),
    } }, radius);
}

pub fn hitRoundedBox(element: *Element, hit_grid: *ares.HitGrid) void {
    const box_data: *BoxData = @ptrCast(@alignCast(element.userdata));
    element.hitRounded(hit_grid, box_data.base_radius);
}

const GradientData = struct {
    stops: []const Element.ColorStop,
    direction: Element.GradientDirection,
    char: []const u8,
};

const gradient_examples = [_]GradientData{
    .{
        .stops = &.{
            .{ .position = 0.0, .color = .{ .rgba = .{ 255, 0, 0, 255 } } },
            .{ .position = 1.0, .color = .{ .rgba = .{ 0, 0, 255, 255 } } },
        },
        .direction = .horizontal,
        .char = "▐",
    },
    .{
        .stops = &.{
            .{ .position = 0.0, .color = .{ .rgba = .{ 255, 100, 0, 255 } } },
            .{ .position = 0.5, .color = .{ .rgba = .{ 255, 0, 100, 255 } } },
            .{ .position = 1.0, .color = .{ .rgba = .{ 100, 0, 255, 255 } } },
        },
        .direction = .vertical,
        .char = "▄",
    },
    .{
        .stops = &.{
            .{ .position = 0.0, .color = .{ .rgba = .{ 0, 255, 100, 255 } } },
            .{ .position = 0.33, .color = .{ .rgba = .{ 0, 100, 255, 255 } } },
            .{ .position = 0.66, .color = .{ .rgba = .{ 255, 0, 200, 255 } } },
            .{ .position = 1.0, .color = .{ .rgba = .{ 255, 200, 0, 255 } } },
        },
        .direction = .horizontal,
        .char = "▐",
    },
    .{
        .stops = &.{
            .{ .position = 0.0, .color = .{ .rgba = .{ 20, 20, 40, 255 } } },
            .{ .position = 1.0, .color = .{ .rgba = .{ 80, 120, 200, 255 } } },
        },
        .direction = .vertical,
        .char = "▄",
    },
};

pub fn drawGradientBox(element: *Element, buffer: *ares.Buffer) void {
    const data: *const GradientData = @ptrCast(@alignCast(element.userdata));
    element.fillGradient(buffer, data.stops, data.direction, data.char);
}

pub fn onMouseEnter(element: *Element, _: Element.EventData) void {
    const box_data: *BoxData = @ptrCast(@alignCast(element.userdata));
    const ctx = element.context orelse return;
    box_data.unhover_anim.cancel();
    box_data.hover_anim.start = box_data.state;
    box_data.hover_anim.play(ctx);
}

pub fn onMouseLeave(element: *Element, _: Element.EventData) void {
    const box_data: *BoxData = @ptrCast(@alignCast(element.userdata));
    const ctx = element.context orelse return;
    box_data.hover_anim.cancel();
    box_data.unhover_anim.start = box_data.state;
    box_data.unhover_anim.play(ctx);
}

pub fn main() !void {
    var gpa: GPA = .{};
    defer _ = gpa.deinit();

    const alloc = gpa.allocator();

    var app = try App.create(alloc, .{
        .root = .{
            .style = .{
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
                .justify_content = .center,
                .align_items = .center,
                .flex_direction = .column,
                .gap = .{ .row = .{ .point = 2 } },
            },
        },
    });
    defer app.destroy();

    try app.root().addEventListener(.key_press, keyPressFn);

    var boxes_row = Element.init(alloc, .{
        .style = .{
            .flex_direction = .row,
            .gap = .{ .column = .{ .point = 2 } },
        },
    });
    defer boxes_row.deinit();
    try app.root().addChild(&boxes_row);

    var box_data: [5]BoxData = undefined;
    var boxes: [5]Element = undefined;
    for (&boxes, &box_data, 4..) |*box, *data, radius| {
        data.* = .{
            .base_radius = @floatFromInt(radius),
            .state = base_color,
            .hover_anim = Animation.Animation(BoxState).init(.{
                .start = base_color,
                .end = hover_color,
                .duration_us = 150_000,
                .updateFn = BoxState.lerp,
                .callback = BoxData.animCallback,
                .userdata = data,
                .easing = .ease_out_cubic,
            }),
            .unhover_anim = Animation.Animation(BoxState).init(.{
                .start = hover_color,
                .end = base_color,
                .duration_us = 150_000,
                .updateFn = BoxState.lerp,
                .callback = BoxData.animCallback,
                .userdata = data,
                .easing = .ease_out_cubic,
            }),
        };
        box.* = Element.init(alloc, .{
            .style = .{
                .width = .{ .point = 20 },
                .height = .{ .point = 10 },
            },
            .drawFn = drawRoundedBox,
            .hitFn = hitRoundedBox,
            .userdata = data,
        });
        try box.addEventListener(.mouse_enter, onMouseEnter);
        try box.addEventListener(.mouse_leave, onMouseLeave);
        try boxes_row.addChild(box);
    }
    defer for (&box_data) |*data| {
        data.hover_anim.cancel();
        data.unhover_anim.cancel();
    };
    defer for (&boxes) |*box| box.deinit();

    var gradient_row = Element.init(alloc, .{
        .style = .{
            .flex_direction = .row,
            .gap = .{ .column = .{ .point = 2 } },
        },
    });
    defer gradient_row.deinit();
    try app.root().addChild(&gradient_row);

    var gradient_boxes: [gradient_examples.len]Element = undefined;
    for (&gradient_boxes, 0..) |*gbox, i| {
        gbox.* = Element.init(alloc, .{
            .style = .{
                .width = .{ .point = 30 },
                .height = .{ .point = 20 },
            },
            .drawFn = drawGradientBox,
            .userdata = @constCast(&gradient_examples[i]),
        });
        try gradient_row.addChild(gbox);
    }
    defer for (&gradient_boxes) |*gbox| gbox.deinit();

    app.run() catch |err| {
        std.log.err("App exit with an err: {}", .{err});
    };
}
