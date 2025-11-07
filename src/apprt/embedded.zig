const std = @import("std");
const objc = @import("objc");
const CoreApp = @import("../App.zig");
const CoreSurface = @import("../Surface.zig");
const log = std.log;

pub const App = struct {
    core_app: *CoreApp,

    pub fn init(self: *App, core_app: *CoreApp) !void {
        self.* = .{ .core_app = core_app };
    }

    pub fn newSurface(self: *App, opts: Surface.Options) !*Surface {
        var surface = try self.core_app.alloc.create(Surface);
        errdefer self.core_app.alloc.destroy(surface);

        try surface.init(self, opts);
        errdefer surface.deinit();

        return surface;
    }

    pub fn closeSurface(self: *App, surface: *Surface) void {
        surface.deinit();
        self.core_app.alloc.destroy(surface);
    }
};

pub const Platform = struct {
    macos: MacOs,

    pub const MacOs = struct { nsview: objc.Object };

    pub const C = extern struct {
        macos: extern struct { nsview: ?*anyopaque },
    };

    pub fn init(c_platform: C) !Platform {
        const nsview = objc.Object.fromId(c_platform.macos.nsview);
        return .{ .macos = .{ .nsview = nsview } };
    }
};

pub const SurfaceSize = struct {
    width: u32,
    height: u32,
};

pub const ContentScale = struct {
    x: f32,
    y: f32,
};

pub const Surface = struct {
    app: *App,
    core_surface: CoreSurface,
    platform: Platform,
    size: SurfaceSize,
    content_scale: ContentScale,

    pub const Options = extern struct {
        platform: Platform.C = undefined,
        scale_factor: f64 = 1,
    };

    pub fn init(self: *Surface, app: *App, opts: Options) !void {
        self.* = .{
            .app = app,
            .core_surface = undefined,
            .platform = try .init(opts.platform),
            .content_scale = .{
                .x = @floatCast(opts.scale_factor),
                .y = @floatCast(opts.scale_factor),
            },
            .size = .{ .width = 800, .height = 600 },
        };

        try app.core_app.addSurface(self);
        errdefer app.core_app.deleteSurface(self);

        try self.core_surface.init(app.core_app.alloc, app.core_app, app, self);
        errdefer self.core_surface.deinit();
    }

    pub fn deinit(self: *Surface) void {
        self.app.core_app.deleteSurface(self);
        self.core_surface.deinit();
    }

    pub fn updateSize(self: *Surface, width: u32, height: u32) void {
        if (self.size.width == width and self.size.height == height) return;

        self.size = .{
            .width = width,
            .height = height,
        };

        self.core_surface.sizeCallback(self.size);
    }

    pub fn updateContentScale(self: *Surface, x: f64, y: f64) void {
        const x_scaled = @max(1, if (std.math.isNan(x)) 1 else x);
        const y_scaled = @max(1, if (std.math.isNan(y)) 1 else y);

        const scale = ContentScale{ .x = @floatCast(x_scaled), .y = @floatCast(y_scaled) };

        if (self.content_scale.x == scale.x and self.content_scale.y == scale.y) return;

        self.content_scale = scale;

        self.core_surface.contentScaleCallback(self.content_scale);
    }

    pub fn getSize(self: *Surface) SurfaceSize {
        return self.size;
    }

    pub fn updateFilePwd(self: *Surface, pwd: [:0]const u8) void {
        self.core_surface.setFilePwd(pwd) catch |err| {
            log.err("error with new pwd: {}", .{err});
        };
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

    export fn ares_surface_new(app: *App, opts: Surface.Options) ?*Surface {
        return surface_new(app, opts) catch {
            log.err("error initializing surface", .{});
            return null;
        };
    }

    fn surface_new(app: *App, opts: Surface.Options) !*Surface {
        log.info("surface initialized", .{});
        return try app.newSurface(opts);
    }

    export fn ares_surface_free(ptr: *Surface) void {
        ptr.app.closeSurface(ptr);
    }

    export fn ares_surface_set_size(surface: *Surface, w: u32, h: u32) void {
        surface.updateSize(w, h);
    }

    export fn ares_surface_set_content_scale(surface: *Surface, x: f64, y: f64) void {
        surface.updateContentScale(x, y);

        surface.core_surface.contentScaleCallback(surface.content_scale);
    }

    export fn ares_surface_set_file(surface: *Surface, pwd: [*:0]const u8) void {
        surface.updateFilePwd(std.mem.sliceTo(pwd, 0));
    }
};
