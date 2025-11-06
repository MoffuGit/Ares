const FrameState = @This();

const rendererpkg = @import("../renderer.zig");
const GraphicsAPI = rendererpkg.GraphicsAPI;
const Target = GraphicsAPI.Target;
const shaderpkg = GraphicsAPI.shaders;
const Buffer = GraphicsAPI.Buffer;

const UniformBuffer = Buffer(shaderpkg.Uniforms);
const VertexBuffer = Buffer(shaderpkg.VertexInput);

target: Target,
uniforms: UniformBuffer,
vertex: VertexBuffer,

pub fn init(api: *GraphicsAPI) !FrameState {
    // Initialize the target. Just as with the other resources,
    // start it off as small as we can since it'll be resized.
    var target = try api.initTarget(1, 1);
    errdefer target.deinit();

    var uniforms = try UniformBuffer.init(api.uniformBufferOptions(), 1);
    errdefer uniforms.deinit();

    var vertex = try VertexBuffer.init(api.uniformBufferOptions(), 1);
    errdefer vertex.deinit();

    const quad_vertices: [4]shaderpkg.VertexInput = .{
        .{ .position = .{ -1.0, -1.0, 0.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 0.0 } }, // Bottom-left
        .{ .position = .{ 1.0, -1.0, 0.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 0.0 } }, // Bottom-right
        .{ .position = .{ -1.0, 1.0, 0.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 0.0 } }, // Top-left
        .{ .position = .{ 1.0, 1.0, 0.0, 1.0 }, .color = .{ 1.0, 0.0, 0.0, 0.0 } }, // Top-right
    };

    try vertex.sync(&quad_vertices);

    return .{ .target = target, .uniforms = uniforms, .vertex = vertex };
}

pub fn deinit(self: *FrameState) void {
    self.target.deinit();
    self.vertex.deinit();
    self.uniforms.deinit();
}

pub fn resize(
    self: *FrameState,
    api: *GraphicsAPI,
    width: usize,
    height: usize,
) !void {
    const target = try api.initTarget(width, height);
    self.target.deinit();
    self.target = target;
}
