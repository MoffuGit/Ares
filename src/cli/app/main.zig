const std = @import("std");
const tui = @import("tui");

const Element = tui.Element;
const App = tui.App;

pub fn keyPressFn(_: *Element, data: Element.ElementEvent) void {
    const key = data.event.key_press;
    if (key.matches('c', .{ .ctrl = true })) {
        if (data.element.context) |ctx| {
            ctx.stop() catch {};
        }
        data.ctx.stopPropagation();
    }
}

const GPA = std.heap.GeneralPurposeAllocator(.{});

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    const app = try App.create(alloc, .{});
    defer app.destroy();

    try app.root().addEventListener(.key_press, Element, app.root(), keyPressFn);

    app.run() catch |err| {
        std.log.err("App exit with an err: {}", .{err});
    };
}
