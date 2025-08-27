/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Math helper functions used by the renderer.
*/

import Foundation
import simd

// Generic matrix math utility functions
extension matrix_float4x4 {
    init(rotationAngle: Float, axis: SIMD3<Float>) {
        self.init()
        
        // Note: rotationInAngle is in radians
        let unitAxis = normalize(axis)
        let cos = cosf(rotationAngle)
        let sin = sinf(rotationAngle)
        let cosI = 1 - cos
        let xVal = unitAxis.x, yVal = unitAxis.y, zVal = unitAxis.z
        
        self[0] = vector_float4(cos + xVal * xVal * cosI,
                                yVal * xVal * cosI + zVal * sin,
                                zVal * xVal * cosI - yVal * sin,
                                0)
        self[1] = vector_float4(xVal * yVal * cosI - zVal * sin,
                                cos + yVal * yVal * cosI,
                                zVal * yVal * cosI + xVal * sin,
                                0)
        self[2] = vector_float4(xVal * zVal * cosI + yVal * sin,
                                yVal * zVal * cosI - xVal * sin,
                                cos + zVal * zVal * cosI,
                                0)
        self[3] = vector_float4(0, 0, 0, 1)
    }
    
    init(translationX: Float, translationY: Float, translationZ: Float) {
        self.init(1.0)
        self[3, 0] = translationX
        self[3, 1] = translationY
        self[3, 2] = translationZ
    }
    
    init(fieldOfView: Float, aspectRatio: Float, nearZ: Float, farZ: Float) {
        let yVal = 1 / tan(fieldOfView * 0.5)
        let xVal = yVal / aspectRatio
        let zVal = farZ / (nearZ - farZ)
        
        self.init(diagonal: SIMD4(xVal, yVal, zVal, 0))
        self[2, 3] = -1
        self[3, 2] = zVal * nearZ
    }
}

func radians(fromDegrees degrees: Float) -> Float {
    return (degrees / 180) * .pi
}
