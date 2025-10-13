import Metal
import MetalKit
import simd
import StarryNight

/// Renders a rotating crosshair around a selected star
final class CrosshairRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    
    private let crosshairVertexBuffer: MTLBuffer
    private let crosshairIndexBuffer: MTLBuffer
    
    // Crosshair state
    private var selectedStarWorldPosition: SIMD3<Float>?
    private var rotationAngle: Float = 0.0
    
    enum CrosshairRendererError: Error {
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
        self.pipelineState = try CrosshairRenderer.createPipeline(device: device, view: view)
        
        // Create depth state - test but don't write, render on top
        let crosshairDepthDesc = MTLDepthStencilDescriptor()
        crosshairDepthDesc.depthCompareFunction = .always
        crosshairDepthDesc.isDepthWriteEnabled = false
        guard let ds = device.makeDepthStencilState(descriptor: crosshairDepthDesc) else { 
            throw CrosshairRendererError.depthStateCreationFailed 
        }
        self.depthState = ds
        
        // Create crosshair geometry
        (crosshairVertexBuffer, crosshairIndexBuffer) = try CrosshairRenderer.createCrosshairGeometry(device: device)
    }
    
    /// Update the selected star position and animate the crosshair
    func updateSelectedStar(_ star: Star?, deltaTime: Float) {
        if let star = star {
            // Convert star coordinate to world position
            let coord = simd_normalize(SIMD3<Float>(star.coordinate))
            self.selectedStarWorldPosition = starToWorldTransform * coord * 10.0
            
            // Update rotation animation
            rotationAngle += deltaTime * 0.5 // Rotate at 0.5 radians per second
            if rotationAngle > 2 * Float.pi {
                rotationAngle -= 2 * Float.pi
            }
        } else {
            self.selectedStarWorldPosition = nil
            rotationAngle = 0.0
        }
    }
    
    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        projectionMatrix: matrix_float4x4,
        viewMatrix: matrix_float4x4,
        fov: Float
    ) {
        guard let starPosition = selectedStarWorldPosition else { return }
        
        renderEncoder.pushDebugGroup("Crosshair")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setCullMode(.none)
        
        // Create model matrix for crosshair at star position (no rotation needed for billboard)
        let translationMatrix = matrix_float4x4(translationX: starPosition.x, translationY: starPosition.y, translationZ: starPosition.z)
        let modelMatrix = translationMatrix
        
        var uniforms = Uniforms(
            projectionMatrix: projectionMatrix,
            modelViewMatrix: viewMatrix * modelMatrix,
            blendMode: 0,
            transparency: rotationAngle / (2 * Float.pi), // Pass normalized rotation angle
            fov: fov, // Pass FOV for perspective scaling
            color: SIMD4<Float>(1.0, 1.0, 0.0, 0.8) // Yellow with some transparency
        )
        
        renderEncoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.size, index: BufferIndex.uniforms.rawValue)
        renderEncoder.setVertexBuffer(crosshairVertexBuffer, offset: 0, index: 0)
        
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: 24, // 4 quads * 6 indices each (2 triangles)
            indexType: .uint16,
            indexBuffer: crosshairIndexBuffer,
            indexBufferOffset: 0
        )
        
        renderEncoder.popDebugGroup()
    }
    
    // MARK: - Private helpers
    
    private static func createCrosshairGeometry(device: MTLDevice) throws -> (MTLBuffer, MTLBuffer) {
        let length: Float = 0.3
        let thickness: Float = 0.02
        let gap: Float = 0.12

        let vertices: [SIMD3<Float>] = [
            // Left horizontal rectangle (4 vertices)
            SIMD3<Float>(-length, -thickness, 0),  // 0: bottom-left
            SIMD3<Float>(-gap, -thickness, 0),     // 1: bottom-right
            SIMD3<Float>(-gap, thickness, 0),      // 2: top-right
            SIMD3<Float>(-length, thickness, 0),   // 3: top-left
            
            // Right horizontal rectangle (4 vertices)
            SIMD3<Float>(gap, -thickness, 0),      // 4: bottom-left
            SIMD3<Float>(length, -thickness, 0),   // 5: bottom-right
            SIMD3<Float>(length, thickness, 0),    // 6: top-right
            SIMD3<Float>(gap, thickness, 0),       // 7: top-left
            
            // Bottom vertical rectangle (4 vertices)
            SIMD3<Float>(-thickness, -length, 0),  // 8: bottom-left
            SIMD3<Float>(thickness, -length, 0),   // 9: bottom-right
            SIMD3<Float>(thickness, -gap, 0),      // 10: top-right
            SIMD3<Float>(-thickness, -gap, 0),     // 11: top-left
            
            // Top vertical rectangle (4 vertices)
            SIMD3<Float>(-thickness, gap, 0),      // 12: bottom-left
            SIMD3<Float>(thickness, gap, 0),       // 13: bottom-right
            SIMD3<Float>(thickness, length, 0),    // 14: top-right
            SIMD3<Float>(-thickness, length, 0),   // 15: top-left
        ]
        
        let indices: [UInt16] = [
            // Left horizontal rectangle
            0, 1, 2,  0, 2, 3,
            // Right horizontal rectangle
            4, 5, 6,  4, 6, 7,
            // Bottom vertical rectangle
            8, 9, 10,  8, 10, 11,
            // Top vertical rectangle
            12, 13, 14,  12, 14, 15
        ]
        
        guard let vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<SIMD3<Float>>.stride) else {
            throw CrosshairRendererError.vertexBufferCreationFailed
        }
        guard let indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride) else {
            throw CrosshairRendererError.indexBufferCreationFailed
        }
        
        vertexBuffer.label = "Crosshair Vertices"
        indexBuffer.label = "Crosshair Indices"
        
        return (vertexBuffer, indexBuffer)
    }
    
    private static func createPipeline(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw CrosshairRendererError.defaultLibraryUnavailable
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Crosshair Pipeline"
        guard let vertexFunction = library.makeFunction(name: "crosshair_vertex") else {
            throw CrosshairRendererError.vertexFunctionMissing("crosshair_vertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "crosshair_fragment") else {
            throw CrosshairRendererError.fragmentFunctionMissing("crosshair_fragment")
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
            throw CrosshairRendererError.pipelineCreationFailed(underlying: error)
        }
    }
}
