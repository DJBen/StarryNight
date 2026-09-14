import XCTest
import SQLite
import simd
@testable import StarryNight

final class CatalogConcurrencyTests: XCTestCase {
    func testReleaseDatabaseIndexesAndIntegrity() throws {
        let manager = try StarManager()
        XCTAssertEqual(try manager.db.scalar("PRAGMA integrity_check") as? String, "ok")
        XCTAssertEqual(try manager.db.scalar("PRAGMA user_version") as? Int64, 30200)
        for table in ["stars_brightest_300", "stars_h3_0", "stars_h3_1", "stars_h3_2"] {
            let plan = try manager.db.prepare("EXPLAIN QUERY PLAN SELECT * FROM \(table) WHERE id = 1")
            XCTAssertTrue(plan.map { String(describing: $0) }.joined().contains("idx_\(table)_id"))
        }
        XCTAssertThrowsError(try manager.db.run("CREATE TABLE forbidden (id INTEGER)"))
    }

    func testSnapshotLoadsEveryEndpointEvenBelowMagnitudeCutoff() throws {
        let snapshot = try StarManager().skySnapshot(maximumMagnitude: 1)
        XCTAssertFalse(snapshot.stars.isEmpty)
        XCTAssertTrue(snapshot.stars.allSatisfy { $0.magnitude <= 1 })
        XCTAssertGreaterThan(snapshot.constellations.count, 85)
        for lines in snapshot.lines.values {
            for line in lines {
                XCTAssertNotNil(snapshot.starsByID[line.star1Id])
                XCTAssertNotNil(snapshot.starsByID[line.star2Id])
            }
        }
    }

    func testInclusiveMagnitudeBoundaryAcrossAllTables() throws {
        let manager = try StarManager()
        for level in 0...2 {
            let first = try XCTUnwrap(manager.stars(forH3Level: level).first)
            XCTAssertTrue(manager.stars(forH3Level: level, maximumMagnitude: first.magnitude).contains(first))
        }
    }

    func testConeSearchMatchesFullCatalogAcrossPolesAndWraparound() throws {
        let manager = try StarManager()
        let stars = manager.stars(maximumMagnitude: 6)
        for direction in [SIMD3<Double>(1, 0, 0), .init(0, 0, 1), .init(-1, 0.001, 0)] {
            let normalized = simd_normalize(direction)
            let expected = Set(stars.filter { simd_dot(normalized, simd_normalize($0.coordinate)) >= cos(0.3) - 1e-14 }.map(\.id))
            let actual = manager.closeStars(around: direction, maximumAngularDistance: 0.3, maximumMagnitude: 6)
            XCTAssertEqual(Set(actual.map(\.id)), expected)
        }
        XCTAssertTrue(manager.closeStars(around: .zero, maximumAngularDistance: 1).isEmpty)
    }

    func testSharedLegacyManagerFromConcurrentWorkers() throws {
        let manager = try StarManager()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            XCTAssertEqual(manager.brightestStars().count, 299)
            XCTAssertNotNil(manager.constellation(iau: "Ori"))
            XCTAssertFalse(manager.stars(maximumMagnitude: 4).isEmpty)
        }
    }

    func testActorConcurrentSnapshotsAndCancellation() async throws {
        let catalog = StarCatalog()
        let counts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<20 {
                group.addTask { try await catalog.snapshot(maximumMagnitude: 6).stars.count }
            }
            var result: [Int] = []
            for try await count in group { result.append(count) }
            return result
        }
        XCTAssertEqual(Set(counts).count, 1)
        XCTAssertGreaterThan(counts[0], 299)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await catalog.snapshot()
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled requests must not return a snapshot")
        } catch is CancellationError {} 
    }

    func testSnapshotHitTesting() throws {
        let snapshot = try StarManager().skySnapshot(maximumMagnitude: 6)
        let star = try XCTUnwrap(snapshot.stars.first)
        XCTAssertEqual(snapshot.closestStar(to: star.coordinate, maximumAngularDistance: 0)?.id, star.id)
        XCTAssertNil(snapshot.closestStar(to: .zero))
        XCTAssertNil(snapshot.closestStar(to: .init(.nan, 0, 0)))
    }
}
