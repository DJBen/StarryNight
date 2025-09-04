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
}

class Camera {
    
    // MARK: - Properties
    
    weak var delegate: CameraDelegate?
    
    // Camera rotation state (spherical coordinates)
    private var azimuth: Float = 0      // Horizontal rotation (longitude) -π to π
    private var altitude: Float = 0     // Vertical rotation (latitude) -π/2 to π/2
    
    // Momentum properties for smooth pan animations
    private var azimuthVelocity: Float = 0
    private var altitudeVelocity: Float = 0
    private var isMomentumActive: Bool = false
    
    // Field of view properties
    private var currentFOV: Float = 90.0
    private let minFOV: Float = 5.0       // Maximum zoom (narrowest view)
    private let maxFOV: Float = 120.0     // Minimum zoom (widest view)
    
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
            // Stop any existing momentum
            stopMomentum()
            
        case .changed:
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
            
            // Calculate velocities from gesture velocity with FOV adjustment
            azimuthVelocity = -Float(velocity.x) * adjustedSensitivity
            altitudeVelocity = -Float(velocity.y) * adjustedSensitivity

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
            // Stop any existing momentum
            stopMomentum()
            
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
        // Stop momentum animation if it's running
        stopMomentum()
    }
    
    // MARK: - Matrix Updates
    
    private func updateViewMatrix() {
        // Create view matrix using spherical coordinates
        // Camera stays at origin, but we rotate the world around it
        
        // Create individual rotations
        let azimuthRotation = matrix_float4x4(rotationAngle: azimuth, axis: SIMD3<Float>(0, 1, 0))
        let altitudeRotation = matrix_float4x4(rotationAngle: altitude, axis: SIMD3<Float>(1, 0, 0))
        
        // Combine rotations: apply azimuth first, then altitude
        viewMatrix = altitudeRotation * azimuthRotation
        
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
        azimuthVelocity = 0
        altitudeVelocity = 0
    }
    
    // Public method for external momentum updates from renderer's display link
    func updateMomentumWithDeltaTime(_ deltaTime: Float) {
        guard isMomentumActive else { return }
        
        let damping: Float = 0.925
        let minimumVelocity: Float = 0.02
        
        // Apply velocities to rotation using provided delta time
        azimuth += azimuthVelocity * deltaTime
        altitude += altitudeVelocity * deltaTime
        
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
        
        // Update view matrix
        updateViewMatrix()
        
        // Stop momentum if velocities are too small
        if abs(azimuthVelocity) < minimumVelocity && abs(altitudeVelocity) < minimumVelocity {
            stopMomentum()
        }
    }
    
    // MARK: - Public Interface
    
    /// Update aspect ratio (call when view size changes)
    func updateAspectRatio(_ aspectRatio: Float) {
        self.aspectRatio = aspectRatio
        updateProjectionMatrix()
    }
    
    /// Get current camera rotation in degrees
    var rotation: (azimuth: Float, altitude: Float) {
        return (azimuth * 180.0 / Float.pi, altitude * 180.0 / Float.pi)
    }
    
    /// Get current field of view in degrees
    var fieldOfView: Float {
        return currentFOV
    }
    
    /// Get current view matrix
    var currentViewMatrix: matrix_float4x4 {
        return viewMatrix
    }
    
    /// Get current projection matrix
    var currentProjectionMatrix: matrix_float4x4 {
        return projectionMatrix
    }
    
    /// Programmatically set camera rotation in degrees
    func setRotation(azimuth: Float, altitude: Float) {
        self.azimuth = azimuth * Float.pi / 180.0
        self.altitude = max(-90.0, min(90.0, altitude)) * Float.pi / 180.0
        
        stopMomentum()
        updateViewMatrix()
    }
    
    /// Programmatically set field of view in degrees
    func setFieldOfView(_ fov: Float) {
        currentFOV = max(minFOV, min(maxFOV, fov))
        updateProjectionMatrix()
    }
    
    /// Reset camera to default position
    func resetToDefault() {
        azimuth = 0
        altitude = 0
        currentFOV = 90.0
        
        stopMomentum()
        updateViewMatrix()
        updateProjectionMatrix()
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
