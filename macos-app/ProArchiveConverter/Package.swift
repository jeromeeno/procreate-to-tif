// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ProArchiveConverter",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "ProcreateBridgeCore",
            targets: ["ProcreateBridgeCore"]
        ),
        .executable(
            name: "ProArchiveConverterApp",
            targets: ["ProArchiveConverterApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "ProcreateBridgeCore"
        ),
        .executableTarget(
            name: "ProArchiveConverterApp",
            dependencies: ["ProcreateBridgeCore"],
            path: "Sources/ProArchiveConverterApp",
            resources: [
                .copy("Resources"),
            ]
        ),
        .testTarget(
            name: "ProcreateBridgeCoreTests",
            dependencies: [
                "ProcreateBridgeCore",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
