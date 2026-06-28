// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Airspace",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Airspace", targets: ["Airspace"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "Airspace",
            dependencies: [],
            path: "Sources/Airspace"
        ),
        .testTarget(
            name: "AirspaceTests",
            dependencies: ["Airspace"],
            path: "Tests/AirspaceTests"
        )
    ]
)
