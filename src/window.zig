const std = @import("std");
const Io = std.Io;
const builtin = @import("builtin");

const rgfw = @import("rgfw");
const Flags = rgfw.Window.Flags;

const renderer = @import("renderer.zig");
const Renderer = renderer.Renderer;
const RenderState = Renderer.RenderState;

pub const Options = struct {
    name: [:0]const u8,
    x: i32,
    y: i32,
    width: i32,
    height: i32,
    flags: Flags,
};

pub const Window = window: {
    if (!builtin.is_test) break :window struct {
        os: rgfw.Window,
        state: RenderState,

        pub fn init(
            self: *@This(),
            options: Options,
            render: *Renderer,
            io: Io,
        ) !void {
            self.* = .{
                .os = undefined,
                .state = undefined,
            };

            try self.os.init(
                options.name,
                options.x,
                options.y,
                options.width,
                options.height,
                options.flags,
            );

            try self.state.init(render, &self.os, io);
        }

        pub fn deinit(self: *@This()) void {
            self.state.deinit();
            self.os.deinit();
        }
    };

    break :window struct {
        pub fn init(
            _: *@This(),
            _: Options,
            _: *Renderer,
            _: Io,
        ) !void {}

        pub fn deinit(self: *@This()) void {
            _ = self;
        }
    };
};
