import UIKit
import RealityKit
import ARKit
import Combine

class PlanetariumViewController: UIViewController {
    private var arView: ARView!
    private var sceneAnchor: AnchorEntity?
    private var cameraController: PlanetariumCameraController!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Initialize camera controller
        cameraController = PlanetariumCameraController()
        cameraController.delegate = self
    
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
        
        // Configure environment
        arView.environment.background = .color(.black)
        
        // Set up camera controller
        cameraController.setupCamera(in: arView)
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

// MARK: - PlanetariumCameraControllerDelegate

extension PlanetariumViewController: PlanetariumCameraControllerDelegate {
    func cameraController(_ controller: PlanetariumCameraController, didUpdateViewport corners: [(latitude: Float, longitude: Float)]) {
        // Handle viewport updates here
        // For example, you could use this to update star visibility or culling
        // This is where you'd integrate with your star management system
    }
}
