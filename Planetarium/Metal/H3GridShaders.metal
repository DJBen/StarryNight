/*
 Metal shaders for screen-space width line segments used to draw H3 grid.
*/

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

struct LineVertexOut {
    float4 position [[position]];
    float4 color;
};

struct LineInstance {
    float3 p0;    // world space
    float3 p1;    // world space
    uint   level; // H3 resolution level for coloring
};

// Expands one line segment into a quad in clip space with constant pixel width
vertex LineVertexOut h3line_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant Uniforms &u [[buffer(BufferIndexUniforms)]],
    const device LineInstance* segs [[buffer(0)]],
    constant float &pixelWidth [[buffer(4)]],
    constant float2 &viewportSize [[buffer(5)]],
    constant float4 *levelColors [[buffer(6)]],
    constant uint &numColors [[buffer(7)]]
) {
    LineVertexOut out;

    LineInstance s = segs[iid];
    float4 p0w = float4(s.p0, 1.0);
    float4 p1w = float4(s.p1, 1.0);

    // World -> clip
    float4 p0c = u.projectionMatrix * (u.modelViewMatrix * p0w);
    float4 p1c = u.projectionMatrix * (u.modelViewMatrix * p1w);

    // Clip -> NDC
    float2 p0ndc = p0c.xy / p0c.w;
    float2 p1ndc = p1c.xy / p1c.w;

    // NDC -> pixels for length/normal computation
    float2 halfSize = viewportSize * 0.5;
    float2 p0px = p0ndc * halfSize + halfSize;
    float2 p1px = p1ndc * halfSize + halfSize;

    // Build perpendicular of length half-width in pixels
    float2 dir = p1px - p0px;
    float len = length(dir);
    float2 n = len > 1e-5 ? float2(-dir.y, dir.x) / len : float2(0.0, 0.0);
    float2 offsetPx = n * (pixelWidth * 0.5);
    float2 offsetNdc = offsetPx / halfSize; // offset vector in NDC units

    // Corner clip-space positions, offsetting each endpoint using its own w
    float4 vClip;
    switch (vid & 3) {
        case 0: // p0 - offset
            vClip = float4(p0c.xy + (-offsetNdc * p0c.w), p0c.z, p0c.w);
            break;
        case 1: // p1 - offset
            vClip = float4(p1c.xy + (-offsetNdc * p1c.w), p1c.z, p1c.w);
            break;
        case 2: // p1 + offset
            vClip = float4(p1c.xy + ( offsetNdc * p1c.w), p1c.z, p1c.w);
            break;
        default: // p0 + offset
            vClip = float4(p0c.xy + ( offsetNdc * p0c.w), p0c.z, p0c.w);
            break;
    }

    out.position = vClip;
    uint l = min(segs[iid].level, numColors-1);
    out.color = levelColors[l];
    return out;
}

fragment half4 h3line_fragment(LineVertexOut in [[stage_in]]) {
    return half4(in.color);
}
