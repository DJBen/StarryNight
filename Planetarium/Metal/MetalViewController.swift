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

class MetalViewController: PlatformViewController
{

    private let starManager: StarManaging
    var renderer: Renderer!
    var mtkView: MTKView!

    init(starManager: any StarManaging) {
        self.starManager = starManager
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

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

        // Set up Metal display link (iOS 17+)
        guard let metalLayer = mtkView.layer as? CAMetalLayer else {
            fatalError("MTKView layer must be CAMetalLayer for iOS 17+ CAMetalDisplayLink support")
        }

        renderer.setupMetalDisplayLink(metalLayer: metalLayer)
        // Disable MTKView's internal rendering loop since we're using CAMetalDisplayLink
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = true
    }

    @objc private func resetCamera() {
        renderer?.camera.resetToDefault()
    }

    @objc private func showOptions() {
        #if os(iOS) || os(tvOS)
        let isGridOn = renderer?.isH3GridVisible ?? true
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        let toggleTitle = isGridOn ? "Hide H3 Grid" : "Show H3 Grid"
        sheet.addAction(UIAlertAction(title: toggleTitle, style: .default, handler: { [weak self] _ in
            guard let self = self, let renderer = self.renderer else { return }
            renderer.isH3GridVisible.toggle()
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
}
