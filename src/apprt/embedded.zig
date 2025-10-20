const std = @import("std");
const CoreApp = @import("../App.zig");
const log = std.log;

pub const App = struct {
    core_app: *CoreApp,

    pub fn init(self: *App, core_app: *CoreApp) !void {
        self.* = .{ .core_app = core_app };
    }
};

pub const CAPI = struct {
    const global = &@import("../global.zig").state;

    export fn ares_app_free(app: *App) void {
        const core_app = app.core_app;
        global.alloc.destroy(app);
        core_app.destroy();
    }

    export fn ares_app_new() ?*App {
        return app_new() catch {
            log.err("error initializing app", .{});
            return null;
        };
    }

    fn app_new() !*App {
        const core_app = try CoreApp.create(global.alloc);
        errdefer core_app.destroy();

        var app = try global.alloc.create(App);
        errdefer global.alloc.destroy(app);
        try app.init(core_app);
        errdefer app.terminate();

        return app;
    }
};
