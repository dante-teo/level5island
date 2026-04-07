// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Level5Island",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "Level5IslandCore",
            path: "Sources/Level5IslandCore"
        ),
        .executableTarget(
            name: "Level5Island",
            dependencies: ["Level5IslandCore"],
            path: "Sources/Level5Island",
            resources: [
                .copy("Resources")
            ]
        ),
        .executableTarget(
            name: "level5island-bridge",
            dependencies: ["Level5IslandCore"],
            path: "Sources/Level5IslandBridge"
        ),
        .testTarget(
            name: "Level5IslandCoreTests",
            dependencies: ["Level5IslandCore"],
            path: "Tests/Level5IslandCoreTests"
        ),
        .testTarget(
            name: "Level5IslandTests",
            dependencies: ["Level5Island"],
            path: "Tests/Level5IslandTests"
        ),
    ]
)
