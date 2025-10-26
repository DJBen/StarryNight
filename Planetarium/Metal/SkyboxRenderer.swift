import Metal
import MetalKit
import simd

enum SkyboxRendererError: Error {
    case depthStateCreationFailed
    case pipelineCreationFailed(underlying: Error)
    case vertexBufferCreationFailed
    case textureLoadFailed(underlying: Error)
}

/// Renders the cubemap skybox. Owns its own Metal resources.
final class SkyboxRenderer {
    private let device: MTLDevice
    private let pipelineState: MTLRenderPipelineState
    private let depthState: MTLDepthStencilState
    private let vertexBuffer: MTLBuffer
    private let texture: MTLTexture

    init(device: MTLDevice, view: MTKView) throws {
        self.device = device

        // Depth state: render skybox with lessEqual depth test, no depth writes
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
            throw SkyboxRendererError.depthStateCreationFailed
        }
        self.depthState = depthState

        // Pipeline state
        do {
            self.pipelineState = try SkyboxRenderer.createPipelineState(device: device, view: view)
        } catch {
            throw SkyboxRendererError.pipelineCreationFailed(underlying: error)
        }

        // Geometry + texture
        self.vertexBuffer = try SkyboxRenderer.createVertexBuffer(device: device)
        do {
            self.texture = try SkyboxRenderer.loadTexture(device: device, contentScaleFactor: view.contentScaleFactor)
        } catch {
            throw SkyboxRendererError.textureLoadFailed(underlying: error)
        }
    }

    func draw(renderEncoder: MTLRenderCommandEncoder, projectionMatrix: matrix_float4x4, viewMatrix: matrix_float4x4) {
        renderEncoder.pushDebugGroup("Render Skybox")
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setDepthStencilState(depthState)
        // We are inside the celestial sphere looking at the backside
        renderEncoder.setCullMode(.front)

        // Vertex buffer
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Uniforms: remove translation from view to keep skybox at infinity
        var skyboxUniforms = Uniforms()
        skyboxUniforms.projectionMatrix = projectionMatrix
        var skyboxView = viewMatrix
        skyboxView.columns.3 = SIMD4<Float>(0, 0, 0, 1)
        skyboxUniforms.modelViewMatrix = skyboxView
        renderEncoder.setVertexBytes(&skyboxUniforms, length: MemoryLayout<Uniforms>.size, index: 1)

        // Texture
        renderEncoder.setFragmentTexture(texture, index: 0)

        // Draw
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
        renderEncoder.popDebugGroup()
    }

    // MARK: - Private helpers

    private static func loadTexture(device: MTLDevice, contentScaleFactor: CGFloat) throws -> any MTLTexture {
        let loader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]
        return try loader.newTexture(name: "milky_way", scaleFactor: contentScaleFactor, bundle: nil, options: options)
    }

    private static func createVertexBuffer(device: MTLDevice) throws -> MTLBuffer {
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
            throw SkyboxRendererError.vertexBufferCreationFailed
        }
        return buffer
    }

    private static func createPipelineState(device: MTLDevice, view: MTKView) throws -> MTLRenderPipelineState {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 3
        vertexDescriptor.layouts[0].stepFunction = .perVertex

        return try buildRenderPipelineWithDevice(
            device: device,
            metalKitView: view,
            vertexFunctionName: "skybox_vertex",
            fragmentFunctionName: "skybox_fragment",
            mtlVertexDescriptor: vertexDescriptor
        )
    }
}
