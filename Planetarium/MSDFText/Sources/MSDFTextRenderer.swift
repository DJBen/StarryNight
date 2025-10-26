import Foundation
import Metal
import simd

// MARK: - Shared types

public struct MSDFTextRenderStyle {
    public var textColor: SIMD4<Float>

    public init(textColor: SIMD4<Float> = SIMD4<Float>(1, 1, 1, 1)) {
        self.textColor = textColor
    }
}

enum _MSDFBufferIndex: Int {
    case meshPositions = 0
    case meshGenerics = 1
    case uniforms = 2
}

enum _MSDFVertexAttribute: Int {
    case position = 0
    case texcoord = 1
}

public struct MSDFUniforms {
    public var projectionMatrix: matrix_float4x4
    public var modelViewMatrix: matrix_float4x4
    public var textColor: SIMD4<Float>
    public var unitRange: SIMD2<Float>
    public var _padding: SIMD2<Float>

    public init() {
        projectionMatrix = matrix_identity_float4x4
        modelViewMatrix = matrix_identity_float4x4
        textColor = SIMD4<Float>(1, 1, 1, 1)
        unitRange = SIMD2<Float>(0, 0)
        _padding = SIMD2<Float>(0, 0)
    }
}

// MARK: - Renderer

public final class MSDFTextRenderer {
    public let device: MTLDevice
    public var pipelineState: MTLRenderPipelineState
    public let depthState: MTLDepthStencilState

    public var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    public var modelViewMatrix: matrix_float4x4 = matrix_identity_float4x4

    // Distance range in texels from the atlas metadata
    private let atlasPxRange: Float

    // Internal ring buffer for style-based uniforms to avoid per-draw allocations
    private let styleUniformRingCount: Int = 3
    private let styleUniformStride: Int = MemoryLayout<MSDFUniforms>.stride
    private let styleUniformStrideAligned: Int
    private var styleUniformRingBuffer: MTLBuffer
    private var styleUniformRingIndex: Int = 0

    public init(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int = 1,
        atlasPxRange: Float,
        depthPixelFormat: MTLPixelFormat = .invalid,
        stencilPixelFormat: MTLPixelFormat = .invalid,
        customLibrary: MTLLibrary? = nil,
        vertexFunctionName: String = "msdfVertexShader",
        fragmentFunctionName: String = "msdfFragmentShader",
    ) throws {
        self.device = device
        self.atlasPxRange = atlasPxRange

        // Pipeline
        let vertexDescriptor = Self.buildMetalVertexDescriptor()
        pipelineState = try Self.buildRenderPipeline(
            device: device,
            pixelFormat: pixelFormat,
            sampleCount: sampleCount,
            vertexDescriptor: vertexDescriptor,
            depthPixelFormat: depthPixelFormat,
            stencilPixelFormat: stencilPixelFormat,
            customLibrary: customLibrary,
            vertexFunctionName: vertexFunctionName,
            fragmentFunctionName: fragmentFunctionName,
        )
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .always
        depthDescriptor.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDescriptor) else {
            throw NSError(domain: "MSDFTextRenderer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to create depth state"])
        }
        self.depthState = depthState

        // Compute 256-byte aligned stride per Metal constant buffer requirements
        styleUniformStrideAligned = ((styleUniformStride + 255) / 256) * 256

        // Preallocate a small ring buffer for style-based encoding (aligned)
        guard let ringBuffer = device.makeBuffer(
            length: styleUniformStrideAligned * styleUniformRingCount,
            options: .storageModeShared,
        ) else {
            throw NSError(domain: "MSDFTextRenderer", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to create ring buffer"])
        }
        styleUniformRingBuffer = ringBuffer
        styleUniformRingBuffer.label = "MSDFText.StyleUniformRing"
    }

    public func setOrthoProjection(width: Float, height: Float) {
        let sx: Float = width != 0 ? 2.0 / width : 0
        let sy: Float = height != 0 ? -2.0 / height : 0
        projectionMatrix = matrix_float4x4(columns: (
            SIMD4<Float>(sx, 0, 0, 0),
            SIMD4<Float>(0, sy, 0, 0),
            SIMD4<Float>(0, 0, 1, 0),
            SIMD4<Float>(-1, 1, 0, 1),
        ))
    }

    public func encode(
        encoder: MTLRenderCommandEncoder,
        mesh: MSDFTextMesh,
        atlasTexture: MTLTexture,
        style: MSDFTextRenderStyle,
    ) {
        // Update uniforms
        var uniforms = MSDFUniforms()
        uniforms.projectionMatrix = projectionMatrix
        uniforms.modelViewMatrix = modelViewMatrix
        uniforms.textColor = style.textColor
        uniforms.unitRange = unitRange(for: atlasTexture)

        // Route through the buffer-based encode using an internal ring to avoid allocations
        let ring = styleUniformRingBuffer
        let offset = styleUniformRingIndex * styleUniformStrideAligned
        memcpy(ring.contents().advanced(by: offset), &uniforms, styleUniformStride)
        encode(
            encoder: encoder,
            mesh: mesh,
            atlasTexture: atlasTexture,
            uniformBuffer: ring,
            uniformOffset: offset,
            overridePipeline: nil,
        )
        styleUniformRingIndex = (styleUniformRingIndex + 1) % styleUniformRingCount
    }

    // MARK: - Custom pipeline/uniforms

    /// Computes the unit range in UV space for the provided atlas texture.
    /// This should match the `pxRange` used to bake the atlas.
    public func unitRange(for atlasTexture: MTLTexture) -> SIMD2<Float> {
        SIMD2<Float>(
            atlasPxRange / Float(atlasTexture.width),
            atlasPxRange / Float(atlasTexture.height),
        )
    }

    // Removed the raw-bytes overload to consolidate on the buffer-based API.

    /// Encodes a draw using a caller-provided uniforms buffer and optional pipeline override.
    public func encode(
        encoder: MTLRenderCommandEncoder,
        mesh: MSDFTextMesh,
        atlasTexture: MTLTexture,
        uniformBuffer: MTLBuffer,
        uniformOffset: Int = 0,
        overridePipeline: MTLRenderPipelineState? = nil,
    ) {
        encoder.setRenderPipelineState(overridePipeline ?? pipelineState)
        encoder.setDepthStencilState(depthState)
        encoder.setCullMode(.none)

        encoder.setVertexBuffer(mesh.vertexBuffer, offset: 0, index: _MSDFBufferIndex.meshPositions.rawValue)
        encoder.setVertexBuffer(uniformBuffer, offset: uniformOffset, index: _MSDFBufferIndex.uniforms.rawValue)
        encoder.setFragmentBuffer(uniformBuffer, offset: uniformOffset, index: _MSDFBufferIndex.uniforms.rawValue)
        encoder.setFragmentTexture(atlasTexture, index: 0)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: mesh.indexCount,
            indexType: .uint32,
            indexBuffer: mesh.indexBuffer,
            indexBufferOffset: 0,
        )
    }

    // MARK: - Helpers

    public static func buildMetalVertexDescriptor() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = _MSDFBufferIndex.meshPositions.rawValue

        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD3<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = _MSDFBufferIndex.meshPositions.rawValue

        vertexDescriptor.layouts[0].stride = MemoryLayout<MSDFGlyphVertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        return vertexDescriptor
    }

    private static func buildRenderPipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat,
        sampleCount: Int,
        vertexDescriptor: MTLVertexDescriptor,
        depthPixelFormat: MTLPixelFormat,
        stencilPixelFormat: MTLPixelFormat,
        customLibrary: MTLLibrary?,
        vertexFunctionName: String,
        fragmentFunctionName: String,
    ) throws -> MTLRenderPipelineState {
        let library: MTLLibrary = if let customLibrary {
            customLibrary
        } else {
            try device.makeDefaultLibrary(bundle: .module)
        }

        guard let vfn = library.makeFunction(name: vertexFunctionName),
              let ffn = library.makeFunction(name: fragmentFunctionName)
        else {
            throw NSError(domain: "MSDFTextRenderer", code: -3, userInfo: [NSLocalizedDescriptionKey: "Metal shader functions not found: \(vertexFunctionName), \(fragmentFunctionName)"])
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "MSDFText.Pipeline"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.vertexDescriptor = vertexDescriptor
        desc.rasterSampleCount = sampleCount
        desc.colorAttachments[0].pixelFormat = pixelFormat
        desc.depthAttachmentPixelFormat = depthPixelFormat
        desc.stencilAttachmentPixelFormat = stencilPixelFormat

        if let attachment = desc.colorAttachments[0] {
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.rgbBlendOperation = .add
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            attachment.alphaBlendOperation = .add
        }

        return try device.makeRenderPipelineState(descriptor: desc)
    }
}
