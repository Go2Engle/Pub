// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Pub",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "Pub",
            targets: ["Pub"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "Pub"
        ),
        .testTarget(
            name: "PubTests",
            dependencies: ["Pub"]
        ),
    ]
)
