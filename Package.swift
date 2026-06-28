// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SpatialGestures",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SpatialGestures", targets: ["SpatialGestures"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "SpatialGestures",
            dependencies: [],
            path: "Sources/SpatialGestures"
        ),
        .testTarget(
            name: "SpatialGesturesTests",
            dependencies: ["SpatialGestures"],
            path: "Tests/SpatialGesturesTests"
        )
    ]
)
