/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Helper functions for creating Metal resources.
*/

import Foundation
import Metal
import MetalKit
import simd

func allocatePiplines(device: MTLDevice, metalKitView: MTKView,
                      mtlVertexDescriptor: MTLVertexDescriptor) -> [MTLRenderPipelineState] {
    var pipelines = [MTLRenderPipelineState]()
    do {
        pipelines.append(try buildRenderPipelineWithDevice(device: device,
                                                           metalKitView: metalKitView,
                                                           vertexFunctionName: "vertexShader",
                                                           fragmentFunctionName: "fragmentShader",
                                                           mtlVertexDescriptor: mtlVertexDescriptor))
        #if os(macOS) || targetEnvironment(simulator)
        pipelines.append(try buildRenderPipelineWithDevice(device: device,
                                                           metalKitView: metalKitView,
                                                           vertexFunctionName: "vertexShader",
                                                           fragmentFunctionName: "blendFragmentShader",
                                                           mtlVertexDescriptor: mtlVertexDescriptor))
        #endif
    } catch {
        print("Unable to compile render pipeline state.  Error info: \(error)")
    }
    return pipelines
}

func allocateColorMap(device: MTLDevice) -> MTLTexture? {
    do {
        return try Renderer.loadTexture(device: device, textureName: "ColorMap")
    } catch {
        print("Unable to load texture. Error info: \(error)")
        return nil
    }
}

func allocateUniformBuffers(device: MTLDevice) -> MTLBuffer? {
    let uniformBufferSize = alignedUniformsSize * maxBuffersInFlight
    guard let buffer = device.makeBuffer(length: uniformBufferSize,
                                         options: [MTLResourceOptions.storageModeShared]) else { return nil }
    buffer.label = "UniformBuffer"
    return buffer
}

func allocateMeshes(device: MTLDevice, mtlVertexDescriptor: MTLVertexDescriptor) -> [MTKMesh] {
    do {
        let metalAllocator = MTKMeshBufferAllocator(device: device)
        var meshes = [MTKMesh]()
        meshes.append(try buildMesh(device: device, dimensions: SIMD3<Float>(3, 3, 3), segments: SIMD3<UInt32>(2, 2, 2),
                                    metalAllocator: metalAllocator, mtlVertexDescriptor: mtlVertexDescriptor))
        meshes.append(try buildMesh(device: device, dimensions: SIMD3<Float>(3, 3, 3), segments: SIMD3<UInt32>(2, 2, 2),
                                    metalAllocator: metalAllocator, mtlVertexDescriptor: mtlVertexDescriptor))
        return meshes
    } catch {
        print("Unable to build MetalKit Mesh. Error info: \(error)")
        return []
    }
}

func allocateConstantBuffers(device: MTLDevice) -> [MTLBuffer] {
    let constantBufferLength = MemoryLayout<vector_float4>.size * numFloatValues
    return (0..<numConstantDataBuffers).map { _ in
        device.makeBuffer(length: constantBufferLength, options: [MTLResourceOptions.storageModeShared])!
    }
}

func writeLinearTextureData(dstPtr: UnsafeMutableRawPointer, textureWidth: Int, textureHeight: Int,
                            bytesPerRow: Int) {
    
    // Initialize all pixels to red
    for curHeight in 0..<textureHeight {
        let curPixel: UnsafeMutablePointer<SIMD4<UInt32>> = UnsafeMutableRawPointer(dstPtr +
            curHeight * bytesPerRow).bindMemory(to: SIMD4<UInt32>.self, capacity: textureWidth)
        for curWidth in 0..<textureWidth {
            curPixel[curWidth].x = 255
            curPixel[curWidth].y = 0
            curPixel[curWidth].z = 0
            curPixel[curWidth].w = 255
        }
    }
}

func initializeLinearTextureData(backingBuffer: MTLBuffer, commandQueue: MTLCommandQueue, textureWidth: Int, textureHeight: Int, bytesPerRow: Int) {
    if backingBuffer.storageMode == .private {
        // Create a shared buffer, initialize the shared buffer's data,
        // and blit the shared texture to the linear texture's backing buffer
        let bytesPerImage = bytesPerRow * textureHeight
        let tmpBuffer = backingBuffer.device.makeBuffer(length: bytesPerImage, options: .storageModeShared)!
        writeLinearTextureData(dstPtr: tmpBuffer.contents(), textureWidth: textureWidth, textureHeight: textureHeight, bytesPerRow: bytesPerRow)
        
        let blitCommandBuffer = commandQueue.makeCommandBuffer()!
        let blitEncoder = blitCommandBuffer.makeBlitCommandEncoder()!
        
        blitEncoder.copy(from: tmpBuffer, sourceOffset: 0, to: backingBuffer, destinationOffset: 0, size: bytesPerImage)
        
        blitEncoder.endEncoding()
        blitCommandBuffer.commit()
        blitCommandBuffer.waitUntilCompleted()
        
    } else {
        // copying data directly to the buffer's contents pointer is only allowed for shared buffers
        writeLinearTextureData(dstPtr: backingBuffer.contents(), textureWidth: textureWidth, textureHeight: textureHeight, bytesPerRow: bytesPerRow)

    }
}

func allocateLinearTexture(device: MTLDevice, commandQueue: MTLCommandQueue) -> (backingBuffer: MTLBuffer, linearTexture: MTLTexture) {
    #if os(macOS) || targetEnvironment(simulator)
    let options = MTLResourceOptions.storageModePrivate
    #else
    let options = MTLResourceOptions.storageModeShared
    #endif
    let textureWidth = 256
    let textureHeight = 512
    let pixelSize = 4 * MemoryLayout<UInt32>.size
    
    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.pixelFormat = MTLPixelFormat.rgba32Uint
    textureDescriptor.width = textureWidth
    textureDescriptor.height = textureHeight
    textureDescriptor.resourceOptions = options
    
    let requiredAlignment = device.minimumLinearTextureAlignment(for: textureDescriptor.pixelFormat)
    let bytesPerRow = align(textureWidth * pixelSize, alignment: requiredAlignment)
    let bytesPerImage = bytesPerRow * textureHeight
    
    let linearTextureBacking = device.makeBuffer(length: bytesPerImage, options: options)!
    let linearTexture = linearTextureBacking.makeTexture(descriptor: textureDescriptor, offset: 0, bytesPerRow: bytesPerRow)!
    
    initializeLinearTextureData(backingBuffer: linearTextureBacking, commandQueue: commandQueue,
                                textureWidth: textureWidth, textureHeight: textureHeight, bytesPerRow: bytesPerRow)
    
    return (linearTextureBacking, linearTexture)
}

func allocateMSAATexture(device: MTLDevice) -> MTLTexture {
    let msaaTextureDescriptor = MTLTextureDescriptor()
    msaaTextureDescriptor.textureType = MTLTextureType.type2DMultisample
    msaaTextureDescriptor.width = 1024
    msaaTextureDescriptor.height = 1024
    msaaTextureDescriptor.pixelFormat = MTLPixelFormat.rgba8Unorm
    #if os(macOS) || targetEnvironment(simulator)
    msaaTextureDescriptor.sampleCount = 4
    msaaTextureDescriptor.storageMode = MTLStorageMode.private
    #else
    msaaTextureDescriptor.sampleCount = 2
    msaaTextureDescriptor.storageMode = MTLStorageMode.shared
    #endif
    return device.makeTexture(descriptor: msaaTextureDescriptor)!
}

func allocateDepthStencilTextures(device: MTLDevice,
                                  metalKitView: MTKView) -> (depthTexture: MTLTexture, stencilTexture: MTLTexture) {
    #if os(macOS) || targetEnvironment(simulator)
    let depthPixelFormat = MTLPixelFormat.depth32Float_stencil8
    let stencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
    let storageMode = MTLStorageMode.private
    #else
    let depthPixelFormat = MTLPixelFormat.depth32Float
    let stencilPixelFormat = MTLPixelFormat.stencil8
    let storageMode = MTLStorageMode.shared
    #endif
    
    let depthStencilTextureDescriptor = MTLTextureDescriptor()
    depthStencilTextureDescriptor.textureType = MTLTextureType.type2D
    depthStencilTextureDescriptor.width = Int(metalKitView.drawableSize.width)
    depthStencilTextureDescriptor.height = Int(metalKitView.drawableSize.height)
    depthStencilTextureDescriptor.usage = MTLTextureUsage.renderTarget
    depthStencilTextureDescriptor.storageMode = storageMode
    
    depthStencilTextureDescriptor.pixelFormat = depthPixelFormat
    let depthTexture = device.makeTexture(descriptor: depthStencilTextureDescriptor)!
    var stencilTexture: MTLTexture
    if depthPixelFormat != stencilPixelFormat {
        depthStencilTextureDescriptor.pixelFormat = stencilPixelFormat
        stencilTexture = device.makeTexture(descriptor: depthStencilTextureDescriptor)!
    } else {
        stencilTexture = depthTexture
    }
    return (depthTexture, stencilTexture)
}

func buildRenderPipelineWithDevice(device: MTLDevice,
                                   metalKitView: MTKView,
                                   vertexFunctionName: String,
                                   fragmentFunctionName: String,
                                   mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTLRenderPipelineState {
    /// Build a render state pipeline object
    #if os(macOS) || targetEnvironment(simulator)
    let depthPixelFormat = MTLPixelFormat.depth32Float_stencil8
    let stencilPixelFormat = MTLPixelFormat.depth32Float_stencil8
    #else
    let depthPixelFormat = MTLPixelFormat.depth32Float
    let stencilPixelFormat = MTLPixelFormat.stencil8
    #endif
    
    let library = device.makeDefaultLibrary()
    
    let vertexFunction = library?.makeFunction(name: vertexFunctionName)
    let fragmentFunction = library?.makeFunction(name: fragmentFunctionName)
    
    let pipelineDescriptor = MTLRenderPipelineDescriptor()
    pipelineDescriptor.label = "RenderPipeline"
    pipelineDescriptor.sampleCount = metalKitView.sampleCount
    pipelineDescriptor.vertexFunction = vertexFunction
    pipelineDescriptor.fragmentFunction = fragmentFunction
    pipelineDescriptor.vertexDescriptor = mtlVertexDescriptor
    
    pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
    pipelineDescriptor.depthAttachmentPixelFormat = depthPixelFormat
    pipelineDescriptor.stencilAttachmentPixelFormat = stencilPixelFormat
    
    return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
}

func buildMesh(device: MTLDevice,
               dimensions: vector_float3, segments: vector_uint3,
               metalAllocator: MTKMeshBufferAllocator,
               mtlVertexDescriptor: MTLVertexDescriptor) throws -> MTKMesh {
    /// Create and condition mesh data to feed into a pipeline using the given vertex descriptor
    
    let mdlMesh = MDLMesh.newBox(withDimensions: dimensions,
                                 segments: segments,
                                 geometryType: MDLGeometryType.triangles,
                                 inwardNormals: false,
                                 allocator: metalAllocator)
    
    let mdlVertexDescriptor = MTKModelIOVertexDescriptorFromMetal(mtlVertexDescriptor)
    
    guard let attributes = mdlVertexDescriptor.attributes as? [MDLVertexAttribute] else {
        throw RendererError.badVertexDescriptor
    }
    attributes[VertexAttribute.position.rawValue].name = MDLVertexAttributePosition
    attributes[VertexAttribute.texcoord.rawValue].name = MDLVertexAttributeTextureCoordinate
    
    mdlMesh.vertexDescriptor = mdlVertexDescriptor
    
    return try MTKMesh(mesh: mdlMesh, device: device)
}
