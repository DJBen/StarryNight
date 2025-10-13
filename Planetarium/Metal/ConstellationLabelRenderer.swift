import Foundation
import CoreGraphics
import CoreText
import Metal
import MetalKit
import MSDFText
import simd
import StarryNight

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders constellation name labels at their display centers using MSDF text.
final class ConstellationLabelRenderer {

    private struct LabelEntry {
        let mesh: MSDFTextMesh
        let worldPosition: SIMD3<Float>
        let color: SIMD4<Float>
        let uniformBuffer: MTLBuffer
        let bounds: SIMD2<Float>
    }

    enum ConstellationLabelRendererError: Error {
        case atlasJSONMissing
        case atlasLoadFailed(underlying: Error)
        case atlasTextureMissing
        case atlasTextureLoadFailed(underlying: Error)
        case msdfRendererCreationFailed(underlying: Error)
        case fontResourceMissing
        case fontDataProviderCreationFailed
        case fontRegistrationFailed(underlying: Error)
        case meshCreationFailed(constellation: String)
        case invalidConstellationCenter(constellation: String)
        case uniformBufferAllocationFailed(constellation: String)
    }

    private let device: MTLDevice
    private let msdfRenderer: MSDFTextRenderer
    private let atlasTexture: MTLTexture
    private let atlasUnitRange: SIMD2<Float>
    private var labels: [LabelEntry] = []
    private var drawableSize: CGSize
    private let styleColor = SIMD4<Float>(0.82, 0.87, 1.0, 0.9)
    private let labelDistance: Float = 10.0
    private let labelMargin: CGFloat = 4.0
    private let labelFrame = CGSize(width: 360, height: 96)
    private let contentScale: CGFloat

    /// Toggle for label visibility.
    var isVisible: Bool = true

    init(
        device: MTLDevice,
        view: MTKView,
        starManager: any StarManaging
    ) throws {
        self.device = device
        self.drawableSize = view.drawableSize
        self.contentScale = ConstellationLabelRenderer.computeContentScale(for: view)

        let atlas = try ConstellationLabelRenderer.loadAtlas()
        self.atlasTexture = try ConstellationLabelRenderer.loadAtlasTexture(device: device)

        do {
            #if os(macOS) || targetEnvironment(simulator)
            let depthPixelFormat: MTLPixelFormat = .depth32Float_stencil8
            let stencilPixelFormat: MTLPixelFormat = .depth32Float_stencil8
            #else
            let depthPixelFormat: MTLPixelFormat = .depth32Float
            let stencilPixelFormat: MTLPixelFormat = .stencil8
            #endif
            msdfRenderer = try MSDFTextRenderer(
                device: device,
                pixelFormat: view.colorPixelFormat,
                sampleCount: view.sampleCount,
                atlasPxRange: atlas.atlas.distanceRange,
                depthPixelFormat: depthPixelFormat,
                stencilPixelFormat: stencilPixelFormat
            )
        } catch {
            throw ConstellationLabelRendererError.msdfRendererCreationFailed(underlying: error)
        }
        atlasUnitRange = msdfRenderer.unitRange(for: atlasTexture)

        let ctFont = try ConstellationLabelRenderer.makeFont(size: 14)
        let meshBuilder = MSDFTextMeshBuilder(device: device, atlas: atlas, font: ctFont)
        try buildLabels(
            builder: meshBuilder,
            constellations: Array(starManager.allConstellations()).sorted(by: { $0.name < $1.name })
        )

        msdfRenderer.setOrthoProjection(
            width: Float(view.drawableSize.width),
            height: Float(view.drawableSize.height)
        )
    }

    func drawableSizeWillChange(to size: CGSize) {
        drawableSize = size
        guard size.width > 0, size.height > 0 else { return }
        msdfRenderer.setOrthoProjection(
            width: Float(size.width),
            height: Float(size.height)
        )
    }

    func draw(
        renderEncoder: MTLRenderCommandEncoder,
        projectionMatrix: matrix_float4x4,
        viewMatrix: matrix_float4x4
    ) {
        guard isVisible,
              !labels.isEmpty,
              drawableSize.width > 0,
              drawableSize.height > 0
        else {
            return
        }

        let viewportWidth = Float(drawableSize.width)
        let viewportHeight = Float(drawableSize.height)
        let mvp = projectionMatrix * viewMatrix

        for label in labels {
            let clip = mvp * SIMD4<Float>(label.worldPosition, 1.0)
            guard clip.w > 0 else { continue }

            let invW = 1.0 / clip.w
            let ndc = SIMD3<Float>(clip.x * invW, clip.y * invW, clip.z * invW)

            guard abs(ndc.x) <= 1.05,
                  abs(ndc.y) <= 1.05,
                  ndc.z >= -1.0,
                  ndc.z <= 1.0
            else {
                continue
            }

            let pixelX = (ndc.x * 0.5 + 0.5) * viewportWidth
            let pixelY = (-ndc.y * 0.5 + 0.5) * viewportHeight

            let halfWidth = label.bounds.x * 0.5
            let anchorY = label.bounds.y * 0.5

            let translation = matrix_float4x4(
                translationX: pixelX - halfWidth,
                translationY: pixelY - anchorY,
                translationZ: 0.0
            )

            var uniforms = MSDFUniforms()
            uniforms.projectionMatrix = msdfRenderer.projectionMatrix
            uniforms.modelViewMatrix = translation
            uniforms.textColor = label.color
            uniforms.unitRange = atlasUnitRange

            memcpy(
                label.uniformBuffer.contents(),
                &uniforms,
                MemoryLayout<MSDFUniforms>.stride
            )

            msdfRenderer.encode(
                encoder: renderEncoder,
                mesh: label.mesh,
                atlasTexture: atlasTexture,
                uniformBuffer: label.uniformBuffer
            )
        }
    }

    // MARK: - Private helpers

    private func buildLabels(
        builder: MSDFTextMeshBuilder,
        constellations: [Constellation]
    ) throws {
        labels = try constellations.map { constellation in
            guard let mesh = builder.buildMesh(
                text: constellation.localizedName,
                in: labelFrame,
                margin: labelMargin,
                scale: contentScale
            ) else {
                throw ConstellationLabelRendererError.meshCreationFailed(constellation: constellation.name)
            }

            let direction = SIMD3<Float>(
                Float(constellation.center.x),
                Float(constellation.center.y),
                Float(constellation.center.z)
            )
            let length = simd_length(direction)
            guard length > 0 else {
                throw ConstellationLabelRendererError.invalidConstellationCenter(constellation: constellation.name)
            }
            let normalizedDir = direction / length
            let worldPosition = starToWorldTransform * normalizedDir * labelDistance

            guard let buffer = device.makeBuffer(
                length: MemoryLayout<MSDFUniforms>.stride,
                options: .storageModeShared
            ) else {
                throw ConstellationLabelRendererError.uniformBufferAllocationFailed(constellation: constellation.name)
            }
            buffer.label = "\(constellation.iAUName).LabelUniforms"

            return LabelEntry(
                mesh: mesh,
                worldPosition: worldPosition,
                color: styleColor,
                uniformBuffer: buffer,
                bounds: SIMD2<Float>(
                    Float(mesh.bounds.width),
                    Float(mesh.bounds.height)
                )
            )
        }
    }

    private static func loadAtlas() throws -> MSDFAtlas {
        guard let url = Bundle.main.url(forResource: "SF-Pro-Display_mtsdf", withExtension: "json") else {
            throw ConstellationLabelRendererError.atlasJSONMissing
        }
        do {
            return try MSDFAtlas.load(from: url)
        } catch {
            throw ConstellationLabelRendererError.atlasLoadFailed(underlying: error)
        }
    }

    private static func loadAtlasTexture(device: MTLDevice) throws -> MTLTexture {
        let textureLoader = MTKTextureLoader(device: device)
        let options: [MTKTextureLoader.Option: Any] = [
            .SRGB: false,
            .origin: MTKTextureLoader.Origin.topLeft,
            .generateMipmaps: false,
            .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue),
            .textureStorageMode: NSNumber(value: MTLStorageMode.private.rawValue),
        ]

        guard let url = Bundle.main.url(forResource: "SF-Pro-Display_mtsdf", withExtension: "png") else {
            throw ConstellationLabelRendererError.atlasTextureMissing
        }

        do {
            return try textureLoader.newTexture(URL: url, options: options)
        } catch {
            throw ConstellationLabelRendererError.atlasTextureLoadFailed(underlying: error)
        }
    }

    private static func makeFont(size: CGFloat) throws -> CTFont {
        guard let fontURL = Bundle.main.url(forResource: "SF-Pro-Display-Regular", withExtension: "otf") else {
            throw ConstellationLabelRendererError.fontResourceMissing
        }

        guard let dataProvider = CGDataProvider(url: fontURL as CFURL),
              let cgFont = CGFont(dataProvider)
        else {
            throw ConstellationLabelRendererError.fontDataProviderCreationFailed
        }

        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &error) {
            if let cfError = error?.takeRetainedValue() {
                let code = CFErrorGetCode(cfError)
                if let ctError = CTFontManagerError(rawValue: code), ctError == .alreadyRegistered {
                    // Font already registered; nothing to do.
                } else {
                    throw ConstellationLabelRendererError.fontRegistrationFailed(underlying: cfError)
                }
            }
        }

        return CTFontCreateWithGraphicsFont(cgFont, size, nil, nil)
    }

    private static func computeContentScale(for view: MTKView) -> CGFloat {
#if os(macOS)
        if let scale = view.layer?.contentsScale {
            return CGFloat(scale)
        }
        if let windowScale = view.window?.backingScaleFactor {
            return CGFloat(windowScale)
        }
        return 1.0
#else
        return view.contentScaleFactor
#endif
    }
}
