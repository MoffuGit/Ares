const std = @import("std");
const ares = @import("ares");

const App = ares.App;

const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn keyPressFn(element: *ares.Element, data: ares.Element.EventData) void {
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

pub fn drawRoundedBox(element: *ares.Element, buffer: *ares.Buffer) void {
    const radius: f32 = @floatFromInt(@intFromPtr(element.userdata));
    element.fillRounded(buffer, .{ .rgb = .{ 0x44, 0x88, 0xff } }, radius);
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
                .flex_direction = .row,
                .gap = .{ .column = .{ .point = 2 } },
            },
        },
    });
    defer app.destroy();

    try app.root().addEventListener(.key_press, keyPressFn);

    var boxes: [5]ares.Element = undefined;
    for (&boxes, 4..) |*box, radius| {
        box.* = ares.Element.init(alloc, .{
            .style = .{
                .width = .{ .point = 20 },
                .height = .{ .point = 10 },
            },
            .drawFn = drawRoundedBox,
            .userdata = @ptrFromInt(radius),
        });
        try app.root().addChild(box);
    }
    defer for (&boxes) |*box| box.deinit();

    app.run() catch |err| {
        std.log.err("App exit with an err: {}", .{err});
    };
}
