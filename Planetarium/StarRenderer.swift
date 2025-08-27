//
//  StarRenderer.swift
//  Planetarium
//
//  Created by GitHub Copilot on 8/17/25.
//

import Foundation
import RealityKit
import Metal
import UIKit
import simd
import StarryNight

struct StarVertex {
    let position: SIMD3<Float>
    let magnitude: Float
    let spectralColor: SIMD3<Float>
}

class StarRenderer {
    private var stars: [Star] = []
    private var starPointCloudEntity: ModelEntity?
    private let sphereRadius: Float = 10.0 // Distance from camera center
    
    // Configuration for scalability
    private var maximumMagnitude: Double = 6.0 // Only show stars up to this magnitude
    private var pointSize: Float = 1.0 // Scale factor for point sizes
    
    func loadStars(from starManager: any StarManaging, maximumMagnitude: Double = 6.0) {
        self.maximumMagnitude = maximumMagnitude
        
        // Load stars with magnitude filter for better performance
        self.stars = starManager.brightestStars()
        print("Loaded \(stars.count) stars for rendering (magnitude ≤ \(maximumMagnitude))")
    }
    
    func updatePointSize(_ size: Float) {
        self.pointSize = size
        // In a real implementation, you could update the material uniforms here
    }
    
    func createStarPointCloudEntity() throws -> ModelEntity {
        // For scalability, create individual small spheres positioned as a point cloud
        // This is more compatible with RealityKit than trying to use actual point primitives
        
        var childEntities: [ModelEntity] = []
        
        for star in stars {
            // Normalize the coordinate to unit sphere (virtual globe surface)
            let coord = simd_normalize(star.coordinate)
            let convertedCoord = SIMD3<Float>(
                x: Float(coord.x),
                y: Float(coord.z),
                z: Float(-coord.y)
            )

            // Scale to desired distance from camera
            let position = convertedCoord * sphereRadius

            // Calculate star size based on magnitude (smaller for dimmer stars)
            let normalizedMagnitude = max(0, min(1, (6.0 - star.magnitude) / 8.0))
            let starSize = Float(0.01 + normalizedMagnitude * 0.04) // Very small spheres
            
            // Create a tiny sphere for the star
            let mesh = MeshResource.generateSphere(radius: starSize)
            
            // Get spectral color and create material
            let spectralColor = getSpectralColor(for: star)
            let brightness = Float(max(0.3, min(1.0, (6.0 - star.magnitude) / 6.0)))
            
            // Create unlit material with star color
            var material = UnlitMaterial()
            material.color = .init(tint: UIColor(
                red: CGFloat(spectralColor.x),
                green: CGFloat(spectralColor.y),
                blue: CGFloat(spectralColor.z),
                alpha: CGFloat(brightness)
            ))
            
            // Create model entity
            let starEntity = ModelEntity(mesh: mesh, materials: [material])
            starEntity.position = position
            
            childEntities.append(starEntity)
        }
        
        // Create a parent entity to hold all stars
        let parentEntity = ModelEntity()
        for child in childEntities {
            parentEntity.addChild(child)
        }
        
        self.starPointCloudEntity = parentEntity
        return parentEntity
    }
    
    
    private func getSpectralColor(for star: Star) -> SIMD3<Float> {
        // Map spectral class to color
        guard let spectralClass = star.spectralClass?.uppercased() else {
            return SIMD3<Float>(1.0, 1.0, 1.0) // Default white
        }
        
        let firstChar = String(spectralClass.prefix(1))
        
        switch firstChar {
        case "O":
            return SIMD3<Float>(0.6, 0.7, 1.0) // Blue
        case "B":
            return SIMD3<Float>(0.7, 0.8, 1.0) // Blue-white
        case "A":
            return SIMD3<Float>(0.9, 0.9, 1.0) // White
        case "F":
            return SIMD3<Float>(1.0, 1.0, 0.9) // Yellow-white
        case "G":
            return SIMD3<Float>(1.0, 1.0, 0.7) // Yellow (like our Sun)
        case "K":
            return SIMD3<Float>(1.0, 0.8, 0.6) // Orange
        case "M":
            return SIMD3<Float>(1.0, 0.6, 0.4) // Red
        default:
            return SIMD3<Float>(1.0, 1.0, 1.0) // Default white
        }
    }
    
    // MARK: - Scalability Features
    
    /// Reload stars with a different magnitude limit
    func reloadStars(from starManager: any StarManaging, maximumMagnitude: Double) async {
        await Task.detached { [weak self] in
            self?.loadStars(from: starManager)
        }.value
    }
    
    /// Get current star count for performance monitoring
    func getStarCount() -> Int {
        return stars.count
    }
    
    /// Update the sphere radius (distance from camera)
    func updateSphereRadius(_ radius: Float) {
        // This would require recreating the point cloud entity
        // For now, we'll just update the internal value
        // In a more advanced implementation, we could update vertex buffers dynamically
    }
}
