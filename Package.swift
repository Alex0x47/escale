// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Gouvernail",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gouvernail", targets: ["Gouvernail"])
    ],
    targets: [
        .executableTarget(
            name: "Gouvernail",
            path: "Sources/Gouvernail",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "GouvernailTests",
            dependencies: ["Gouvernail"],
            path: "Tests/GouvernailTests"
        )
    ]
)
