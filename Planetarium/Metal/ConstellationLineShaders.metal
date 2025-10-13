/*
 Metal shaders dedicated to constellation line rendering.
 */

#include <metal_stdlib>
#include <simd/simd.h>
#include "ShaderTypes.h"

using namespace metal;

struct ConstellationLineVertexOut {
    float4 position [[position]];
    float3 baseColor;
    float baseAlpha;
    float fovMultiplier;
    float lineLength [[flat]];
    float progress [[center_no_perspective]];
};

struct ConstellationLineVertexIn {
    float3 position;
    float3 lineStart;
    float3 lineEnd;
};

vertex ConstellationLineVertexOut constellation_line_vertex(
    uint vid [[vertex_id]],
    constant Uniforms &uniforms [[buffer(BufferIndexUniforms)]],
    constant float2 &viewportSize [[buffer(BufferIndexViewportSize)]],
    const device ConstellationLineVertexIn *vertices [[buffer(0)]]
) {
    ConstellationLineVertexOut out;

    const ConstellationLineVertexIn vert = vertices[vid];

    const float4 worldPosition = float4(vert.position, 1.0);
    const float4 worldStart = float4(vert.lineStart, 1.0);
    const float4 worldEnd = float4(vert.lineEnd, 1.0);

    const float4 clipPosition = uniforms.projectionMatrix * (uniforms.modelViewMatrix * worldPosition);
    const float4 clipStart = uniforms.projectionMatrix * (uniforms.modelViewMatrix * worldStart);
    const float4 clipEnd = uniforms.projectionMatrix * (uniforms.modelViewMatrix * worldEnd);

    const float safeW = 1e-5;
    float currentW = fabs(clipPosition.w) < safeW ? copysign(safeW, clipPosition.w) : clipPosition.w;
    float startW = fabs(clipStart.w) < safeW ? copysign(safeW, clipStart.w) : clipStart.w;
    float endW = fabs(clipEnd.w) < safeW ? copysign(safeW, clipEnd.w) : clipEnd.w;

    const float2 ndcCurrent = clipPosition.xy / currentW;
    const float2 ndcStart = clipStart.xy / startW;
    const float2 ndcEnd = clipEnd.xy / endW;

    const float2 halfViewport = viewportSize * 0.5;
    const float2 deltaPoints = (ndcEnd - ndcStart) * halfViewport;
    const float2 toCurrentPoints = (ndcCurrent - ndcStart) * halfViewport;

    const float lineLength = length(deltaPoints);
    const float distanceFromStart = length(toCurrentPoints);

    out.position = clipPosition;
    out.lineLength = lineLength;
    out.progress = lineLength > 0.0001 ? clamp(distanceFromStart / lineLength, 0.0, 1.0) : 0.0;

    float fovMultiplier = 1.0;
    const float fov = uniforms.fov;
    if (fov < 90.0) {
        fovMultiplier = clamp((fov - 15.0) / (90.0 - 15.0), 0.0, 1.0);
    }

    out.fovMultiplier = fovMultiplier;
    out.baseAlpha = uniforms.color.w;
    out.baseColor = uniforms.color.xyz;

    return out;
}

fragment half4 constellation_line_fragment(ConstellationLineVertexOut in [[stage_in]]) {
    const float targetFadeDistance = 36;
    const float lineLength = in.lineLength;
    const float progress = clamp(in.progress, 0.0, 1.0);

    const float fadeLength = min(targetFadeDistance, lineLength * 0.5);
    const float distanceFromStart = progress * lineLength;
    const float distanceFromEnd = (1.0 - progress) * lineLength;
    const float startAlpha = smoothstep(0.0, fadeLength, distanceFromStart);
    const float endAlpha = smoothstep(0.0, fadeLength, distanceFromEnd);
    float gradientAlpha = startAlpha * endAlpha;

    float finalAlpha = clamp(in.baseAlpha * in.fovMultiplier * gradientAlpha, 0.0, 1.0);
    const float3 rgb = in.baseColor * finalAlpha;
    const float4 premultiplied = float4(rgb, finalAlpha);
    return half4(premultiplied);
}
