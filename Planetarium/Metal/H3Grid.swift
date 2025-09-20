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

/// Build all unique boundary segments for the entire set of H3 cells at resolution 0.
/// - Parameters:
///   - radius: scale factor applied to unit-sphere coordinates to place them in world space (match stars at ~10.0).
/// - Returns: Unique undirected segments covering res0 cell boundaries in StarryNight's render coordinate space.
public func makeGridLines(forRes res: Int32, radius: Float = 10.0) -> [GridLine] {
    // 1) Find all indexes at the given resolution by expanding k-rings from an origin until reaching expected count.
    let origin = withUnsafePointer(to: GeoCoord(lat: 0.0, lon: 0.0)) { geoPtr in
        geoToH3(geoPtr, res)
    }
    let expected = max(0, Int(numHexagons(res)))

    var discovered = Set<UInt64>()
    if origin != 0 {
        discovered.insert(origin)
    }

    // Increase k until we have all, with a hard cap to avoid runaway (res<=3 is small)
    var k: Int32 = 1
    while discovered.count < expected && k <= 30 {
        let maxCount = Int(maxKringSize(k))
        let buffer = UnsafeMutablePointer<H3Index>.allocate(capacity: maxCount)
        defer { buffer.deallocate() }
        kRing(origin, k, buffer)
        for i in 0..<maxCount {
            let idx = buffer[i]
            if idx != 0 { discovered.insert(idx) }
        }
        k += 1
    }

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

    for idx in discovered {
        var gb = GeoBoundary() // zero-initialized; verts capacity = MAX_CELL_BNDRY_VERTS
        // Fetch boundary in radians
        h3ToGeoBoundary(idx, &gb)

        let n = Int(gb.numVerts)
        guard n >= 3 else { continue }

        // Copy C fixed array (tuple) to Swift array for indexed access
        var verts: [GeoCoord] = []
        verts.reserveCapacity(n)
        withUnsafePointer(to: &gb.verts) { tPtr in
            tPtr.withMemoryRebound(to: GeoCoord.self, capacity: Int(MAX_CELL_BNDRY_VERTS)) { gPtr in
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
            let cla = Float(cos(a.lon)); let sla = Float(sin(a.lon))
            var pa = simd_float3(ca * cla, sa, ca * sla)

            let cb = Float(cos(b.lat)); let sb = Float(sin(b.lat))
            let clb = Float(cos(b.lon)); let slb = Float(sin(b.lon))
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

/// Compute the FOV threshold in degrees for a given H3 resolution.
/// If current FOV is below this threshold, it means the viewport can fit ~4x the edge length of that resolution.
public func fovThresholdDegrees(forRes res: Int32) -> Float {
    let edgeKm = Float(edgeLengthKm(res))
    let circumferenceKm: Float = 40075.017
    let fraction = (4.0 * edgeKm) / circumferenceKm
    return fraction * 360.0
}
