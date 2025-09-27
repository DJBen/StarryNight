/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Metal shaders for crosshair rendering with rainbow effect
*/

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

// MARK: - Crosshair Shaders

struct CrosshairVaryings {
    float4 position [[position]];
    float4 color;
};

vertex CrosshairVaryings crosshair_vertex(
    uint vertexID                [[vertex_id]],
    const device float3*  verts  [[buffer(0)]],
    constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]]
) {
    CrosshairVaryings out;
    
    // Get the local vertex position (in crosshair space)
    float3 localPos = verts[vertexID];
    
    // Billboard in view space: transform crosshair center to view space
    float4 crosshairView = uniforms.modelViewMatrix * float4(0, 0, 0, 1);
    
    // Apply rotation for animation
    // Use the transparency value to pass rotation angle (hack for this demo)
    float rotationAngle = uniforms.transparency * 6.28318530718; // Convert 0-1 to 0-2π
    float cosAngle = cos(rotationAngle);
    float sinAngle = sin(rotationAngle);
    
    // Rotate the crosshair vertex
    float2 rotatedOffset = float2(
        localPos.x * cosAngle - localPos.y * sinAngle,
        localPos.x * sinAngle + localPos.y * cosAngle
    );
    
    // Apply the rotated offset in view space (like stars do)
    // Counteract perspective scaling by making the crosshair size proportional to tan(fov/2)
    float fov_rad = uniforms.fov * (3.14159265359 / 180.0);
    float perspective_scale = tan(fov_rad / 2.0);

    // Scale with FOV to maintain relatively constant apparent size
    float crosshairScale = 1 * pow(perspective_scale, 0.8);
    crosshairView.xy += rotatedOffset * crosshairScale;
    
    // Project to clip space
    out.position = uniforms.projectionMatrix * crosshairView;
    out.color = float4(1.0, 1.0, 1.0, uniforms.color.a); // White color with original alpha
    
    return out;
}

fragment half4 crosshair_fragment(CrosshairVaryings in [[stage_in]]) {
    return half4(in.color);
}