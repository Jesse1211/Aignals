// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Aignals",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AignalsCore", targets: ["AignalsCore"]),
    ],
    targets: [
        .target(
            name: "AignalsCore",
            path: "Sources/AignalsCore"
        ),
        .testTarget(
            name: "AignalsCoreTests",
            dependencies: ["AignalsCore"],
            path: "Tests/AignalsCoreTests"
        ),
        .testTarget(
            name: "AignalsE2ETests",
            dependencies: ["AignalsCore"],
            path: "Tests/AignalsE2ETests",
            resources: [.copy("Resources")]
        ),
    ]
)
