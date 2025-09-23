import Ch3
import Metal
import MetalKit
import simd
import StarryNight

/// Renders brightest stars as instanced billboards. Owns its own Metal resources.
final class StarRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let starManager: StarManaging

    private var quadVertexBuffer: MTLBuffer?
    private var quadIndexBuffer: MTLBuffer?
    private var instanceBuffer: MTLBuffer?

    // Data for adaptive rendering
    private var brightestStarInstances: [StarInstance] = []
    private var h3StarCache: [H3Index: [StarInstance]] = [:]
    private var activeH3CellsByRes: [Int: Set<H3Index>] = [0: [], 1: [], 2: []]

    init(device: MTLDevice, view: MTKView, starManager: any StarManaging) {
        self.device = device
        self.starManager = starManager

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

        // Preload brightest stars (FOV-independent now)
        self.brightestStarInstances = starManager.brightestStars().map { 
            StarRenderer.starToInstance($0) 
        }
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        projectionMatrix: matrix_float4x4,
        viewMatrix: matrix_float4x4,
        time: Float,
        fov: Float
    ) {
        // 1. Determine which resolution levels to show
        var resolutionsToShow: [Int32] = [0]
        if fov < fovThresholdDegrees(forRes: 0) { resolutionsToShow.append(1) }
        if fov < fovThresholdDegrees(forRes: 1) { resolutionsToShow.append(2) }

        // 2. Determine visible H3 cells for each resolution
        let viewportCorners = [
            simd_float3(-1, -1, 1), simd_float3(1, -1, 1),
            simd_float3(1, 1, 1), simd_float3(-1, 1, 1)
        ]
        let invMVP = (projectionMatrix * viewMatrix).inverse
        let worldCorners = viewportCorners.map {
            let worldPos = invMVP * simd_float4($0, 1.0)
            return simd_normalize(SIMD3<Float>(x: worldPos.x, y: worldPos.y, z: worldPos.z) / worldPos.w)
        }
        let latLngVertices = worldCorners.map { worldCoord -> LatLng in
            let eci = starToWorldTransform.inverse * worldCoord
            let lat = Double(asin(eci.z))
            let lng = Double(atan2(eci.y, eci.x))
            return LatLng(lat: lat, lng: lng)
        }

        var starInstanceBufferNeedsChange = false

        // 3. Update active cells and fetch new star data if needed
        for res in 0...2 {
            let res32 = Int32(res)
            var newCells = Set<H3Index>()
            if resolutionsToShow.contains(res32) {
                newCells = Set(H3Utils.h3Cells(inViewport: latLngVertices, resolution: res32))
            }

            if activeH3CellsByRes[res] != newCells {
                starInstanceBufferNeedsChange = true
                activeH3CellsByRes[res] = newCells
                
                // Fetch data for cells not in cache
                for cell in newCells {
                    if h3StarCache[cell] == nil {
                        let stars = starManager.stars(inH3Cell: cell, maximumMagnitude: nil)
                        h3StarCache[cell] = stars.map { StarRenderer.starToInstance($0) }
                    }
                }
            }
        }
        
        // 4. Re-assemble instances and recreate buffer only if needed
        if starInstanceBufferNeedsChange || self.instanceBuffer == nil {
            var allInstances = brightestStarInstances
            for (res, cells) in activeH3CellsByRes {
                if resolutionsToShow.contains(Int32(res)) {
                    for cell in cells {
                        if let cachedInstances = h3StarCache[cell] {
                            allInstances.append(contentsOf: cachedInstances)
                        }
                    }
                }
            }
            
            if !allInstances.isEmpty {
                self.instanceBuffer = device.makeBuffer(bytes: allInstances, length: allInstances.count * MemoryLayout<StarInstance>.stride, options: .storageModeShared)
                self.instanceBuffer?.label = "Dynamic Star Instances"
            } else {
                self.instanceBuffer = nil // Clear buffer if no stars are visible
            }
        }

        // 5. Draw using the current state of the instance buffer
        guard let quadVB = quadVertexBuffer,
              let quadIB = quadIndexBuffer,
              let currentInstanceBuffer = self.instanceBuffer,
              currentInstanceBuffer.length > 0 else { return }
        
        let instanceCount = currentInstanceBuffer.length / MemoryLayout<StarInstance>.stride

        renderEncoder.pushDebugGroup("Stars")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)

        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix,
            blendMode: 0,
            transparency: time,
            fov: fov,
            forceColor: false,
            color: SIMD4<Float>(0,0,0,0)
        )
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)

        renderEncoder.setVertexBuffer(quadVB, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(currentInstanceBuffer, offset: 0, index: 1)

        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 6,
            indexType: .uint16,
            indexBuffer: quadIB,
            indexBufferOffset: 0,
            instanceCount: instanceCount
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

    private static func starToInstance(_ star: Star) -> StarInstance {
        let coord = simd_normalize(SIMD3<Float>(Float(star.coordinate.x), Float(star.coordinate.y), Float(star.coordinate.z)))
        let converted = starToWorldTransform * coord

        let color = spectralColor(for: star)
        return StarInstance(
            position: converted * 10.0,
            magnitude: Float(star.magnitude),
            color: SIMD4<Float>(color.x, color.y, color.z, 1.0),
            sensorPixelSize: 4.63e-6,
            waveLength: averageWavelength(for: star) * 10e-9,
            _pad0: .zero,
        )
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
