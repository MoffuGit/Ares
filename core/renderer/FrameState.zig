const FrameState = @This();

const rendererpkg = @import("../Renderer.zig");
const GraphicsAPI = rendererpkg.GraphicsAPI;
const Target = GraphicsAPI.Target;
const shaderpkg = GraphicsAPI.shaders;
const Buffer = GraphicsAPI.Buffer;
const Texture = GraphicsAPI.Texture;

const UniformBuffer = Buffer(shaderpkg.Uniforms);
const CellBuffer = Buffer(shaderpkg.CellText);
const CellBgBuffer = Buffer(shaderpkg.CellBg);

target: Target,
uniforms: UniformBuffer,
cells: CellBuffer,
cells_bg: CellBgBuffer,
grayscale: Texture,

pub fn init(api: *GraphicsAPI) !FrameState {
    // Initialize the target. Just as with the other resources,
    // start it off as small as we can since it'll be resized.
    var target = try api.initTarget(1, 1);
    errdefer target.deinit();

    var uniforms = try UniformBuffer.init(api.uniformBufferOptions(), 1);
    errdefer uniforms.deinit();

    var cells = try CellBuffer.init(api.uniformBufferOptions(), 1);
    errdefer cells.deinit();

    var cells_bg = try CellBgBuffer.init(api.bgBufferOptions(), 1);
    errdefer cells_bg.deinit();

    const grayscale = try api.initAtlasTexture(&.{
        .data = undefined,
        .size = 1,
        .format = .grayscale,
    });
    errdefer grayscale.deinit();

    return .{
        .target = target,
        .uniforms = uniforms,
        .cells = cells,
        .cells_bg = cells_bg,
        .grayscale = grayscale,
    };
}

pub fn deinit(self: *FrameState) void {
    self.target.deinit();
    self.cells.deinit();
    self.cells_bg.deinit();
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
