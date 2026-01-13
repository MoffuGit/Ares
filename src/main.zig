const std = @import("std");
const datastruct = @import("datastruct/mod.zig");

const vaxis = @import("vaxis");
const Cell = vaxis.Cell;

const App = @import("App.zig");

const log = std.log.scoped(.main);

const global = &@import("global.zig").state;

pub fn main() !void {
    const alloc = global.alloc;

    var app = try App.init(alloc);
    defer app.deinit();

    app.run() catch |err| {
        log.err("App exist with err: {}", .{err});
    };
}
