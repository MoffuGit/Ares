const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const macos = @import("macos");
const objc = @import("objc");

const buffer = @import("buffer.zig");
const Buffer = buffer.Buffer;
const c = @import("c.zig");
const Pipeline = @import("Pipeline.zig");

const log = std.log.scoped(.metal);

pub const VertexBuffer = Buffer(VertexInput);

pub const VertexInput = extern struct {
    position: [3]f32 align(16), // Corresponds to float3 position [[attribute(0)]]
    color: [4]f32 align(16), // Corresponds to float4 color [[attribute(1)]]

};

const pipeline_descs: []const struct { [:0]const u8, PipelineDescription } =
    &.{
        .{
            "bg_color",
            .{
                .vertex_fn = "vertexShader",
                .fragment_fn = "fragmentShader",
                .blending_enabled = false,
                .vertex_attributes = VertexInput,
            },
        },
    };

/// All the comptime-known info about a pipeline, so that
/// we can define them ahead-of-time in an ergonomic way.
const PipelineDescription = struct {
    vertex_attributes: ?type = null,
    vertex_fn: []const u8,
    fragment_fn: []const u8,
    step_fn: c.MTLVertexStepFunction = .per_vertex,
    blending_enabled: bool,

    fn initPipeline(
        self: PipelineDescription,
        device: objc.Object,
        library: objc.Object,
        pixel_format: c.MTLPixelFormat,
    ) !Pipeline {
        return try .init(self.vertex_attributes, .{
            .device = device,
            .vertex_fn = self.vertex_fn,
            .fragment_fn = self.fragment_fn,
            .vertex_library = library,
            .fragment_library = library,
            .step_fn = self.step_fn,
            .attachments = &.{.{
                .pixel_format = pixel_format,
                .blending_enabled = self.blending_enabled,
            }},
        });
    }
};

/// We create a type for the pipeline collection based on our desc array.
const PipelineCollection = t: {
    const StructField = std.builtin.Type.StructField;

    var names: [pipeline_descs.len][]const u8 = undefined;
    var types = [_]type{Pipeline} ** pipeline_descs.len;
    var attrs = [_]StructField.Attributes{.{ .@"align" = @alignOf(Pipeline) }} ** pipeline_descs.len;

    for (pipeline_descs, &names) |pipeline, *name| {
        name.* = pipeline[0];
    }
    break :t @Struct(.auto, null, &names, &types, &attrs);
};

/// This contains the state for the shaders used by the Metal renderer.
pub const Shaders = struct {
    library: objc.Object,

    /// Collection of available render pipelines.
    pipelines: PipelineCollection,

    /// Set to true when deinited, if you try to deinit a defunct set
    /// of shaders it will just be ignored, to prevent double-free.
    defunct: bool = false,

    /// Initialize our shader set.
    pub fn init(
        self: *Shaders,
        device: objc.Object,
        pixel_format: c.MTLPixelFormat,
        io: Io,
    ) !void {
        const library = try initLibrary(device, io);
        errdefer library.msgSend(void, objc.sel("release"), .{});

        var pipelines: PipelineCollection = undefined;

        var initialized_pipelines: usize = 0;

        errdefer inline for (pipeline_descs, 0..) |pipeline, i| {
            if (i < initialized_pipelines) {
                @field(pipelines, pipeline[0]).deinit();
            }
        };

        inline for (pipeline_descs) |pipeline| {
            @field(pipelines, pipeline[0]) = try pipeline[1].initPipeline(
                device,
                library,
                pixel_format,
            );
            initialized_pipelines += 1;
        }

        self.* = .{
            .library = library,
            .pipelines = pipelines,
        };
    }

    pub fn deinit(self: *Shaders) void {
        if (self.defunct) return;
        self.defunct = true;

        // Release our primary shaders
        inline for (pipeline_descs) |pipeline| {
            @field(self.pipelines, pipeline[0]).deinit();
        }
        self.library.msgSend(void, objc.sel("release"), .{});
    }
};

/// Initialize the MTLLibrary. A MTLLibrary is a collection of shaders.
fn initLibrary(device: objc.Object, io: Io) !objc.Object {
    const start: std.Io.Timestamp = .now(io, .awake);

    const data = try macos.dispatch.Data.create(
        @embedFile("odyssey_metallib"),
        macos.dispatch.queue.getMain(),
        macos.dispatch.Data.DESTRUCTOR_DEFAULT,
    );
    defer data.release();

    var err: ?*anyopaque = null;
    const library = device.msgSend(
        objc.Object,
        objc.sel("newLibraryWithData:error:"),
        .{
            data,
            &err,
        },
    );
    try checkError(err);

    log.debug("shader library loaded time={}us", .{start.untilNow(io, .awake).toMicroseconds()});

    return library;
}

fn checkError(err_: ?*anyopaque) !void {
    const nserr = objc.Object.fromId(err_ orelse return);
    const str = @as(
        *macos.foundation.String,
        @ptrCast(nserr.getProperty(?*anyopaque, "localizedDescription").?),
    );

    log.err("metal error={s}", .{str.cstringPtr(.ascii).?});
    return error.MetalFailed;
}
