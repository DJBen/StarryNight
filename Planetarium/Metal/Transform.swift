import Ch3
import simd

// The coordinate system for rendering stars is different from the one used for H3 grids.
// Star data has the directions such that x is towards RA 0, Dec 0, y towards RA 6 hr., Dec 0, and z towards Dec 90 degrees.
// The renderer uses a right-handed system where Z is up.
// Combine those: swizzle: (x, y, z) -> (x, z, -y), rotation: 90 degrees around Y-axis
let starToWorldTransform = float3x3(
    SIMD3<Float>(0, 0, -1),
    SIMD3<Float>(-1, 0, 0),
    SIMD3<Float>(0, 1, 0)
)

// The directions are such that x is towards RA 0, Dec 0, y towards RA 6 hr., Dec 0, and z towards Dec 90 degrees.
@inlinable func latLngToCelestialCoord(_ latLng: LatLng) -> simd_float3 {
    let cosLat = Float(cos(latLng.lat))
    return simd_float3(
        cosLat * Float(cos(latLng.lng)),
        cosLat * Float(sin(latLng.lng)),
        Float(sin(latLng.lat))
    )
}
