#include <metal_stdlib>

using namespace metal;

struct RectInput {
    float4 position [[attribute(0)]];
    float4 color_0  [[attribute(1)]];
    float4 color_1  [[attribute(2)]];
    float4 color_2  [[attribute(3)]];
    float4 color_3  [[attribute(4)]];
};

struct VertexOutput {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
  float2 viewport_size;
};

vertex VertexOutput vertexShader(
    uint v_id [[vertex_id]],
    RectInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    float4x2 vertices = float4x2(float2(-1.0f, -1.0f), float2(-1.0f, 1.0f), float2(1.0f, -1.0f), float2(1.0f, 1.0f));

    float2 half_size = (in.position.zw - in.position.xy) / 2.0;
    float2 center    = (in.position.zw + in.position.xy) / 2.0;
    float2 position  = vertices[v_id] * half_size + center;

    float4x4 colors = float4x4(in.color_0, in.color_1, in.color_2, in.color_3);

    VertexOutput out;
    out.position = float4(
        2.0f * position.x / uniforms.viewport_size.x - 1.0f,
        2.0f * (1.0f - position.y / uniforms.viewport_size.y) - 1.0f,
        0.0f,
        1.0f
    );
    out.color = colors[v_id];
    return out;
}

fragment float4 fragmentShader(VertexOutput in [[stage_in]]) {
    return in.color;
}
