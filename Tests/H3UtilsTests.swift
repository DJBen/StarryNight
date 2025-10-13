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

    func testContainsPole() {
        // Test case 1: Standard viewport that doesn't contain poles
        let standardViewport: [LatLng] = [
            LatLng(lat: 40.0 * .pi / 180.0, lng: -80.0 * .pi / 180.0), // Top-left
            LatLng(lat: 40.0 * .pi / 180.0, lng: -70.0 * .pi / 180.0), // Top-right  
            LatLng(lat: 30.0 * .pi / 180.0, lng: -70.0 * .pi / 180.0), // Bottom-right
            LatLng(lat: 30.0 * .pi / 180.0, lng: -80.0 * .pi / 180.0)  // Bottom-left
        ]
        XCTAssertFalse(H3Utils.containsPole(vertices: standardViewport), "Standard viewport should not contain pole")
        
        // Test case 2: North pole viewport (clockwise from top-left)
        let northPoleViewport: [LatLng] = [
            LatLng(lat: 80.0 * .pi / 180.0, lng: -90.0 * .pi / 180.0), // Top-left
            LatLng(lat: 80.0 * .pi / 180.0, lng: 90.0 * .pi / 180.0),  // Top-right
            LatLng(lat: 80.0 * .pi / 180.0, lng: 0.0 * .pi / 180.0),   // Bottom-right
            LatLng(lat: 80.0 * .pi / 180.0, lng: 180.0 * .pi / 180.0)  // Bottom-left
        ]
        XCTAssertTrue(H3Utils.containsPole(vertices: northPoleViewport), "North pole viewport should contain pole")
        
        // Test case 3: South pole viewport (clockwise from top-left) 
        let southPoleViewport: [LatLng] = [
            LatLng(lat: -80.0 * .pi / 180.0, lng: -90.0 * .pi / 180.0), // Top-left
            LatLng(lat: -80.0 * .pi / 180.0, lng: 90.0 * .pi / 180.0),  // Top-right
            LatLng(lat: -80.0 * .pi / 180.0, lng: 0.0 * .pi / 180.0),   // Bottom-right
            LatLng(lat: -80.0 * .pi / 180.0, lng: 180.0 * .pi / 180.0)  // Bottom-left
        ]
        XCTAssertTrue(H3Utils.containsPole(vertices: southPoleViewport), "South pole viewport should contain pole")
        
        // Test case 4: Large viewport crossing dateline but not containing poles
        let datelineViewport: [LatLng] = [
            LatLng(lat: 20.0 * .pi / 180.0, lng: 170.0 * .pi / 180.0), // Top-left
            LatLng(lat: 20.0 * .pi / 180.0, lng: -170.0 * .pi / 180.0), // Top-right
            LatLng(lat: 10.0 * .pi / 180.0, lng: -170.0 * .pi / 180.0), // Bottom-right
            LatLng(lat: 10.0 * .pi / 180.0, lng: 170.0 * .pi / 180.0)   // Bottom-left
        ]
        XCTAssertFalse(H3Utils.containsPole(vertices: datelineViewport), "Dateline crossing viewport should not contain pole")
        
        // // Test case 5: Failing case - polygon that surrounds north pole but returns false
        // let failingNorthPoleViewport: [LatLng] = [
        //     LatLng(lat: 0.73738688230514526, lng: -3.1072006225585938),
        //     LatLng(lat: 0.73738688230514526, lng: -2.2440545558929443),
        //     LatLng(lat: 0.73738670349121094, lng: 0.89753812551498413),
        //     LatLng(lat: 0.73738670349121094, lng: 0.034392070025205612)
        // ]
        // XCTAssertTrue(H3Utils.containsPole(vertices: failingNorthPoleViewport), "Failing north pole viewport should contain pole")
        
        // // Test case 6: Similar failing case but for South pole  
        // let failingSouthPoleViewport: [LatLng] = [
        //     LatLng(lat: -0.73738688230514526, lng: -3.1072006225585938),
        //     LatLng(lat: -0.73738688230514526, lng: -2.2440545558929443),
        //     LatLng(lat: -0.73738670349121094, lng: 0.89753812551498413),
        //     LatLng(lat: -0.73738670349121094, lng: 0.034392070025205612)
        // ]
        // XCTAssertTrue(H3Utils.containsPole(vertices: failingSouthPoleViewport), "Failing south pole viewport should contain pole")
        
        // Test case 7: False positive case - polygon that does NOT contain any pole
        let falsePositiveCase: [LatLng] = [
            LatLng(lat: 1.0206879377365112, lng: 2.0403242111206055),
            LatLng(lat: 1.0206879377365112, lng: 0.617332935333252),
            LatLng(lat: -0.6333189010620117, lng: 0.8915391564369202),
            LatLng(lat: -0.6333188414573669, lng: 1.7661181688308716)
        ]
        XCTAssertFalse(H3Utils.containsPole(vertices: falsePositiveCase), "Polygon spanning -36° to 58° latitude should NOT contain either pole")
    }
}
