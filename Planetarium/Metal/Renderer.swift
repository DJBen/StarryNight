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

    var depthTexture: MTLTexture
    var stencilTexture: MTLTexture

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

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var projectionMatrix: float4x4 = float4x4()
    var viewMatrix: float4x4 = matrix_identity_float4x4
    var rotation: Float = 0
    var blendMode = BlendMode.transparency
    var transparency: Float = 0.5
    // Time accumulator for star breathing animation (seconds)
    private var starTime: Float = 0.0

    // Star rendering resources
    var starInstances: [StarInstance]
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

        let depthStencilTextures = allocateDepthStencilTextures(device: self.device, metalKitView: metalKitView)
        self.depthTexture = depthStencilTextures.depthTexture
        self.stencilTexture = depthStencilTextures.stencilTexture

        // Initialize skybox
        self.skyboxTexture = try! Self.loadSkyboxTexture(device: self.device, contentScaleFactor: metalKitView.contentScaleFactor)
        self.skyboxVertexBuffer = Self.createSkyboxVertexBuffer(device: self.device)

        // Create skybox depth state - render skybox with lessEqual test and no depth writes
        let skyboxDepthStateDesc = MTLDepthStencilDescriptor()
        skyboxDepthStateDesc.depthCompareFunction = .lessEqual
        skyboxDepthStateDesc.isDepthWriteEnabled = false
        guard let skyboxDepthState = device.makeDepthStencilState(descriptor: skyboxDepthStateDesc) else { return nil }
        self.skyboxDepthState = skyboxDepthState

        // Star depth state: depth test lessEqual, no depth writes to avoid occluding skybox at translucent edges
        let starDepthDesc = MTLDepthStencilDescriptor()
        starDepthDesc.depthCompareFunction = .lessEqual
        starDepthDesc.isDepthWriteEnabled = false
        guard let starDepthState = device.makeDepthStencilState(descriptor: starDepthDesc) else { return nil }
        self.starDepthState = starDepthState

#if os(macOS) || targetEnvironment(simulator)
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
        // Premultiplied alpha "over" blending to avoid dark/black edges while preserving color
        if let att = descriptor.colorAttachments[0] {
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.sourceAlphaBlendFactor = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        // Explicit vertex layout not needed (we provide buffers directly)
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func loadBrightestStars(device: MTLDevice) -> ([StarInstance], MTLBuffer?) {
        guard let starManager = try? StarManager() else {
            return ([], nil)
        }
        let brightest = starManager.brightestStars()
        let starInstances = brightest.map { star in
            let coord = simd_normalize(SIMD3<Float>(Float(star.coordinate.x), Float(star.coordinate.y), Float(star.coordinate.z)))
            // Reorder to match Metal scene axis convention used by skybox (x,z,-y) then 90deg around Y
            var converted = SIMD3<Float>(coord.x, coord.z, -coord.y)
            let rotY = float3x3(
                SIMD3<Float>(0, 0, -1),
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(1, 0, 0)
            )
            converted = rotY * converted

            let color = spectralColor(for: star)
            return StarInstance(
                position: converted * 10.0, // on a 10x radius of unit sphere
                magnitude: Float(star.magnitude),
                color: SIMD4<Float>(color.x, color.y, color.z, 1.0),
                lambdaN: averageWavelength(for: star) * 10e-9 * 3, // f/3
                exposureMultiplier: 10,
                sensorPixelSize: 4.63e-6,
                _pad0: .zero
            )
        }
        var starInstanceBuffer: MTLBuffer?
        if starInstances.count > 0 {
            starInstanceBuffer = device.makeBuffer(bytes: starInstances,
                                                   length: starInstances.count * MemoryLayout<StarInstance>.stride,
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

    private static func averageWavelength(for star: Star) -> Float {
        guard let s = star.spectralClass?.uppercased(), let first = s.first else { return 550.0 } // Default to green
        switch first {
        case "O": return 400.0 // Violet-Blue
        case "B": return 450.0 // Blue
        case "A": return 500.0 // Blue-Green
        case "F": return 550.0 // Green
        case "G": return 600.0 // Yellow
        case "K": return 650.0 // Orange
        case "M": return 700.0 // Red
        default: return 550.0
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

            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalRenderPassDescriptor) {

                /// Primary pass rendering - render objects first
                prepareEncoder(renderEncoder: renderEncoder, label: "Primary Render Encoder")

                // Draw skybox before stars so stars can blend over it
                self.renderSkybox(renderEncoder: renderEncoder)
                // Stars blended additively over prior content
                self.drawStars(renderEncoder: renderEncoder)

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
