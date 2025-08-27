import RealityKit
import simd
import Metal

class CelestialGridRenderer {
    
    // MARK: - Properties
    
    private var currentGridEntity: ModelEntity?
    private var currentStepDegrees: Float = 0
    private let sphereRadius: Float = 5.0  // Match the marker radius in PlanetariumViewController
    
    // Grid density levels based on FOV
    private struct GridLevel {
        let minFOV: Float
        let maxFOV: Float
        let raDegrees: Float
        let decDegrees: Float
    }
    
    private let gridLevels: [GridLevel] = [
        GridLevel(minFOV: 0, maxFOV: 3, raDegrees: 0.625, decDegrees: 0.625),
        GridLevel(minFOV: 3, maxFOV: 15, raDegrees: 2.5, decDegrees: 2.5),
        GridLevel(minFOV: 15, maxFOV: 45, raDegrees: 7.5, decDegrees: 7.5),
        GridLevel(minFOV: 45, maxFOV: 90, raDegrees: 15, decDegrees: 15)
    ]
    
    // MARK: - Public Methods
    
    func updateGrid(for fov: Float, anchor: AnchorEntity) {
        let targetLevel = getGridLevel(for: fov)
        let newStepRA = targetLevel.raDegrees
        let newStepDec = targetLevel.decDegrees
        
        // Only regenerate if the step size has changed significantly
        if abs(newStepRA - currentStepDegrees) > 0.1 {
            removeCurrentGrid(from: anchor)
            let newGridEntity = createGridEntity(raStepDegrees: newStepRA, decStepDegrees: newStepDec)
            anchor.addChild(newGridEntity)
            currentGridEntity = newGridEntity
            currentStepDegrees = newStepRA
        }
    }
    
    func removeCurrentGrid(from anchor: AnchorEntity) {
        if let currentGrid = currentGridEntity {
            currentGrid.removeFromParent()
            currentGridEntity = nil
        }
    }
    
    // MARK: - Private Methods
    
    private func getGridLevel(for fov: Float) -> GridLevel {
        for level in gridLevels {
            if fov >= level.minFOV && fov < level.maxFOV {
                return level
            }
        }
        return gridLevels.last! // Fallback to the most zoomed out level
    }
    
    private func createGridEntity(raStepDegrees: Float, decStepDegrees: Float) -> ModelEntity {
        // Create individual line entities and combine them
        let gridAnchor = Entity()
        
        // Generate Declination (DEC) Lines - circles parallel to celestial equator
        generateDeclinationLineEntities(
            stepDegrees: decStepDegrees,
            parent: gridAnchor
        )
        
        // Generate Right Ascension (RA) Lines - great circles through poles
        generateRightAscensionLineEntities(
            stepDegrees: raStepDegrees,
            parent: gridAnchor
        )
        
        // Create a container ModelEntity
        let containerEntity = ModelEntity()
        containerEntity.addChild(gridAnchor)
        
        return containerEntity
    }
    
    private func generateDeclinationLineEntities(stepDegrees: Float, parent: Entity) {
        // Generate DEC lines from -75° to +75° (avoiding poles where lines converge)
        let decRange = stride(from: -75.0, through: 75.0, by: Double(stepDegrees))
        
        for decDegrees in decRange {
            let decRadians = Float(decDegrees) * Float.pi / 180.0
            var positions: [SIMD3<Float>] = []
            
            // Generate circle of points at this declination
            let raSteps = 144 // 2.5-degree steps around the circle for smooth lines
            for i in 0...raSteps {
                let raRadians = Float(i) * 2.0 * Float.pi / Float(raSteps)
                
                // Spherical to Cartesian conversion
                let x = cos(raRadians) * cos(decRadians) * sphereRadius
                let y = sin(decRadians) * sphereRadius
                let z = sin(raRadians) * cos(decRadians) * sphereRadius
                
                positions.append(SIMD3<Float>(x, y, z))
            }
            
            // Create line entity from positions
            if let lineEntity = createLineEntity(from: positions) {
                parent.addChild(lineEntity)
            }
        }
    }
    
    private func generateRightAscensionLineEntities(stepDegrees: Float, parent: Entity) {
        // Generate RA lines based on stepDegrees
        let raRange = stride(from: 0.0, to: 360.0, by: Double(stepDegrees))
        
        for raDegrees in raRange {
            let raRadians = Float(raDegrees) * Float.pi / 180.0
            var positions: [SIMD3<Float>] = []
            
            // Generate points from south pole to north pole
            let decSteps = 72 // 2.5-degree steps from -90 to +90
            for i in 0...decSteps {
                let decRadians = (Float(i) / Float(decSteps)) * Float.pi - Float.pi / 2.0 // -90° to +90°
                
                // Spherical to Cartesian conversion
                let x = cos(raRadians) * cos(decRadians) * sphereRadius
                let y = sin(decRadians) * sphereRadius
                let z = sin(raRadians) * cos(decRadians) * sphereRadius
                
                positions.append(SIMD3<Float>(x, y, z))
            }
            
            // Create line entity from positions
            if let lineEntity = createLineEntity(from: positions) {
                parent.addChild(lineEntity)
            }
        }
    }
    
    private func createLineEntity(from positions: [SIMD3<Float>]) -> ModelEntity? {
        guard positions.count >= 2 else { return nil }
        
        // Create a thin tube connecting all the points
        var meshDescriptor = MeshDescriptor(name: "gridLine")
        var allPositions: [SIMD3<Float>] = []
        var allIndices: [UInt32] = []
        
        let lineRadius: Float = 0.002 // Very thin line
        let segments = 8 // Number of segments around the tube circumference
        
        // Generate tube geometry
        for i in 0..<(positions.count - 1) {
            let start = positions[i]
            let end = positions[i + 1]
            
            // Create a small tube segment between start and end
            let direction = normalize(end - start)
            
            // Find perpendicular vectors
            let up = abs(direction.y) < 0.9 ? SIMD3<Float>(0, 1, 0) : SIMD3<Float>(1, 0, 0)
            let right = normalize(cross(direction, up))
            let actualUp = cross(right, direction)
            
            let baseIndex = UInt32(allPositions.count)
            
            // Create vertices for this segment
            for j in 0...segments {
                let angle = Float(j) * 2.0 * Float.pi / Float(segments)
                let offset = right * cos(angle) * lineRadius + actualUp * sin(angle) * lineRadius
                
                // Start and end vertices
                allPositions.append(start + offset)
                allPositions.append(end + offset)
            }
            
            // Create triangle indices for this segment
            for j in 0..<segments {
                let j1 = j
                let j2 = (j + 1) % (segments + 1)
                
                // Two triangles per quad
                let v1 = baseIndex + UInt32(j1 * 2)     // start of current segment
                let v2 = baseIndex + UInt32(j1 * 2 + 1) // end of current segment  
                let v3 = baseIndex + UInt32(j2 * 2)     // start of next segment
                let v4 = baseIndex + UInt32(j2 * 2 + 1) // end of next segment
                
                // First triangle
                allIndices.append(v1)
                allIndices.append(v2)
                allIndices.append(v3)
                
                // Second triangle
                allIndices.append(v2)
                allIndices.append(v4)
                allIndices.append(v3)
            }
        }
        
        meshDescriptor.positions = MeshBuffers.Positions(allPositions)
        meshDescriptor.primitives = .triangles(allIndices)
        
        do {
            let mesh = try MeshResource.generate(from: [meshDescriptor])
            let material = UnlitMaterial(color: .cyan.withAlphaComponent(0.3))
            return ModelEntity(mesh: mesh, materials: [material])
        } catch {
            print("Failed to create line entity: \(error)")
            return nil
        }
    }
}
