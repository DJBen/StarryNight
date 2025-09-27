/*
See the LICENSE.txt file for this sample's licensing information.

Abstract:
Metal shaders for triangle indicator rendering
*/

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

// MARK: - Triangle Indicator Shaders

struct TriangleIndicatorVaryings {
    float4 position [[position]];
    float4 color;
};

struct TriangleIndicatorParameters {
    float2 screenPositionPixels;
    float rotation;
    float3 padding;
};

vertex TriangleIndicatorVaryings triangle_indicator_vertex(
    uint vertexID                [[vertex_id]],
    const device float2*  verts  [[buffer(0)]],
    constant TriangleIndicatorParameters &params [[buffer(1)]],
    constant float2 &viewportSize [[buffer(BufferIndexViewportSize)]],
    constant Uniforms & uniforms [[buffer(BufferIndexUniforms)]]
) {
    TriangleIndicatorVaryings out;
    
    // Get the local vertex position (triangle geometry)
    float2 localPos = verts[vertexID];
    
    // Apply rotation provided by the CPU side and flip 180 degrees
    float rotationAngle = params.rotation + 3.14159265f;
    float cosAngle = cos(rotationAngle);
    float sinAngle = sin(rotationAngle);
    
    // Rotate the triangle vertex around Z axis
    float2 rotatedOffset = float2(
        localPos.x * cosAngle - localPos.y * sinAngle,
        localPos.x * sinAngle + localPos.y * cosAngle
    );
    
    // Position in pixel space relative to viewport center
    float2 finalPixelPosition = params.screenPositionPixels + rotatedOffset;

    // Convert pixel coordinates to clip space using viewport dimensions
    float2 clipSpace = finalPixelPosition / (viewportSize / 2.0);
    
    // Output position in clip space (NDC * w = clip coordinates)
    out.position = float4(clipSpace.x, clipSpace.y, 0.0, 1.0);
    out.color = uniforms.color;
    
    return out;
}

fragment half4 triangle_indicator_fragment(TriangleIndicatorVaryings in [[stage_in]]) {
    return half4(in.color);
}