import Foundation
import simd
import Ch3

extension LatLng: @retroactive Equatable, @retroactive Hashable, @unchecked Sendable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(lat)
        hasher.combine(lng)
    }

    public static func == (lhs: LatLng, rhs: LatLng) -> Bool {
        lhs.lat == rhs.lat && lhs.lng == rhs.lng
    }
}

public enum H3Utils {
    
    /// Get H3 cells for a given viewport and resolution.
    /// Handles viewports that cross the poles by splitting them into smaller polygons.
    /// - Parameters:
    ///   - vertices: An array of 4 tuples representing the corners of the viewport in
    ///               (latitude, longitude) format. The vertices should be ordered
    ///               either clockwise or counter-clockwise.
    ///   - resolution: The desired H3 resolution (0-15).
    /// - Returns: An array of H3Index values covering the specified viewport.
    public static func h3Cells(
        inViewport vertices: [LatLng], 
        resolution: Int32
    ) -> [H3Index] {
        guard vertices.count == 4 else {
            print("Error: Viewport must have exactly 4 vertices")
            return []
        }

        // Check for pole containment
        if containsPole(vertices: vertices) {
            return cellsForPolarViewport(vertices: vertices, resolution: resolution)
        } else {
            return cellsForStandardViewport(vertices: vertices, resolution: resolution)
        }
    }
    
    private static func cellsForStandardViewport(vertices: [LatLng], resolution: Int32) -> [H3Index] {
        let geoloop = GeoLoop(numVerts: Int32(vertices.count), verts: UnsafeMutablePointer<LatLng>.allocate(capacity: vertices.count))
        for (index, coord) in vertices.enumerated() {
            geoloop.verts[index] = coord
        }
        defer {
            geoloop.verts.deallocate()
        }
        
        var polygon = GeoPolygon(geoloop: geoloop, numHoles: 0, holes: nil)
        return getCells(for: &polygon, resolution: resolution)
    }
    
    private static func cellsForPolarViewport(vertices: [LatLng], resolution: Int32) -> [H3Index] {
        // Fan out many small "pizza slices" from the pole to the boundary latitude
        // to avoid polyfill artifacts near the pole and dateline wrapping issues.
        // Assumptions: vertices define a polar cap-like viewport (e.g., a rectangle)
        // and are already in radians.

        guard !vertices.isEmpty else { return [] }

        var allCells = Set<H3Index>()

        // Determine which pole and the boundary latitude (closest to equator)
        let avgLat = vertices.reduce(0.0) { $0 + $1.lat } / Double(vertices.count)
        let isNorth = avgLat >= 0
        
        // Note: we avoid using the pole directly to reduce singularity issues
        // when polyfilling; instead we fan from a near-pole latitude.

        // Boundary latitude is the minimum (north cap) or maximum (south cap)
        // latitude among the vertices
        let boundaryLat: Double
        if isNorth {
            boundaryLat = vertices.map { $0.lat }.min() ?? (Double.pi / 3)
        } else {
            boundaryLat = vertices.map { $0.lat }.max() ?? (-Double.pi / 3)
        }

        // Build 12 quadrilateral "pizza slices" around the pole.
        // Near-pole latitude (±89.9° in radians)
        let nearPoleLatDeg = 89.9
        let nearPoleLat = (isNorth ? 1.0 : -1.0) * (nearPoleLatDeg * Double.pi / 180.0)

        // 12 slices of 30° each, starting at 0° longitude (wrap handled by normalizeLng)
        let slices = 12
        let step = 2.0 * Double.pi / Double(slices) // 30° in radians
        let base = 0.0 // 0° in radians

        for k in 0..<slices {
            let lon0 = normalizeLng(base + Double(k) * step)
            let lon1 = normalizeLng(base + Double(k + 1) * step)

            // 4-vertex quadrilateral (near pole band to boundary latitude band)
            let v0 = LatLng(lat: nearPoleLat, lng: lon0)
            let v1 = LatLng(lat: nearPoleLat, lng: lon1)
            let v2 = LatLng(lat: boundaryLat, lng: lon1)
            let v3 = LatLng(lat: boundaryLat, lng: lon0)

            let geoloop = GeoLoop(numVerts: 4, verts: UnsafeMutablePointer<LatLng>.allocate(capacity: 4))
            geoloop.verts[0] = v0
            geoloop.verts[1] = v1
            geoloop.verts[2] = v2
            geoloop.verts[3] = v3
            defer { geoloop.verts.deallocate() }

            var polygon = GeoPolygon(geoloop: geoloop, numHoles: 0, holes: nil)
            let cells = getCells(for: &polygon, resolution: resolution)
            allCells.formUnion(cells)
        }

        return Array(allCells)
    }

    // Normalize longitude to [-pi, pi)
    private static func normalizeLng(_ lng: Double) -> Double {
        var x = fmod(lng + Double.pi, 2 * Double.pi)
        if x < 0 { x += 2 * Double.pi }
        return x - Double.pi
    }

    private static func getCells(for polygon: inout GeoPolygon, resolution: Int32) -> [H3Index] {
        var maxCellsCount: Int64 = 0
        let flags: UInt32 = 2 // CONTAINMENT_OVERLAPPING
        
        let sizeErr = maxPolygonToCellsSizeExperimental(&polygon, resolution, flags, &maxCellsCount)
        guard sizeErr == 0, maxCellsCount > 0 else {
            return []
        }
        
        let h3Cells = UnsafeMutablePointer<H3Index>.allocate(capacity: Int(maxCellsCount))
        h3Cells.initialize(repeating: 0, count: Int(maxCellsCount))
        defer {
            h3Cells.deallocate()
        }
        
        let fillErr = polygonToCellsExperimental(&polygon, resolution, flags, maxCellsCount, h3Cells)
        guard fillErr == 0 else {
            return []
        }
        
        var cells: [H3Index] = []
        for i in 0..<Int(maxCellsCount) {
            if h3Cells[i] != 0 {
                cells.append(h3Cells[i])
            }
        }
        
        return cells
    }
    
    public static func containsPole(vertices: [LatLng]) -> Bool {
        guard vertices.count > 2 else { return false }

        let lats = vertices.map { $0.lat }
        let allPositive = lats.allSatisfy { $0 > 0 }
        let allNegative = lats.allSatisfy { $0 < 0 }

        if !allPositive && !allNegative {
            return false // Straddles equator, cannot contain a pole
        }

        // Check if the polygon defined by the vertices contains a pole.
        // This can be determined by summing the angles between successive vertices
        // from the pole's perspective. If the sum is +/- 2*pi, the pole is contained.
        var angleSum: Double = 0
        for i in 0..<vertices.count {
            let p1 = vertices[i]
            let p2 = vertices[(i + 1) % vertices.count]
            
            var deltaLon = p2.lng - p1.lng
            
            // Adjust for wrapping
            if deltaLon > .pi {
                deltaLon -= 2 * .pi
            } else if deltaLon < -.pi {
                deltaLon += 2 * .pi
            }
            
            angleSum += deltaLon
        }

        // If the absolute sum of angles is close to 2*pi, it encloses the pole.
        return abs(angleSum) > .pi
    }
}
