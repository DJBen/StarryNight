/*
 Metal shaders dedicated to constellation line rendering.
 */

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

struct ConstellationLineVertexOut {
    float4 position [[position]];
    float4 color;
};

struct ConstellationLineVertexIn {
    float4 positionAlpha;
};

vertex ConstellationLineVertexOut constellation_line_vertex(
    uint vid [[vertex_id]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    const device ConstellationLineVertexIn *vertices [[buffer(0)]]
) {
    ConstellationLineVertexOut out;

    const ConstellationLineVertexIn vert = vertices[vid];

    const float3 position = vert.positionAlpha.xyz;
    out.position = uniforms.projectionMatrix * (uniforms.modelViewMatrix * float4(position, 1.0));

    float fovMultiplier = 1.0;
    const float fov = uniforms.fov;
    if (fov < 90.0) {
        fovMultiplier = clamp((fov - 15.0) / (90.0 - 15.0), 0.0, 1.0);
    }

    const float alpha = uniforms.color.w * vert.positionAlpha.w * fovMultiplier;
    const float3 rgb = uniforms.color.xyz * alpha;
    out.color = float4(rgb, alpha);

    return out;
}

fragment half4 constellation_line_fragment(ConstellationLineVertexOut in [[stage_in]]) {
    return half4(in.color);
}
