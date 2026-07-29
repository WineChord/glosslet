// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Glosslet",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Glosslet",
            targets: ["Glosslet"]
        ),
        .library(
            name: "GlossletCore",
            targets: ["GlossletCore"]
        ),
    ],
    targets: [
        .target(
            name: "GlossletCore"
        ),
        .executableTarget(
            name: "Glosslet",
            dependencies: ["GlossletCore"],
            resources: [
                .copy("Resources/MarkdownRenderer")
            ]
        ),
        .testTarget(
            name: "GlossletCoreTests",
            dependencies: ["GlossletCore"]
        ),
    ]
)
