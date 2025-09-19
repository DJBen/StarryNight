/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Metal shaders for starfield instanced rendering
*/

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

struct StarVaryings {
    float4 position [[position]];
    float2 uv;
    float4 color;
    float omega0;
    float size;
    float multiplier; // flux * exposureMultiplier;
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

    // https://en.wikipedia.org/wiki/Apparent_magnitude
    // flux relative to mag 0
    float flux = pow(10, -0.4 * star.magnitude);

    float omega_0 = 0.9 * star.lambdaN;
    float multiplier = flux * star.exposureMultiplier;

    // Per-instance phase hash (kept) and time for flicker
    float h = sin((float)instanceID * 12.9898 + 78.233) * 43758.5453;
    float phase = fract(h) * 6.2831853; // [0, 2pi)
    float time = uniforms.transparency;

    // Time-varying flicker, desynchronized per star using a
    // right-skewed Beta-like modulation approximated via Kumaraswamy(a,b)
    const float a = 5.0;
    const float b = 0.1;
    float h1 = fract(sin(phase * 12.9898 + 78.233) * 43758.5453);
    float speed = 5.0 + 5.0 * h1; // ~5 to 10 Hz
    float t = time * speed;
    float tb = floor(t);
    float tf = fract(t);
    float u0 = fract(sin((tb + phase * 17.0) * 12.9898 + 78.233) * 43758.5453);
    float u1 = fract(sin(((tb + 1.0) + phase * 19.0) * 12.9898 + 78.233) * 43758.5453);
    u0 = clamp(u0, 1e-4, 1.0 - 1e-4);
    u1 = clamp(u1, 1e-4, 1.0 - 1e-4);
    float x0 = pow(1.0 - pow(1.0 - u0, 1.0 / b), 1.0 / a);
    float x1 = pow(1.0 - pow(1.0 - u1, 1.0 / b), 1.0 / a);
    float flicker = mix(x0, x1, tf);

    // Apply flicker to multiplier so it impacts size and fragment brightness
    multiplier *= flicker;

    // Distance where radiance drops to 1/255
    // x = omega_0 * np.sqrt(-0.5 * np.log(1/255))
    // Size in meters
    float size = omega_0 * sqrt(-0.5 * log(1 / 255.0 / multiplier));

    starView.xy += quadPos.xy * size / star.sensorPixelSize * 0.01;

    out.position = uniforms.projectionMatrix * starView;
    out.uv = quadPos.xy * 0.5 + 0.5;
    out.color = star.color;
    out.omega0 = omega_0;
    out.size = size;
    out.multiplier = multiplier;
    // Use uniforms.transparency channel to carry time without changing shared struct layout
    out.time = time;
    // Keep phase available in varyings
    out.phase = phase; // [0, 2pi)
    return out;
}

fragment half4 star_fragment(StarVaryings in [[stage_in]]) {
    // Normalized quad coords [-0.5, 0.5]; keep core the same even if quad is enlarged
    float2 uv = in.uv - 0.5;
    float distCore = length(uv);

    // https://en.wikipedia.org/wiki/Airy_disk#Approximation_using_a_Gaussian_profile
    float irradiance = exp(-2 * pow(distCore * 2 * in.size, 2) / pow(in.omega0, 2)) * in.multiplier;

    float alpha = saturate(irradiance) * clamp(in.color.a, 0.0, 1.0);

    // Premultiply color for blending
    float3 premul = clamp(in.color.rgb, 0.0, 1.0) * alpha;
    return half4(half3(premul), half(alpha));
}
