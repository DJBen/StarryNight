import XCTest
@testable import StarryNight
import Ch3
import simd

class H3UtilsTests: XCTestCase {

    private func isPointInPolygon(point: LatLng, polygon: [LatLng]) -> Bool {
        guard polygon.count >= 3 else { return false }

        var angleSum: Double = 0.0
        let pointRad = (lat: point.lat, lon: point.lng)

        for i in 0..<polygon.count {
            let p1 = polygon[i]
            let p2 = polygon[(i + 1) % polygon.count]

            let p1Rad = (lat: p1.lat, lon: p1.lng)
            let p2Rad = (lat: p2.lat, lon: p2.lng)

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
        let viewport: [LatLng] = [
            LatLng(lat: 40.7128 * .pi / 180.0, lng: -74.0060 * .pi / 180.0), // New York City
            LatLng(lat: 34.0522 * .pi / 180.0, lng: -118.2437 * .pi / 180.0), // Los Angeles
            LatLng(lat: 25.7617 * .pi / 180.0, lng: -80.1918 * .pi / 180.0),  // Miami
            LatLng(lat: 41.8781 * .pi / 180.0, lng: -87.6298 * .pi / 180.0)   // Chicago
        ]
        
        let cells = H3Utils.h3Cells(inViewport: viewport, resolution: 2)
        XCTAssertFalse(cells.isEmpty, "Should return some H3 cells for a standard viewport")
    }

    func testNorthPoleViewport() {
        let viewport: [LatLng] = [
            LatLng(lat: 80.0 * .pi / 180.0, lng: 0.0),
            LatLng(lat: 80.0 * .pi / 180.0, lng: 90.0 * .pi / 180.0),
            LatLng(lat: 80.0 * .pi / 180.0, lng: 180.0 * .pi / 180.0),
            LatLng(lat: 80.0 * .pi / 180.0, lng: -90.0 * .pi / 180.0)
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
            let center = LatLng(lat: centerCoord.lat, lng: centerCoord.lng)
            let centerLatDeg = center.lat * 180.0 / .pi
            XCTAssertTrue(centerLatDeg >= 75.0, "Cell center latitude (\(centerLatDeg)) should be within or close to the viewport boundary (>= 80)")
        }
    }

    func testSouthPoleViewport() {
        let viewport: [LatLng] = [
            LatLng(lat: -80.0 * .pi / 180.0, lng: 0.0),
            LatLng(lat: -80.0 * .pi / 180.0, lng: 90.0 * .pi / 180.0),
            LatLng(lat: -80.0 * .pi / 180.0, lng: 180.0 * .pi / 180.0),
            LatLng(lat: -80.0 * .pi / 180.0, lng: -90.0 * .pi / 180.0)
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
            let center = LatLng(lat: centerCoord.lat, lng: centerCoord.lng)
            let centerLatDeg = center.lat * 180.0 / .pi
            XCTAssertTrue(centerLatDeg <= -75.0, "Cell center latitude (\(centerLatDeg)) should be within or close to the viewport boundary (<= -80)")
        }
    }

    func testPrintViewportCells_FOV90() {
        // Viewport derived from: Camera FOV updated to: 90.0°
        // LatLng vertices provided by the user
        let viewport: [LatLng] = [
            LatLng(lat: -42.252130771778326 * .pi / 180.0, lng: 24.714298436166192 * .pi / 180.0),
            LatLng(lat: -42.252130771778326 * .pi / 180.0, lng: -24.714298436166192 * .pi / 180.0),
            LatLng(lat: 42.252130771778326 * .pi / 180.0, lng: -24.714298436166192 * .pi / 180.0),
            LatLng(lat: 42.252130771778326 * .pi / 180.0, lng: 24.714298436166192 * .pi / 180.0)
        ]

        let resolution: Int32 = 0
        let cells = H3Utils.h3Cells(inViewport: viewport, resolution: resolution)
        XCTAssertEqual(cells.count, 20)

        print("FOV=90° viewport vertices: \(viewport)")
        print("H3 cells (count=\(cells.count), res=\(resolution)):")
        for cell in cells {
            var centerCoord = LatLng()
            cellToLatLng(cell, &centerCoord)
            let centerLatDeg = centerCoord.lat * 180.0 / .pi
            let centerLngDeg = centerCoord.lng * 180.0 / .pi
            let hex = String(cell, radix: 16)
            print("- cell=0x\(hex) center=(lat: \(centerLatDeg), lng: \(centerLngDeg))")
        }
    }
}
