const std = @import("std");
const vaxis = @import("vaxis");
const messagepkg = @import("../message.zig");
const eventpkg = @import("../event.zig");

pub var element_counter: std.atomic.Value(u64) = .init(0);

pub const Animation = @import("Animation.zig");
pub const Timer = @import("Timer.zig");
pub const Style = @import("Style.zig");
pub const Node = @import("Node.zig");

const Buffer = @import("../../Buffer.zig");
const HitGrid = @import("../HitGrid.zig");
const apppkg = @import("../../mod.zig");
const Context = apppkg.Context;
const EventContext = @import("../EventContext.zig");
const Event = eventpkg.Event;
const Mouse = eventpkg.Mouse;
const Allocator = std.mem.Allocator;
const Childrens = @import("Childrens.zig");

pub const Callback = *const fn (element: *Element, data: EventData) void;
pub const CallbackList = std.ArrayListUnmanaged(Callback);
pub const EventListeners = std.EnumArray(EventType, CallbackList);
pub const DrawFn = *const fn (element: *Element, buffer: *Buffer) void;
pub const HitFn = *const fn (element: *Element, hit_grid: *HitGrid) void;
pub const UpdateFn = *const fn (element: *Element) void;

pub const Layout = struct {
    left: u16 = 0,
    top: u16 = 0,
    right: u16 = 0,
    bottom: u16 = 0,
    width: u16 = 0,
    height: u16 = 0,
    direction: Node.yoga.YGDirection = Node.yoga.YGDirectionInherit,
    had_overflow: bool = false,
    margin: Edges = .{},
    border: Edges = .{},
    padding: Edges = .{},

    pub const Edges = struct {
        left: u16 = 0,
        top: u16 = 0,
        right: u16 = 0,
        bottom: u16 = 0,
    };
};

pub const EventType = enum {
    remove,
    key_press,
    key_release,
    focus,
    blur,
    mouse_down,
    mouse_up,
    click,
    mouse_move,
    mouse_enter,
    mouse_leave,
    mouse_over,
    mouse_out,
    wheel,
    drag,
    drag_end,
    resize,
};

pub const EventData = union(EventType) {
    remove: void,
    key_press: struct { ctx: *EventContext, key: vaxis.Key },
    key_release: struct { ctx: *EventContext, key: vaxis.Key },
    focus: void,
    blur: void,
    mouse_down: struct { ctx: *EventContext, mouse: Mouse },
    mouse_up: struct { ctx: *EventContext, mouse: Mouse },
    click: struct { ctx: *EventContext, mouse: Mouse },
    mouse_move: struct { ctx: *EventContext, mouse: Mouse },
    mouse_enter: Mouse,
    mouse_leave: Mouse,
    mouse_over: struct { ctx: *EventContext, mouse: Mouse },
    mouse_out: struct { ctx: *EventContext, mouse: Mouse },
    wheel: struct { ctx: *EventContext, mouse: Mouse },
    drag: struct { ctx: *EventContext, mouse: Mouse },
    drag_end: struct { ctx: *EventContext, mouse: Mouse },
    resize: struct { width: u16, height: u16 },
};

pub const Options = struct {
    id: ?[]const u8 = null,
    visible: bool = true,
    zIndex: usize = 0,
    style: Style = .{},
    userdata: ?*anyopaque = null,
    beforeDrawFn: ?DrawFn = null,
    drawFn: ?DrawFn = null,
    afterDrawFn: ?DrawFn = null,
    beforeHitFn: ?HitFn = null,
    hitFn: ?HitFn = null,
    afterHitFn: ?HitFn = null,
    updateFn: ?UpdateFn = null,
};

pub const Element = @This();

alloc: Allocator,
id: []const u8,
num: u64,

node: Node,

visible: bool = true,
removed: bool = true,
focused: bool = false,
hovered: bool = false,
dragging: bool = false,

zIndex: usize = 0,

childrens: ?Childrens = null,
parent: ?*Element = null,

layout: Layout = .{},

style: Style = .{},

context: ?*Context = null,

userdata: ?*anyopaque = null,

updateFn: ?UpdateFn = null,

drawFn: ?DrawFn = null,
hitFn: ?HitFn = null,

beforeDrawFn: ?DrawFn = null,
afterDrawFn: ?DrawFn = null,
beforeHitFn: ?HitFn = null,
afterHitFn: ?HitFn = null,

listeners: EventListeners = EventListeners.initFill(.{}),

pub fn init(alloc: std.mem.Allocator, opts: Options) Element {
    const num = element_counter.fetchAdd(1, .monotonic);
    var id_buf: [32]u8 = undefined;
    const generated_id = std.fmt.bufPrint(&id_buf, "element-{}", .{num}) catch "element-?";

    const node = Node.init(num);

    opts.style.apply(node);

    return .{
        .alloc = alloc,
        .id = opts.id orelse generated_id,
        .num = num,
        .visible = opts.visible,
        .zIndex = opts.zIndex,
        .style = opts.style,
        .userdata = opts.userdata,
        .beforeDrawFn = opts.beforeDrawFn,
        .afterDrawFn = opts.afterDrawFn,
        .beforeHitFn = opts.beforeHitFn,
        .afterHitFn = opts.afterHitFn,
        .drawFn = opts.drawFn,
        .hitFn = opts.hitFn,
        .updateFn = opts.updateFn,
        .node = node,
    };
}

pub fn addEventListener(self: *Element, event_type: EventType, callback: Callback) !void {
    try self.listeners.getPtr(event_type).append(self.alloc, callback);
}

pub fn dispatchEvent(self: *Element, data: EventData) void {
    const callbacks = self.listeners.get(@as(EventType, data));
    for (callbacks.items) |callback| {
        callback(self, data);
    }
}

pub fn fill(element: *Element, buffer: *Buffer, cell: vaxis.Cell) void {
    buffer.fillRect(element.layout.left, element.layout.top, element.layout.width, element.layout.height, cell);
}

pub fn fillRounded(element: *Element, buffer: *Buffer, color: vaxis.Color, radius: f32) void {
    const layout = element.layout;

    const left: f32 = @floatFromInt(layout.left);
    const top: f32 = @floatFromInt(layout.top);
    const width: f32 = @floatFromInt(layout.width);
    const height: f32 = @floatFromInt(layout.height);

    const lower = "▄";
    const upper = "▀";

    const r_squared = radius * radius;

    const tl_cx = left + radius - 1;
    const tl_cy = top + ((radius - 1) / 2.0);
    const tr_cx = left + width - radius;
    const tr_cy = top + ((radius - 1) / 2.0);
    const bl_cx = left + radius - 1;
    const bl_cy = top + height - (radius / 2.0);
    const br_cx = left + width - radius;
    const br_cy = top + height - (radius / 2.0);

    var py: f32 = 0;
    while (py < height * 2) : (py += 1) {
        var px: f32 = 0;
        while (px < width) : (px += 1) {
            const cell_x = left + px;
            const cell_y = top + (py / 2.0);

            const in_left_zone = px < radius;
            const in_right_zone = px >= width - radius;
            const in_top_zone = py < radius;
            const in_bottom_zone = py >= height * 2 - radius;

            var inside = true;

            if (in_left_zone and in_top_zone) {
                const dx = cell_x - tl_cx;
                const dy = (cell_y - tl_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            } else if (in_right_zone and in_top_zone) {
                const dx = cell_x - tr_cx;
                const dy = (cell_y - tr_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            } else if (in_left_zone and in_bottom_zone) {
                const dx = cell_x - bl_cx;
                const dy = (cell_y - bl_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            } else if (in_right_zone and in_bottom_zone) {
                const dx = cell_x - br_cx;
                const dy = (cell_y - br_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            }

            if (inside) {
                const curr_x_cell: u16 = @intFromFloat(@floor(cell_x));
                const curr_y_cell: u16 = @intFromFloat(@floor(cell_y));
                const curr_y_frac = cell_y - @floor(cell_y);
                const is_upper_now = curr_y_frac < 0.5;
                const new_char = if (is_upper_now) upper else lower;

                const existing = buffer.readCell(curr_x_cell, curr_y_cell);
                if (existing) |cell| {
                    const g = cell.char.grapheme;
                    const is_lower = std.mem.eql(u8, g, lower);
                    const is_upper = std.mem.eql(u8, g, upper);
                    if ((is_lower and is_upper_now) or (is_upper and !is_upper_now)) {
                        buffer.writeCell(curr_x_cell, curr_y_cell, .{ .char = .{ .grapheme = "█" }, .style = .{ .fg = color } });
                        continue;
                    }
                }

                buffer.writeCell(curr_x_cell, curr_y_cell, .{ .char = .{ .grapheme = new_char }, .style = .{ .fg = color } });
            }
        }
    }
}

fn toLinear(c: f32) f32 {
    return if (c >= 0.04045) std.math.pow(f32, (c + 0.055) / 1.055, 2.4) else c / 12.92;
}

pub const OkLab = struct { l: f32, a: f32, b: f32 };

fn rgbaToOkLab(red: u8, green: u8, blue: u8) OkLab {
    const r = toLinear(@as(f32, @floatFromInt(red)) / 255.0);
    const g = toLinear(@as(f32, @floatFromInt(green)) / 255.0);
    const b = toLinear(@as(f32, @floatFromInt(blue)) / 255.0);

    var l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
    var m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
    var s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;

    l = std.math.cbrt(l);
    m = std.math.cbrt(m);
    s = std.math.cbrt(s);

    return .{
        .l = l * 0.2104542553 + m * 0.7936177850 + s * -0.0040720468,
        .a = l * 1.9779984951 + m * -2.4285922050 + s * 0.4505937099,
        .b = l * 0.0259040371 + m * 0.7827717662 + s * -0.8086757660,
    };
}

fn fromLinear(c: f32) f32 {
    return if (c >= 0.0031308) 1.055 * std.math.pow(f32, c, 1.0 / 2.4) - 0.055 else 12.92 * c;
}

fn okLabToRgba(lab: OkLab) struct { r: u8, g: u8, b: u8 } {
    const l = lab.l + 0.3963377774 * lab.a + 0.2158037573 * lab.b;
    const m = lab.l - 0.1055613458 * lab.a - 0.0638541728 * lab.b;
    const s = lab.l - 0.0894841775 * lab.a - 1.2914855480 * lab.b;

    const l3 = l * l * l;
    const m3 = m * m * m;
    const s3 = s * s * s;

    const r_linear = 4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
    const g_linear = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
    const b_linear = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

    const r = fromLinear(r_linear);
    const g = fromLinear(g_linear);
    const b = fromLinear(b_linear);

    return .{
        .r = @intFromFloat(std.math.clamp(r * 255.0, 0.0, 255.0)),
        .g = @intFromFloat(std.math.clamp(g * 255.0, 0.0, 255.0)),
        .b = @intFromFloat(std.math.clamp(b * 255.0, 0.0, 255.0)),
    };
}

fn lerpOkLab(a: OkLab, b_lab: OkLab, t: f32) OkLab {
    return .{
        .l = a.l + (b_lab.l - a.l) * t,
        .a = a.a + (b_lab.a - a.a) * t,
        .b = a.b + (b_lab.b - a.b) * t,
    };
}

fn colorToOkLab(color: vaxis.Color) OkLab {
    const rgba = color.rgba;
    return rgbaToOkLab(rgba[0], rgba[1], rgba[2]);
}

fn okLabToColor(lab: OkLab, alpha: u8) vaxis.Color {
    const rgb = okLabToRgba(lab);
    return .{ .rgba = .{ rgb.r, rgb.g, rgb.b, alpha } };
}

pub const GradientDirection = enum {
    horizontal,
    vertical,
};

pub const ColorStop = struct {
    position: f32,
    color: vaxis.Color,
};

pub fn fillGradient(
    element: *Element,
    buffer: *Buffer,
    stops: []const ColorStop,
    direction: GradientDirection,
    char: []const u8,
) void {
    if (stops.len == 0) return;
    if (stops.len == 1) {
        element.fill(buffer, .{ .style = .{ .bg = stops[0].color } });
        return;
    }

    const layout = element.layout;
    const left = layout.left;
    const top = layout.top;
    const width = layout.width;
    const height = layout.height;

    if (width == 0 or height == 0) return;

    const total_steps: f32 = switch (direction) {
        .horizontal => @floatFromInt(width),
        .vertical => @as(f32, @floatFromInt(height)) * 2.0,
    };

    var py: u16 = 0;
    while (py < height) : (py += 1) {
        var px: u16 = 0;
        while (px < width) : (px += 1) {
            const bg_color: vaxis.Color = blk: {
                const t: f32 = switch (direction) {
                    .horizontal => @as(f32, @floatFromInt(px)) / total_steps,
                    .vertical => @as(f32, @floatFromInt(py * 2)) / total_steps,
                };
                break :blk interpolateColor(stops, t);
            };

            const fg_color: vaxis.Color = blk: {
                const t: f32 = switch (direction) {
                    .horizontal => (@as(f32, @floatFromInt(px)) + 0.5) / total_steps,
                    .vertical => (@as(f32, @floatFromInt(py * 2)) + 1.0) / total_steps,
                };
                break :blk interpolateColor(stops, t);
            };

            buffer.writeCell(left + px, top + py, .{
                .char = .{ .grapheme = char },
                .style = .{ .fg = fg_color, .bg = bg_color },
            });
        }
    }
}

fn interpolateColor(stops: []const ColorStop, t: f32) vaxis.Color {
    const clamped_t = std.math.clamp(t, 0.0, 1.0);

    if (clamped_t <= stops[0].position) return stops[0].color;
    if (clamped_t >= stops[stops.len - 1].position) return stops[stops.len - 1].color;

    var i: usize = 0;
    while (i < stops.len - 1) : (i += 1) {
        if (clamped_t >= stops[i].position and clamped_t <= stops[i + 1].position) {
            const segment_t = (clamped_t - stops[i].position) / (stops[i + 1].position - stops[i].position);

            const lab_a = colorToOkLab(stops[i].color);
            const lab_b = colorToOkLab(stops[i + 1].color);
            const lerped = lerpOkLab(lab_a, lab_b, segment_t);

            const alpha_a: f32 = @floatFromInt(stops[i].color.rgba[3]);
            const alpha_b: f32 = @floatFromInt(stops[i + 1].color.rgba[3]);
            const alpha: u8 = @intFromFloat(alpha_a + (alpha_b - alpha_a) * segment_t);

            return okLabToColor(lerped, alpha);
        }
    }

    return stops[stops.len - 1].color;
}

pub fn hitSelf(element: *Element, hit_grid: *HitGrid) void {
    hit_grid.fillRect(element.layout.left, element.layout.top, element.layout.width, element.layout.height, element.num);
}

pub fn hitRounded(element: *Element, hit_grid: *HitGrid, radius: f32) void {
    const layout = element.layout;

    const left: f32 = @floatFromInt(layout.left);
    const top: f32 = @floatFromInt(layout.top);
    const width: f32 = @floatFromInt(layout.width);
    const height: f32 = @floatFromInt(layout.height);

    const r_squared = radius * radius;

    const tl_cx = left + radius - 1;
    const tl_cy = top + ((radius - 1) / 2.0);
    const tr_cx = left + width - radius;
    const tr_cy = top + ((radius - 1) / 2.0);
    const bl_cx = left + radius - 1;
    const bl_cy = top + height - (radius / 2.0);
    const br_cx = left + width - radius;
    const br_cy = top + height - (radius / 2.0);

    var py: f32 = 0;
    while (py < height * 2) : (py += 1) {
        var px: f32 = 0;
        while (px < width) : (px += 1) {
            const cell_x = left + px;
            const cell_y = top + (py / 2.0);

            const in_left_zone = px < radius;
            const in_right_zone = px >= width - radius;
            const in_top_zone = py < radius;
            const in_bottom_zone = py >= height * 2 - radius;

            var inside = true;

            if (in_left_zone and in_top_zone) {
                const dx = cell_x - tl_cx;
                const dy = (cell_y - tl_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            } else if (in_right_zone and in_top_zone) {
                const dx = cell_x - tr_cx;
                const dy = (cell_y - tr_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            } else if (in_left_zone and in_bottom_zone) {
                const dx = cell_x - bl_cx;
                const dy = (cell_y - bl_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            } else if (in_right_zone and in_bottom_zone) {
                const dx = cell_x - br_cx;
                const dy = (cell_y - br_cy) * 2.0;
                inside = (dx * dx + dy * dy) < r_squared;
            }

            if (inside) {
                const curr_x_cell: u16 = @intFromFloat(@floor(cell_x));
                const curr_y_cell: u16 = @intFromFloat(@floor(cell_y));
                hit_grid.set(curr_x_cell, curr_y_cell, element.num);
            }
        }
    }
}

pub fn syncLayout(self: *Element) void {
    const old_width = self.layout.width;
    const old_height = self.layout.height;

    const new_width = self.node.getLayoutWidth();
    const new_height = self.node.getLayoutHeight();

    const parent_left: u16 = if (self.parent) |p| p.layout.left else 0;
    const parent_top: u16 = if (self.parent) |p| p.layout.top else 0;

    self.layout = .{
        .left = parent_left + self.node.getLayoutLeft(),
        .top = parent_top + self.node.getLayoutTop(),
        .right = self.node.getLayoutRight(),
        .bottom = self.node.getLayoutBottom(),
        .width = new_width,
        .height = new_height,
        .direction = self.node.getLayoutDirection(),
        .had_overflow = self.node.getLayoutHadOverflow(),
        .margin = .{
            .left = self.node.getLayoutMargin(.left),
            .top = self.node.getLayoutMargin(.top),
            .right = self.node.getLayoutMargin(.right),
            .bottom = self.node.getLayoutMargin(.bottom),
        },
        .border = .{
            .left = self.node.getLayoutBorder(.left),
            .top = self.node.getLayoutBorder(.top),
            .right = self.node.getLayoutBorder(.right),
            .bottom = self.node.getLayoutBorder(.bottom),
        },
        .padding = .{
            .left = self.node.getLayoutPadding(.left),
            .top = self.node.getLayoutPadding(.top),
            .right = self.node.getLayoutPadding(.right),
            .bottom = self.node.getLayoutPadding(.bottom),
        },
    };

    if (old_width != new_width or old_height != new_height) {
        self.dispatchEvent(.{ .resize = .{ .width = new_width, .height = new_height } });
    }
}

pub fn deinit(self: *Element) void {
    if (self.childrens) |*childrens| {
        childrens.deinit(self.alloc);
        self.childrens = null;
    }

    for (&self.listeners.values) |*list| {
        list.deinit(self.alloc);
    }

    self.node.deinit();
}

pub fn update(self: *Element) void {
    if (self.updateFn) |callback| {
        callback(self);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            child.update();
        }
    }
}

pub fn draw(self: *Element, buffer: *Buffer) void {
    if (!self.visible) return;

    if (self.beforeDrawFn) |callback| {
        callback(self, buffer);
    }

    if (self.drawFn) |callback| {
        callback(self, buffer);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_z_index.items) |child| {
            child.draw(buffer);
        }
    }

    if (self.afterDrawFn) |callback| {
        callback(self, buffer);
    }
}

pub fn hit(self: *Element, hit_grid: *HitGrid) void {
    if (!self.visible) return;

    if (self.beforeHitFn) |callback| {
        callback(self, hit_grid);
    }

    if (self.hitFn) |callback| {
        callback(self, hit_grid);
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_z_index.items) |child| {
            child.hit(hit_grid);
        }
    }

    if (self.afterHitFn) |callback| {
        callback(self, hit_grid);
    }
}

pub fn setContext(self: *Element, ctx: *Context) !void {
    self.context = ctx;
    try ctx.app.window.addElement(self);

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            try child.setContext(ctx);
        }
    }
}

pub fn remove(self: *Element) void {
    if (self.removed) return;

    if (self.parent) |parent| {
        parent.removeChild(self.num);
    } else {
        if (self.context) |ctx| {
            ctx.window.removeElement(self.num);
        }

        self.context = null;
        self.removed = true;

        self.dispatchEvent(.{ .remove = {} });
    }

    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            child.remove();
        }
    }
}

pub fn addChild(self: *Element, child: *Element) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }

    child.parent = self;
    child.removed = false;

    if (self.context) |ctx| {
        try child.setContext(ctx);
    }

    try self.childrens.?.add(child, self.alloc);

    self.node.insertChild(child.node, self.childrens.?.len() - 1);
}

pub fn insertChild(self: *Element, child: *Element, index: usize) !void {
    if (self.childrens == null) {
        self.childrens = .{};
    }

    child.parent = self;
    child.removed = false;

    if (self.context) |ctx| {
        try child.setContext(ctx);
    }

    try self.childrens.?.insert(child, index, self.alloc);

    self.node.insertChild(child.node, index);
}

pub fn removeChild(self: *Element, num: u64) void {
    if (self.childrens) |*childrens| {
        const child = childrens.remove(num) orelse return;

        self.node.removeChild(child.node);

        if (child.context) |ctx| {
            ctx.window.removeElement(num);
        }

        child.parent = null;
        child.context = null;
        child.removed = true;

        child.dispatchEvent(.{ .remove = {} });
    }
}

pub fn getChildById(self: *Element, id: []const u8) ?*Element {
    if (self.childrens) |*childrens| {
        for (childrens.by_order.items) |child| {
            if (std.mem.eql(u8, child.id, id)) {
                return child;
            }
        }
    }
    return null;
}

pub fn handleEvent(self: *Element, ctx: *EventContext, event: Event) void {
    switch (event) {
        .key_press => |key| self.handleKeyPress(ctx, key),
        .key_release => |key| self.handleKeyRelease(ctx, key),
        .blur => self.handleBlur(),
        .focus => self.handleFocus(),
        .mouse => {},
    }
}

pub fn handleKeyPress(self: *Element, ctx: *EventContext, key: vaxis.Key) void {
    self.dispatchEvent(.{ .key_press = .{ .ctx = ctx, .key = key } });
}

pub fn handleKeyRelease(self: *Element, ctx: *EventContext, key: vaxis.Key) void {
    self.dispatchEvent(.{ .key_release = .{ .ctx = ctx, .key = key } });
}

pub fn handleFocus(self: *Element) void {
    self.dispatchEvent(.{ .focus = {} });
}

pub fn handleBlur(self: *Element) void {
    self.dispatchEvent(.{ .blur = {} });
}

pub fn handleResize(self: *Element, width: u16, height: u16) void {
    self.dispatchEvent(.{ .resize = .{ .width = width, .height = height } });
}

pub fn isAncestorOf(self: *Element, other: *Element) bool {
    var current: ?*Element = other.parent;
    while (current) |elem| : (current = elem.parent) {
        if (elem == self) return true;
    }
    return false;
}

test "add child to element" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);

    try testing.expect(child.parent == &parent);
    try testing.expect(parent.childrens != null);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_z_index.items.len);
    try testing.expect(parent.childrens.?.by_order.items[0] == &child);
}

test "add multiple children with z-index ordering" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child1 = Element.init(alloc, .{ .zIndex = 2 });
    defer child1.deinit();

    var child2 = Element.init(alloc, .{ .zIndex = 0 });
    defer child2.deinit();

    var child3 = Element.init(alloc, .{ .zIndex = 1 });
    defer child3.deinit();

    try parent.addChild(&child1);
    try parent.addChild(&child2);
    try parent.addChild(&child3);

    try testing.expectEqual(@as(usize, 3), parent.childrens.?.by_order.items.len);
    try testing.expectEqual(@as(usize, 3), parent.childrens.?.by_z_index.items.len);

    try testing.expect(parent.childrens.?.by_order.items[0] == &child1);
    try testing.expect(parent.childrens.?.by_order.items[1] == &child2);
    try testing.expect(parent.childrens.?.by_order.items[2] == &child3);

    try testing.expect(parent.childrens.?.by_z_index.items[0] == &child2);
    try testing.expect(parent.childrens.?.by_z_index.items[1] == &child3);
    try testing.expect(parent.childrens.?.by_z_index.items[2] == &child1);
}

test "remove child from element" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);
    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);

    parent.removeChild(child.num);

    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_order.items.len);
    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_z_index.items.len);
    try testing.expect(child.parent == null);
    try testing.expect(child.removed == true);
}

test "remove middle child preserves order" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child1 = Element.init(alloc, .{});
    defer child1.deinit();

    var child2 = Element.init(alloc, .{});
    defer child2.deinit();

    var child3 = Element.init(alloc, .{});
    defer child3.deinit();

    try parent.addChild(&child1);
    try parent.addChild(&child2);
    try parent.addChild(&child3);

    parent.removeChild(child2.num);

    try testing.expectEqual(@as(usize, 2), parent.childrens.?.by_order.items.len);
    try testing.expect(parent.childrens.?.by_order.items[0] == &child1);
    try testing.expect(parent.childrens.?.by_order.items[1] == &child3);
}

test "element remove via parent" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);

    child.remove();

    try testing.expectEqual(@as(usize, 0), parent.childrens.?.by_order.items.len);
    try testing.expect(child.parent == null);
    try testing.expect(child.removed == true);
}

test "isAncestorOf" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var grandparent = Element.init(alloc, .{});
    defer grandparent.deinit();

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try grandparent.addChild(&parent);
    try parent.addChild(&child);

    try testing.expect(grandparent.isAncestorOf(&child) == true);
    try testing.expect(grandparent.isAncestorOf(&parent) == true);
    try testing.expect(parent.isAncestorOf(&child) == true);
    try testing.expect(child.isAncestorOf(&grandparent) == false);
    try testing.expect(child.isAncestorOf(&parent) == false);
}

test "getChildById" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child1 = Element.init(alloc, .{ .id = "first" });
    defer child1.deinit();

    var child2 = Element.init(alloc, .{ .id = "second" });
    defer child2.deinit();

    try parent.addChild(&child1);
    try parent.addChild(&child2);

    const found = parent.getChildById("second");
    try testing.expect(found != null);
    try testing.expect(found.? == &child2);

    const not_found = parent.getChildById("nonexistent");
    try testing.expect(not_found == null);
}

test "remove nonexistent child does nothing" {
    const testing = std.testing;
    const alloc = testing.allocator;

    var parent = Element.init(alloc, .{});
    defer parent.deinit();

    var child = Element.init(alloc, .{});
    defer child.deinit();

    try parent.addChild(&child);

    parent.removeChild(999999);

    try testing.expectEqual(@as(usize, 1), parent.childrens.?.by_order.items.len);
}
