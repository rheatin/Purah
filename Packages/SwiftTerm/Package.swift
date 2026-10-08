// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftTerm",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "SwiftTerm", targets: ["SwiftTerm"])
    ],
    targets: [
        .target(
            name: "SwiftTerm",
            path: "Sources/SwiftTerm",
            exclude: [
                "Mac/README.md"
            ],
            resources: [
                .process("Apple/Metal/Shaders.metal")
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-strict-concurrency=minimal"])
            ]
        )
    ],
    swiftLanguageVersions: [.v5]
)
