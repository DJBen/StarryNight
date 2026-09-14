import Foundation
import simd

/// Immutable, reusable rendering data. Drawing and hit testing perform no SQLite I/O.
public struct SkySnapshot: Sendable {
    public let stars: [Star]
    public let constellations: Set<Constellation>
    public let lines: [Int: [Constellation.Line]]
    public let starsByID: [Int: Star]

    public init(stars: [Star], constellations: Set<Constellation>, lines: [Int: [Constellation.Line]], starsByID: [Int: Star]) {
        self.stars = stars
        self.constellations = constellations
        self.lines = lines
        self.starsByID = starsByID
    }

    public func closestStar(to coordinate: SIMD3<Double>, maximumAngularDistance: Double = .pi) -> Star? {
        guard coordinate.x.isFinite, coordinate.y.isFinite, coordinate.z.isFinite,
              simd_length_squared(coordinate) > 0,
              maximumAngularDistance.isFinite, maximumAngularDistance >= 0 else { return nil }
        let direction = simd_normalize(coordinate)
        let threshold = cos(min(maximumAngularDistance, .pi))
        return stars.lazy.filter {
            simd_dot(direction, simd_normalize($0.coordinate)) >= threshold - 1e-14
        }.max {
            let lhs = simd_dot(direction, simd_normalize($0.coordinate))
            let rhs = simd_dot(direction, simd_normalize($1.coordinate))
            return lhs == rhs ? $0.id > $1.id : lhs < rhs
        }
    }
}

/// Preferred API for Swift concurrency clients. Opens the read-only database lazily
/// on this actor, never on the caller's main actor. Reuse one catalog per app.
public actor StarCatalog {
    private var manager: StarManager?
    private var cachedSnapshot: (magnitude: Double, snapshot: SkySnapshot)?

    public init() {}

    private func database() throws -> StarManager {
        if let manager { return manager }
        let manager = try StarManager()
        self.manager = manager
        return manager
    }

    public func snapshot(maximumMagnitude: Double = 6.5) throws -> SkySnapshot {
        try Task.checkCancellation()
        if let cachedSnapshot, cachedSnapshot.magnitude == maximumMagnitude {
            return cachedSnapshot.snapshot
        }
        let snapshot = try database().skySnapshot(maximumMagnitude: maximumMagnitude)
        try Task.checkCancellation()
        // Keep one rendering snapshot rather than an unbounded cache of zoom levels.
        cachedSnapshot = (maximumMagnitude, snapshot)
        return snapshot
    }

    public func starInfo(forID id: Int) throws -> StarInfo? {
        try Task.checkCancellation()
        return try database().starInfo(forId: id)
    }

    public func searchStars(matching name: String) throws -> [Star] {
        try Task.checkCancellation()
        return try database().searchStars(matching: name)
    }
}
