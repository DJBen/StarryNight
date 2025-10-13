// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MSDFText",
    platforms: [
        .iOS(.v13),
    ],
    products: [
        .library(name: "MSDFText", targets: ["MSDFText"]),
    ],
    targets: [
        .target(
            name: "MSDFText",
        ),
    ],
)
