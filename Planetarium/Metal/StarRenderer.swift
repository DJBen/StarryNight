import Metal
import MetalKit
import simd
import StarryNight

/// Renders brightest stars as instanced billboards. Owns its own Metal resources.
final class StarRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer: MTLBuffer?

    private(set) var instances: [StarInstance] = []
    private var instanceBuffer: MTLBuffer?

    init(device: MTLDevice, view: MTKView) {
        self.device = device

        // Pipeline
        self.pipelineState = try! StarRenderer.createPipeline(device: device, view: view)

        // Depth state: test but don't write so translucent edges don't occlude the skybox
        let starDepthDesc = MTLDepthStencilDescriptor()
        starDepthDesc.depthCompareFunction = .lessEqual
        starDepthDesc.isDepthWriteEnabled = false
        guard let ds = device.makeDepthStencilState(descriptor: starDepthDesc) else { fatalError("Star depth state") }
        self.depthState = ds

        // Geometry buffers
        (quadVertexBuffer, quadIndexBuffer) = StarRenderer.createQuad(device: device)

        // Instance data
        (instances, instanceBuffer) = StarRenderer.loadBrightestStars(device: device)
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, projectionMatrix: matrix_float4x4, viewMatrix: matrix_float4x4, time: Float) {
        guard let quadVB = quadVertexBuffer,
              let quadIB = quadIndexBuffer,
              let instBuf = instanceBuffer,
              instances.count > 0 else { return }

        renderEncoder.pushDebugGroup("Stars")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)

        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: time,
            forceColor: false,
            color: SIMD4<Float>(0,0,0,0)
        )
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)

        renderEncoder.setVertexBuffer(quadVB, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(instBuf, offset: 0, index: 1)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: quadIB,
            indexBufferOffset: 0,
            instanceCount: instances.count
        )
        renderEncoder.popDebugGroup()
    }

    // MARK: - Private helpers

    private static func createQuad(device: MTLDevice) -> (MTLBuffer?, MTLBuffer?) {
        let verts: [SIMD3<Float>] = [
            SIMD3(-1, -1, 0),
            SIMD3( 1, -1, 0),
            SIMD3( 1,  1, 0),
            SIMD3(-1,  1, 0),
        ]
        let indices: [UInt16] = [0,1,2, 0,2,3]
        let vb = device.makeBuffer(bytes: verts, length: verts.count * MemoryLayout<SIMD3<Float>>.stride)
        let ib = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride)
        return (vb, ib)
    }

    private static func createPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
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
        // Premultiplied alpha blending
        if let att = descriptor.colorAttachments[0] {
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.sourceAlphaBlendFactor = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    private static func loadBrightestStars(device: MTLDevice) -> ([StarInstance], MTLBuffer?) {
        guard let starManager = try? StarManager() else {
            return ([], nil)
        }
        let brightest = starManager.brightestStars()
        let stars = brightest.map { star -> StarInstance in
            let coord = simd_normalize(SIMD3<Float>(Float(star.coordinate.x), Float(star.coordinate.y), Float(star.coordinate.z)))
            var converted = SIMD3<Float>(coord.x, coord.z, -coord.y)
            let rotY = float3x3(
                SIMD3<Float>(0, 0, -1),
                SIMD3<Float>(0, 1, 0),
                SIMD3<Float>(1, 0, 0)
            )
            converted = rotY * converted

            let color = spectralColor(for: star)
            return StarInstance(
                position: converted * 10.0,
                magnitude: Float(star.magnitude),
                color: SIMD4<Float>(color.x, color.y, color.z, 1.0),
                lambdaN: averageWavelength(for: star) * 10e-9 * 3,
                exposureMultiplier: 10,
                sensorPixelSize: 4.63e-6,
                _pad0: .zero
            )
        }
        var buffer: MTLBuffer?
        if !stars.isEmpty {
            buffer = device.makeBuffer(bytes: stars, length: stars.count * MemoryLayout<StarInstance>.stride, options: .storageModeShared)
            buffer?.label = "Star Instances"
        }
        return (stars, buffer)
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
        guard let s = star.spectralClass?.uppercased(), let first = s.first else { return 550.0 }
        switch first {
        case "O": return 400.0
        case "B": return 450.0
        case "A": return 500.0
        case "F": return 550.0
        case "G": return 600.0
        case "K": return 650.0
        case "M": return 700.0
        default: return 550.0
        }
    }
}
