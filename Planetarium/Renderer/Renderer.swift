/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A platform independent renderer class
*/
import Metal
import MetalKit
import simd

#if os(macOS) || targetEnvironment(simulator)
let requiredConstantBufferAlignment = 256
#else
let requiredConstantBufferAlignment = 4
#endif

let uniformsConstantBufferAlignment = max(requiredConstantBufferAlignment, MemoryLayout<Uniforms>.alignment)
// The aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size & ~(uniformsConstantBufferAlignment - 1)) + uniformsConstantBufferAlignment
let maxBuffersInFlight = 3
let numConstantDataBuffers = 13
let numObjects = 2
let numFloatValues = 100

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {
    
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    var dynamicUniformBuffer: MTLBuffer
    var constantData: [MTLBuffer]
    var linearTextureBacking: MTLBuffer
    var depthTexture: MTLTexture
    var stencilTexture: MTLTexture
    var linearTexture: MTLTexture
    var msaaTexture: MTLTexture
    var pipelineState: MTLRenderPipelineState
#if os(macOS) || targetEnvironment(simulator)
    var blendPipelineState: MTLRenderPipelineState
#endif
    var depthState: MTLDepthStencilState
    
    // Skybox properties
    var skyboxTexture: MTLTexture
    var skyboxVertexBuffer: MTLBuffer
    var skyboxPipelineState: MTLRenderPipelineState
    var skyboxDepthState: MTLDepthStencilState
    
    var colorMap: MTLTexture
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var projectionMatrix: float4x4 = float4x4()
    var rotation: Float = 0
    var blendMode = BlendMode.transparency
    var transparency: Float = 0.5
    
    var meshes: [MTKMesh]
    
    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        self.dynamicUniformBuffer = allocateUniformBuffers(device: self.device)!
        self.constantData = allocateConstantBuffers(device: self.device)
        self.colorMap = allocateColorMap(device: self.device)!
        self.msaaTexture = allocateMSAATexture(device: self.device)
        let linearTextureResources = allocateLinearTexture(device: self.device, commandQueue: self.commandQueue)
        self.linearTextureBacking = linearTextureResources.backingBuffer
        self.linearTexture = linearTextureResources.linearTexture
        let depthStencilTextures = allocateDepthStencilTextures(device: self.device, metalKitView: metalKitView)
        self.depthTexture = depthStencilTextures.depthTexture
        self.stencilTexture = depthStencilTextures.stencilTexture
        let mtlVertexDescriptor = Renderer.buildMetalVertexDescriptor()
        self.meshes = allocateMeshes(device: self.device, mtlVertexDescriptor: mtlVertexDescriptor)
        
        // Initialize skybox
        self.skyboxTexture = Self.loadSkyboxTexture(device: self.device)
        self.skyboxVertexBuffer = Self.createSkyboxVertexBuffer(device: self.device)
        
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: depthStateDesciptor) else { return nil }
        depthState = state
        
        // Create skybox depth state - render skybox first with always pass
        let skyboxDepthStateDesc = MTLDepthStencilDescriptor()
        skyboxDepthStateDesc.depthCompareFunction = .always
        skyboxDepthStateDesc.isDepthWriteEnabled = true
        guard let skyboxDepthState = device.makeDepthStencilState(descriptor: skyboxDepthStateDesc) else { return nil }
        self.skyboxDepthState = skyboxDepthState
        
        let pipelines = allocatePiplines(device: device, metalKitView: metalKitView, mtlVertexDescriptor: mtlVertexDescriptor)
        pipelineState = pipelines[0]

        #if os(macOS) || targetEnvironment(simulator)
        blendPipelineState = pipelines[1]
        metalKitView.framebufferOnly = false
        #endif
        
        // Create skybox pipeline state
        do {
            let skyboxPipeline = try Self.createSkyboxPipelineState(device: device, metalKitView: metalKitView)
            self.skyboxPipelineState = skyboxPipeline
        } catch {
            fatalError()
        }

        super.init()
    }
    
    class func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        // Creete a Metal vertex descriptor specifying how vertices will by laid out for input into our render
        //   pipeline and how we'll layout our Model IO vertices
        
        let mtlVertexDescriptor = MTLVertexDescriptor()
        
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].format = MTLVertexFormat.float3
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.position.rawValue].bufferIndex = BufferIndex.meshPositions.rawValue
        
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].format = MTLVertexFormat.float2
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].offset = 0
        mtlVertexDescriptor.attributes[VertexAttribute.texcoord.rawValue].bufferIndex = BufferIndex.meshGenerics.rawValue
        
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stride = MemoryLayout<Float>.stride * 3 // float3 is a packed type
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshPositions.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stride = MemoryLayout<SIMD2<Float>>.stride
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepRate = 1
        mtlVertexDescriptor.layouts[BufferIndex.meshGenerics.rawValue].stepFunction = MTLVertexStepFunction.perVertex
        
        return mtlVertexDescriptor
    }
    
    class func loadTexture(device: MTLDevice,
                           textureName: String) throws -> MTLTexture {
        /// Load texture data with optimal parameters for sampling
        
        let textureLoader = MTKTextureLoader(device: device)
        
        let textureLoaderOptions = [
            MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            MTKTextureLoader.Option.textureStorageMode: NSNumber(value: MTLStorageMode.`private`.rawValue)
        ]
        
        return try textureLoader.newTexture(name: textureName,
                                            scaleFactor: 1.0,
                                            bundle: nil,
                                            options: textureLoaderOptions)
        
    }
    
    private func updateDynamicBufferState() {
        /// Update the state of our uniform buffers before rendering
        
        uniformBufferIndex = (uniformBufferIndex + 1) % maxBuffersInFlight
        
        uniformBufferOffset = alignedUniformsSize * numObjects * uniformBufferIndex
    }
    
    private func uniformsForObject(index: Int) -> UnsafeMutablePointer<Uniforms> {
        let offsetInBuffer = uniformBufferOffset + alignedUniformsSize * index
        return UnsafeMutableRawPointer(dynamicUniformBuffer.contents() + offsetInBuffer).bindMemory(to: Uniforms.self, capacity: 1)
    }
    
    private func updateGameState() {
        self.updateDynamicBufferState()

        /// Update any game state before rendering
        let uniforms0 = uniformsForObject(index: 0)
        uniforms0[0].projectionMatrix = projectionMatrix
        let rotationAxis = SIMD3<Float>(1, 1, 0)
        var modelMatrix = float4x4(translationX: 0.0, translationY: -1.0, translationZ: 0.0) * float4x4(rotationAngle: rotation, axis: rotationAxis)
        let viewMatrix = float4x4(translationX: 0.0, translationY: 0.0, translationZ: -8.0)
        uniforms0[0].modelViewMatrix = viewMatrix * modelMatrix
        
        uniforms0[0].forceColor = false
        uniforms0[0].color = SIMD4<Float>(1.0, 0.0, 1.0, 1.0)
        uniforms0[0].blendMode = UInt32(BlendMode.none.rawValue)
        uniforms0[0].transparency = 1.0
        
        let uniforms1 = uniformsForObject(index: 1)
        uniforms1[0].projectionMatrix = projectionMatrix
        modelMatrix = float4x4(translationX: 1.0, translationY: 0.0, translationZ: 1.0) * float4x4(rotationAngle: rotation, axis: rotationAxis)
        uniforms1[0].modelViewMatrix = viewMatrix * modelMatrix
        
        uniforms1[0].forceColor = true
        uniforms1[0].color = SIMD4<Float>(0.0, 0.0, 1.0, 1.0)
        uniforms1[0].blendMode = UInt32(self.blendMode.rawValue)
        uniforms1[0].transparency = self.transparency
        
        rotation += 0.01
    }
    
    private func bindVertexDescriptorsForMesh(mesh: MTKMesh, renderEncoder: MTLRenderCommandEncoder) {
        for (index, element) in mesh.vertexDescriptor.layouts.enumerated() {
            guard let layout = element as? MDLVertexBufferLayout else {
                return
            }
            
            if layout.stride != 0 {
                let buffer = mesh.vertexBuffers[index]
                renderEncoder.setVertexBuffer(buffer.buffer, offset: buffer.offset, index: index)
            }
        }
    }
    
    private func drawBox(boxIndex: Int, renderEncoder: MTLRenderCommandEncoder) {
        assert(boxIndex < numObjects)
        self.bindVertexDescriptorsForMesh(mesh: meshes[boxIndex], renderEncoder: renderEncoder)

        renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset: boxIndex * alignedUniformsSize, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset: boxIndex * alignedUniformsSize, index: BufferIndex.uniforms.rawValue)

        var constantBufferIndex = BufferIndex.uniforms.rawValue + 1
        let constantBufferOffset = MemoryLayout<vector_float4>.size * 16

        assert((constantBufferOffset & (requiredConstantBufferAlignment - 1)) == 0)

        for index in 0..<numConstantDataBuffers {
            renderEncoder.setFragmentBuffer(self.constantData[index], offset: constantBufferOffset, index: constantBufferIndex)
            constantBufferIndex += 1
        }

        renderEncoder.setFragmentTexture(colorMap, index: TextureIndex.color.rawValue)
        renderEncoder.setFragmentTexture(self.linearTexture, index: TextureIndex.linear.rawValue)
        renderEncoder.setFragmentTexture(self.msaaTexture, index: TextureIndex.MSAA.rawValue)
        
        for submesh in meshes[boxIndex].submeshes {
            renderEncoder.drawIndexedPrimitives(type: submesh.primitiveType,
                                                indexCount: submesh.indexCount,
                                                indexType: submesh.indexType,
                                                indexBuffer: submesh.indexBuffer.buffer,
                                                indexBufferOffset: submesh.indexBuffer.offset)
            
        }
    }
    
    private static func loadSkyboxTexture(device: MTLDevice) -> any MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
            .origin: MTKTextureLoader.Origin.bottomLeft
        ]
        
        do {
            let texture = try textureLoader.newTexture(name: "milky_way", scaleFactor: 1.0, bundle: nil, options: options)
            print("Skybox texture loaded successfully: \(texture.width)x\(texture.height)")
            return texture
        } catch {
            print("Could not load skybox texture: \(error)")
            fatalError("Could not load skybox texture: \(error)")
        }
    }
    
    private static func createSkyboxVertexBuffer(device: MTLDevice) -> MTLBuffer {
        // Create a large cube that will encompass the entire view
        let vertices: [Float] = [
            // Front face
            -1,  1,  1,   -1, -1,  1,    1, -1,  1,    1, -1,  1,    1,  1,  1,   -1,  1,  1,
            // Back face  
            -1,  1, -1,    1,  1, -1,    1, -1, -1,    1, -1, -1,   -1, -1, -1,   -1,  1, -1,
            // Left face
            -1,  1, -1,   -1,  1,  1,   -1, -1,  1,   -1, -1,  1,   -1, -1, -1,   -1,  1, -1,
            // Right face
             1,  1,  1,    1,  1, -1,    1, -1, -1,    1, -1, -1,    1, -1,  1,    1,  1,  1,
            // Top face
            -1,  1, -1,   -1,  1,  1,    1,  1,  1,    1,  1,  1,    1,  1, -1,   -1,  1, -1,
            // Bottom face
            -1, -1,  1,   -1, -1, -1,    1, -1, -1,    1, -1, -1,    1, -1,  1,   -1, -1,  1
        ]
        
        guard let buffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: []) else {
            fatalError("Could not create skybox vertex buffer")
        }
        return buffer
    }
    
    private static func createSkyboxPipelineState(device: MTLDevice, metalKitView: MTKView) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()!

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "skybox_vertex")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "skybox_fragment")
        pipelineDescriptor.colorAttachments[0].pixelFormat = metalKitView.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 3
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        pipelineDescriptor.vertexDescriptor = vertexDescriptor
        
        return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
    }
    
    private func renderSkybox(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.pushDebugGroup("Render Skybox")
        renderEncoder.setRenderPipelineState(skyboxPipelineState)
        renderEncoder.setDepthStencilState(skyboxDepthState)
        renderEncoder.setCullMode(.none) // Don't cull any faces for skybox
        
        // Set vertex buffer
        renderEncoder.setVertexBuffer(skyboxVertexBuffer, offset: 0, index: 0)
        
        // Set uniforms (view matrix without translation)
        var skyboxUniforms = Uniforms()
        skyboxUniforms.projectionMatrix = projectionMatrix
        
        // Remove translation from view matrix but keep rotation
        let viewMatrix = float4x4(translationX: 0.0, translationY: 0.0, translationZ: -8.0)
        var viewNoTranslation = viewMatrix
        viewNoTranslation.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        skyboxUniforms.modelViewMatrix = viewNoTranslation
        
        renderEncoder.setVertexBytes(&skyboxUniforms, length: MemoryLayout<Uniforms>.size, index: 1)
        
        // Set skybox texture
        renderEncoder.setFragmentTexture(skyboxTexture, index: 0)
        
        // Draw the skybox
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        renderEncoder.popDebugGroup()
    }
    
    func prepareEncoder(renderEncoder: MTLRenderCommandEncoder, label: String) {
        renderEncoder.label = label
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
        renderEncoder.setDepthStencilState(depthState)
    }
    
    func draw(in view: MTKView) {
        /// Per frame updates hare
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }
            
            self.updateGameState()
            
            /// Delay getting the currentRenderPassDescriptor until we absolutely need it to avoid
            ///   holding onto the drawable and blocking the display pipeline any longer than necessary
            let renderPassDescriptor = view.currentRenderPassDescriptor
            renderPassDescriptor?.depthAttachment.texture = self.depthTexture
            renderPassDescriptor?.stencilAttachment.texture = self.stencilTexture
#if os(macOS) || targetEnvironment(simulator)
            renderPassDescriptor?.configureStoreActionForAttachments(.store)
#endif

            if var renderPassDescriptor = renderPassDescriptor,
                var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) {
                
                /// Render skybox first to establish background
                self.renderSkybox(renderEncoder: renderEncoder)
                
                /// Final pass rendering code here
                prepareEncoder(renderEncoder: renderEncoder, label: "Primary Render Encoder")
                renderEncoder.setRenderPipelineState(pipelineState)
                self.drawBox(boxIndex: 0, renderEncoder: renderEncoder)
                
#if os(macOS) || targetEnvironment(simulator)
                renderEncoder.endEncoding()
                
                renderPassDescriptor = view.currentRenderPassDescriptor!
                renderPassDescriptor.depthAttachment.texture = self.depthTexture
                renderPassDescriptor.stencilAttachment.texture = self.stencilTexture
                renderPassDescriptor.configureLoadActionForAttachments(.load)
                renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
                
                prepareEncoder(renderEncoder: renderEncoder, label: "Blend Render Encoder")
                renderEncoder.setRenderPipelineState(blendPipelineState)
                renderEncoder.setFragmentTexture(view.currentRenderPassDescriptor?.colorAttachments[0].texture, index: TextureIndex.FB.rawValue)
#endif
                self.drawBox(boxIndex: 1, renderEncoder: renderEncoder)
                
                renderEncoder.endEncoding()
                
                if let drawable = view.currentDrawable {
                    commandBuffer.present(drawable)
                }
            }
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = float4x4(fieldOfView: radians(fromDegrees: 65),
                                    aspectRatio: aspect, nearZ: 0.1, farZ: 100.0)
    }
}

func align(_ value: Int, alignment: Int) -> Int {
    return (value + (alignment - 1)) & ~(alignment - 1)
}

#if os(macOS) || targetEnvironment(simulator)
extension MTLRenderPassDescriptor {
    func configureLoadActionForAttachments(_ loadAction: MTLLoadAction) {
        // We need to ensure that the previous render encoder's attachments are loaded
        self.colorAttachments[0].loadAction = loadAction
        self.depthAttachment.loadAction = loadAction
        self.stencilAttachment.loadAction = loadAction
    }
    
    func configureStoreActionForAttachments(_ storeAction: MTLStoreAction) {
        // We need to ensure that the current render encoder's attachments are stored for the next encoder to load
        self.colorAttachments[0].storeAction = storeAction
        self.depthAttachment.storeAction = storeAction
        self.stencilAttachment.storeAction = storeAction
    }
    
}
#endif
