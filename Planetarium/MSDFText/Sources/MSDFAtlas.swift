import CoreGraphics
import Foundation

public struct MSDFAtlas: Decodable {
    private enum CodingKeys: String, CodingKey {
        case atlas
        case metrics
        case glyphs
    }

    public struct AtlasInfo: Decodable {
        public let distanceRange: Float
        public let distanceRangeMiddle: Float
        public let size: Float
        public let width: Int
        public let height: Int
    }

    public struct GlyphBounds: Decodable {
        public let left: Float
        public let bottom: Float
        public let right: Float
        public let top: Float
    }

    public struct GlyphDescriptor: Decodable {
        public let index: UInt32
        public let advance: Float
        public let planeBounds: GlyphBounds?
        public let atlasBounds: GlyphBounds?
    }

    public struct Metrics: Decodable {
        public let emSize: Float
        public let lineHeight: Float
        public let ascender: Float
        public let descender: Float
    }

    public let atlas: AtlasInfo
    public let metrics: Metrics
    public let glyphs: [GlyphDescriptor]

    private var glyphMap: [CGGlyph: GlyphDescriptor] = [:]

    public var textureSize: CGSize {
        CGSize(width: atlas.width, height: atlas.height)
    }

    public func descriptor(for glyph: CGGlyph) -> GlyphDescriptor? {
        glyphMap[glyph]
    }

    public mutating func buildGlyphMap() {
        glyphMap.removeAll(keepingCapacity: true)
        glyphs.forEach { glyphMap[CGGlyph($0.index)] = $0 }
    }

    public static func load(from url: URL) throws -> MSDFAtlas {
        let data = try Data(contentsOf: url)
        var atlas = try JSONDecoder().decode(MSDFAtlas.self, from: data)
        atlas.buildGlyphMap()
        return atlas
    }
}
