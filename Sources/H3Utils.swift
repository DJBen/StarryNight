import Foundation
import simd
import Ch3

extension LatLng: @retroactive Equatable, @retroactive Hashable, @retroactive @unchecked Sendable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(lat)
        hasher.combine(lng)
    }

    public static func == (lhs: LatLng, rhs: LatLng) -> Bool {
        lhs.lat == rhs.lat && lhs.lng == rhs.lng
    }
}

public struct Viewport: Equatable, Hashable, Sendable {
    public var topLeft: LatLng
    public var topRight: LatLng
    public var bottomLeft: LatLng
    public var bottomRight: LatLng

    public init(topLeft: LatLng, topRight: LatLng, bottomLeft: LatLng, bottomRight: LatLng) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomLeft = bottomLeft
        self.bottomRight = bottomRight
    }
}

public enum H3Utils {
    
    /// Get H3 cells for a given viewport and resolution.
    /// Handles viewports that cross the poles by splitting them into smaller polygons.
    /// - Parameters:
    ///   - viewport: A Viewport struct representing the corners of the viewport.
    ///   - resolution: The desired H3 resolution (0-15).
    /// - Returns: An array of H3Index values covering the specified viewport.
    public static func h3Cells(
        inViewport viewport: Viewport, 
        resolution: Int32
    ) -> [H3Index] {
        // Check for pole containment
        if containsPole(viewport: viewport) {
            return cellsForPolarViewport(viewport: viewport, resolution: resolution)
        } else {
            return cellsForStandardViewport(viewport: viewport, resolution: resolution)
        }
    }
    
    static func cellsForStandardViewport(viewport: Viewport, resolution: Int32) -> [H3Index] {
        func makeGeoPolygon(from viewport: Viewport) -> (GeoPolygon, () -> Void) {
            let vertices = [viewport.topLeft, viewport.topRight, viewport.bottomRight, viewport.bottomLeft]
            // Warning: geoloop needs to be kept as long as GeoPolygon is involved in computation
            let geoloop = GeoLoop(numVerts: Int32(vertices.count), verts: UnsafeMutablePointer<LatLng>.allocate(capacity: vertices.count))
            geoloop.verts[0] = vertices[0]
            geoloop.verts[1] = vertices[1]
            geoloop.verts[2] = vertices[2]
            geoloop.verts[3] = vertices[3]
            
            let polygon = GeoPolygon(geoloop: geoloop, numHoles: 0, holes: nil)
            return (polygon, {
                geoloop.verts.deallocate()
            })
        }

        let isCenterNorthern = abs(viewport.topLeft.lat) > abs(viewport.bottomLeft.lat)
        // Check if the viewport wraps around longitude
        let wraps = sign(normalizeLng(viewport.topLeft.lng - viewport.topRight.lng)) != sign(normalizeLng(viewport.bottomLeft.lng - viewport.bottomRight.lng))
        let topWraps = isCenterNorthern && wraps
        let bottomWraps = !isCenterNorthern && wraps

        var allCells = Set<H3Index>()
        if topWraps {
            // Split into two polygons: TL-0-BR-BL and 0-TR-BR-BL
//            let viewport1 = Viewport(
//                topLeft: viewport.topLeft,
//                topRight: LatLng(lat: viewport.topRight.lat, lng: 0),
//                bottomLeft: viewport.bottomLeft,
//                bottomRight: LatLng(lat: viewport.bottomRight.lat, lng: 0)
//            )
//            let viewport2 = Viewport(
//                topLeft: LatLng(lat: viewport.topLeft.lat, lng: 0),
//                topRight: viewport.topRight,
//                bottomLeft: LatLng(lat: viewport.bottomLeft.lat, lng: 0),
//                bottomRight: viewport.bottomRight
//            )
//            var (polygon1, deallocateVerts1) = makeGeoPolygon(from: viewport1)
//            var (polygon2, deallocateVerts2) = makeGeoPolygon(from: viewport2)
//
//            let cells1 = getCells(for: &polygon1, resolution: resolution)
//            let cells2 = getCells(for: &polygon2, resolution: resolution)
//            allCells.formUnion(cells1)
//            allCells.formUnion(cells2)
//
//            deallocateVerts1()
//            deallocateVerts2()
            print("T: \(viewport)")
        } else if bottomWraps {
            // Split into two polygons: TL-TR-0-BL and TL-TR-BR-0
//            let viewport1 = Viewport(
//                topLeft: viewport.topLeft,
//                topRight: viewport.topRight,
//                bottomLeft: viewport.bottomLeft,
//                bottomRight: LatLng(lat: viewport.bottomRight.lat, lng: 0)
//            )
//            let viewport2 = Viewport(
//                topLeft: viewport.topLeft,
//                topRight: viewport.topRight,
//                bottomLeft: LatLng(lat: viewport.bottomLeft.lat, lng: 0),
//                bottomRight: viewport.bottomRight
//            )
//
//            var (polygon1, deallocateVerts1) = makeGeoPolygon(from: viewport1)
//            var (polygon2, deallocateVerts2) = makeGeoPolygon(from: viewport2)
//
//            let cells1 = getCells(for: &polygon1, resolution: resolution)
//            let cells2 = getCells(for: &polygon2, resolution: resolution)
//            allCells.formUnion(cells1)
//            allCells.formUnion(cells2)
//
//            deallocateVerts1()
//            deallocateVerts2()
            print("B: \(viewport)")
        }
        var (polygon, deallocateVerts) = makeGeoPolygon(from: viewport)
        allCells = Set(getCells(for: &polygon, resolution: resolution))
        deallocateVerts()

        return Array(allCells)
    }
    
    static func cellsForPolarViewport(viewport: Viewport, resolution: Int32) -> [H3Index] {
        // Fan out many small "pizza slices" from the pole to the boundary latitude
        // to avoid polyfill artifacts near the pole and dateline wrapping issues.
        
        let vertices = [viewport.topLeft, viewport.topRight, viewport.bottomRight, viewport.bottomLeft]
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
    
    /// Determines if a polygon contains either the North or South pole.
    /// - Parameter vertices: Array of LatLng coordinates defining the polygon boundary in clockwise order
    /// - Returns: true if the polygon contains either pole, false otherwise
    public static func containsPole(vertices: [LatLng]) -> Bool {
        guard vertices.count >= 3 else { return false }
        
        // Check both poles
        return containsNorthPole(vertices: vertices) || containsSouthPole(vertices: vertices)
    }
    
    /// Determines if a polygon contains the North pole using the winding number algorithm.
    /// - Parameter vertices: Array of LatLng coordinates defining the polygon boundary in clockwise order
    /// - Returns: true if the polygon contains the North pole
    private static func containsNorthPole(vertices: [LatLng]) -> Bool {
        // Use winding number algorithm adapted for spherical coordinates
        // The North pole is at latitude π/2 (longitude doesn't matter at pole)
        
        // For a point at the pole, we need to check if it's inside the polygon
        // We'll use a modified ray casting algorithm that works with spherical geometry
        
        var windingNumber = 0.0
        let n = vertices.count
        
        for i in 0..<n {
            let current = vertices[i]
            let next = vertices[(i + 1) % n]
            
            // Calculate the longitude difference, handling the dateline crossing
            let lonDiff = longitudeDifference(from: current.lng, to: next.lng)
            
            // Check if this edge crosses a meridian that passes through the pole
            // For the North pole, we need to check if the edge crosses above it
            if current.lat < Double.pi / 2 && next.lat < Double.pi / 2 {
                // Both points are south of the pole, so this edge can contribute to winding
                windingNumber += lonDiff / (2 * Double.pi)
            }
        }
        
        // For clockwise ordering, a positive winding number indicates containment
        return abs(windingNumber) > 0.5
    }
    
    /// Determines if a polygon contains the South pole using the winding number algorithm.
    /// - Parameter vertices: Array of LatLng coordinates defining the polygon boundary in clockwise order
    /// - Returns: true if the polygon contains the South pole
    private static func containsSouthPole(vertices: [LatLng]) -> Bool {
        // Similar to North pole but for South pole at latitude -π/2
        var windingNumber = 0.0
        let n = vertices.count
        
        for i in 0..<n {
            let current = vertices[i]
            let next = vertices[(i + 1) % n]
            
            // Calculate the longitude difference, handling the dateline crossing
            let lonDiff = longitudeDifference(from: current.lng, to: next.lng)
            
            // Check if this edge crosses a meridian that passes through the pole
            // For the South pole, we need to check if the edge crosses below it
            if current.lat > -Double.pi / 2 && next.lat > -Double.pi / 2 {
                // Both points are north of the South pole, so this edge can contribute to winding
                windingNumber += lonDiff / (2 * Double.pi)
            }
        }
        
        // For clockwise ordering, a positive winding number indicates containment
        return abs(windingNumber) > 0.5
    }
    
    /// Calculates the signed longitude difference between two longitude values,
    /// taking into account the spherical nature and dateline crossing.
    /// - Parameters:
    ///   - fromLng: Starting longitude in radians
    ///   - toLng: Ending longitude in radians
    /// - Returns: The signed difference in radians, normalized to [-π, π]
    private static func longitudeDifference(from fromLng: Double, to toLng: Double) -> Double {
        var diff = toLng - fromLng
        
        // Normalize to [-π, π] range
        while diff > Double.pi {
            diff -= 2 * Double.pi
        }
        while diff < -Double.pi {
            diff += 2 * Double.pi
        }
        
        return diff
    }
    
    public static func containsPole(viewport: Viewport) -> Bool {
        let vertices = [viewport.topLeft, viewport.topRight, viewport.bottomRight, viewport.bottomLeft]
        return containsPole(vertices: vertices)
    }
}
