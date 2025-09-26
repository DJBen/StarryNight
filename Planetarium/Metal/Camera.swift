/*
 Camera implementation for Metal-based planetarium.
 
 Abstract:
 A camera system that stays at the origin (0,0,0) and provides spherical rotation
 and field-of-view control through touch gestures.
 */

import UIKit
import Metal
import MetalKit
import simd

protocol CameraDelegate: AnyObject {
    func camera(_ camera: Camera, didUpdateViewMatrix viewMatrix: matrix_float4x4)
    func camera(_ camera: Camera, didUpdateProjectionMatrix projectionMatrix: matrix_float4x4)
    func camera(_ camera: Camera, didUpdateFOV fov: Float)
    func camera(_ camera: Camera, didTapAt location: CGPoint, in viewSize: CGSize)
}

/// Animation state for smooth panning to specific coordinates
private struct PanAnimation {
    let startRA: Float
    let startDec: Float
    let endRA: Float
    let endDec: Float
    let deltaRA: Float  // Shortest angular distance considering wrapping
    let deltaDec: Float
    let duration: Float
    var elapsedTime: Float = 0
    
    init(from: (ra: Float, dec: Float), to: (ra: Float, dec: Float), duration: Float = 1.5) {
        self.startRA = from.ra
        self.startDec = from.dec
        self.endRA = to.ra
        self.endDec = to.dec
        self.duration = duration
        
        // Calculate shortest angular distance for RA considering wrapping
        var deltaRA = to.ra - from.ra
        if deltaRA > Float.pi {
            deltaRA -= 2 * Float.pi
        } else if deltaRA < -Float.pi {
            deltaRA += 2 * Float.pi
        }
        self.deltaRA = deltaRA
        self.deltaDec = to.dec - from.dec
    }
    
    /// Get interpolated position at current time using smooth easing
    func getCurrentPosition() -> (ra: Float, dec: Float) {
        let t = min(elapsedTime / duration, 1.0)
        
        // Use smooth easing function (ease-in-out cubic)
        let easedT = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        
        // Linear interpolation with easing
        let currentRA = startRA + deltaRA * easedT
        let currentDec = startDec + deltaDec * easedT
        
        // Normalize RA to [0, 2π] range
        var normalizedRA = currentRA
        while normalizedRA < 0 {
            normalizedRA += 2 * Float.pi
        }
        while normalizedRA >= 2 * Float.pi {
            normalizedRA -= 2 * Float.pi
        }
        
        return (ra: normalizedRA, dec: currentDec)
    }
    
    /// Check if animation is complete
    var isComplete: Bool {
        return elapsedTime >= duration
    }
}

class Camera {
    
    // MARK: - Properties
    
    weak var delegate: CameraDelegate?
    
    // Camera rotation state (spherical coordinates)
    private var ra: Float = 0      // Horizontal rotation (longitude) 0 to 2π
    private var dec: Float = 0     // Vertical rotation (latitude) -π/2 to π/2
    
    // Momentum properties for smooth pan animations
    private var raVelocity: Float = 0
    private var decVelocity: Float = 0
    private var isMomentumActive: Bool = false
    
    // Pan animation state
    private var panAnimation: PanAnimation?
    
    // Field of view properties
    private(set) var currentFOV: Float = 90.0
    private let minFOV: Float = 5       // Maximum zoom (narrowest view)
    private let maxFOV: Float = 105.0   // Minimum zoom (widest view)

    // Projection matrix properties
    private var aspectRatio: Float = 1.0
    private let nearPlane: Float = 0.1
    private let farPlane: Float = 1000.0
    
    // Current matrices
    private var viewMatrix: matrix_float4x4 = matrix_identity_float4x4
    private var projectionMatrix: matrix_float4x4 = matrix_identity_float4x4
    
    // MARK: - Initialization
    
    init() {
        updateViewMatrix()
        updateProjectionMatrix()
    }
    
    deinit {
        // No cleanup needed since CAMetalDisplayLink is managed by Renderer
    }
    
    // MARK: - Setup
    
    func setupGestures(for view: UIView) {
        // Add pan gesture for rotation
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        view.addGestureRecognizer(panGesture)
        
        // Add pinch gesture for zooming
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)
        
        // Add tap gesture to stop momentum
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        view.addGestureRecognizer(tapGesture)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: gesture.view)
        let velocity = gesture.velocity(in: gesture.view)
        
        // Calculate FOV-adjusted sensitivity to maintain consistent panning speed
        // When FOV is smaller (zoomed in), reduce sensitivity proportionally
        let baseSensitivity: Float = 0.0025
        let fovAdjustment = currentFOV / maxFOV
        let adjustedSensitivity = baseSensitivity * fovAdjustment
        
        // Convert pan to rotation with FOV-adjusted sensitivity
        let deltaX = -Float(translation.x) * adjustedSensitivity
        let deltaY = -Float(translation.y) * adjustedSensitivity
        
        switch gesture.state {
        case .began:
            // Stop any existing animations
            stopAllAnimations()
            
        case .changed:
            // Update ra (horizontal pan = rotate around Y axis)
            ra += deltaX
            
            // Keep ra in 0 to 2π range for consistency
            while ra < 0 {
                ra += 2 * Float.pi
            }
            while ra >= 2 * Float.pi {
                ra -= 2 * Float.pi
            }
            
            // Update dec (vertical pan = rotate around X axis)
            dec += deltaY
            
            // Clamp dec to prevent flipping over poles
            dec = max(-Float.pi/2, min(Float.pi/2, dec))
            
            // Calculate velocities from gesture velocity with FOV adjustment
            raVelocity = -Float(velocity.x) * adjustedSensitivity
            decVelocity = -Float(velocity.y) * adjustedSensitivity
            
            // Update view matrix
            updateViewMatrix()
            
        case .cancelled:
            startMomentum()
        case .ended:
            startMomentum()
            
        default:
            break
        }
        
        gesture.setTranslation(.zero, in: gesture.view)
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        switch gesture.state {
        case .began:
            // Stop any existing animations
            stopAllAnimations()
            
        case .changed:
            // Calculate new FOV based on pinch scale
            // Pinch out (scale > 1) = zoom in = smaller FOV
            // Pinch in (scale < 1) = zoom out = larger FOV
            let scaleFactor = gesture.scale
            let newFOV = currentFOV / Float(scaleFactor)
            
            // Clamp FOV to valid range
            currentFOV = max(minFOV, min(maxFOV, newFOV))
            
            // Update projection matrix
            updateProjectionMatrix()
            
            // Reset gesture scale to avoid accumulation
            gesture.scale = 1.0
            
        case .ended, .cancelled:
            break
            
        default:
            break
        }
    }
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Notify delegate about tap location for star detection
        if let view = gesture.view, !isMomentumActive && panAnimation == nil {
            let tapLocation = gesture.location(in: view)
            delegate?.camera(self, didTapAt: tapLocation, in: view.bounds.size)
        } else {
            // Stop any active animations if they're running
            stopAllAnimations()
        }
    }
    
    // MARK: - Matrix Updates
    
    private func updateViewMatrix() {
        // Create view matrix using spherical coordinates
        // Camera stays at origin, but we rotate the world around it
        
        // Create individual rotations
        let raRotation = matrix_float4x4(rotationAngle: ra, axis: SIMD3<Float>(0, 1, 0))
        let decRotation = matrix_float4x4(rotationAngle: dec, axis: SIMD3<Float>(1, 0, 0))
        
        // Combine rotations: apply ra first, then dec
        viewMatrix = decRotation * raRotation
        
        // Notify delegate
        delegate?.camera(self, didUpdateViewMatrix: viewMatrix)
    }
    
    private func updateProjectionMatrix() {
        // Create perspective projection matrix
        projectionMatrix = matrix_float4x4(
            fieldOfView: radians(fromDegrees: currentFOV),
            aspectRatio: aspectRatio,
            nearZ: nearPlane,
            farZ: farPlane
        )
        
        // Notify delegate
        delegate?.camera(self, didUpdateProjectionMatrix: projectionMatrix)
        delegate?.camera(self, didUpdateFOV: currentFOV)
    }
    
    // MARK: - Momentum Animation
    
    private func startMomentum() {
        isMomentumActive = true
        // Momentum animation is handled by the renderer's CAMetalDisplayLink
    }
    
    private func stopMomentum() {
        isMomentumActive = false
        raVelocity = 0
        decVelocity = 0
    }
    
    private func stopAllAnimations() {
        stopMomentum()
        panAnimation = nil
    }
    
    // Public method for external momentum updates from renderer's display link
    func updateMomentumWithDeltaTime(_ deltaTime: Float) {
        // Handle pan animation first (higher priority)
        if var animation = panAnimation {
            animation.elapsedTime += deltaTime
            
            let position = animation.getCurrentPosition()
            ra = position.ra
            dec = position.dec
            
            // Clamp dec to prevent flipping over poles
            dec = max(-Float.pi/2, min(Float.pi/2, dec))
            
            updateViewMatrix()
            
            if animation.isComplete {
                panAnimation = nil
            } else {
                panAnimation = animation
            }
            
            return
        }
        
        // Handle momentum animation if no pan animation is active
        guard isMomentumActive else { return }
        
        let damping: Float = 0.925
        let minimumVelocity: Float = 0.02
        
        // Apply velocities to rotation using provided delta time
        ra += raVelocity * deltaTime
        dec += decVelocity * deltaTime
        
        // Keep ra in 0 to 2π range
        while ra < 0 {
            ra += 2 * Float.pi
        }
        while ra >= 2 * Float.pi {
            ra -= 2 * Float.pi
        }
        
        // Clamp dec to prevent flipping over poles
        dec = max(-Float.pi/2, min(Float.pi/2, dec))
        
        // Apply damping to velocities
        raVelocity *= damping
        decVelocity *= damping
        
        // Update view matrix
        updateViewMatrix()
        
        // Stop momentum if velocities are too small
        if abs(raVelocity) < minimumVelocity && abs(decVelocity) < minimumVelocity {
            stopMomentum()
        }
    }
    
    // MARK: - Public Interface
    
    /// Update aspect ratio (call when view size changes)
    func updateAspectRatio(_ aspectRatio: Float) {
        self.aspectRatio = aspectRatio
        updateProjectionMatrix()
    }

    /// Check if any animation is currently active
    var isAnimating: Bool {
        return isMomentumActive || panAnimation != nil
    }
    
    /// Get current view matrix
    var currentViewMatrix: matrix_float4x4 {
        return viewMatrix
    }
    
    /// Get current projection matrix
    var currentProjectionMatrix: matrix_float4x4 {
        return projectionMatrix
    }

    /// Reset camera to default position
    func resetToDefault() {
        ra = 0
        dec = 0
        currentFOV = 90.0
        
        stopAllAnimations()
        updateViewMatrix()
        updateProjectionMatrix()
    }
    
    /// Start smooth animation to target rotation using the new animation system
    func startPanAnimationTo(ra targetRa: Float, dec targetDec: Float) {
        // Stop any existing animations
        stopAllAnimations()
        
        // Clamp target declination to valid range
        let clampedTargetDec = max(-Float.pi/2, min(Float.pi/2, targetDec))
        
        // Create new pan animation
        panAnimation = PanAnimation(
            from: (ra: ra, dec: dec),
            to: (ra: targetRa, dec: clampedTargetDec),
            duration: 1.5
        )
    }
    
    // MARK: - Coordinate Conversion Utilities
    
    /// Convert screen coordinates to world ray direction
    func screenToWorldRay(screenPoint: CGPoint, viewSize: CGSize) -> SIMD3<Float> {
        // Convert screen coordinates to normalized device coordinates (-1 to 1)
        let x = Float((screenPoint.x / viewSize.width) * 2.0 - 1.0)
        let y = Float(1.0 - (screenPoint.y / viewSize.height) * 2.0)
        
        // Create ray in clip space
        let rayClip = SIMD4<Float>(x, y, -1.0, 1.0)
        
        // Transform to eye space
        let invProjection = projectionMatrix.inverse
        let rayEye = invProjection * rayClip
        let rayEyeNormalized = SIMD4<Float>(rayEye.x, rayEye.y, -1.0, 0.0)
        
        // Transform to world space
        let invView = viewMatrix.inverse
        let rayWorld4 = invView * rayEyeNormalized
        let rayWorld = SIMD3<Float>(rayWorld4.x, rayWorld4.y, rayWorld4.z)
        
        return normalize(rayWorld)
    }
    
    /// Get the four corner rays of the current camera frustum
    func getFrustumCornerRays(viewSize: CGSize) -> [SIMD3<Float>] {
        let corners = [
            CGPoint(x: 0, y: 0),                           // Top-left
            CGPoint(x: viewSize.width, y: 0),              // Top-right
            CGPoint(x: 0, y: viewSize.height),             // Bottom-left
            CGPoint(x: viewSize.width, y: viewSize.height) // Bottom-right
        ]
        
        return corners.map { screenToWorldRay(screenPoint: $0, viewSize: viewSize) }
    }
}
