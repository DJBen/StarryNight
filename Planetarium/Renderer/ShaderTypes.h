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
    BufferIndexUniforms      = 2
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
    
    bool forceColor;
    vector_float4 color;
} Uniforms;

#endif /* ShaderTypes_h */

