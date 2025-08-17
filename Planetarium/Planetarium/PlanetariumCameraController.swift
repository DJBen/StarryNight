import UIKit
import RealityKit
import ARKit
import Combine

protocol PlanetariumCameraControllerDelegate: AnyObject {
    func cameraController(_ controller: PlanetariumCameraController, didUpdateViewport corners: [(latitude: Float, longitude: Float)])
}

class PlanetariumCameraController {
    
    // MARK: - Properties
    
    weak var delegate: PlanetariumCameraControllerDelegate?
    
    private weak var arView: ARView?
    private var cameraEntity: Entity?
    private var cancellables = Set<AnyCancellable>()
    
    // Camera rotation state
    private var azimuth: Float = 0      // Horizontal rotation (longitude) -π to π
    private var altitude: Float = 0     // Vertical rotation (latitude) -π/2 to π/2
    
    // Momentum properties
    private var azimuthVelocity: Float = 0
    private var altitudeVelocity: Float = 0
    private var isMomentumActive: Bool = false
    private var lastPanTime: CFTimeInterval = 0
    
    // Zoom properties
    private var currentFOV: Float = 90.0  // Start at minimum zoom (widest view)
    private let minFOV: Float = 2.0       // Maximum zoom (narrowest view)
    private let maxFOV: Float = 90.0      // Minimum zoom (widest view)
    
    // MARK: - Initialization
    
    init() {}
    
    // MARK: - Setup
    
    func setupCamera(in arView: ARView) {
        self.arView = arView
        
        // Create an entity to hold the camera component
        let cameraEntity = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = currentFOV
        cameraEntity.components.set(component)
        
        // Store reference to camera entity
        self.cameraEntity = cameraEntity
        
        // Add camera to scene
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
        
        // Set up gesture recognizers
        setupGestureRecognizers()
        
        // Subscribe to scene updates
        arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            self?.updateScene(on: event)
        }.store(in: &cancellables)
    }
    
    private func setupGestureRecognizers() {
        guard let arView = arView else { return }
        
        // Add pan gesture for rotation
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(panGesture)
        
        // Add pinch gesture for zooming
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)
        
        // Add tap gesture to stop momentum
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let arView = arView else { return }
        
        let translation = gesture.translation(in: arView)
        let currentTime = CACurrentMediaTime()
        
        // Calculate FOV-adjusted sensitivity to maintain consistent panning speed
        // When FOV is smaller (zoomed in), reduce sensitivity proportionally
        let baseSensitivity: Float = 0.002
        let fovAdjustment = currentFOV / maxFOV  // This gives us a ratio from minFOV/maxFOV to 1.0
        let adjustedSensitivity = baseSensitivity * fovAdjustment
        
        // Convert pan to rotation with FOV-adjusted sensitivity
        let deltaX = Float(translation.x) * adjustedSensitivity
        let deltaY = Float(translation.y) * adjustedSensitivity
        
        switch gesture.state {
        case .began:
            // Stop any existing momentum
            isMomentumActive = false
            lastPanTime = currentTime
            
        case .changed:
            // Calculate time delta for velocity calculation
            let timeDelta = Float(currentTime - lastPanTime)
            
            // Update azimuth (horizontal pan = rotate around Y axis)
            azimuth += deltaX
            
            // Keep azimuth in -π to π range for consistency
            if azimuth > Float.pi {
                azimuth -= 2 * Float.pi
            } else if azimuth < -Float.pi {
                azimuth += 2 * Float.pi
            }
            
            // Update altitude (vertical pan = rotate around X axis)
            altitude += deltaY
            
            // Clamp altitude to prevent flipping over poles
            altitude = max(-Float.pi/2, min(Float.pi/2, altitude))
            
            // Calculate velocities based on change over time
            if timeDelta > 0 {
                azimuthVelocity = deltaX / timeDelta
                altitudeVelocity = deltaY / timeDelta
            }
            
            // Apply rotation
            updateCameraRotation()
            
            lastPanTime = currentTime
            
        case .ended, .cancelled:
            // Start momentum animation if velocity is significant
            let velocityThreshold: Float = 0.1
            if abs(azimuthVelocity) > velocityThreshold || abs(altitudeVelocity) > velocityThreshold {
                isMomentumActive = true
            }
            
        default:
            break
        }
        
        gesture.setTranslation(.zero, in: arView)
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Stop momentum animation if it's running
        isMomentumActive = false
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Stop any existing momentum
            isMomentumActive = false
            
        case .changed:
            // Calculate new FOV based on pinch scale
            // Pinch out (scale > 1) = zoom in = smaller FOV
            // Pinch in (scale < 1) = zoom out = larger FOV
            let scaleFactor = gesture.scale
            let newFOV = currentFOV / Float(scaleFactor)

            // Clamp FOV to valid range
            currentFOV = max(minFOV, min(maxFOV, newFOV))
            
            // Update camera component
            updateCameraFOV()
            
            // Reset gesture scale to avoid accumulation
            gesture.scale = 1.0
            
        case .ended, .cancelled:
            break
            
        default:
            break
        }
    }
    
    // MARK: - Camera Updates
    
    private func updateCameraRotation() {
        guard let cameraEntity = cameraEntity else { return }
        
        // Create camera rotation using standard spherical coordinates
        // Azimuth rotates around Y (up/down) axis
        // Altitude rotates around X (left/right) axis
        
        // Create individual rotations
        let azimuthRotation = simd_quatf(angle: azimuth, axis: SIMD3<Float>(0, 1, 0))
        let altitudeRotation = simd_quatf(angle: altitude, axis: SIMD3<Float>(1, 0, 0))
        
        // Apply rotations in order: azimuth first, then altitude
        // This ensures the camera always stays level with latitude lines
        let cameraRotation = azimuthRotation * altitudeRotation
        
        // Apply rotation to the camera entity
        cameraEntity.transform.rotation = cameraRotation
    }
    
    private func updateCameraFOV() {
        guard let cameraEntity = cameraEntity else { return }
        
        // Update the camera component's field of view
        var component = cameraEntity.components[PerspectiveCameraComponent.self] ?? PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = currentFOV
        cameraEntity.components.set(component)
    }
    
    private func updateMomentum(deltaTime: TimeInterval) {
        guard isMomentumActive else { return }
        
        let damping: Float = 0.9
        let minimumVelocity: Float = 0.01 // Threshold below which we stop the animation
        
        // Use the provided deltaTime from SceneEvents.Update
        let frameDuration = Float(deltaTime)
        
        // Apply velocities to rotation using actual frame duration
        azimuth += azimuthVelocity * frameDuration
        altitude += altitudeVelocity * frameDuration
        
        // Keep azimuth in -π to π range
        if azimuth > Float.pi {
            azimuth -= 2 * Float.pi
        } else if azimuth < -Float.pi {
            azimuth += 2 * Float.pi
        }
        
        // Clamp altitude to prevent flipping over poles
        altitude = max(-Float.pi/2, min(Float.pi/2, altitude))
        
        // Apply damping to velocities
        azimuthVelocity *= damping
        altitudeVelocity *= damping
        
        // Update camera rotation
        updateCameraRotation()
        
        // Stop momentum if velocities are too small
        if abs(azimuthVelocity) < minimumVelocity && abs(altitudeVelocity) < minimumVelocity {
            isMomentumActive = false
        }
    }
    
    func updateScene(on event: SceneEvents.Update) {
        // Update momentum animation using the render loop's deltaTime
        updateMomentum(deltaTime: event.deltaTime)
        
        // Calculate camera viewport vertices
        calculateCameraViewportVertices()
    }
    
    // MARK: - Viewport Calculations
    
    /// Calculate the camera's four vertices in the world space, converted to lat lon.
    private func calculateCameraViewportVertices() {
        guard let arView = arView,
              let cameraEntity = cameraEntity,
              let cameraComponent = cameraEntity.components[PerspectiveCameraComponent.self] else {
            return
        }
        
        // Get camera's field of view
        let fovRadians = cameraComponent.fieldOfViewInDegrees * Float.pi / 180.0
        
        // Get viewport aspect ratio
        let viewportSize = arView.bounds.size
        let aspectRatio = Float(viewportSize.width / viewportSize.height)
        
        // Calculate half angles for viewport corners
        let halfVerticalFOV = fovRadians / 2.0
        let halfHorizontalFOV = atan(tan(halfVerticalFOV) * aspectRatio)
        
        // Define the four corners of the viewport in camera space
        // Assuming a distance of 1 unit from camera (on the near plane)
        let distance: Float = 1.0
        
        let corners: [SIMD3<Float>] = [
            // Top-left
            SIMD3<Float>(-tan(halfHorizontalFOV) * distance, tan(halfVerticalFOV) * distance, -distance),
            // Top-right
            SIMD3<Float>(tan(halfHorizontalFOV) * distance, tan(halfVerticalFOV) * distance, -distance),
            // Bottom-left
            SIMD3<Float>(-tan(halfHorizontalFOV) * distance, -tan(halfVerticalFOV) * distance, -distance),
            // Bottom-right
            SIMD3<Float>(tan(halfHorizontalFOV) * distance, -tan(halfVerticalFOV) * distance, -distance)
        ]
        
        // Transform corners from camera space to world space
        let cameraTransform = cameraEntity.transform.matrix
        var worldCorners: [SIMD3<Float>] = []
        
        for corner in corners {
            // Convert to homogeneous coordinates
            let homogeneousCorner = SIMD4<Float>(corner.x, corner.y, corner.z, 1.0)
            
            // Transform to world space
            let worldCorner = cameraTransform * homogeneousCorner
            
            // Normalize the direction vector (ignore w component for direction)
            let direction = normalize(SIMD3<Float>(worldCorner.x, worldCorner.y, worldCorner.z))
            
            worldCorners.append(direction)
        }
        
        // Convert world space directions to latitude/longitude
        var latLonCorners: [(latitude: Float, longitude: Float)] = []
        
        for direction in worldCorners {
            // Convert Cartesian coordinates to spherical coordinates
            // Assuming Y is up, X is east, Z is north (adjust based on your coordinate system)
            let latitude = asin(direction.y) // Y component gives latitude
            let longitude = atan2(direction.x, direction.z) // X and Z give longitude
            
            // Convert from radians to degrees
            let latDegrees = latitude * 180.0 / Float.pi
            let lonDegrees = longitude * 180.0 / Float.pi
            
            latLonCorners.append((latitude: latDegrees, longitude: lonDegrees))
        }
        
        // Notify delegate about viewport changes
        delegate?.cameraController(self, didUpdateViewport: latLonCorners)
        
        // Debug output (consider removing or making optional)
        print("Camera viewport corners (lat, lon):")
        for (index, corner) in latLonCorners.enumerated() {
            let cornerName = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"][index]
            print("  \(cornerName): (\(corner.latitude)°, \(corner.longitude)°)")
        }
    }
    
    // MARK: - Public Interface
    
    /// Get current camera rotation in degrees
    var cameraRotation: (azimuth: Float, altitude: Float) {
        return (azimuth * 180.0 / Float.pi, altitude * 180.0 / Float.pi)
    }
    
    /// Get current field of view in degrees
    var fieldOfView: Float {
        return currentFOV
    }
    
    /// Programmatically set camera rotation
    func setCameraRotation(azimuth: Float, altitude: Float) {
        self.azimuth = azimuth * Float.pi / 180.0
        self.altitude = max(-Float.pi/2, min(Float.pi/2, altitude * Float.pi / 180.0))
        
        // Stop any ongoing momentum
        isMomentumActive = false
        azimuthVelocity = 0
        altitudeVelocity = 0
        
        updateCameraRotation()
    }
    
    /// Programmatically set field of view
    func setFieldOfView(_ fov: Float) {
        currentFOV = max(minFOV, min(maxFOV, fov))
        updateCameraFOV()
    }
    
    /// Stop any ongoing momentum animation
    func stopMomentum() {
        isMomentumActive = false
        azimuthVelocity = 0
        altitudeVelocity = 0
    }
    
    // MARK: - Cleanup
    
    deinit {
        cancellables.removeAll()
    }
}
