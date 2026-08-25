#include <metal_stdlib>

using namespace metal;

struct VertexInput {
    float4 position [[attribute(0)]];
    float4 color [[attribute(1)]];
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
    VertexInput in [[stage_in]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    float4x2 vertices = float4x2(float2(-1.0f, -1.0f), float2(-1.0f, 1.0f), float2(1.0f, -1.0f), float2(1.0f, 1.0f));

    float2 half_size = (in.position.zw - in.position.xy) / 2.0;
    float2 center    = (in.position.zw + in.position.xy) / 2.0;
    float2 position  = vertices[v_id] * half_size + center;

    VertexOutput out;
    out.position = float4(
        2.0f * position.x / uniforms.viewport_size.x - 1.0f,
        2.0f * (1.0f - position.y / uniforms.viewport_size.y) - 1.0f,
        0.0f,
        1.0f
    );
    out.color = in.color;
    return out;
}

fragment float4 fragmentShader(VertexOutput in [[stage_in]]) {
    return in.color;
}
