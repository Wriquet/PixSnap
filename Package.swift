// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "PixSnap",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PixSnap", targets: ["PixSnap"])
    ],
    targets: [
        .executableTarget(
            name: "PixSnap",
            path: "Sources/PixSnap",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        ),
        .testTarget(
            name: "PixSnapTests",
            dependencies: ["PixSnap"],
            path: "Tests/PixSnapTests",
            swiftSettings: [
                .enableUpcomingFeature("ApproachableConcurrency")
            ]
        )
    ]
)
