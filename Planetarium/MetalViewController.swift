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

class MetalViewController: PlatformViewController
{

    var renderer: Renderer!
    var mtkView: MTKView!

#if os(iOS)
    var transparencySlider: UISlider!
    var blendMode: UISegmentedControl!
#endif

    override func viewDidLoad() {
        super.viewDidLoad()

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

#if os(iOS)
        setupUIControls()
#endif

        guard let newRenderer = Renderer(metalKitView: mtkView) else {
            print("Renderer cannot be initialized")
            return
        }

        renderer = newRenderer

        renderer.mtkView(mtkView, drawableSizeWillChange: mtkView.drawableSize)
        renderer.blendMode = BlendMode.transparency
        renderer.transparency = 0.5
        
        mtkView.delegate = renderer
    }

#if os(iOS)
    private func setupUIControls() {
        // Create segmented control
        blendMode = UISegmentedControl(items: ["None", "Transparency", "Invert", "Overlay"])
        blendMode.selectedSegmentIndex = 1
        blendMode.translatesAutoresizingMaskIntoConstraints = false
        blendMode.addTarget(self, action: #selector(blendModeChanged(_:)), for: .valueChanged)
        view.addSubview(blendMode)
        
        // Create slider
        transparencySlider = UISlider()
        transparencySlider.minimumValue = 0.0
        transparencySlider.maximumValue = 1.0
        transparencySlider.value = 0.5
        transparencySlider.translatesAutoresizingMaskIntoConstraints = false
        transparencySlider.addTarget(self, action: #selector(transparencyChanged(_:)), for: .valueChanged)
        view.addSubview(transparencySlider)
        
        // Set up constraints
        NSLayoutConstraint.activate([
            blendMode.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            blendMode.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            blendMode.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            
            transparencySlider.topAnchor.constraint(equalTo: blendMode.bottomAnchor, constant: 10),
            transparencySlider.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 50),
            transparencySlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -50)
        ])
    }

    @objc private func blendModeChanged(_ sender: UISegmentedControl) {
        let blendMode = BlendMode(rawValue: sender.selectedSegmentIndex)!
        renderer.blendMode = blendMode
        self.transparencySlider.isHidden = blendMode != BlendMode.transparency
    }
    
    @objc private func transparencyChanged(_ sender: UISlider) {
        renderer.transparency = sender.value
    }
#endif
}
