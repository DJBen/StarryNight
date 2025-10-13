import Metal
import MetalKit
import simd
import StarryNight

/// Renders triangle indicators on screen edges for selected stars that are out of viewport
final class TriangleIndicatorRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    
    private let triangleVertexBuffer: MTLBuffer
    private let triangleIndexBuffer: MTLBuffer
    private var viewportSizePixels = SIMD2<Float>(repeating: 0)
    
    // Indicator state
    private var selectedStarWorldPosition: SIMD3<Float>?
    private var indicatorScreenPosition: SIMD2<Float>?
    private var indicatorRotation: Float = 0.0
    private var isStarVisible: Bool = false

    private struct IndicatorVertexParameters {
        var screenPositionPixels: SIMD2<Float>
        var rotation: Float
        var padding: SIMD3<Float> = .zero
    }
    
    enum TriangleIndicatorRendererError: Error {
        case defaultLibraryUnavailable
        case vertexFunctionMissing(String)
        case fragmentFunctionMissing(String)
        case pipelineCreationFailed(underlying: Error)
        case depthStateCreationFailed
        case vertexBufferCreationFailed
        case indexBufferCreationFailed
    }

    init(device: MTLDevice, view: MTKView) throws {
        self.device = device
        
        // Create pipeline state
        self.pipelineState = try TriangleIndicatorRenderer.createPipeline(device: device, view: view)
        
        // Create depth state - render on top of everything
        let indicatorDepthDesc = MTLDepthStencilDescriptor()
        indicatorDepthDesc.depthCompareFunction = .always
        indicatorDepthDesc.isDepthWriteEnabled = false
        guard let ds = device.makeDepthStencilState(descriptor: indicatorDepthDesc) else { 
            throw TriangleIndicatorRendererError.depthStateCreationFailed 
        }
        self.depthState = ds
        
        // Create triangle geometry
        (triangleVertexBuffer, triangleIndexBuffer) = try TriangleIndicatorRenderer.createTriangleGeometry(device: device)
    }
    
    /// Update the selected star and calculate indicator position
    func updateSelectedStar(_ star: Star?, projectionMatrix: matrix_float4x4, viewMatrix: matrix_float4x4, viewSize: CGSize) {
        viewportSizePixels = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))

        guard let star = star else {
            selectedStarWorldPosition = nil
            indicatorScreenPosition = nil
            isStarVisible = false
            return
        }
        
        // Convert star coordinate to world position
        let coord = simd_normalize(SIMD3<Float>(star.coordinate))
        selectedStarWorldPosition = starToWorldTransform * coord * 10.0
        
        // Project star position to screen coordinates
        guard let worldPos = selectedStarWorldPosition else { return }
        
        let mvp = projectionMatrix * viewMatrix
        let clipPos = mvp * SIMD4<Float>(worldPos, 1.0)
        
        // Check if star is behind the camera
        if clipPos.w <= 0 {
            isStarVisible = false
            return
        }
        
        let ndc = SIMD2<Float>(clipPos.x / clipPos.w, clipPos.y / clipPos.w)
        
        // Check if star is within viewport (with small margin)
        let margin: Float = 0.05
        isStarVisible = ndc.x >= -1.0 - margin && ndc.x <= 1.0 + margin && 
                       ndc.y >= -1.0 - margin && ndc.y <= 1.0 + margin
        
        if !isStarVisible {
            // Calculate edge position and rotation
            calculateEdgeIndicator(ndc: ndc, viewSize: viewSize)
        }
    }
    
    private func calculateEdgeIndicator(ndc: SIMD2<Float>, viewSize: CGSize) {
        // Find intersection with screen edge
        var edgePos = ndc
        var rotation: Float = 0
        
        // Normalize direction from center to star
        let direction = simd_normalize(ndc)
        
        // Calculate intersections with screen edges
        let rightEdge = 1.0 / abs(direction.x)
        let topEdge = 1.0 / abs(direction.y)
        
        if rightEdge < topEdge {
            // Hit left or right edge first
            edgePos.x = direction.x > 0 ? 1.0 : -1.0  // Leave small margin from edge
            edgePos.y = direction.y * (edgePos.x / direction.x)
            edgePos.y = max(-1.0, min(1.0, edgePos.y))  // Clamp to screen bounds
            
            // Point towards center
            rotation = direction.x > 0 ? Float.pi : 0  // Right edge: point left, Left edge: point right
        } else {
            // Hit top or bottom edge first
            edgePos.y = direction.y > 0 ? 1.0 : -1.0
            edgePos.x = direction.x * (edgePos.y / direction.y)
            edgePos.x = max(-1.0, min(1.0, edgePos.x))  // Clamp to screen bounds
            
            // Point towards center
            rotation = direction.y > 0 ? -Float.pi/2 : Float.pi/2  // Top edge: point down, Bottom edge: point up
        }
        
        indicatorScreenPosition = edgePos
        indicatorRotation = rotation
    }
    
    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        projectionMatrix: matrix_float4x4,
        viewMatrix: matrix_float4x4,
        fov: Float
    ) {
        // Only draw if we have a selected star that's not visible
        guard !isStarVisible,
              let screenPos = indicatorScreenPosition,
              viewportSizePixels.x > 0,
              viewportSizePixels.y > 0 else { return }
        
        renderEncoder.pushDebugGroup("Triangle Indicator")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)
        
    // Create uniforms with indicator appearance
        let indicatorColor = SIMD4<Float>(1.0, 0.8, 0.2, 0.9)
        var uniforms = Uniforms(
            projectionMatrix: matrix_identity_float4x4,  // Use identity since we're in screen space
            modelViewMatrix: matrix_identity_float4x4,
            blendMode: UInt32(BlendMode.transparency.rawValue),
            transparency: indicatorColor.w,
            fov: fov,
            color: indicatorColor  // Orange/yellow color
        )
        
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setVertexBuffer(triangleVertexBuffer, offset: 0, index: 0)
        
        // Convert indicator center from NDC to pixel space relative to viewport center
        let viewportPixels = viewportSizePixels
        let screenPositionPixels = SIMD2<Float>(
            screenPos.x * viewportPixels.x * 0.5,
            screenPos.y * viewportPixels.y * 0.5
        )

        var indicatorParameters = IndicatorVertexParameters(
            screenPositionPixels: screenPositionPixels,
            rotation: indicatorRotation
        )

        renderEncoder.setVertexBytes(
            &indicatorParameters,
            length: MemoryLayout<IndicatorVertexParameters>.stride,
            index: 1
        )

        var viewportCopy = viewportPixels
        renderEncoder.setVertexBytes(
            &viewportCopy,
            length: MemoryLayout<SIMD2<Float>>.stride,
            index: BufferIndex.viewportSize.rawValue
        )
        
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 3,
            indexType: .uint16,
            indexBuffer: triangleIndexBuffer,
            indexBufferOffset: 0
        )
        
        renderEncoder.popDebugGroup()
    }
    
    /// Check if a tap at screen coordinates hits the indicator
    func hitTest(tapLocation: CGPoint, viewSize: CGSize) -> Bool {
        guard !isStarVisible, let screenPos = indicatorScreenPosition else { return false }
        
        // Convert tap to NDC
        let tapNDC = SIMD2<Float>(
            Float((tapLocation.x / viewSize.width) * 2.0 - 1.0),
            Float(1.0 - (tapLocation.y / viewSize.height) * 2.0)
        )
        
        // Check distance to indicator position
        let distance = simd_length(tapNDC - screenPos)
        let hitRadius: Float = 0.1  // Adjust for desired hit area

        return distance <= hitRadius
    }
    
    // MARK: - Private helpers
    
    private static func createTriangleGeometry(device: MTLDevice) throws -> (MTLBuffer, MTLBuffer) {
        // Create equilateral triangle pointing right (will be rotated as needed)
        let sideLength: Float = 64.0
        let height = sideLength * sqrt(3.0) / 2.0

        let vertices: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0),                        // Tip (pointing right)
            SIMD2<Float>(-height, sideLength / 2),     // Bottom-left corner
            SIMD2<Float>(-height, -sideLength / 2)     // Top-left corner
        ]
        
        let indices: [UInt16] = [0, 1, 2]
        
        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD2<Float>>.stride) else {
            throw TriangleIndicatorRendererError.vertexBufferCreationFailed
        }
        guard let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride) else {
            throw TriangleIndicatorRendererError.indexBufferCreationFailed
        }
        
        vertexBuffer.label = "Triangle Indicator Vertices"
        indexBuffer.label = "Triangle Indicator Indices"
        
        return (vertexBuffer, indexBuffer)
    }
    
    private static func createPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw TriangleIndicatorRendererError.defaultLibraryUnavailable
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Triangle Indicator Pipeline"
        guard let vertexFunction = library.makeFunction(name: "triangle_indicator_vertex") else {
            throw TriangleIndicatorRendererError.vertexFunctionMissing("triangle_indicator_vertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "triangle_indicator_fragment") else {
            throw TriangleIndicatorRendererError.fragmentFunctionMissing("triangle_indicator_fragment")
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
        
        // Enable alpha blending for transparency
        if let att = descriptor.colorAttachments[0] {
            att.isBlendingEnabled = true
            att.rgbBlendOperation = .add
            att.alphaBlendOperation = .add
            att.sourceRGBBlendFactor = .sourceAlpha
            att.destinationRGBBlendFactor = .oneMinusSourceAlpha
            att.sourceAlphaBlendFactor = .one
            att.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }
        
        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            throw TriangleIndicatorRendererError.pipelineCreationFailed(underlying: error)
        }
    }
}
