// swift-tools-version:6.1
import PackageDescription

let package = Package(
    name: "StarryNight",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "StarryNight",
            targets: ["StarryNight"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.15.0"),
        .package(url: "https://github.com/DJBen/Ch3.git", from: "3.6.0-fix"),
        .package(url: "https://github.com/DJBen/SatelliteKit.git", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "StarryNight",
            dependencies: [
                "SatelliteKit",
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Ch3", package: "Ch3")
            ],
            path: "Sources",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "StarryNightTests",
            dependencies: ["StarryNight"],
            path: "Tests"
        )
    ]
)
