import Metal
import MetalKit
import simd
import StarryNight

// Renderer that draws H3 res0 grid lines with constant screen-space thickness
final class H3GridRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    struct LineInstance { var p0: simd_float3; var p1: simd_float3 }

    private var lineInstances: [LineInstance] = []
    private var lineBuffer: MTLBuffer?

    // Config
    var color: SIMD4<Float> = SIMD4<Float>(0.2, 0.7, 1.0, 0.6)
    var pixelWidth: Float = 2
    private var viewportSize: SIMD2<Float> = .zero

    init(device: MTLDevice, view: MTKView) {
        self.device = device

        // Pipeline
        self.pipelineState = try! H3GridRenderer.buildPipeline(device: device, view: view)

        // Depth: test but don't write
        let ds = MTLDepthStencilDescriptor()
        ds.depthCompareFunction = .lessEqual
        ds.isDepthWriteEnabled = false
        guard let depth = device.makeDepthStencilState(descriptor: ds) else { fatalError("grid depth state") }
        self.depthState = depth

        // Build geometry from library helper
        let lines = makeRes0GridLines(radius: 10.0)
        self.lineInstances = lines.map { LineInstance(p0: $0.p0, p1: $0.p1) }
        if !lineInstances.isEmpty {
            let len = lineInstances.count * MemoryLayout<LineInstance>.stride
            self.lineBuffer = device.makeBuffer(bytes: lineInstances, length: len, options: .storageModeShared)
            self.lineBuffer?.label = "H3 Grid Lines"
        }
    }

    func drawableSizeWillChange(to size: CGSize) {
        viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, projectionMatrix: matrix_float4x4, viewMatrix: matrix_float4x4) {
        guard let lineBuffer = lineBuffer, lineInstances.count > 0 else { return }

        renderEncoder.pushDebugGroup("H3 Grid")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)

        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: 1.0,
            forceColor: false,
            color: SIMD4<Float>(0,0,0,0)
        )
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)

    renderEncoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)

    var width = pixelWidth
    var vp = viewportSize
    var gridColor = color
    renderEncoder.setVertexBytes(&width, length: MemoryLayout<Float>.size, index: 4)
    renderEncoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.size, index: 5)
    renderEncoder.setVertexBytes(&gridColor, length: MemoryLayout<SIMD4<Float>>.size, index: 6)

        // Each line becomes a quad (4 verts) drawn as two triangles
        let vertexCountPerInstance = 4
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCountPerInstance, instanceCount: lineInstances.count)
        renderEncoder.popDebugGroup()
    }

    private static func buildPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()
        let desc = MTLRenderPipelineDescriptor()
        desc.label = "H3 Grid Pipeline"
        desc.vertexFunction = library?.makeFunction(name: "h3line_vertex")
        desc.fragmentFunction = library?.makeFunction(name: "h3line_fragment")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
#if os(macOS) || targetEnvironment(simulator)
        desc.depthAttachmentPixelFormat = .depth32Float_stencil8
        desc.stencilAttachmentPixelFormat = .depth32Float_stencil8
#else
        desc.depthAttachmentPixelFormat = .depth32Float
        desc.stencilAttachmentPixelFormat = .stencil8
#endif
        if let att = desc.colorAttachments[0] {
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .one
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.sourceAlphaBlendFactor = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: desc)
    }
}
