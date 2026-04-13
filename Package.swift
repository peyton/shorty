// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Shorty",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Shorty", targets: ["Shorty"]),
        .library(name: "ShortyCore", targets: ["ShortyCore"]),
    ],
    targets: [
        .executableTarget(
            name: "Shorty",
            dependencies: ["ShortyCore"],
            path: "Sources/Shorty"
        ),
        .target(
            name: "ShortyCore",
            dependencies: [],
            path: "Sources/ShortyCore",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "ShortyCoreTests",
            dependencies: ["ShortyCore"],
            path: "Tests/ShortyCoreTests"
        ),
    ]
)
