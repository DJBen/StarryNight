/*
 See the LICENSE.txt file for this sample’s licensing information.

 Abstract:
 Implementation of the view controller.
 */

#if os(macOS)
import Cocoa
typealias PlatformViewController = NSViewController
#else
import UIKit
typealias PlatformViewController = UIViewController
#endif
import MetalKit
import StarryNight
import Ch3

class MetalViewController: PlatformViewController, StarTapDelegate
{
    
    // MARK: - UserDefaults Keys
    private struct UserDefaultsKeys {
        static let isH3GridVisible = "MetalViewController.isH3GridVisible"
        static let areConstellationBordersVisible = "MetalViewController.areConstellationBordersVisible"
        static let areConstellationLinesVisible = "MetalViewController.areConstellationLinesVisible"
        static let isDebugViewportVisible = "MetalViewController.isDebugViewportVisible"
        static let isDebugFormatRadians = "MetalViewController.isDebugFormatRadians"
    }

    private let starManager: StarManaging
    var renderer: Renderer!
    var mtkView: MTKView!
    
    // Star selection UI
    private var selectedStar: Star?
    private var starToolbar: UIToolbar!
    private var starNameButton: UIBarButtonItem!
    
    // Debug viewport UI
    private var debugInfoLabel: UILabel!
    private var isDebugFormatRadians = true {
        didSet {
            UserDefaults.standard.set(isDebugFormatRadians, forKey: UserDefaultsKeys.isDebugFormatRadians)
        }
    }

    init(starManager: any StarManaging) {
        self.starManager = starManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Restore persisted settings
        restorePersistedSettings()

        // Add Reset button to navigation bar
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: "Reset",
            style: .plain,
            target: self,
            action: #selector(resetCamera)
        )

        // Add Options button to navigation bar (right)
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Options",
            style: .plain,
            target: self,
            action: #selector(showOptions)
        )

        // Create MTKView programmatically
        mtkView = MTKView(frame: view.bounds)
        mtkView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mtkView)
        
        // Create star toolbar
        setupStarToolbar()
        
        // Create debug info label
        setupDebugInfoLabel()

        // Set up MTKView constraints
        NSLayoutConstraint.activate([
            mtkView.topAnchor.constraint(equalTo: view.topAnchor),
            mtkView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mtkView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mtkView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Select the device to render with.  We choose the default device
        guard let defaultDevice = MTLCreateSystemDefaultDevice() else {
            print("Metal is not supported")
            return
        }

        mtkView.device = defaultDevice
#if os(iOS) || os(tvOS)
        mtkView.backgroundColor = UIColor.black
#endif

        guard let newRenderer = Renderer(metalKitView: mtkView, starManager: starManager) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        mtkView.delegate = renderer

        // Set up camera gestures
        renderer.camera.setupGestures(for: mtkView)
        
        // Set up star tap delegation
        renderer.starTapDelegate = self
        
        // Set up debug viewport reference
        renderer.metalViewController = self
        
        // Apply persisted settings to renderer
        applyPersistedSettingsToRenderer()

        // Set up Metal display link (iOS 17+)
        guard let metalLayer = mtkView.layer as? CAMetalLayer else {
            fatalError("MTKView layer must be CAMetalLayer for iOS 17+ CAMetalDisplayLink support")
        }

        renderer.setupMetalDisplayLink(metalLayer: metalLayer)
        // Disable MTKView's internal rendering loop since we're using CAMetalDisplayLink
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = true
    }
    
    private func setupStarToolbar() {
        starToolbar = UIToolbar()
        starToolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(starToolbar)
        
        // Create star name button (initially hidden)
        starNameButton = UIBarButtonItem(
            title: "",
            style: .plain,
            target: self,
            action: #selector(showSelectedStarInfo)
        )
        starNameButton.isEnabled = false
        
        // Create flexible spaces for centering
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        // Set toolbar items
        starToolbar.setItems([flexibleSpace, starNameButton, flexibleSpace], animated: false)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            starToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            starToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            starToolbar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            starToolbar.heightAnchor.constraint(equalToConstant: 44)
        ])
        
        // Initially hide the toolbar
        starToolbar.isHidden = true
    }
    
    private func setupDebugInfoLabel() {
        // Create a container view for padding
        let containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.black.withAlphaComponent(0.7)
        containerView.layer.cornerRadius = 8
        containerView.clipsToBounds = true
        view.addSubview(containerView)
        
        debugInfoLabel = UILabel()
        debugInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        debugInfoLabel.textColor = .white
        debugInfoLabel.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        debugInfoLabel.numberOfLines = 0
        debugInfoLabel.textAlignment = .left
        containerView.addSubview(debugInfoLabel)
        
        // Set up constraints for container
        NSLayoutConstraint.activate([
            containerView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            containerView.bottomAnchor.constraint(equalTo: starToolbar.topAnchor, constant: -8),
            containerView.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16)
        ])
        
        // Set up constraints for debug label with padding
        NSLayoutConstraint.activate([
            debugInfoLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 8),
            debugInfoLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 8),
            debugInfoLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -8),
            debugInfoLabel.bottomAnchor.constraint(equalTo: containerView.bottomAnchor, constant: -8)
        ])
        
        // Add tap gesture to toggle format
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(toggleDebugFormat))
        containerView.addGestureRecognizer(tapGesture)
        containerView.isUserInteractionEnabled = true
        
        // Initially hide the container
        containerView.isHidden = true
        
        // Store reference to container for hiding/showing
        debugInfoLabel.superview?.isHidden = true
        
    }

    @objc private func resetCamera() {
        renderer?.camera.resetToDefault()
        // Clear star selection when resetting camera
        updateSelectedStar(nil)
    }
    
    @objc private func showSelectedStarInfo() {
        guard let star = selectedStar else { return }
        showStarInfoAlert(for: star)
    }
    
    @objc private func toggleDebugFormat() {
        isDebugFormatRadians.toggle()
        updateDebugInfo()
    }
    
    private func updateSelectedStar(_ star: Star?) {
        let star = star?.withInfo(starManager: starManager)
        selectedStar = star
        
        // Update the renderer with the selected star for crosshair display
        renderer?.setSelectedStar(star)

        if let star = star {
            // Show toolbar with star name
            var displayName: String
            if let bayerFlamsteedDesignation = star.info?.bayerFlamsteedDesignation, let properName = star.info?.properName {
                displayName = String(
                    format: NSLocalizedString(
                        "%@ (%@)",
                        comment: "Bayer flamsteed designation plus proper name"
                    ),
                    bayerFlamsteedDesignation,
                    properName
                )
            } else {
                displayName = star.info?.displayName ?? "Unknown star"
            }
            starNameButton.title = displayName
            starNameButton.isEnabled = true
            starToolbar.isHidden = false
        } else {
            // Hide toolbar
            starNameButton.title = ""
            starNameButton.isEnabled = false
            starToolbar.isHidden = true
        }
    }

    @objc private func showOptions() {
        #if os(iOS) || os(tvOS)
        let isGridOn = renderer?.isH3GridVisible ?? true
        let isDebugOn = renderer?.isDebugViewportVisible ?? false
        let areBordersVisible = renderer?.areConstellationBordersVisible ?? false
        let areLinesVisible = renderer?.areConstellationLinesVisible ?? false
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        
        let gridToggleTitle = isGridOn ? "Hide H3 Grid" : "Show H3 Grid"
        sheet.addAction(UIAlertAction(title: gridToggleTitle, style: .default, handler: { [weak self] _ in
            guard let self = self, let renderer = self.renderer else { return }
            renderer.isH3GridVisible.toggle()
            // Persist the setting
            UserDefaults.standard.set(renderer.isH3GridVisible, forKey: UserDefaultsKeys.isH3GridVisible)
        }))

        let linesToggleTitle = areLinesVisible ? "Hide Constellation Lines" : "Show Constellation Lines"
        sheet.addAction(UIAlertAction(title: linesToggleTitle, style: .default, handler: { [weak self] _ in
            guard let self = self, let renderer = self.renderer else { return }
            renderer.areConstellationLinesVisible.toggle()
            UserDefaults.standard.set(renderer.areConstellationLinesVisible, forKey: UserDefaultsKeys.areConstellationLinesVisible)
        }))

        let bordersToggleTitle = areBordersVisible ? "Hide Constellation Borders" : "Show Constellation Borders"
        sheet.addAction(UIAlertAction(title: bordersToggleTitle, style: .default, handler: { [weak self] _ in
            guard let self = self, let renderer = self.renderer else { return }
            renderer.areConstellationBordersVisible.toggle()
            UserDefaults.standard.set(renderer.areConstellationBordersVisible, forKey: UserDefaultsKeys.areConstellationBordersVisible)
        }))
        
        let debugToggleTitle = isDebugOn ? "Hide Debug Viewport" : "Show Debug Viewport"
        sheet.addAction(UIAlertAction(title: debugToggleTitle, style: .default, handler: { [weak self] _ in
            guard let self = self, let renderer = self.renderer else { return }
            renderer.isDebugViewportVisible.toggle()
            self.updateDebugViewportVisibility()
            // Persist the setting
            UserDefaults.standard.set(renderer.isDebugViewportVisible, forKey: UserDefaultsKeys.isDebugViewportVisible)
        }))
        
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))

        // iPad popover anchor
        if let pop = sheet.popoverPresentationController, let barButton = navigationItem.rightBarButtonItem {
            pop.barButtonItem = barButton
        } else {
            sheet.modalPresentationStyle = .overFullScreen
        }
        present(sheet, animated: true)
        #endif
    }
    
    // MARK: - StarTapDelegate
    
    func didSelectStars(_ stars: [Star], fov: Float) {
        let starToSelect: Star?
        if stars.contains(where: { $0.id == selectedStar?.id }) {
            starToSelect = stars.first { $0.id != selectedStar?.id }
        } else if let firstCandidate = stars.first {
            starToSelect = firstCandidate
        } else {
            starToSelect = nil
        }
        updateSelectedStar(starToSelect)
    }
    
    private func showStarInfoAlert(for star: Star) {
        #if os(iOS) || os(tvOS)
        let alert = UIAlertController(title: "Star Information", message: nil, preferredStyle: .alert)
        
        // Build star information text
        var infoText = ""
        
        // Display name (proper name, Bayer/Flamsteed, or catalog ID)
        if let displayName = star.info?.displayName {
            infoText += "Name: \(displayName)\n"
        }
        
        // Magnitude
        infoText += String(format: "Magnitude: %.2f\n", star.magnitude)
        
        // Right Ascension and Declination
        let raDec = coordinatesToRaDec(star.coordinate)
        infoText += "RA: \(formatRA(raDec.ra))\n"
        infoText += "Dec: \(formatDec(raDec.dec))\n"
        
        // Spectral class
        if let spectralClass = star.spectralClass {
            infoText += "Spectral Class: \(spectralClass)\n"
        }
        
        // Additional detailed information if available
        if let info = star.info {
            // Absolute magnitude
            if let absMag = info.absoluteMagnitude {
                infoText += String(format: "Absolute Magnitude: %.2f\n", absMag)
            }
            
            // Constellation
            if let constellation = info.constellation {
                infoText += "Constellation: \(constellation.localizedName)\n"
            }
            
            // Catalog IDs
            var catalogIds: [String] = []
            if let hip = info.hipIdString { catalogIds.append(hip) }
            if let hd = info.hdIdString { catalogIds.append(hd) }
            if let hr = info.hrIdString { catalogIds.append(hr) }
            if !catalogIds.isEmpty {
                infoText += "Catalog IDs: \(catalogIds.joined(separator: ", "))\n"
            }
            
            // Variable star information
            if info.isVariable {
                infoText += "Variable Star"
                if let designation = info.variableDesignation {
                    infoText += " (\(designation))"
                }
                infoText += "\n"
                
                if let minMag = info.variableMin, let maxMag = info.variableMax {
                    infoText += String(format: "Magnitude Range: %.2f - %.2f\n", maxMag, minMag)
                }
            }
            
            // Spectral type (more detailed than spectral class)
            if let spectralType = info.spectralType, spectralType != star.spectralClass {
                infoText += "Spectral Type: \(spectralType)\n"
            }
        }
        
        // Remove trailing newline
        if infoText.hasSuffix("\n") {
            infoText = String(infoText.dropLast())
        }
        
        alert.message = infoText
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        
        present(alert, animated: true)
        #endif
    }
    
    // MARK: - Coordinate Conversion Helpers
    
    private func coordinatesToRaDec(_ coordinate: SIMD3<Double>) -> (ra: Double, dec: Double) {
        let coord_norm = simd_normalize(coordinate)
        // Convert to spherical coordinates
        // Declination: arcsin(z)
        let decRadians = asin(coord_norm.z)
        let decDegrees = decRadians * 180.0 / .pi
        
        // Right Ascension: atan2(y, x), converted to hours (0-24)
        let raRadians = atan2(coord_norm.y, coord_norm.x)
        var raHours = raRadians * 12.0 / .pi // Convert radians to hours (24h = 2π radians)
        
        // Ensure RA is in range 0-24 hours
        if raHours < 0 {
            raHours += 24.0
        }
        
        return (ra: raHours, dec: decDegrees)
    }
    
    private func formatRA(_ raHours: Double, showDecimalSeconds: Bool = true) -> String {
        let hours = Int(raHours)
        let minutesFloat = (raHours - Double(hours)) * 60.0
        let minutes = Int(minutesFloat)
        let seconds = (minutesFloat - Double(minutes)) * 60.0
        
        if showDecimalSeconds {
            return String(format: "%02dh %02dm %04.1fs", hours, minutes, seconds)
        } else {
            return String(format: "%02dh %02dm %02ds", hours, minutes, Int(seconds.rounded()))
        }
    }
    
    private func formatDec(_ decDegrees: Double, showDecimalSeconds: Bool = true) -> String {
        let sign = decDegrees >= 0 ? "+" : "-"
        let absDecDegrees = abs(decDegrees)
        let degrees = Int(absDecDegrees)
        let minutesFloat = (absDecDegrees - Double(degrees)) * 60.0
        let minutes = Int(minutesFloat)
        let seconds = (minutesFloat - Double(minutes)) * 60.0
        
        if showDecimalSeconds {
            return String(format: "%@%02lld° %02lld' %04.1lf\"", sign, degrees, minutes, seconds)
        } else {
            return String(format: "%@%02lld° %02lld' %02lld\"", sign, degrees, minutes, Int(seconds.rounded()))
        }
    }
    
    // MARK: - Debug Viewport Methods
    
    private func updateDebugViewportVisibility() {
        guard let renderer = renderer else { return }
        let shouldShow = renderer.isDebugViewportVisible
        debugInfoLabel.superview?.isHidden = !shouldShow
        
        if shouldShow {
            updateDebugInfo()
        }
    }
    
    private func updateDebugInfo() {
        guard let renderer = renderer, renderer.isDebugViewportVisible else {
            debugInfoLabel.superview?.isHidden = true
            return
        }
        
        let viewSize = mtkView.bounds.size
        let cornerRays = renderer.camera.getFrustumCornerRays(viewSize: viewSize)
        
        // Convert rays to lat/lng
        var debugText = isDebugFormatRadians ? "Viewport (RA/Dec rad)\n" : "Viewport (RA/Dec)\n"
        let cornerNames = ["Top-Left:\t", "Top-Right:\t", "Bottom-Left:", "Bottom-Right:"]

        for (index, ray) in cornerRays.enumerated() {
            let latLng = rayToLatLng(ray)
            let formattedCoords = formatCoordinatesForDebug(latLng.lat, latLng.lng)
            debugText += String(format: "%@\t%@\n", cornerNames[index], formattedCoords)
        }
        
        // Get center coordinates
        let centerPoint = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let centerRay = renderer.camera.screenToWorldRay(screenPoint: centerPoint, viewSize: viewSize)
        let centerLatLng = rayToLatLng(centerRay)
        let centerFormatted = formatCoordinatesForDebug(centerLatLng.lat, centerLatLng.lng)
        debugText += String(format: "Center:\t\t\t%@\n", centerFormatted)

        // Check if poles are visible using H3Utils
        let cornerLatLngs = cornerRays.map { ray -> LatLng in
            let latLng = rayToLatLng(ray)
            return LatLng(lat: Double(latLng.lat), lng: Double(latLng.lng))
        }
        let isPoleVisible = H3Utils.containsPole(vertices: cornerLatLngs)
        debugText += String(format: "\nFOV: %.1f°", renderer.camera.currentFOV)
        debugText += String(format: "\nPole Visible: %@", isPoleVisible ? "Yes" : "No")
        
        debugInfoLabel.text = debugText
    }
    
    private func rayToLatLng(_ ray: SIMD3<Float>) -> (lat: Float, lng: Float) {
        let normalizedRay = normalize(starToWorldTransform.inverse * ray)
        
        // Convert to spherical coordinates
        // Latitude: arcsin(z) in radians
        let latRadians = asin(normalizedRay.z)
        
        // Longitude: atan2(y, x) in radians
        let lngRadians = atan2(normalizedRay.y, normalizedRay.x)
        
        return (lat: latRadians, lng: lngRadians)
    }
    
    private func formatCoordinatesForDebug(_ latRad: Float, _ lngRad: Float) -> String {
        if isDebugFormatRadians {
            return String(format: "%.3f,\t%.3f", lngRad, latRad)
        } else {
            // Convert to RA/Dec format
            let decDegrees = Double(latRad * 180.0 / .pi)
            var raHours = Double(lngRad * 12.0 / .pi) // Convert radians to hours
            
            // Ensure RA is in range 0-24 hours
            if raHours < 0 {
                raHours += 24.0
            }
            
            let raFormatted = formatRA(raHours, showDecimalSeconds: false)
            let decFormatted = formatDec(decDegrees, showDecimalSeconds: false)
            
            return "\(raFormatted), \(decFormatted)"
        }
    }
    

    
    // MARK: - Public Methods for Renderer
    
    public func updateDebugInfoIfNeeded() {
        if renderer?.isDebugViewportVisible == true {
            updateDebugInfo()
        }
    }
    
    // MARK: - Settings Persistence
    
    private func restorePersistedSettings() {
        // Restore debug format setting (default to radians if not set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.isDebugFormatRadians) != nil {
            isDebugFormatRadians = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isDebugFormatRadians)
        } else {
            // Set default and persist it
            isDebugFormatRadians = true
            UserDefaults.standard.set(true, forKey: UserDefaultsKeys.isDebugFormatRadians)
        }
    }
    
    private func applyPersistedSettingsToRenderer() {
        guard let renderer = renderer else { return }
        
        // Restore H3 Grid visibility (default to false if not set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.isH3GridVisible) != nil {
            renderer.isH3GridVisible = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isH3GridVisible)
        } else {
            // Set default and persist it
            renderer.isH3GridVisible = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isH3GridVisible)
        }

        // Restore constellation border visibility (default to false if not set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.areConstellationBordersVisible) != nil {
            renderer.areConstellationBordersVisible = UserDefaults.standard.bool(forKey: UserDefaultsKeys.areConstellationBordersVisible)
        } else {
            renderer.areConstellationBordersVisible = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.areConstellationBordersVisible)
        }

        // Restore constellation line visibility (default to false if not set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.areConstellationLinesVisible) != nil {
            renderer.areConstellationLinesVisible = UserDefaults.standard.bool(forKey: UserDefaultsKeys.areConstellationLinesVisible)
        } else {
            renderer.areConstellationLinesVisible = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.areConstellationLinesVisible)
        }

        // Restore Debug Viewport visibility (default to false if not set)
        if UserDefaults.standard.object(forKey: UserDefaultsKeys.isDebugViewportVisible) != nil {
            renderer.isDebugViewportVisible = UserDefaults.standard.bool(forKey: UserDefaultsKeys.isDebugViewportVisible)
        } else {
            // Set default and persist it
            renderer.isDebugViewportVisible = false
            UserDefaults.standard.set(false, forKey: UserDefaultsKeys.isDebugViewportVisible)
        }
        
        // Apply debug viewport visibility to UI
        updateDebugViewportVisibility()
    }
}
