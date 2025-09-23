#include <metal_stdlib>
using namespace metal;

struct SkyboxUniforms {
    float4x4 projectionMatrix;
    float4x4 modelViewMatrix;
};

struct SkyboxVertexIn {
    float3 position [[attribute(0)]];
};

struct SkyboxVertexOut {
    float4 position [[position]];
    float3 texCoords;
};

vertex SkyboxVertexOut skybox_vertex(SkyboxVertexIn in [[stage_in]],
                                     constant SkyboxUniforms &uniforms [[buffer(1)]]) {
    SkyboxVertexOut out;
    
    // Transform the vertex position but remove translation from view matrix
    float4x4 rotationOnlyView = uniforms.modelViewMatrix;
    rotationOnlyView[3] = float4(0, 0, 0, 1);
    
    float4 pos = uniforms.projectionMatrix * rotationOnlyView * float4(in.position, 1.0);

    // Set z = w to place skybox at far plane (depth = 1.0 after perspective divide)
    // This ensures skybox is only rendered where no other objects exist
    out.position = pos.xyww;

    // For cube map sampling, we need the direction vector from the center
    // Normalize the vertex position to get a proper direction vector
    out.texCoords = normalize(in.position);
    
    return out;
}

fragment float4 skybox_fragment(SkyboxVertexOut in [[stage_in]],
                                texturecube<float> skyboxTexture [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, mip_filter::linear);
    float3 coords = in.texCoords;
    // Texture coordinates needs to invert around z axis.
    coords.x = -coords.x;
    return skyboxTexture.sample(s, coords);
}
