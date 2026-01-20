const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const Box = @import("element/Box.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const GPA = std.heap.GeneralPurposeAllocator(.{});

const App = @import("App.zig");
const AppContext = @import("AppContext.zig");

const log = std.log.scoped(.main);

pub fn keyPressFn(ctx: *AppContext, key: vaxis.Key) ?vaxis.Key {
    if (key.matches('c', .{ .ctrl = true })) {
        ctx.stopApp() catch {};
        return null;
    }

    return key;
}

pub fn main() !void {
    var gpa: GPA = .{};
    defer if (gpa.deinit() == .leak) {
        std.log.info("We have leaks 🔥", .{});
    };

    const alloc = gpa.allocator();

    var app = try App.create(alloc, .{
        .keyPressFn = keyPressFn,
    });
    defer app.destroy();

    app.run() catch |err| {
        log.err("App exit with an err: {}", .{err});
    };
}
