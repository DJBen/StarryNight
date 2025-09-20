import Metal
import MetalKit
import simd
import StarryNight

// Renderer that draws H3 res0 grid lines with constant screen-space thickness
final class H3GridRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    struct LineInstance { var p0: simd_float3; var p1: simd_float3; var level: UInt32 }

    private var lineInstances: [LineInstance] = []
    private var lineBuffer: MTLBuffer?

    // Keep per-level ranges for adaptive draw
    private var levelRanges: [Int: Range<Int>] = [:]

    // Config
    var colorsByLevel: [SIMD4<Float>] = [
        SIMD4<Float>(0.8, 0.8, 0.8, 0.55), // res0
        SIMD4<Float>(0.2, 0.7, 1.0, 0.55), // res1
        SIMD4<Float>(0.2, 1.0, 0.6, 0.45), // res2
        SIMD4<Float>(1.0, 0.8, 0.2, 0.35)  // res3
    ]
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

        // Build geometry for res 0..3
        var all: [LineInstance] = []
        var cursor = 0
        for level in 0...3 {
            let res = Int32(level)
            let lines = makeGridLines(forRes: res, radius: 10.0)
            let start = cursor
            all.append(contentsOf: lines.map { LineInstance(p0: $0.p0, p1: $0.p1, level: UInt32(level)) })
            cursor = all.count
            levelRanges[level] = start..<cursor
        }
        self.lineInstances = all
        if !lineInstances.isEmpty {
            let len = lineInstances.count * MemoryLayout<LineInstance>.stride
            self.lineBuffer = device.makeBuffer(bytes: lineInstances, length: len, options: .storageModeShared)
            self.lineBuffer?.label = "H3 Grid Lines"
        }
    }

    func drawableSizeWillChange(to size: CGSize) {
        viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, projectionMatrix: matrix_float4x4, viewMatrix: matrix_float4x4, currentFOVDegrees: Float) {
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
        renderEncoder.setVertexBytes(&width, length: MemoryLayout<Float>.size, index: 4)
        renderEncoder.setVertexBytes(&vp, length: MemoryLayout<SIMD2<Float>>.size, index: 5)
        var colorArray = colorsByLevel
        var numColors: UInt32 = UInt32(colorsByLevel.count)
        renderEncoder.setVertexBytes(&colorArray, length: MemoryLayout<SIMD4<Float>>.stride * colorArray.count, index: 6)
        renderEncoder.setVertexBytes(&numColors, length: MemoryLayout<UInt32>.size, index: 7)

        // Adaptive rendering: decide highest level to show given FOV
        // If fov < threshold(level), we can show next level
        let t0 = fovThresholdDegrees(forRes: 0)
        let t1 = fovThresholdDegrees(forRes: 1)
        let t2 = fovThresholdDegrees(forRes: 2)
        let show0 = true
        let show1 = currentFOVDegrees < t0
        let show2 = currentFOVDegrees < t1
        let show3 = currentFOVDegrees < t2
        print("H3Grid draw fov \(currentFOVDegrees) show0 \(show0) show1 \(show1) show2 \(show2) show3 \(show3) thresholds \(t0) \(t1) \(t2)")

        let vertexCountPerInstance = 4
        func drawRange(_ r: Range<Int>) {
            let count = r.count
            guard count > 0 else { return }
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: vertexCountPerInstance, instanceCount: count, baseInstance: r.lowerBound)
        }
        if show0, let r0 = levelRanges[0] { drawRange(r0) }
        if show1, let r1 = levelRanges[1] { drawRange(r1) }
        if show2, let r2 = levelRanges[2] { drawRange(r2) }
        if show3, let r3 = levelRanges[3] { drawRange(r3) }
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
