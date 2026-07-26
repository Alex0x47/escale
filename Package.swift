// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Escale",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "EscaleCore", targets: ["EscaleCore"]),
        .library(name: "EscaleUI", targets: ["EscaleUI"]),
        .executable(name: "Escale", targets: ["EscaleCommunityApp"])
    ],
    targets: [
        .target(
            name: "EscaleCore",
            path: "Sources/EscaleCore"
        ),
        .target(
            name: "EscaleUI",
            dependencies: ["EscaleCore"],
            path: "Sources/EscaleUI"
        ),
        .executableTarget(
            name: "EscaleCommunityApp",
            dependencies: ["EscaleCore", "EscaleUI"],
            path: "Sources/EscaleCommunityApp",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "EscaleCoreTests",
            dependencies: ["EscaleCore"],
            path: "Tests/EscaleCoreTests"
        )
    ]
)
