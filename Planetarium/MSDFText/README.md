# MSDFText (Swift Package)

MSDFText is a lightweight Swift package that renders crisp, scalable text in Metal using multi‑channel signed distance fields (MSDF/MTSDF). It provides:

- `MSDFAtlas` for decoding atlas JSON from `msdf-atlas-gen`.
- `MSDFTextMeshBuilder` for Core Text layout and GPU-friendly quad meshes.
- `MSDFTextRenderer` for a ready-to-use Metal pipeline and draw encoding.

For the full workflow (glyph ranges → baking the atlas → app asset setup), see the root README in this repo. This document focuses on using the Swift package directly.

## Installation

Add the local package in Xcode via Swift Package Manager.

- Package name: `MSDFText`
- Library product: `MSDFText`

You can also add it via a local path in another package’s `Package.swift`:

```
.package(path: "../MSDFText")
```

## Inputs and Assets

MSDFText expects the atlas image (PNG or other) and the companion JSON exported by `msdf-atlas-gen`.

- Atlas type: `msdf` or `mtsdf` (recommended).
- Keep `pxrange` consistent between baking and runtime.
- Load the texture as linear (not sRGB). When using `MTKTextureLoader`, typical options are:

```
let atlasTexture = try MTKTextureLoader(device: device).newTexture(
  URL: pngURL,
  options: [
    .SRGB: false,
    .origin: MTKTextureLoader.Origin.topLeft,
    .generateMipmaps: false,
  ]
)
```

Note: If you manage textures via an asset catalog, ensure the texture remains 8-bit normalized RGBA and interpreted as data (not sRGB) to avoid artifacts.

## Quick Start

```
import MetalKit
import CoreText
import MSDFText

// 1) Load atlas metadata and PNG
let jsonURL = Bundle.main.url(forResource: "YourFont_mtsdf", withExtension: "json")!
var atlas = try MSDFAtlas.load(from: jsonURL)

let pngURL = Bundle.main.url(forResource: "YourFont_mtsdf", withExtension: "png")!
let loader = MTKTextureLoader(device: device)
let atlasTexture = try loader.newTexture(URL: pngURL, options: [
  .SRGB: false,
  .origin: MTKTextureLoader.Origin.topLeft,
  .generateMipmaps: false,
])

// 2) Build a mesh for your text
let ctFont = CTFontCreateWithName("SFProDisplay-Regular" as CFString, 20, nil)
let meshBuilder = MSDFTextMeshBuilder(device: device, atlas: atlas, font: ctFont)
let mesh = meshBuilder.buildMesh(
  for: "Hello, MSDF!",
  in: view.bounds.size,
  margin: 16,
  scale: view.contentScaleFactor
)!

// 3) Create the renderer and encode a draw
let renderer = try MSDFTextRenderer(
  device: device,
  pixelFormat: mtkView.colorPixelFormat,
  sampleCount: mtkView.sampleCount,
  atlasPxRange: atlas.atlas.distanceRange
)
renderer.setOrthoProjection(
  width: Float(mtkView.drawableSize.width),
  height: Float(mtkView.drawableSize.height)
)

let style = MSDFTextRenderStyle(textColor: SIMD4<Float>(1, 1, 1, 1))
renderer.encode(
  encoder: renderEncoder,
  mesh: mesh,
  atlasTexture: atlasTexture,
  style: style
)
```

## Custom Shaders and Uniforms (Optional)

MSDFText includes a default vertex/fragment pair in `Sources/MSDFText/Shaders.metal`. You can bring your own shader functions and/or uniform layout.

- Provide a custom `MTLLibrary` and function names at renderer init; or
- Use the overload that accepts a custom `uniformBuffer` and optional `overridePipeline`.

Contract for custom pipelines:
- Uniforms bound at buffer index `2` in both vertex and fragment stages.
- Atlas texture bound at fragment texture index `0`.
- If using `uniformOffset`, ensure 256‑byte alignment.

Example using your own uniforms and pipeline:

```
var uniforms = MyUniforms(
  projectionMatrix: renderer.projectionMatrix,
  modelViewMatrix: renderer.modelViewMatrix,
  unitRange: renderer.unitRange(for: atlasTexture)
)
let buf = device.makeBuffer(bytes: &uniforms, length: MemoryLayout<MyUniforms>.stride)!
renderer.encode(
  encoder: renderEncoder,
  mesh: mesh,
  atlasTexture: atlasTexture,
  uniformBuffer: buf,
  overridePipeline: myPipeline
)
```

## Notes and Tips

- `MSDFTextMeshBuilder` lays out text with Core Text (wrapping, kerning, baseline positioning). The returned `MSDFTextMesh.bounds` is the logical size after margin/scale.
- `MSDFTextRenderer.unitRange(for:)` derives the UV‑space distance range from `atlasPxRange` and the actual texture size; this must match the `-pxrange` used by `msdf-atlas-gen`.
- For asset generation details and best practices, see the root `README.md` (sections: Generating Glyph Ranges, Baking the MTSDF Atlas, Importing Assets Into the App).

