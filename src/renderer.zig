const Metal = @import("renderer/Metal.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const apprt = @import("apprt/embedded.zig");
const Options = @import("renderer/Options.zig");
const ArenaAllocator = std.heap.ArenaAllocator;
const objc = @import("objc");
const mtl = @import("./renderer/metal/api.zig");

const log = std.log.scoped(.renderer);

pub const Renderer = struct {
    pub const API = Metal;
    const Target = API.Target;
    const shaderpkg = API.shaders;
    const Shaders = shaderpkg.Shaders;
    const Buffer = API.Buffer;

    const VertexBuffer = Buffer(shaderpkg.VertexInput);

    alloc: Allocator,
    size: apprt.SurfaceSize,
    api: Metal,
    target: Target,
    vertexBuffer: VertexBuffer,
    frame_count: usize = 0,
    shaders: Shaders,
    mutex: std.Thread.Mutex = .{},
    health: std.atomic.Value(Health) = .{ .raw = .healthy },

    pub fn init(alloc: Allocator, opts: Options) !Renderer {
        var api = try Metal.init(opts.rt_surface);
        errdefer api.deinit();

        var target = try api.initTarget(800, 600);
        errdefer target.deinit();

        var vertexBuffer = try VertexBuffer.init(.{
            .device = api.device,
            .resource_options = .{
                // Indicate that the CPU writes to this resource but never reads it.
                .cpu_cache_mode = .write_combined,
                .storage_mode = api.default_storage_mode,
            },
        }, 1);
        errdefer vertexBuffer.deinit();

        var renderer = Renderer{ .alloc = alloc, .size = opts.size, .api = api, .target = target, .shaders = undefined, .vertexBuffer = vertexBuffer };
        try renderer.initShaders();

        return renderer;
    }

    pub fn deinit(self: *Renderer) void {
        self.api.deinit();
        self.target.deinit();
        self.deinitShaders();
        self.* = undefined;
    }

    fn deinitShaders(self: *Renderer) void {
        self.shaders.deinit();
    }

    fn initShaders(self: *Renderer) !void {
        var shaders = try self.api.initShaders();
        errdefer shaders.deinit(self.alloc);

        self.shaders = shaders;
    }

    pub fn drawFrame(
        self: *Renderer,
        sync: bool,
    ) !void {
        self.mutex.lock();
        defer self.mutex.unlock();

        self.api.drawFrameStart();
        defer self.api.drawFrameEnd();

        const surface_size = try self.api.surfaceSize();

        self.size = .{ .height = surface_size.height, .width = surface_size.width };

        if (self.size.width > 0 and self.size.height > 0) {
            const target = try self.api.initTarget(self.size.width, self.size.height);
            errdefer target.deinit();
            self.target.deinit();
            self.target = target;
        }

        var frame_ctx = try self.api.beginFrame(self, &self.target);
        defer frame_ctx.complete(sync);

        self.frame_count += 1;

        {
            var render_pass = frame_ctx.renderPass(&.{
                .{
                    .target = .{
                        .target = self.target,
                    },
                    .clear_color = blk: {
                        var r: f32 = 0.0;
                        var g: f32 = 0.0;
                        var b: f32 = 0.0;
                        const segment_size: usize = 256;
                        const total_segments: usize = 6;
                        const cycle_length = segment_size * total_segments;
                        const current_step = self.frame_count % cycle_length;
                        const segment_idx = current_step / segment_size; // Which segment are we in (0-5)
                        // Value from 0.0 to 1.0 within the current segment
                        const segment_offset = @as(f32, @floatFromInt(current_step % segment_size)) / @as(f32, segment_size - 1);
                        switch (segment_idx) {
                            0 => { // Red to Yellow (R=1, G=increasing, B=0)
                                r = 1.0;
                                g = segment_offset;
                                b = 0.0;
                            },
                            1 => { // Yellow to Green (R=decreasing, G=1, B=0)
                                r = 1.0 - segment_offset;
                                g = 1.0;
                                b = 0.0;
                            },
                            2 => { // Green to Cyan (R=0, G=1, B=increasing)
                                r = 0.0;
                                g = 1.0;
                                b = segment_offset;
                            },
                            3 => { // Cyan to Blue (R=0, G=decreasing, B=1)
                                r = 0.0;
                                g = 1.0 - segment_offset;
                                b = 1.0;
                            },
                            4 => { // Blue to Magenta (R=increasing, G=0, B=1)
                                r = segment_offset;
                                g = 0.0;
                                b = 1.0;
                            },
                            5 => { // Magenta to Red (R=1, G=0, B=decreasing)
                                r = 1.0;
                                g = 0.0;
                                b = 1.0 - segment_offset;
                            },
                            else => { // Should not happen with modulo
                                r = 0.0;
                                g = 0.0;
                                b = 0.0; // Default to black
                            },
                        }
                        break :blk .{ r, g, b, 1.0 };
                    },
                },
            });
            defer render_pass.complete();

            const triangle_vertices = [_]shaderpkg.VertexInput{
                .{ .position = .{ 0.0, 0.5, 0.0 }, .color = .{ 1.0, 0.0, 0.0, 1.0 } }, // Top vertex (Red)
                .{ .position = .{ -0.5, -0.5, 0.0 }, .color = .{ 0.0, 1.0, 0.0, 1.0 } }, // Bottom-left vertex (Green)
                .{ .position = .{ 0.5, -0.5, 0.0 }, .color = .{ 0.0, 0.0, 1.0, 1.0 } }, // Bottom-right vertex (Blue)
            };

            try self.vertexBuffer.sync(&triangle_vertices);

            render_pass.step(.{ .pipeline = self.shaders.pipelines.bg_color, .buffers = &.{
                self.vertexBuffer.buffer,
            }, .draw = .{
                .vertex_count = 3,
                .type = .triangle,
            } });
        }
    }
};

pub const Health = enum(c_int) {
    healthy = 0,
    unhealthy = 1,
};
