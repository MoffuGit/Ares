const std = @import("std");
const CoreApp = @import("../App.zig");
const CoreSurface = @import("../Surface.zig");
const log = std.log;

pub const App = struct {
    core_app: *CoreApp,

    pub fn init(self: *App, core_app: *CoreApp) !void {
        self.* = .{ .core_app = core_app };
    }

    pub fn newSurface(self: *App) !*Surface {
        var surface = try self.core_app.alloc.create(Surface);
        errdefer self.core_app.alloc.destroy(surface);

        try surface.init(self);
        errdefer surface.deinit();

        return surface;
    }

    pub fn closeSurface(self: *App, surface: *Surface) void {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
    }
};

pub const Surface = struct {
    app: *App,
    core_surface: CoreSurface,

    pub fn init(self: *Surface, app: *App) !void {
        self.* = .{ .app = app, .core_surface = undefined };

        try app.core_app.addSurface(self);
        errdefer app.core_app.deleteSurface(self);

        try self.core_surface.init(app.core_app.alloc, app.core_app, app, self);
        errdefer self.core_surface.deinit();
    }

    pub fn deinit(self: *Surface) void {
        self.app.core_app.deleteSurface(self);
        self.core_surface.deinit();
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

        log.info("app initialized", .{});
        return app;
    }

    export fn ares_surface_new(app: *App) ?*Surface {
        return surface_new(app) catch {
            log.err("error initializing surface", .{});
            return null;
        };
    }

    fn surface_new(app: *App) !*Surface {
        log.info("surface initialized", .{});
        return try app.newSurface();
    }

    export fn ares_surface_free(ptr: *Surface) void {
        ptr.app.closeSurface(ptr);
    }
};
