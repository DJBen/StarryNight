/*
 See the LICENSE.txt file for this sample’s licensing information.

 Abstract:
 A platform independent renderer class
 */
import Metal
import MetalKit
import simd
import StarryNight

// Protocol for handling star selection
protocol StarTapDelegate: AnyObject {
    func didSelectStars(_ stars: [Star], fov: Float)
}

#if os(macOS) || targetEnvironment(simulator)
let requiredConstantBufferAlignment = 256
#else
let requiredConstantBufferAlignment = 4
#endif

let uniformsConstantBufferAlignment = max(requiredConstantBufferAlignment, MemoryLayout<Uniforms>.alignment)
// The aligned size of our uniform structure
let alignedUniformsSize = (MemoryLayout<Uniforms>.size & ~(uniformsConstantBufferAlignment - 1)) + uniformsConstantBufferAlignment
let maxBuffersInFlight = 3
let numConstantDataBuffers = 13
let numObjects = 2
let numFloatValues = 100

enum RendererError: Error {
    case badVertexDescriptor
}

class Renderer: NSObject, MTKViewDelegate {

    let starManager: any StarManaging
    public let device: MTLDevice
    let commandQueue: MTLCommandQueue
    
    // Delegate for star tap handling
    weak var starTapDelegate: StarTapDelegate?
    
    // Reference to MetalViewController for debug updates
    weak var metalViewController: MetalViewController?

    var depthTexture: MTLTexture
    var stencilTexture: MTLTexture

    // Sub-renderers
    private let skyboxRenderer: SkyboxRenderer
    private let starRenderer: StarRenderer
    private let constellationBorderRenderer: ConstellationBorderRenderer
    private let h3GridRenderer: H3GridRenderer
    private let crosshairRenderer: CrosshairRenderer
    private let triangleIndicatorRenderer: TriangleIndicatorRenderer

    // Camera system
    public var camera: Camera

    // CAMetalDisplayLink properties
    private var metalDisplayLink: CAMetalDisplayLink?
    private var previousTargetPresentationTimestamp: CFTimeInterval = 0
    var isUsingMetalDisplayLink: Bool {
        return metalDisplayLink != nil
    }

    let inFlightSemaphore = DispatchSemaphore(value: maxBuffersInFlight)
    var projectionMatrix: float4x4 = float4x4()
    var viewMatrix: float4x4 = matrix_identity_float4x4
    var rotation: Float = 0
    var blendMode = BlendMode.transparency
    var transparency: Float = 0.5
    // Time accumulator for star breathing animation (seconds)
    private var starTime: Float = 0.0

    // Selected star for crosshair display
    private var selectedStar: Star?

    init?(
        metalKitView: MTKView,
        starManager: any StarManaging
    ) {
        self.starManager = starManager
        self.device = metalKitView.device!

        guard let queue = self.device.makeCommandQueue() else { return nil }
        self.commandQueue = queue
        metalKitView.colorPixelFormat = MTLPixelFormat.bgra8Unorm_srgb
        metalKitView.sampleCount = 1

        // Initialize camera system
        self.camera = Camera()

        let depthStencilTextures = allocateDepthStencilTextures(device: self.device, metalKitView: metalKitView)
        self.depthTexture = depthStencilTextures.depthTexture
        self.stencilTexture = depthStencilTextures.stencilTexture

        // Initialize sub-renderers
        self.skyboxRenderer = SkyboxRenderer(device: self.device, view: metalKitView)
        self.starRenderer = StarRenderer(device: self.device, view: metalKitView, starManager: starManager)
        self.constellationBorderRenderer = ConstellationBorderRenderer(device: self.device, view: metalKitView, starManager: starManager)
        self.h3GridRenderer = H3GridRenderer(device: self.device, view: metalKitView)
        self.crosshairRenderer = CrosshairRenderer(device: self.device, view: metalKitView)
        self.triangleIndicatorRenderer = TriangleIndicatorRenderer(device: self.device, view: metalKitView)

#if os(macOS) || targetEnvironment(simulator)
        metalKitView.framebufferOnly = false
#endif

        // Sub-renderers already created pipelines and resources

        super.init()

        // Set up camera delegate to receive matrix updates
        self.camera.delegate = self
    }

    deinit {
        stopMetalDisplayLink()
    }

    // MARK: - CAMetalDisplayLink Setup

    func setupMetalDisplayLink(metalLayer: CAMetalLayer) {
        // Create and configure the Metal display link
        metalDisplayLink = CAMetalDisplayLink(metalLayer: metalLayer)
        metalDisplayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 60.0, maximum: 120.0, preferred: 120.0)
        metalDisplayLink?.preferredFrameLatency = 2
        metalDisplayLink?.isPaused = false
        metalDisplayLink?.delegate = self

        startMetalDisplayLink()
    }

    private func startMetalDisplayLink() {
        guard let metalDisplayLink = metalDisplayLink else { return }
        previousTargetPresentationTimestamp = CACurrentMediaTime()
        metalDisplayLink.add(to: .current, forMode: .common)
        metalDisplayLink.isPaused = false
    }

    private func stopMetalDisplayLink() {
        guard let metalDisplayLink = metalDisplayLink else { return }
        metalDisplayLink.remove(from: .current, forMode: .common)
        metalDisplayLink.invalidate()
        self.metalDisplayLink = nil
    }

    // MARK: - Sub-renderer helpers

    func prepareEncoder(renderEncoder: MTLRenderCommandEncoder, label: String) {
        renderEncoder.label = label
        renderEncoder.setCullMode(.back)
        renderEncoder.setFrontFacing(.counterClockwise)
    }

    // MARK: - Grid visibility control

    public var isH3GridVisible: Bool {
        get { h3GridRenderer.isVisible }
        set { h3GridRenderer.isVisible = newValue }
    }

    public var areConstellationBordersVisible: Bool {
        get { constellationBorderRenderer.isVisible }
        set { constellationBorderRenderer.isVisible = newValue }
    }
    
    // MARK: - Debug viewport control
    
    public var isDebugViewportVisible: Bool = false
    
    // MARK: - Star selection
    
    public func setSelectedStar(_ star: Star?) {
        selectedStar = star
    }
    
    // MARK: - Triangle indicator hit testing
    
    public func handleTriangleIndicatorTap(at location: CGPoint, in viewSize: CGSize) -> Bool {
        // Check if tap hits triangle indicator
        if triangleIndicatorRenderer.hitTest(tapLocation: location, viewSize: viewSize) {
            // Pan camera to selected star
            if let star = selectedStar {
                let coord_norm = simd_normalize(SIMD3<Float>(star.coordinate))
                // Convert to spherical coordinates:
                // not sure why, I need to negate them to make the result correct
                // Declination: arcsin(z)
                let decRadians = -asin(coord_norm.z)
                // Right Ascension: atan2(y, x), converted to hours (0-24)
                let raRadians = -atan2(coord_norm.y, coord_norm.x)
                camera.startPanAnimationTo(ra: raRadians, dec: decRadians)
                return true
            }
        }
        return false
    }

    func draw(in view: MTKView) {
        // This method is kept for compatibility but actual rendering
        // happens through CAMetalDisplayLink when available
        if !isUsingMetalDisplayLink {
            renderFrame(with: nil, view: view)
        }
    }

    func renderFrame(with update: CAMetalDisplayLink.Update?, view: MTKView? = nil) {
        /// Per frame updates here

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)
        
        // Update triangle indicator for MTKView rendering path
        if let view = view {
            let viewSize = view.drawableSize
            triangleIndicatorRenderer.updateSelectedStar(
                selectedStar,
                projectionMatrix: projectionMatrix,
                viewMatrix: viewMatrix,
                viewSize: viewSize
            )
        }

        if let commandBuffer = commandQueue.makeCommandBuffer() {

            let semaphore = inFlightSemaphore
            commandBuffer.addCompletedHandler { _ in
                semaphore.signal()
            }

            var drawable: CAMetalDrawable?
            var renderPassDescriptor: MTLRenderPassDescriptor?

            // Get drawable from CAMetalDisplayLink or MTKView
            if let update = update {
                drawable = update.drawable
                renderPassDescriptor = MTLRenderPassDescriptor()
                renderPassDescriptor!.colorAttachments[0].texture = drawable!.texture
                renderPassDescriptor!.colorAttachments[0].loadAction = .clear
                renderPassDescriptor!.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
                renderPassDescriptor!.colorAttachments[0].storeAction = .store
            } else if let view = view {
                drawable = view.currentDrawable
                renderPassDescriptor = view.currentRenderPassDescriptor
            }

            guard let finalDrawable = drawable,
                    let finalRenderPassDescriptor = renderPassDescriptor else {
                return
            }

            /// Configure depth and stencil attachments
            finalRenderPassDescriptor.depthAttachment.texture = self.depthTexture
            finalRenderPassDescriptor.stencilAttachment.texture = self.stencilTexture
            finalRenderPassDescriptor.depthAttachment.loadAction = .clear
            finalRenderPassDescriptor.depthAttachment.clearDepth = 1.0
#if os(macOS) || targetEnvironment(simulator)
            finalRenderPassDescriptor.configureStoreActionForAttachments(.store)
#endif

            if let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: finalRenderPassDescriptor) {

                /// Primary pass rendering - render objects first
                prepareEncoder(renderEncoder: renderEncoder, label: "Primary Render Encoder")

                // Draw skybox, grid, then stars
                skyboxRenderer.draw(renderEncoder: renderEncoder, projectionMatrix: projectionMatrix, viewMatrix: viewMatrix)
                h3GridRenderer.draw(renderEncoder: renderEncoder, projectionMatrix: projectionMatrix, viewMatrix: viewMatrix, currentFOVDegrees: camera.currentFOV)
                starRenderer.draw(
                    renderEncoder: renderEncoder,
                    projectionMatrix: projectionMatrix,
                    viewMatrix: viewMatrix,
                    time: starTime,
                    fov: camera.currentFOV
                )
                constellationBorderRenderer.draw(
                    renderEncoder: renderEncoder,
                    projectionMatrix: projectionMatrix,
                    viewMatrix: viewMatrix
                )
                
                // Draw crosshair for selected star (on top)
                crosshairRenderer.draw(
                    renderEncoder: renderEncoder,
                    projectionMatrix: projectionMatrix,
                    viewMatrix: viewMatrix,
                    fov: camera.currentFOV
                )
                
                // Draw triangle indicator for out-of-viewport selected stars (on top of everything)
                triangleIndicatorRenderer.draw(
                    renderEncoder: renderEncoder,
                    projectionMatrix: projectionMatrix,
                    viewMatrix: viewMatrix,
                    fov: camera.currentFOV
                )

                renderEncoder.endEncoding()

                commandBuffer.present(finalDrawable)
            }
            commandBuffer.commit()
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        /// Respond to drawable size or orientation changes here

        let aspect = Float(size.width) / Float(size.height)
        projectionMatrix = float4x4(fieldOfView: radians(fromDegrees: 65),
                                    aspectRatio: aspect, nearZ: 0.1, farZ: 100.0)

        // Update camera's aspect ratio
        camera.updateAspectRatio(aspect)
        h3GridRenderer.drawableSizeWillChange(to: size)
        constellationBorderRenderer.drawableSizeWillChange(to: size)
    }
}

// MARK: - Camera Delegate

extension Renderer: CameraDelegate {
    func camera(_ camera: Camera, didUpdateViewMatrix viewMatrix: matrix_float4x4) {
        self.viewMatrix = viewMatrix
        metalViewController?.updateDebugInfoIfNeeded()
    }

    func camera(_ camera: Camera, didUpdateProjectionMatrix projectionMatrix: matrix_float4x4) {
        self.projectionMatrix = projectionMatrix
        metalViewController?.updateDebugInfoIfNeeded()
    }

    func camera(_ camera: Camera, didUpdateFOV fov: Float) {
        // Optionally handle FOV changes for UI updates or other purposes
        print("Camera FOV updated to: \(fov)°")
        metalViewController?.updateDebugInfoIfNeeded()
    }
    
    func camera(_ camera: Camera, didTapAt location: CGPoint, in viewSize: CGSize) {
        // First check if tap hits triangle indicator
        if handleTriangleIndicatorTap(at: location, in: viewSize) {
            return  // Triangle indicator handled the tap
        }
        
        // Convert screen coordinates to world ray direction
        let worldRay = camera.screenToWorldRay(screenPoint: location, viewSize: viewSize)
        
        // Transform from world coordinates to star coordinate system
        let starCoordinate = starToWorldTransform.inverse * worldRay
        let coordinate = SIMD3<Double>(Double(starCoordinate.x), Double(starCoordinate.y), Double(starCoordinate.z))
        
        // Determine maximum magnitude cutoff based on current FOV and resolution levels shown
        let fov = camera.currentFOV

        let maximumMagnitude: Double? = {
            if fov >= fovThresholdDegrees(forRes: 0) {
                // Only resolution 0 (brightest stars) shown
                return 6.1
            } else if fov >= fovThresholdDegrees(forRes: 1) {
                // Resolution 0 and 1 shown
                return 8.1
            } else {
                // All resolutions shown
                return nil
            }
        }()

        // Calculate max angular distance as 1/50 of FOV in radians
        let maxAngularDistance = Double(fov * Float.pi / 180.0) / 50.0

        // Find the closest star
        let closeStars = starManager.closeStars(
            around: coordinate,
            maximumAngularDistance: maxAngularDistance,
            maximumMagnitude: maximumMagnitude,
        )

        // Notify delegate (MetalViewController) about the selected star
        starTapDelegate?.didSelectStars(closeStars, fov: fov)
    }
}

// MARK: - CAMetalDisplayLink Delegate

extension Renderer: CAMetalDisplayLinkDelegate {
    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        let deltaTime = update.targetPresentationTimestamp - previousTargetPresentationTimestamp
        previousTargetPresentationTimestamp = update.targetPresentationTimestamp

        // Update camera momentum with precise timing
        camera.updateMomentumWithDeltaTime(Float(deltaTime))
        // Advance star animation time
        starTime += Float(deltaTime)
        
        // Update crosshair animation
        crosshairRenderer.updateSelectedStar(selectedStar, deltaTime: Float(deltaTime))
        
        // Update triangle indicator with current matrices and viewport
        let viewSize = CGSize(
            width: CGFloat(update.drawable.texture.width),
            height: CGFloat(update.drawable.texture.height)
        )
        triangleIndicatorRenderer.updateSelectedStar(
            selectedStar,
            projectionMatrix: projectionMatrix,
            viewMatrix: viewMatrix,
            viewSize: viewSize
        )

        // Render the frame
        renderFrame(with: update)
    }
}

#if os(macOS) || targetEnvironment(simulator)
extension MTLRenderPassDescriptor {
    func configureLoadActionForAttachments(_ loadAction: MTLLoadAction) {
        // We need to ensure that the previous render encoder's attachments are loaded
        self.colorAttachments[0].loadAction = loadAction
        self.depthAttachment.loadAction = loadAction
        self.stencilAttachment.loadAction = loadAction
    }

    func configureStoreActionForAttachments(_ storeAction: MTLStoreAction) {
        // We need to ensure that the current render encoder's attachments are stored for the next encoder to load
        self.colorAttachments[0].storeAction = storeAction
        self.depthAttachment.storeAction = storeAction
        self.stencilAttachment.storeAction = storeAction
    }

}
#endif
