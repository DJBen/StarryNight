import Foundation
@preconcurrency import SQLite

extension StarManager {
    /// Batch-loads line endpoints independently of the displayed magnitude cutoff.
    /// At most four indexed endpoint queries, rather than two queries per line.
    public func skySnapshot(maximumMagnitude: Double) throws -> SkySnapshot {
        queryLock.lock()
        defer { queryLock.unlock() }
        let stars = stars(maximumMagnitude: maximumMagnitude)
        let constellations = allConstellations()
        var lines: [Int: [Constellation.Line]] = [:]
        var endpointIDs = Set<Int>()
        for row in try db.prepare(Table("constellation_lines")) {
            let constellationID = try row.get(Expression<Int>("constellation_id"))
            let first = try row.get(Expression<Int>("star1_id"))
            let second = try row.get(Expression<Int>("star2_id"))
            lines[constellationID, default: []].append(.init(star1Id: first, star2Id: second))
            endpointIDs.insert(first)
            endpointIDs.insert(second)
        }
        var starsByID = Dictionary(stars.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let missing = endpointIDs.subtracting(starsByID.keys).sorted()
        // Stay below SQLite's historical 999 bound-variable limit.
        for offset in stride(from: 0, to: missing.count, by: 500) {
            let ids = Array(missing[offset..<min(offset + 500, missing.count)])
            for table in [Tables.starsBrightest300, Tables.starsH3_0, Tables.starsH3_1, Tables.starsH3_2] {
                for row in try db.prepare(table.filter(ids.contains(Tables.id))) {
                    let star = createStar(from: row)
                    starsByID[star.id] = star
                }
            }
        }
        cachedLines.merge(lines) { _, new in new }
        return SkySnapshot(stars: stars, constellations: constellations, lines: lines, starsByID: starsByID)
    }
}
