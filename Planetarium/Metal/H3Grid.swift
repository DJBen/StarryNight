//
//  H3Grid.swift
//  StarryNight
//
//  Utilities to build grid line segments for H3 at resolution 0.
//

import Foundation
import simd
import Ch3

public struct GridLine: Sendable {
    public let p0: simd_float3
    public let p1: simd_float3
    public init(p0: simd_float3, p1: simd_float3) {
        self.p0 = p0
        self.p1 = p1
    }
}

/// Build all unique boundary segments for a given set of H3 cells.
/// - Parameters:
///   - cells: The set of H3 cells to generate grid lines for.
///   - radius: scale factor applied to unit-sphere coordinates to place them in world space (match stars at ~10.0).
/// - Returns: Unique undirected segments covering the cell boundaries in StarryNight's render coordinate space.
public func gridLines(
    forCells cells: [H3Index],
    radius: Float = 10.0
) -> [GridLine] {
    // 2) For each cell, fetch its boundary and emit edges, de-duplicated.
    struct Key: Hashable { let a:Int64; let b:Int64 }
    func quantKey(_ p: simd_float3) -> Int64 {
        // Quantize to ~1e-5 to stabilize keys across shared edges
        let q: Float = 1e5
        let xi = Int64((p.x * q).rounded())
        let yi = Int64((p.y * q).rounded())
        let zi = Int64((p.z * q).rounded())
        // Pack into 64-bit with simple mixing
        var h = xi & 0x1FFFFF // 21 bits
        h = (h << 21) | (yi & 0x1FFFFF)
        h = (h << 21) | (zi & 0x1FFFFF)
        return h
    }

    var seen = Set<Key>()
    var lines: [GridLine] = []

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
            // Convert to unit sphere (ECEF): x=cos(lat)cos(lon) y=sin(lat) z=cos(lat)sin(lon)
            let ca = Float(cos(a.lat)); let sa = Float(sin(a.lat))
            let cla = Float(cos(a.lng)); let sla = Float(sin(a.lng))
            var pa = simd_float3(ca * cla, sa, ca * sla)

            let cb = Float(cos(b.lat)); let sb = Float(sin(b.lat))
            let clb = Float(cos(b.lng)); let slb = Float(sin(b.lng))
            var pb = simd_float3(cb * clb, sb, cb * slb)

            // Apply same axis mapping as stars: (x,y,z) -> (y,z,x)
            pa = simd_float3(pa.y, pa.z, pa.x) * radius
            pb = simd_float3(pb.y, pb.z, pb.x) * radius

            // Deduplicate undirected edge
            let qa = quantKey(pa), qb = quantKey(pb)
            let key = qa <= qb ? Key(a: Int64(qa), b: Int64(qb)) : Key(a: Int64(qb), b: Int64(qa))
            if seen.insert(key).inserted {
                lines.append(GridLine(p0: pa, p1: pb))
            }
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
