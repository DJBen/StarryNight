/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Header containing types and enum constants shared between Metal shaders and Swift/ObjC source
*/
#ifndef ShaderTypes_h
#define ShaderTypes_h

#ifdef __METAL_VERSION__
#define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#define NSInteger metal::int32_t
#else
#import <Foundation/Foundation.h>
#endif

#include <simd/simd.h>

typedef NS_ENUM(NSInteger, BufferIndex)
{
    BufferIndexMeshPositions = 0,
    BufferIndexMeshGenerics  = 1,
    BufferIndexUniforms      = 2,
    BufferIndexViewportSize  = 3
};

typedef NS_ENUM(NSInteger, VertexAttribute)
{
    VertexAttributePosition  = 0,
    VertexAttributeTexcoord  = 1,
};

typedef NS_ENUM(NSInteger, TextureIndex)
{
    TextureIndexColor    = 0,
    TextureIndexFB       = 1,
    TextureIndexLinear   = 2,
    TextureIndexMSAA     = 3
};

typedef NS_ENUM(NSInteger, BlendMode)
{
    BlendModeNone            = 0,
    BlendModeTransparency    = 1,
    BlendModeInvert          = 2,
    BlendModeOverlay         = 3,
};

typedef struct
{
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    
    uint32_t blendMode;
    float transparency;
    float fov;
    vector_float4 color;
} Uniforms;

typedef struct {
    simd_float3 position;
    float magnitude;
    simd_float4 color;
    float sensorPixelSize; // Size of the pixel size of sensor, e.g. 4.63e-6.
    float waveLength;
    simd_float2 _pad0; // Padding to make the size a multiple of 16 bytes
} StarInstance;

#endif /* ShaderTypes_h */

