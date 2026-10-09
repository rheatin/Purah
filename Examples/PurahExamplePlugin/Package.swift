// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurahExamplePlugin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PurahExamplePlugin",
            type: .dynamic,
            targets: ["PurahExamplePlugin"]
        )
    ],
    targets: [
        .target(
            name: "PurahExamplePlugin",
            dependencies: []
        )
    ]
)
