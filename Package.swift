// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Contextory",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "ContextoryCore",
            targets: ["ContextoryCore"]
        )
    ],
    targets: [
        .target(
            name: "ContextoryCore",
            path: "Sources/Contextory/Core"
        ),
        .testTarget(
            name: "ContextoryTests",
            dependencies: ["ContextoryCore"],
            path: "Tests"
        )
    ]
)
