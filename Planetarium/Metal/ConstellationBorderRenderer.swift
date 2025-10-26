import Ch3
import Metal
import MetalKit
import simd
import StarryNight

/// Renders constellation border segments as great-circle line primitives.
final class ConstellationBorderRenderer {
    private struct LineInstance {
        var p0: simd_float3
        var p1: simd_float3
        var color0: SIMD3<Float>
        var color1: SIMD3<Float>
    }

    private struct BorderEdge: Hashable {
        let a: LatLng
        let b: LatLng

        init(_ p0: LatLng, _ p1: LatLng) {
            if BorderEdge.shouldSwap(p0, p1) {
                self.a = p1
                self.b = p0
            } else {
                self.a = p0
                self.b = p1
            }
        }

        private static func shouldSwap(_ lhs: LatLng, _ rhs: LatLng) -> Bool {
            if lhs.lat < rhs.lat { return false }
            if lhs.lat > rhs.lat { return true }
            if lhs.lng < rhs.lng { return false }
            if lhs.lng > rhs.lng { return true }
            return false
        }
    }

    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState

    private var lineBuffer: MTLBuffer?
    private var lineCount: Int = 0

    /// Whether borders should be rendered this frame.
    var isVisible: Bool = false

    /// Global tint (RGB) and opacity (A) applied on top of the declination gradient.
    var lineColor: SIMD4<Float> = SIMD4<Float>(0.8, 0.6, 1.0, 0.7)

    enum ConstellationBorderRendererError: Error {
        case defaultLibraryUnavailable
        case vertexFunctionMissing(String)
        case fragmentFunctionMissing(String)
        case pipelineCreationFailed(underlying: Error)
        case depthStateCreationFailed
    }

    init(device: MTLDevice, view: MTKView, starManager: any StarManaging) throws {
        self.device = device
        self.pipelineState = try ConstellationBorderRenderer.buildPipeline(device: device, view: view)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .lessEqual
        depthDescriptor.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw ConstellationBorderRendererError.depthStateCreationFailed
        }
        self.depthState = depthState

        buildLineBuffer(starManager: starManager)
    }

    func drawableSizeWillChange(to size: CGSize) {
        _ = size
        // Currently no per-viewport state, but method retained for future configuration.
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        projectionMatrix: matrix_float4x4,
        viewMatrix: matrix_float4x4
    ) {
        guard isVisible,
              let lineBuffer,
              lineCount > 0 else { return }

        renderEncoder.pushDebugGroup("Constellation Borders")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)

        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: 1.0,
            fov: 0.0,
            color: lineColor
        )
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setVertexBuffer(lineBuffer, offset: 0, index: 0)

        renderEncoder.drawPrimitives(type: .line, vertexStart: 0, vertexCount: 2, instanceCount: lineCount)

        renderEncoder.popDebugGroup()
    }

    // MARK: - Private helpers

    private func buildLineBuffer(starManager: any StarManaging) {
        let instances = ConstellationBorderRenderer.buildLineInstances(starManager: starManager)
        lineCount = instances.count

        guard !instances.isEmpty else {
            lineBuffer = nil
            return
        }

        lineBuffer = device.makeBuffer(
            bytes: instances,
            length: instances.count * MemoryLayout<LineInstance>.stride,
            options: .storageModeShared
        )
        lineBuffer?.label = "Constellation Border Lines"
    }

    private static func buildLineInstances(starManager: any StarManaging) -> [LineInstance] {
        var processedEdges: Set<BorderEdge> = []
        var instances: [LineInstance] = []

        for constellation in starManager.allConstellations() {
            let borders = starManager.constellationBorders(for: constellation)
            for segment in borders {
                guard segment.start.lat.isFinite,
                      segment.start.lng.isFinite,
                      segment.end.lat.isFinite,
                      segment.end.lng.isFinite else { continue }

                let edge = BorderEdge(segment.start, segment.end)
                guard processedEdges.insert(edge).inserted else { continue }

                if ConstellationBorderRenderer.isConstantDeclination(segment: segment) {
                    instances.append(contentsOf: segmentsFollowingConstantDeclination(segment: segment))
                } else {
                    instances.append(lineInstance(from: segment.start, to: segment.end))
                }
            }
        }

        return instances
    }

    private static func segmentsFollowingConstantDeclination(segment: Constellation.BorderSegment) -> [LineInstance] {
        let startLng = segment.start.lng
        let endLng = segment.end.lng

        var delta = endLng - startLng
        let twoPi = 2.0 * Double.pi
        if delta > Double.pi {
            delta -= twoPi
        } else if delta < -Double.pi {
            delta += twoPi
        }

        if abs(delta) < 1e-6 {
            return []
        }

        let arcLength = abs(delta)
        let stepSize = Double.pi / 90.0 // ~2 degrees per segment
        let subdivisions = max(1, Int(ceil(arcLength / stepSize)))

        var segments: [LineInstance] = []
        var previousLatLng = segment.start

        for step in 1...subdivisions {
            let t = Double(step) / Double(subdivisions)
            let lng = wrapLongitude(startLng + delta * t)
            let latLng = LatLng(lat: segment.start.lat, lng: lng)
            segments.append(lineInstance(from: previousLatLng, to: latLng))
            previousLatLng = latLng
        }

        return segments
    }

    private static func isConstantDeclination(segment: Constellation.BorderSegment) -> Bool {
        return abs(segment.start.lat - segment.end.lat) < 1e-7
    }

    private static func wrapLongitude(_ value: Double) -> Double {
        var lon = value
        let twoPi = 2.0 * Double.pi
        lon.formTruncatingRemainder(dividingBy: twoPi)
        if lon <= -Double.pi {
            lon += twoPi
        } else if lon > Double.pi {
            lon -= twoPi
        }
        return lon
    }

    private static func lineInstance(from start: LatLng, to end: LatLng) -> LineInstance {
        return LineInstance(
            p0: starToWorldTransform * latLngToCelestialCoord(start),
            p1: starToWorldTransform * latLngToCelestialCoord(end),
            color0: gradientColor(forDeclination: start.lat),
            color1: gradientColor(forDeclination: end.lat)
        )
    }

    private static func gradientColor(forDeclination declination: Double) -> SIMD3<Float> {
        let normalized = Float((declination + Double.pi / 2.0) / Double.pi)
        let clamped = max(0.0, min(1.0, normalized))
        let southernColor = SIMD3<Float>(0.2, 0.4, 1.0)
        let northernColor = SIMD3<Float>(1.0, 0.5, 0.2)
        return southernColor + (northernColor - southernColor) * clamped
    }

    private static func buildPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw ConstellationBorderRendererError.defaultLibraryUnavailable
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Constellation Border Pipeline"
        guard let vertexFunction = library.makeFunction(name: "constellation_border_vertex") else {
            throw ConstellationBorderRendererError.vertexFunctionMissing("constellation_border_vertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "constellation_border_fragment") else {
            throw ConstellationBorderRendererError.fragmentFunctionMissing("constellation_border_fragment")
        }
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
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
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw ConstellationBorderRendererError.pipelineCreationFailed(underlying: error)
        }
    }
}
