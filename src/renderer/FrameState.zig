const FrameState = @This();

const rendererpkg = @import("../renderer.zig");
const GraphicsAPI = rendererpkg.GraphicsAPI;
const Target = GraphicsAPI.Target;

target: Target,

pub fn init(api: *GraphicsAPI) !FrameState {
    // Initialize the target. Just as with the other resources,
    // start it off as small as we can since it'll be resized.
    const target = try api.initTarget(1, 1);

    return .{
        .target = target,
    };
}

pub fn deinit(self: *FrameState) void {
    self.target.deinit();
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
