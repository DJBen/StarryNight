import Foundation
import simd
import Ch3

extension LatLng: @retroactive Equatable {
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
        
        let geoCoords = vertices.map { vertex in
            LatLng(lat: vertex.lat * .pi / 180.0, lng: vertex.lng * .pi / 180.0)
        }
        
        // Check for pole containment
        if containsPole(vertices: geoCoords) {
            return cellsForPolarViewport(vertices: geoCoords, resolution: resolution)
        } else {
            return cellsForStandardViewport(vertices: geoCoords, resolution: resolution)
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
        var allCells = Set<H3Index>()
        
        let poleLat = vertices.first!.lat > 0 ? (Double.pi / 2) : (-Double.pi / 2)
        let pole = LatLng(lat: poleLat, lng: 0)
        
        for i in 0..<vertices.count {
            let p1 = vertices[i]
            let p2 = vertices[(i + 1) % vertices.count]
            
            let triangleVerts = [pole, p1, p2]
            
            let geoloop = GeoLoop(numVerts: 3, verts: UnsafeMutablePointer<LatLng>.allocate(capacity: 3))
            for (index, coord) in triangleVerts.enumerated() {
                geoloop.verts[index] = coord
            }
            defer {
                geoloop.verts.deallocate()
            }
            
            var polygon = GeoPolygon(geoloop: geoloop, numHoles: 0, holes: nil)
            let cells = getCells(for: &polygon, resolution: resolution)
            allCells.formUnion(cells)
        }
        
        return Array(allCells)
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
    
    private static func containsPole(vertices: [LatLng]) -> Bool {
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
