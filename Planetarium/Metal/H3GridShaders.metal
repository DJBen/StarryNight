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

// Simple line rendering: outputs p0 or p1 based on vertex_id
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
    float3 p = (vid == 0) ? s.p0 : s.p1;
    float4 pw = float4(p, 1.0);

    // Transform to clip space
    out.position = u.projectionMatrix * (u.modelViewMatrix * pw);
    
    // Color by level
    uint l = min(s.level, numColors - 1);
    out.color = levelColors[l];
    
    return out;
}

fragment half4 h3line_fragment(LineVertexOut in [[stage_in]]) {
    return half4(in.color);
}
