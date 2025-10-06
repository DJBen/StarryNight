import Ch3
import Metal
import MetalKit
import simd
import StarryNight

// Renderer that draws H3 res0 grid lines with constant screen-space thickness
final class H3GridRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    struct LineInstance {
        var p0: simd_float3
        var p1: simd_float3
        var level: UInt32
    }

    // Config
    var colorsByLevel: [SIMD4<Float>] = [
        SIMD4<Float>(0.8, 0.8, 0.8, 0.55), // res0
        SIMD4<Float>(0.2, 0.7, 1.0, 0.55), // res1
        SIMD4<Float>(0.2, 1.0, 0.6, 0.45), // res2
    ]
    var pixelWidth: Float = 2
    private var viewportSize: SIMD2<Float> = .zero
    // Visibility toggle
    var isVisible: Bool = false

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
    }

    func drawableSizeWillChange(to size: CGSize) {
        viewportSize = SIMD2<Float>(Float(size.width), Float(size.height))
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, projectionMatrix: matrix_float4x4, viewMatrix: matrix_float4x4, currentFOVDegrees: Float) {
        // Respect visibility flag
        guard isVisible else { return }
        // Adaptive rendering: decide which levels to show
        var resolutionsToShow: [Int32] = [0]
        if currentFOVDegrees < fovThresholdDegrees(forRes: 0) {
            resolutionsToShow.append(1)
        }
        if currentFOVDegrees < fovThresholdDegrees(forRes: 1) {
            resolutionsToShow.append(2)
        }

        // Project viewport corners to world space to find visible H3 cells
        let viewportCorners = [
            simd_float3(-1, -1, 1), // Bottom-Left
            simd_float3(1, -1, 1),  // Bottom-Right
            simd_float3(1, 1, 1),   // Top-Right
            simd_float3(-1, 1, 1)   // Top-Left
        ]
        let invMVP = (projectionMatrix * viewMatrix).inverse
        let worldCorners = viewportCorners.map {
            let worldPos = invMVP * simd_float4($0, 1.0)
            return simd_normalize(SIMD3<Float>(x: worldPos.x, y: worldPos.y, z: worldPos.z) / worldPos.w)
        }

        // World space to lat/lng in radians
        let latLngVertices = worldCorners.map { worldCoord -> LatLng in
            let eci = starToWorldTransform.inverse * worldCoord
            let lat = Double(asin(eci.z))
            let lng = Double(atan2(eci.y, eci.x))
            return LatLng(lat: lat, lng: lng)
        }

        var allLines: [LineInstance] = []
        for res in resolutionsToShow {
            let cells = H3Utils.h3Cells(
                inViewport: Viewport(
                    topLeft: latLngVertices[3],
                    topRight: latLngVertices[2],
                    bottomLeft: latLngVertices[0],
                    bottomRight: latLngVertices[1]
                ),
                resolution: res
            )
            let lines = gridLines(forCells: cells)
            allLines.append(
                contentsOf: lines.map { line in
                    LineInstance(
                        p0: starToWorldTransform * latLngToCelestialCoord(line.p0),
                        p1: starToWorldTransform * latLngToCelestialCoord(line.p1),
                        level: UInt32(res)
                    )
                }
            )
        }

        guard !allLines.isEmpty else { return }
        let lineBuffer = device.makeBuffer(bytes: allLines, length: allLines.count * MemoryLayout<LineInstance>.stride, options: .storageModeShared)
        lineBuffer?.label = "H3 Grid Lines (Dynamic)"

        renderEncoder.pushDebugGroup("H3 Grid")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)

        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: 1.0,
            fov: currentFOVDegrees,
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

        // Use line primitives for clean, thin lines (2 vertices per line)
        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2, instanceCount: allLines.count)
        
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
