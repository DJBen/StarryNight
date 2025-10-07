/*
 Metal shaders dedicated to constellation border rendering.
 */

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

struct ConstellationBorderVertexOut {
    float4 position [[position]];
    float4 color;
};

struct ConstellationBorderInstance {
    float3 p0;
    float3 p1;
};

vertex ConstellationBorderVertexOut constellation_border_vertex(
    uint vid [[vertex_id]],
    uint iid [[instance_id]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    const device ConstellationBorderInstance *segments [[buffer(0)]]
) {
    ConstellationBorderVertexOut out;

    const ConstellationBorderInstance segment = segments[iid];
    const float3 position = (vid == 0) ? segment.p0 : segment.p1;

    out.position = uniforms.projectionMatrix * (uniforms.modelViewMatrix * float4(position, 1.0));
    out.color = uniforms.color;

    return out;
}

fragment half4 constellation_border_fragment(ConstellationBorderVertexOut in [[stage_in]]) {
    return half4(in.color);
}
