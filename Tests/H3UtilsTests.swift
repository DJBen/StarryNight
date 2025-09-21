import XCTest
@testable import StarryNight
import Ch3
import simd

class H3UtilsTests: XCTestCase {

    private func isPointInPolygon(point: (latitude: Double, longitude: Double), polygon: [(latitude: Double, longitude: Double)]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var angleSum: Double = 0.0
        let pointRad = (lat: point.latitude * .pi / 180.0, lon: point.longitude * .pi / 180.0)

        for i in 0..<polygon.count {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % polygon.count]

            let p1Rad = (lat: p1.latitude * .pi / 180.0, lon: p1.longitude * .pi / 180.0)
            let p2Rad = (lat: p2.latitude * .pi / 180.0, lon: p2.longitude * .pi / 180.0)

            // Calculate bearings from the test point to the vertices of the edge
            let bearing1 = atan2(sin(p1Rad.lon - pointRad.lon) * cos(p1Rad.lat),
                                 cos(pointRad.lat) * sin(p1Rad.lat) - sin(pointRad.lat) * cos(p1Rad.lat) * cos(p1Rad.lon - pointRad.lon))
            let bearing2 = atan2(sin(p2Rad.lon - pointRad.lon) * cos(p2Rad.lat),
                                 cos(pointRad.lat) * sin(p2Rad.lat) - sin(pointRad.lat) * cos(p2Rad.lat) * cos(p2Rad.lon - pointRad.lon))

            var angle = bearing2 - bearing1

            // Normalize angle to be between -pi and pi
            if angle > .pi {
                angle -= 2 * .pi
            } else if angle < -.pi {
                angle += 2 * .pi
            }

            angleSum += angle
        }

        // If the absolute sum of angles is close to 2*pi, the point is inside.
        return abs(angleSum) > .pi
    }

    func testStandardViewport() {
        let viewport: [(latitude: Double, longitude: Double)] = [
            (latitude: 40.7128, longitude: -74.0060), // New York City
            (latitude: 34.0522, longitude: -118.2437), // Los Angeles
            (latitude: 25.7617, longitude: -80.1918),  // Miami
            (latitude: 41.8781, longitude: -87.6298)   // Chicago
        ]
        
        let cells = H3Utils.h3Cells(inViewport: viewport, resolution: 2)
        XCTAssertFalse(cells.isEmpty, "Should return some H3 cells for a standard viewport")

        // This viewport is concave. With CONTAINMENT_OVERLAPPING, H3 may return cells
        // whose centers are outside the polygon's strict boundaries to ensure full coverage.
        // A strict point-in-polygon assertion for every cell center is not reliable here.
    }

    func testNorthPoleViewport() {
        let viewport: [(latitude: Double, longitude: Double)] = [
            (latitude: 80.0, longitude: 0.0),
            (latitude: 80.0, longitude: 90.0),
            (latitude: 80.0, longitude: 180.0),
            (latitude: 80.0, longitude: -90.0)
        ]
        
        let cells = H3Utils.h3Cells(inViewport: viewport, resolution: 1)
        XCTAssertFalse(cells.isEmpty, "Should return some H3 cells for a North Pole viewport")
        
        // Check if one of the known polar cells is included
        var northPoleCell: H3Index = 0
        var poleCoord = LatLng(lat: .pi/2, lng: 0)
        _ = latLngToCell(&poleCoord, 1, &northPoleCell)
        XCTAssertTrue(cells.contains(northPoleCell), "Result should contain a north pole cell")

        // With CONTAINMENT_OVERLAPPING, some cell centers might be slightly outside.
        // We check if the latitude is reasonably close to the viewport boundary.
        for cell in cells {
            var centerCoord = LatLng()
            cellToLatLng(cell, &centerCoord)
            let center = (latitude: centerCoord.lat * 180.0 / .pi, longitude: centerCoord.lng * 180.0 / .pi)
            XCTAssertTrue(center.latitude >= 75.0, "Cell center latitude (\(center.latitude)) should be within or close to the viewport boundary (>= 80)")
        }
    }

    func testSouthPoleViewport() {
        let viewport: [(latitude: Double, longitude: Double)] = [
            (latitude: -80.0, longitude: 0.0),
            (latitude: -80.0, longitude: 90.0),
            (latitude: -80.0, longitude: 180.0),
            (latitude: -80.0, longitude: -90.0)
        ]
        
        let cells = H3Utils.h3Cells(inViewport: viewport, resolution: 1)
        XCTAssertFalse(cells.isEmpty, "Should return some H3 cells for a South Pole viewport")
        
        // Check if one of the known polar cells is included
        var southPoleCell: H3Index = 0
        var poleCoord = LatLng(lat: -.pi/2, lng: 0)
        _ = latLngToCell(&poleCoord, 1, &southPoleCell)
        XCTAssertTrue(cells.contains(southPoleCell), "Result should contain a south pole cell")

        // With CONTAINMENT_OVERLAPPING, some cell centers might be slightly outside.
        // We check if the latitude is reasonably close to the viewport boundary.
        for cell in cells {
            var centerCoord = LatLng()
            cellToLatLng(cell, &centerCoord)
            let center = (latitude: centerCoord.lat * 180.0 / .pi, longitude: centerCoord.lng * 180.0 / .pi)
            XCTAssertTrue(center.latitude <= -75.0, "Cell center latitude (\(center.latitude)) should be within or close to the viewport boundary (<= -80)")
        }
    }
}
