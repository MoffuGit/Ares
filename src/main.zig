const std = @import("std");
const datastruct = @import("datastruct/mod.zig");
const yoga = @import("yoga");

const Box = @import("element/Box.zig");
const Element = @import("element/mod.zig").Element;
const Node = @import("element/Node.zig");
const Style = @import("element/mod.zig").Style;
const Buffer = @import("Buffer.zig");
const HitGrid = @import("HitGrid.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const App = @import("App.zig");
const events = @import("events/mod.zig");
const EventContext = events.EventContext;

const DraggableBox = struct {
    element: Element,
    background: vaxis.Cell.Color,
    pos_x: f32,
    pos_y: f32,

    pub fn create(alloc: std.mem.Allocator) !*DraggableBox {
        const self = try alloc.create(DraggableBox);
        self.* = .{
            .element = Element.init(alloc, .{
                .id = "draggable-box",
                .userdata = self,
                .drawFn = draw,
                .dragFn = onDrag,
                .hitGridFn = onHit,
                .style = .{
                    .position_type = .absolute,
                    .width = .{ .point = 20 },
                    .height = .{ .point = 10 },
                    .position = .{
                        .top = .{ .percent = 50 },
                        .left = .{ .percent = 50 },
                    },
                    .margin = .{
                        .top = .{ .point = -5 },
                        .left = .{ .point = -10 },
                    },
                },
            }),
            .background = .{ .rgba = .{ 0, 0, 0, 170 } },
            .pos_x = 50,
            .pos_y = 50,
        };
        return self;
    }

    pub fn destroy(self: *DraggableBox, alloc: std.mem.Allocator) void {
        self.element.deinit();
        alloc.destroy(self);
    }

    fn onDrag(element: *Element, _: *EventContext, mouse: vaxis.Mouse) void {
        const self: *DraggableBox = @ptrCast(@alignCast(element.userdata));

        const col: f32 = @floatFromInt(mouse.col);
        const row: f32 = @floatFromInt(mouse.row);

        self.pos_x = col;
        self.pos_y = row;

        element.style.position.left = .{ .point = self.pos_x };
        element.style.position.top = .{ .point = self.pos_y };
        element.style.margin.left = .{ .point = -10 };
        element.style.margin.top = .{ .point = -5 };

        element.style.apply(element.node);

        if (element.context) |ctx| {
            ctx.requestDraw();
        }
    }

    fn onHit(element: *Element, hit_grid: *HitGrid) void {
        hit_grid.fillRect(
            element.layout.left,
            element.layout.top,
            element.layout.width,
            element.layout.height,
            element.num,
        );
    }

    fn draw(element: *Element, buffer: *Buffer) void {
        const self: *DraggableBox = @ptrCast(@alignCast(element.userdata));

        const x = element.layout.left;
        const y = element.layout.top;

        var row: u16 = 0;
        while (row < element.layout.height) : (row += 1) {
            var col: u16 = 0;
            while (col < element.layout.width) : (col += 1) {
                const px = x + col;
                const py = y + row;
                if (px < buffer.width and py < buffer.height) {
                    buffer.writeCell(px, py, .{ .style = .{ .bg = self.background } });
                }
            }
        }
    }
};

const log = std.log.scoped(.main);

pub fn keyPressFn(element: *Element, ctx: *EventContext, key: vaxis.Key) void {
    if (key.matches('c', .{ .ctrl = true })) {
        if (element.context) |app_ctx| {
            app_ctx.stopApp() catch {};
        }
        ctx.stopPropagation();
    }
}

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    var app = try App.create(alloc, .{
        .root_opts = .{
            .keyPressFn = keyPressFn,
            .style = .{
                .flex_direction = .row,
                .width = .{ .percent = 100 },
                .height = .{ .percent = 100 },
            },
        },
    });
    defer app.destroy();

    const blue_box = try Box.create(alloc, .{
        .id = "blue-box",
        .style = .{
            .width = .{ .percent = 33.33 },
            .height = .{ .percent = 100 },
        },
        .background = .{ .rgb = .{ 0, 0, 255 } },
    });
    defer blue_box.destroy(alloc);

    const red_box = try Box.create(alloc, .{
        .id = "red-box",
        .style = .{
            .width = .{ .percent = 33.33 },
            .height = .{ .percent = 100 },
        },
        .background = .{ .rgb = .{ 255, 0, 0 } },
    });
    defer red_box.destroy(alloc);

    const green_box = try Box.create(alloc, .{
        .id = "green-box",
        .style = .{
            .width = .{ .percent = 33.33 },
            .height = .{ .percent = 100 },
        },
        .background = .{ .rgb = .{ 0, 255, 0 } },
    });
    defer green_box.destroy(alloc);

    const draggable_box = try DraggableBox.create(alloc);
    defer draggable_box.destroy(alloc);

    try app.window.root.addChild(&blue_box.element);
    try app.window.root.addChild(&red_box.element);
    try app.window.root.addChild(&green_box.element);
    try app.window.root.addChild(&draggable_box.element);

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
