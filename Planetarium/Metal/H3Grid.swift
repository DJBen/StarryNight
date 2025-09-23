//
//  H3Grid.swift
//  StarryNight
//
//  Utilities to build grid line segments for H3 at resolution 0.
//

import Foundation
import simd
import Ch3

public struct GridLine: Equatable, Hashable, Sendable {
    public let p0: LatLng
    public let p1: LatLng

    public init(p0: LatLng, p1: LatLng) {
        // Canonicalize endpoint ordering so undirected edges are identical
        // Sort by (a.lat, a.lng, b.lat, b.lng) lexicographically
        let ab = (p0.lat, p0.lng, p1.lat, p1.lng)
        let ba = (p1.lat, p1.lng, p0.lat, p0.lng)
        if ab <= ba {
            self.p0 = p0
            self.p1 = p1
        } else {
            self.p0 = p1
            self.p1 = p0
        }
    }
}

/// Build all unique boundary segments for a given set of H3 cells.
/// - Parameters:
///   - cells: The set of H3 cells to generate grid lines for.
/// - Returns: Unique undirected segments covering the cell boundaries in StarryNight's render coordinate space.
public func gridLines(
    forCells cells: [H3Index],
) -> Set<GridLine> {
    var lines: Set<GridLine> = []

    for idx in cells {
        var cellBoundary = CellBoundary()
        // Fetch boundary in radians
        cellToBoundary(idx, &cellBoundary)

        let n = Int(cellBoundary.numVerts)
        guard n >= 3 else { continue }

        // Copy C fixed array (tuple) to Swift array for indexed access
        var verts: [LatLng] = []
        verts.reserveCapacity(n)
        withUnsafePointer(to: &cellBoundary.verts) { tPtr in
            tPtr.withMemoryRebound(to: LatLng.self, capacity: Int(MAX_CELL_BNDRY_VERTS)) { gPtr in
                let buf = UnsafeBufferPointer(start: gPtr, count: n)
                verts.append(contentsOf: buf)
            }
        }

        // Loop edges
        for i in 0..<n {
            let a = verts[i]
            let b = verts[(i+1) % n]

            // Insert canonicalized undirected edge
            lines.insert(GridLine(p0: a, p1: b))
        }
    }

    return lines
}

let edgeLengthTableKm: [Float] = [
    1281.256011,
    483.0568391,
    182.5129565,
    68.97922179,
    26.07175968,
    9.854090990,
    3.724532667,
    1.406475763,
    0.531414010,
    0.200786148,
    0.075863783,
    0.028663897,
    0.010830188,
    0.004092010,
    0.001546100,
    0.000584169
]

/// Compute the FOV threshold in degrees for a given H3 resolution.
/// If current FOV is below this threshold, it means the viewport can fit ~4x the edge length of that resolution.
public func fovThresholdDegrees(forRes res: Int32, multiplier: Float = 3.0) -> Float {
    guard res >= 0 && res < edgeLengthTableKm.count else {
        fatalError("Invalid H3 resolution: must be between 0 and 15")
    }

    let edgeKm = edgeLengthTableKm[Int(res)]
    let circumferenceKm: Float = 40075.017
    let fraction = (multiplier * 2.0 * edgeKm) / circumferenceKm
    return fraction * 360.0
}
