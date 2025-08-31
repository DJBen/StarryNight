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
    out.position = float4(pos.xy, pos.w, pos.w);
    
    // Use vertex position as texture coordinates
    out.texCoords = in.position;
    
    return out;
}

fragment float4 skybox_fragment(SkyboxVertexOut in [[stage_in]],
                               texture2d<float> skyboxTexture [[texture(0)]]) {
    constexpr sampler s(mag_filter::linear, min_filter::linear, mip_filter::linear,
                       address::repeat);
    
    // Convert 3D direction to spherical UV coordinates
    float3 dir = normalize(in.texCoords);
    
    // Convert to spherical coordinates
    float phi = atan2(dir.z, dir.x);
    float theta = acos(dir.y);
    
    // Map to UV coordinates
    float u = (phi + M_PI_F) / (2.0 * M_PI_F);
    float v = theta / M_PI_F;
    
    return skyboxTexture.sample(s, float2(u, v));
}
