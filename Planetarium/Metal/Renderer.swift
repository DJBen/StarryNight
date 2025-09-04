/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
A platform independent renderer class
*/
import Metal
import MetalKit
import simd
import StarryNight

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
    // Depth state for stars (no depth writes)
    var starDepthState: MTLDepthStencilState
    
    // Camera system
    public var camera: Camera
    
    // CAMetalDisplayLink properties
    private var metalDisplayLink: CAMetalDisplayLink?
    private var previousTargetPresentationTimestamp: CFTimeInterval = 0
    var isUsingMetalDisplayLink: Bool {
        return metalDisplayLink != nil
    }
    
    var colorMap: MTLTexture
    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var uniformBufferOffset = 0
    var uniformBufferIndex = 0
    var projectionMatrix: float4x4 = float4x4()
    var viewMatrix: float4x4 = matrix_identity_float4x4
    var rotation: Float = 0
    var blendMode = BlendMode.transparency
    var transparency: Float = 0.5
    // Time accumulator for star breathing animation (seconds)
    private var starTime: Float = 0.0
    
    var meshes: [MTKMesh]

    // Star rendering resources
    struct StarInstanceCPU {
        var position: SIMD3<Float>
        var size: Float
        var _pad0: SIMD3<Float> = .zero
        var color: SIMD4<Float>
        var brightness: Float
        var _pad1: SIMD3<Float> = .zero
    }
    var starInstances: [StarInstanceCPU]
    var starInstanceBuffer: MTLBuffer?

    var starQuadVertexBuffer: MTLBuffer?
    var starQuadIndexBuffer: MTLBuffer?
    let starPipelineState: MTLRenderPipelineState

    init?(metalKitView: MTKView) {
        self.device = metalKitView.device!
        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1
        
        // Initialize camera system
        self.camera = Camera()
        
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
        self.skyboxTexture = try! Self.loadSkyboxTexture(device: self.device, contentScaleFactor: metalKitView.contentScaleFactor)
        self.skyboxVertexBuffer = Self.createSkyboxVertexBuffer(device: self.device)
        
        let depthStateDesciptor = MTLDepthStencilDescriptor()
        depthStateDesciptor.depthCompareFunction = MTLCompareFunction.less
        depthStateDesciptor.isDepthWriteEnabled = true
        guard let state = device.makeDepthStencilState(descriptor: depthStateDesciptor) else { return nil }
        depthState = state
        
        // Create skybox depth state - render skybox last with lessEqual depth test and no depth writes
        let skyboxDepthStateDesc = MTLDepthStencilDescriptor()
        skyboxDepthStateDesc.depthCompareFunction = .lessEqual
        skyboxDepthStateDesc.isDepthWriteEnabled = false
        guard let skyboxDepthState = device.makeDepthStencilState(descriptor: skyboxDepthStateDesc) else { return nil }
        self.skyboxDepthState = skyboxDepthState

    // Star depth state: depth test lessEqual, enable depth writes so skybox (last) won't overwrite stars
        let starDepthDesc = MTLDepthStencilDescriptor()
        starDepthDesc.depthCompareFunction = .lessEqual
    starDepthDesc.isDepthWriteEnabled = true
        guard let starDepthState = device.makeDepthStencilState(descriptor: starDepthDesc) else { return nil }
        self.starDepthState = starDepthState
        
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

        // Initialize star rendering resources
        self.starPipelineState = try! Self.createStarPipeline(device: device, view: metalKitView)
        (starQuadVertexBuffer, starQuadIndexBuffer) = Self.createStarQuad(device: device)
        (starInstances, starInstanceBuffer) = Self.loadBrightestStars(device: device)

        super.init()
        
        // Set up camera delegate to receive matrix updates
        self.camera.delegate = self
    }
    
    deinit {
        stopMetalDisplayLink()
    }
    
    // MARK: - CAMetalDisplayLink Setup
    
    func setupMetalDisplayLink(metalLayer: CAMetalLayer) {
        // Create and configure the Metal display link
        metalDisplayLink = CAMetalDisplayLink(metalLayer: metalLayer)
        metalDisplayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: 120.0, preferred: 120.0)
        metalDisplayLink?.preferredFrameLatency = 2
        metalDisplayLink?.isPaused = false
        metalDisplayLink?.delegate = self
        
        startMetalDisplayLink()
    }
    
    private func startMetalDisplayLink() {
        guard let metalDisplayLink = metalDisplayLink else { return }
        previousTargetPresentationTimestamp = CACurrentMediaTime()
        metalDisplayLink.add(to: .current, forMode: .common)
        metalDisplayLink.isPaused = false
    }
    
    private func stopMetalDisplayLink() {
        guard let metalDisplayLink = metalDisplayLink else { return }
        metalDisplayLink.remove(from: .current, forMode: .common)
        metalDisplayLink.invalidate()
        self.metalDisplayLink = nil
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
        // Move the first box closer and more in front of the camera for better visibility
        var modelMatrix = float4x4(translationX: 0.0, translationY: 0.0, translationZ: -5.0) * float4x4(rotationAngle: rotation, axis: rotationAxis)
        // Use the camera's view matrix instead of hardcoded view transformation
        uniforms0[0].modelViewMatrix = viewMatrix * modelMatrix
        
        uniforms0[0].forceColor = false
        uniforms0[0].color = SIMD4<Float>(1.0, 0.0, 1.0, 1.0)
        uniforms0[0].blendMode = UInt32(BlendMode.none.rawValue)
        uniforms0[0].transparency = 1.0
        
        let uniforms1 = uniformsForObject(index: 1)
        uniforms1[0].projectionMatrix = projectionMatrix
        // Move the second box closer and to the side for better visibility
        modelMatrix = float4x4(translationX: 3.0, translationY: 0.0, translationZ: -5.0) * float4x4(rotationAngle: rotation, axis: rotationAxis)
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

        let uniformOffset = uniformBufferOffset + boxIndex * alignedUniformsSize

        renderEncoder.setVertexBuffer(dynamicUniformBuffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setFragmentBuffer(dynamicUniformBuffer, offset: uniformOffset, index: BufferIndex.uniforms.rawValue)

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

    // MARK: - Stars
    private static func createStarQuad(device: MTLDevice) -> (MTLBuffer?, MTLBuffer?) {
        // Quad in NDC-like local space [-1,1] with z=0
        let verts: [SIMD3<Float>] = [
            SIMD3(-1, -1, 0),
            SIMD3( 1, -1, 0),
            SIMD3( 1,  1, 0),
            SIMD3(-1,  1, 0),
        ]
        let indices: [UInt16] = [0,1,2, 0,2,3]
        let starQuadVertexBuffer = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<SIMD3<Float>>.stride)
        let starQuadIndexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride)
        return (starQuadVertexBuffer, starQuadIndexBuffer)
    }

    private static func createStarPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Star Pipeline"
        descriptor.vertexFunction = library?.makeFunction(name: "star_vertex")
        descriptor.fragmentFunction = library?.makeFunction(name: "star_fragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
#if os(macOS) || targetEnvironment(simulator)
        descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
#else
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.stencilAttachmentPixelFormat = .stencil8
#endif
        // Additive RGB for visibility, with alpha channel using premultiplied alpha semantics
        if let att = descriptor.colorAttachments[0] {
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one              // additive color
            att.destinationRGBBlendFactor = .one
            att.sourceAlphaBlendFactor = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        // Explicit vertex layout not needed (we provide buffers directly)
       return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func loadBrightestStars(device: MTLDevice) -> ([StarInstanceCPU], MTLBuffer?) {
        guard let starManager = try? StarManager() else {
            return ([], nil)
        }
        let brightest = starManager.brightestStars()
        let starInstances = brightest.map { star in
            // Convert DB coordinate (Double) to Float and rotate to match current convention used in RealityKit code
            let coord = simd_normalize(SIMD3<Float>(Float(star.coordinate.x), Float(star.coordinate.y), Float(star.coordinate.z)))
            // Reorder to match Metal scene axis convention used by skybox (x,z,-y) then 90deg around Y
            var converted = SIMD3<Float>(coord.x, coord.z, -coord.y)
            let rotY = float3x3(
                SIMD3<Float>(0, 0, -1),
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(1, 0, 0)
            )
            converted = rotY * converted

            // Size and brightness from magnitude
            let normMag = max(0.0, min(1.0, Float((6.0 - star.magnitude) / 8.0)))
            let size = 0.012 + normMag * 0.06 // slightly larger for visibility
            let brightness = max(0.3, min(1.0, Float((6.0 - star.magnitude) / 6.0)))

            let color = spectralColor(for: star)
            return StarInstanceCPU(position: converted * 10.0, // on sphere radius ~10 like markers
                                   size: size,
                                   color: SIMD4<Float>(color.x, color.y, color.z, 1.0),
                                   brightness: brightness)
        }
        var starInstanceBuffer: MTLBuffer?
        if starInstances.count > 0 {
            starInstanceBuffer = device.makeBuffer(bytes: starInstances,
                                                         length: starInstances.count * MemoryLayout<StarInstanceCPU>.stride,
                                                         options: .storageModeShared)
            starInstanceBuffer?.label = "Star Instances"
        }
        return (starInstances, starInstanceBuffer)
    }

    private static func spectralColor(for star: Star) -> SIMD3<Float> {
        guard let s = star.spectralClass?.uppercased(), let first = s.first else { return SIMD3<Float>(1,1,1) }
        switch first {
        case "O": return SIMD3(0.6, 0.7, 1.0)
        case "B": return SIMD3(0.7, 0.8, 1.0)
        case "A": return SIMD3(0.9, 0.9, 1.0)
        case "F": return SIMD3(1.0, 1.0, 0.9)
        case "G": return SIMD3(1.0, 1.0, 0.7)
        case "K": return SIMD3(1.0, 0.8, 0.6)
        case "M": return SIMD3(1.0, 0.6, 0.4)
        default: return SIMD3(1.0, 1.0, 1.0)
        }
    }

    private func drawStars(renderEncoder: MTLRenderCommandEncoder) {
        let starPSO = starPipelineState
        guard let quadVB = starQuadVertexBuffer,
              let quadIB = starQuadIndexBuffer,
              let instBuf = starInstanceBuffer,
              starInstances.count > 0 else { return }

        renderEncoder.pushDebugGroup("Stars")
        renderEncoder.setRenderPipelineState(starPSO)
        renderEncoder.setDepthStencilState(starDepthState)
        renderEncoder.setCullMode(.none) // billboard quads

        // Provide camera projection + view (no model) for star billboards
        var starUniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: starTime,
            forceColor: false,
            color: SIMD4<Float>(0,0,0,0)
        )
        renderEncoder.setVertexBytes(&starUniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)

        // Set quad and instance buffers
        renderEncoder.setVertexBuffer(quadVB, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(instBuf, offset: 0, index: 1)

        // Draw instanced
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: quadIB,
            indexBufferOffset: 0,
            instanceCount: starInstances.count
        )
        renderEncoder.popDebugGroup()
    }
    
    private static func loadSkyboxTexture(
        device: MTLDevice,
        contentScaleFactor: CGFloat
    ) throws -> any MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        
        let texture = try textureLoader.newTexture(name: "milky_way", scaleFactor: contentScaleFactor, bundle: nil, options: options)
        return texture
    }
    
    private static func createSkyboxVertexBuffer(device: MTLDevice) -> MTLBuffer {
        // Create a cube with vertices positioned to create proper direction vectors for cube map sampling
        let vertices: [Float] = [
            // Front face
            -1,  1,  1,   -1, -1,  1,    1, -1,  1,    1, -1,  1,    1,  1,  1,   -1,  1,  1,
            // Back face  
            -1,  1, -1,    1,  1, -1,    1, -1, -1,    1, -1, -1,   -1, -1, -1,   -1,  1, -1,
            // Left face
            -1,  1,  1,   -1,  1, -1,   -1, -1, -1,   -1, -1, -1,   -1, -1,  1,   -1,  1,  1,
            // Right face
             1,  1, -1,    1,  1,  1,    1, -1,  1,    1, -1,  1,    1, -1, -1,    1,  1, -1,
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
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 3
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        return try buildRenderPipelineWithDevice(
            device: device,
            metalKitView: metalKitView,
            vertexFunctionName: "skybox_vertex",
            fragmentFunctionName: "skybox_fragment",
            mtlVertexDescriptor: vertexDescriptor
        )
    }
    
    private func renderSkybox(renderEncoder: MTLRenderCommandEncoder) {
        renderEncoder.pushDebugGroup("Render Skybox")
        renderEncoder.setRenderPipelineState(skyboxPipelineState)
        renderEncoder.setDepthStencilState(skyboxDepthState)
        // Since we are in the origin of a celetial sphere with the skybox surrounding us,
        // we are seeing its backside.
        renderEncoder.setCullMode(.front)

        // Set vertex buffer
        renderEncoder.setVertexBuffer(skyboxVertexBuffer, offset: 0, index: 0)
        
        // Set uniforms (view matrix without translation)
        var skyboxUniforms = Uniforms()
        skyboxUniforms.projectionMatrix = projectionMatrix
        
        // Use the camera's view matrix but remove translation to keep skybox at infinity
        var skyboxViewMatrix = viewMatrix
        skyboxViewMatrix.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        skyboxUniforms.modelViewMatrix = skyboxViewMatrix
        
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
        // This method is kept for compatibility but actual rendering 
        // happens through CAMetalDisplayLink when available
        if !isUsingMetalDisplayLink {
            renderFrame(with: nil, view: view)
        }
    }
    
    func renderFrame(with update: CAMetalDisplayLink.Update?, view: MTKView? = nil) {
        /// Per frame updates here
        
        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        if let commandBuffer = commandQueue.makeCommandBuffer() {
            
            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }
            
            self.updateGameState()
            
            var drawable: CAMetalDrawable?
            var renderPassDescriptor: MTLRenderPassDescriptor?
            
            // Get drawable from CAMetalDisplayLink or MTKView
            if let update = update {
                drawable = update.drawable
                renderPassDescriptor = MTLRenderPassDescriptor()
                renderPassDescriptor!.colorAttachments[0].texture = drawable!.texture
                renderPassDescriptor!.colorAttachments[0].loadAction = .clear
                renderPassDescriptor!.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
                renderPassDescriptor!.colorAttachments[0].storeAction = .store
            } else if let view = view {
                drawable = view.currentDrawable
                renderPassDescriptor = view.currentRenderPassDescriptor
            }
            
            guard let finalDrawable = drawable, 
                  let finalRenderPassDescriptor = renderPassDescriptor else {
                return
            }
            
            /// Configure depth and stencil attachments
            finalRenderPassDescriptor.depthAttachment.texture = self.depthTexture
            finalRenderPassDescriptor.stencilAttachment.texture = self.stencilTexture
            finalRenderPassDescriptor.depthAttachment.loadAction = .clear
            finalRenderPassDescriptor.depthAttachment.clearDepth = 1.0
#if os(macOS) || targetEnvironment(simulator)
            finalRenderPassDescriptor.configureStoreActionForAttachments(.store)
#endif

            if var renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalRenderPassDescriptor) {

                /// Primary pass rendering - render objects first
                prepareEncoder(renderEncoder: renderEncoder, label: "Primary Render Encoder")
                renderEncoder.setRenderPipelineState(pipelineState)
                self.drawBox(boxIndex: 0, renderEncoder: renderEncoder)
                
#if os(macOS) || targetEnvironment(simulator)
                renderEncoder.endEncoding()
                
                let newRenderPassDescriptor = finalRenderPassDescriptor
                newRenderPassDescriptor.configureLoadActionForAttachments(.load)
                renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: newRenderPassDescriptor)!
                
                prepareEncoder(renderEncoder: renderEncoder, label: "Blend Render Encoder")
                renderEncoder.setRenderPipelineState(blendPipelineState)
                renderEncoder.setFragmentTexture(finalRenderPassDescriptor.colorAttachments[0].texture, index: TextureIndex.FB.rawValue)
#endif
                self.drawBox(boxIndex: 1, renderEncoder: renderEncoder)
                // Stars blended additively over prior content
                self.drawStars(renderEncoder: renderEncoder)
                /// Render skybox last - only pixels not covered by other objects or stars will render
                self.renderSkybox(renderEncoder: renderEncoder)
                
                renderEncoder.endEncoding()
                
                commandBuffer.present(finalDrawable)
            }
            commandBuffer.commit()
        }
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here
        
        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = float4x4(fieldOfView: radians(fromDegrees: 65),
                                    aspectRatio: aspect, nearZ: 0.1, farZ: 100.0)
        
        // Update camera's aspect ratio
        camera.updateAspectRatio(aspect)
    }
}

// MARK: - Camera Delegate

extension Renderer: CameraDelegate {
    func camera(_ camera: Camera, didUpdateViewMatrix viewMatrix: matrix_float4x4) {
        self.viewMatrix = viewMatrix
    }
    
    func camera(_ camera: Camera, didUpdateProjectionMatrix projectionMatrix: matrix_float4x4) {
        self.projectionMatrix = projectionMatrix
    }
    
    func camera(_ camera: Camera, didUpdateFOV fov: Float) {
        // Optionally handle FOV changes for UI updates or other purposes
        print("Camera FOV updated to: \(fov)°")
    }
}

// MARK: - CAMetalDisplayLink Delegate

extension Renderer: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let deltaTime = update.targetPresentationTimestamp - previousTargetPresentationTimestamp
        previousTargetPresentationTimestamp = update.targetPresentationTimestamp
        
        // Update camera momentum with precise timing
        camera.updateMomentumWithDeltaTime(Float(deltaTime))
    // Advance star animation time
    starTime += Float(deltaTime)
        
        // Render the frame
        renderFrame(with: update)
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
