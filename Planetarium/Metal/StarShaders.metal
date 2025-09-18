/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Metal shaders for starfield instanced rendering
*/

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;



// Star-instance data must match the Swift layout (see Renderer.swift)
struct StarInstance {
    float3 position;   // world-space center on celestial sphere
    float  size;       // quad size in view-space units
    float3 _pad0;      // padding to align next float4
    float4 color;      // rgb color, a used as base alpha
    float  brightness; // 0..1
    float3 _pad1;      // padding to 16-byte alignment
};

struct StarVaryings {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float  brightness;
    float  time;      // global time (seconds) for breathing
    float  phase;     // per-instance phase offset
};

vertex StarVaryings star_vertex(
    uint vertexID                [[vertex_id]],
    uint instanceID              [[instance_id]],
    const device float3*  verts  [[buffer(0)]],
    const device StarInstance* s [[buffer(1)]],
    constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]]
){
    StarVaryings out;

    StarInstance star = s[instanceID];
    float3 quadPos = verts[vertexID]; // expected range [-1,1] in xy, z=0

    // Billboard in view space: transform star to view space then offset by quad in view plane
    float4 starView = uniforms.modelViewMatrix * float4(star.position, 1.0);
    // Simple round star: no spike extension
    starView.xy += quadPos.xy * star.size;

    out.position = uniforms.projectionMatrix * starView;
    out.uv = quadPos.xy * 0.5 + 0.5;
    out.color = star.color;
    out.brightness = star.brightness;
    // Use uniforms.transparency channel to carry time without changing shared struct layout
    out.time = uniforms.transparency;
    // Cheap hash to desynchronize breathing per star
    float h = sin((float)instanceID * 12.9898 + 78.233) * 43758.5453;
    out.phase = fract(h) * 6.2831853; // [0, 2pi)
    return out;
}

fragment half4 star_fragment(StarVaryings in [[stage_in]]) {
    // Normalized quad coords [-0.5, 0.5]; keep core the same even if quad is enlarged
    float2 uv = in.uv - 0.5;
    float distCore = length(uv);

    // Solid center with smooth edge falloff
    const float rSolid = 0.18; // fully opaque radius
    const float rEdge  = 0.50; // fully transparent by here
    float alphaBase = 1.0 - smoothstep(rSolid, rEdge, distCore);
    // Scale by brightness so bright stars stand out more
    float alpha = saturate(alphaBase * (0.5 + 0.9 * in.brightness)) * clamp(in.color.a, 0.0, 1.0);

    // Early discard for quad edges
    if (alpha < 0.002) discard_fragment();

    // Premultiply color for blending
    float3 premul = clamp(in.color.rgb, 0.0, 1.0) * alpha;
    return half4(half3(premul), half(saturate(alpha)));
}
