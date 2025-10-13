import Ch3
import Metal
import MetalKit
import simd
import StarryNight

/// Renders constellation connection lines that link stars belonging to the same constellation.
final class ConstellationLineRenderer {
    private struct LineVertex {
        var positionAlpha: simd_float4
    }

    private struct StarEdge: Hashable {
        let a: Int
        let b: Int

        init?(_ first: Int, _ second: Int) {
            guard first != second else { return nil }
            if first < second {
                self.a = first
                self.b = second
            } else {
                self.a = second
                self.b = first
            }
        }
    }

    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private var lineBuffer: MTLBuffer?
    private var vertexCount: Int = 0

    /// Whether constellation lines should be rendered this frame.
    var isVisible: Bool = false

    /// RGBA color applied to all constellation lines.
    var lineColor: SIMD4<Float> = SIMD4<Float>(0.9, 0.8, 1.0, 0.8)

    init(device: MTLDevice, view: MTKView, starManager: any StarManaging) {
        self.device = device
        self.pipelineState = try! ConstellationLineRenderer.buildPipeline(device: device, view: view)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            fatalError("Failed to create depth state for constellation lines")
        }
        self.depthState = depthState

        buildLineBuffer(starManager: starManager)
    }

    func drawableSizeWillChange(to size: CGSize) {
        _ = size
        // Constellation lines are resolution-independent; no per-size adjustments required.
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        projectionMatrix: matrix_float4x4,
        viewMatrix: matrix_float4x4,
        fovDegrees: Float
    ) {
        guard isVisible,
              let lineBuffer,
              vertexCount > 0 else { return }

        renderEncoder.pushDebugGroup("Constellation Lines")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)

        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: 1.0,
            fov: fovDegrees,
            color: lineColor
        )
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)

        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: vertexCount)

        renderEncoder.popDebugGroup()
    }

    // MARK: - Private helpers

    private func buildLineBuffer(starManager: any StarManaging) {
        let vertices = ConstellationLineRenderer.buildLineVertices(starManager: starManager)
        vertexCount = vertices.count

        guard !vertices.isEmpty else {
            lineBuffer = nil
            return
        }

        lineBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<LineVertex>.stride,
            options: .storageModeShared
        )
        lineBuffer?.label = "Constellation Lines"
    }

    private static func buildLineVertices(starManager: any StarManaging) -> [LineVertex] {
        var processedEdges: Set<StarEdge> = []
        var cachedStarWorldPositions: [Int: simd_float3] = [:]
        var vertices: [LineVertex] = []

        for constellation in starManager.allConstellations() {
            let lines = starManager.constellationLines(for: constellation)
            for line in lines {
                guard let edge = StarEdge(line.star1Id, line.star2Id) else { continue }
                guard processedEdges.insert(edge).inserted else { continue }

                guard let p0 = worldPosition(forStarId: edge.a, starManager: starManager, cache: &cachedStarWorldPositions),
                      let p1 = worldPosition(forStarId: edge.b, starManager: starManager, cache: &cachedStarWorldPositions) else {
                    continue
                }

                vertices.append(contentsOf: buildVerticesForLine(start: p0, end: p1))
            }
        }

        return vertices
    }

    private static func buildVerticesForLine(start: simd_float3, end: simd_float3) -> [LineVertex] {
        let startLength = simd_length(start)
        let endLength = simd_length(end)
        let radius = max(startLength, endLength)

        let startDir = startLength > 0 ? simd_normalize(start) : start
        let endDir = endLength > 0 ? simd_normalize(end) : end

        func point(at t: Float) -> simd_float3 {
            let mixed = simd_normalize(startDir + (endDir - startDir) * t)
            return mixed * radius
        }

        let nearStart = point(at: 0.2)
        let nearEnd = point(at: 0.8)

        return [
            LineVertex(positionAlpha: simd_float4(start, 0.0)),
            LineVertex(positionAlpha: simd_float4(nearStart, 1.0)),
            LineVertex(positionAlpha: simd_float4(nearStart, 1.0)),
            LineVertex(positionAlpha: simd_float4(nearEnd, 1.0)),
            LineVertex(positionAlpha: simd_float4(nearEnd, 1.0)),
            LineVertex(positionAlpha: simd_float4(end, 0.0))
        ]
    }

    private static func worldPosition(
        forStarId starId: Int,
        starManager: any StarManaging,
        cache: inout [Int: simd_float3]
    ) -> simd_float3? {
        if let cached = cache[starId] {
            return cached
        }

        guard let star = starManager.star(withId: starId) else { return nil }
        let coordinate = star.coordinate
        let floatCoordinate = simd_float3(
            Float(coordinate.x),
            Float(coordinate.y),
            Float(coordinate.z)
        )
        let worldPosition = starToWorldTransform * floatCoordinate
        cache[starId] = worldPosition
        return worldPosition
    }

    private static func buildPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        let library = device.makeDefaultLibrary()
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Constellation Line Pipeline"
        descriptor.vertexFunction = library?.makeFunction(name: "constellation_line_vertex")
        descriptor.fragmentFunction = library?.makeFunction(name: "constellation_line_fragment")
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
#if os(macOS) || targetEnvironment(simulator)
        descriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        descriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
#else
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.stencilAttachmentPixelFormat = .stencil8
#endif
        if let attachment = descriptor.colorAttachments[0] {
            attachment.isBlendingEnabled = true
            attachment.rgbBlendOperation = .add
            attachment.alphaBlendOperation = .add
            attachment.sourceRGBBlendFactor = .one
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        return try device.makeRenderPipelineState(descriptor: descriptor)
    }
}
