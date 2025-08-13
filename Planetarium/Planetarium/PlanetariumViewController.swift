import UIKit
import RealityKit
import ARKit
import Combine

class PlanetariumViewController: UIViewController {
    private var arView: ARView!
    private var cancellables = Set<AnyCancellable>()
    private var azimuth: Float = 0      // Horizontal rotation (longitude) -π to π
    private var altitude: Float = 0     // Vertical rotation (latitude) -π/2 to π/2
    private var sceneAnchor: AnchorEntity?
    private var cameraEntity: Entity?
    
    // Momentum properties
    private var azimuthVelocity: Float = 0
    private var altitudeVelocity: Float = 0
    private var isMomentumActive: Bool = false
    private var lastPanTime: CFTimeInterval = 0
    
    // Zoom properties
    private var currentFOV: Float = 90.0  // Start at minimum zoom (widest view)
    private let minFOV: Float = 2.0       // Maximum zoom (narrowest view)
    private let maxFOV: Float = 90.0      // Minimum zoom (widest view)

    override func viewDidLoad() {
        super.viewDidLoad()
    
        // Configure the ARView
        setupARView()
        
        // Load and display the Scene.usdz
        Task { @MainActor in
            try await loadScene()
        }
    }
    
    override func loadView() {
        arView = ARView(frame: .zero)
        self.view = arView
    }
    
    private func setupARView() {
        // Disable AR features and use it as a 3D viewer
        arView.automaticallyConfigureSession = false
        
        // Set camera position at origin with non-AR mode
        arView.cameraMode = .nonAR
                
        arView.scene.subscribe(to: SceneEvents.Update.self) {
            [unowned self] in self.updateScene(on: $0)
        }.store(in: &cancellables)
        
        // Create an entity to hold the camera component
        let cameraEntity = Entity()
        var component = PerspectiveCameraComponent()
        component.fieldOfViewInDegrees = currentFOV
        // Create an orthographic camera component and add it to the camera entity
        cameraEntity.components.set(component)
        
        // Store reference to camera entity
        self.cameraEntity = cameraEntity
        
        // Add camera to scene
        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
        
        // Configure environment
        arView.environment.background = .color(.black)
        
        // Add pan gesture for rotation (but not translation)
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        arView.addGestureRecognizer(panGesture)
        
        // Add pinch gesture for zooming
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)
        
        // Add tap gesture to stop momentum
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)
    }
    
    private func loadScene() async throws {
        // Load the Scene.usdz file
        guard let sceneURL = Bundle.main.url(forResource: "Scene", withExtension: "usdz") else {
            print("Could not find Scene.usdz in bundle")
            return
        }
        
        // Load the scene asynchronously
        let entity = try await Entity(contentsOf: sceneURL, withName: nil)
        
        // Add the loaded scene to the anchor at origin
        let anchor = AnchorEntity(world: [0, 0, 0])
        anchor.addChild(entity)
        
        // Add directional markers for debugging
        addDirectionalMarkers(to: anchor)
        
        self.arView.scene.addAnchor(anchor)
        self.sceneAnchor = anchor
    }
    
    private func addDirectionalMarkers(to anchor: AnchorEntity) {
        let markerRadius: Float = 5.0  // Distance from center
        
        // Create simple sphere markers
        let markerMesh = MeshResource.generateSphere(radius: 0.1)
        
        // North (positive Y) - Blue
        let northMaterial = SimpleMaterial(color: .blue, isMetallic: false)
        let northMarker = ModelEntity(mesh: markerMesh, materials: [northMaterial])
        northMarker.position = SIMD3<Float>(0, markerRadius, 0)
        anchor.addChild(northMarker)
        
        // South (negative Y) - Red
        let southMaterial = SimpleMaterial(color: .red, isMetallic: false)
        let southMarker = ModelEntity(mesh: markerMesh, materials: [southMaterial])
        southMarker.position = SIMD3<Float>(0, -markerRadius, 0)
        anchor.addChild(southMarker)
        
        // East (positive X) - Green
        let eastMaterial = SimpleMaterial(color: .green, isMetallic: false)
        let eastMarker = ModelEntity(mesh: markerMesh, materials: [eastMaterial])
        eastMarker.position = SIMD3<Float>(markerRadius, 0, 0)
        anchor.addChild(eastMarker)
        
        // West (negative X) - Yellow
        let westMaterial = SimpleMaterial(color: .yellow, isMetallic: false)
        let westMarker = ModelEntity(mesh: markerMesh, materials: [westMaterial])
        westMarker.position = SIMD3<Float>(-markerRadius, 0, 0)
        anchor.addChild(westMarker)
        
        // Zenith (positive Z) - White
        let zenithMaterial = SimpleMaterial(color: .white, isMetallic: false)
        let zenithMarker = ModelEntity(mesh: markerMesh, materials: [zenithMaterial])
        zenithMarker.position = SIMD3<Float>(0, 0, markerRadius)
        anchor.addChild(zenithMarker)
        
        // Nadir (negative Z) - Black with emissive
        let nadirMaterial = SimpleMaterial(color: .black, isMetallic: false)
        let nadirMarker = ModelEntity(mesh: markerMesh, materials: [nadirMaterial])
        nadirMarker.position = SIMD3<Float>(0, 0, -markerRadius)
        anchor.addChild(nadirMarker)
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {        
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
    
    /// Calculate the camera's four vertices in the world space, converted to lat lon.
    private func calculateCameraViewportVertices() {
        guard let cameraEntity = cameraEntity,
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
        
        // Debug output
        print("Camera viewport corners (lat, lon):")
        for (index, corner) in latLonCorners.enumerated() {
            let cornerName = ["Top-left", "Top-right", "Bottom-left", "Bottom-right"][index]
            print("  \(cornerName): (\(corner.latitude)°, \(corner.longitude)°)")
        }
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return .allButUpsideDown
        } else {
            return .all
        }
    }
}
