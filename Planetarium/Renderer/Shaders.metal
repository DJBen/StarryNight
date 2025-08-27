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
