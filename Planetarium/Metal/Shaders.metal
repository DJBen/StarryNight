/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Metal shaders used for this sample
*/

#include <metal_stdlib>
#include <simd/simd.h>
#include <TargetConditionals.h>

// Including header shared between this Metal shader code and Swift/C code executing Metal API commands
#include "ShaderTypes.h"

using namespace metal;

// Scale factor to extend spikes relative to the star core radius
constant float kSpikeExtentScale = 2.0;

// Inline helper to shape line weights around an axis
inline float lineWeight(float a, float width) {
    return pow(1.0 - smoothstep(0.0, width, fabs(a)), 3.0);
}

struct Vertex
{
    float3 position [[attribute(VertexAttributePosition)]];
    float2 texCoord [[attribute(VertexAttributeTexcoord)]];
};

struct ColorInOut
{
    float4 position [[position]];
    float2 texCoord;
};

vertex ColorInOut vertexShader(Vertex in [[stage_in]],
                               constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]])
{
    ColorInOut out;

    float4 position = float4(in.position, 1.0);
    out.position = uniforms.projectionMatrix * uniforms.modelViewMatrix * position;
    out.texCoord = in.texCoord;

    return out;
}

struct ColorOut
{
    float4 color0 [[ color(0) ]];
};

#define BlendOverlay(a, b) ( (b<0.5) ? (2.0*b*a) : (1.0-2.0*(1.0-a)*(1.0-b)) )

float4 applyBlend(constant Uniforms &uniforms, float4 color0, float4 color1)
{
    if((BlendMode)uniforms.blendMode == BlendModeTransparency)
    {
        // Any blend function can be applied
        return uniforms.transparency * color0 + (1.0 - uniforms.transparency) * color1;
    }
    else if((BlendMode)uniforms.blendMode == BlendModeInvert)
    {
        return float4(1.01) - color1;
    }
    else if((BlendMode)uniforms.blendMode == BlendModeOverlay)
    {
        return float4(BlendOverlay(color0.r, color1.r),
                      BlendOverlay(color0.g, color1.g),
                      BlendOverlay(color0.b, color1.b),
                      BlendOverlay(color0.a, color1.a));
    }
    else // BlendModeNone
        return color0;
}

#define USE_MULTIPLE_RENDER_PASSES (TARGET_OS_SIMULATOR || TARGET_OS_OSX)

fragment ColorOut fragmentShader(ColorInOut in [[stage_in]],
#if !USE_MULTIPLE_RENDER_PASSES
                                 ColorOut colorIn,
#endif
                                 constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                                 constant float4* data0 [[ buffer(0) ]],
                                 constant float4* data1 [[ buffer(1) ]],
                                 constant float4* data3 [[ buffer(3) ]],
                                 constant float4* data4 [[ buffer(4) ]],
                                 constant float4* data5 [[ buffer(5) ]],
                                 constant float4* data6 [[ buffer(6) ]],
                                 constant float4* data7 [[ buffer(7) ]],
                                 constant float4* data8 [[ buffer(8) ]],
                                 constant float4* data9 [[ buffer(9) ]],
                                 constant float4* data10 [[ buffer(10) ]],
                                 constant float4* data11 [[ buffer(11) ]],
                                 constant float4* data12 [[ buffer(12) ]],
                                 constant float4* data13 [[ buffer(13) ]],
#if USE_MULTIPLE_RENDER_PASSES
                                 device float4* data14 [[ buffer(14) ]],
#else
                                 constant float4* data14 [[ buffer(14) ]],
#endif
                                 texture2d<half> colorMap       [[ texture(TextureIndexColor) ]],
                                 texture2d<half> linearTexture  [[ texture(TextureIndexLinear) ]],
                                 texture2d_ms<half> msaaTexture [[ texture(TextureIndexMSAA) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    float4 colorSample = uniforms.forceColor ? uniforms.color : float4(colorMap.sample(colorSampler, in.texCoord.xy));
    ColorOut out;
#if USE_MULTIPLE_RENDER_PASSES
    out.color0 = float4(colorSample);
#else
    out.color0 = applyBlend(uniforms, colorSample, colorIn.color0);
#endif
    return out;
}

#if USE_MULTIPLE_RENDER_PASSES
fragment ColorOut blendFragmentShader(ColorInOut in [[stage_in]],
                                      constant Uniforms & uniforms [[ buffer(BufferIndexUniforms) ]],
                                      texture2d<half> colorMap     [[ texture(TextureIndexColor) ]],
                                      texture2d<half> prevColor     [[ texture(TextureIndexFB) ]])
{
    constexpr sampler colorSampler(mip_filter::linear,
                                   mag_filter::linear,
                                   min_filter::linear);

    float4 colorSample = uniforms.forceColor ? uniforms.color : float4(colorMap.sample(colorSampler, in.texCoord.xy));
    float4 previousColor = float4(prevColor.read(ushort2(in.position.xy)));
    ColorOut out;
    out.color0 = applyBlend(uniforms, colorSample, previousColor);
    return out;
}
#endif

// === Starfield instanced rendering shaders ===

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

// Quad vertices are provided as float3 in buffer(0) addressed by vertex_id
// Star instances are provided in buffer(1)
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
    // Enlarge quad so spikes can extend ~2x the core radius
    starView.xy += quadPos.xy * star.size * kSpikeExtentScale;

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
    float2 uvCore = uv * kSpikeExtentScale;
    float distCore = length(uvCore);

    // Solid center with smooth edge falloff
    const float rSolid = 0.18; // fully opaque radius
    const float rEdge  = 0.50; // fully transparent by here
    float alphaBase = 1.0 - smoothstep(rSolid, rEdge, distCore);
    // Scale by brightness so bright stars stand out more
    float alpha = saturate(alphaBase * (0.5 + 0.9 * in.brightness)) * in.color.a;

    // Early discard for quad edges
    if (alpha < 0.002) discard_fragment();

    // Premultiply color for blending
    float3 premul = in.color.rgb * alpha;
    return half4(half3(premul), half(alpha));
}
