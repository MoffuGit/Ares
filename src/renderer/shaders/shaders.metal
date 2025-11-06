#include <metal_stdlib>

using namespace metal;

struct Uniforms {
  float2 screen_size;
  float2 cell_size;
  ushort2 grid_size;
};

struct VertexInput {
    float4 position [[attribute(0)]];
    float4 color [[attribute(1)]];
};

struct VertexOutput {
    float4 position [[position]];
    float4 color [[flat]];
};

vertex VertexOutput vertexShader(VertexInput in [[stage_in]]) {
    VertexOutput out;
    out.position = in.position;
    out.color = in.color;
    return out;
}

fragment float4 fragmentShader(VertexOutput in [[stage_in]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    float2 fragCoord = in.position.xy;

    float line_thickness = 2.0f;

    bool is_horizontal_line = (fmod(fragCoord.y, uniforms.cell_size.y) < line_thickness) ||
                              (fmod(fragCoord.y, uniforms.cell_size.y) > (uniforms.cell_size.y - line_thickness));

    bool is_vertical_line = (fmod(fragCoord.x, uniforms.cell_size.x) < line_thickness) ||
                            (fmod(fragCoord.x, uniforms.cell_size.x) > (uniforms.cell_size.x - line_thickness));

    if (is_horizontal_line || is_vertical_line) {
        return float4(0.5f, 0.5f, 0.5f, 1.0f);
    }

    return in.color;
}
