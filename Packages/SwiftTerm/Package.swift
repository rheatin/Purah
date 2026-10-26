// swift-tools-version: 6.0
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
                "Mac/README.md",
                "Apple/Metal/Shaders.metal"
            ],
            // SwiftTerm is upstream code built for Swift 5; several of its
            // AppKit subclasses implement `NSTextInputClient` and
            // `TerminalDelegate` members that are main-actor isolated here and
            // non-isolated in the protocol. Under Swift 6 language mode those
            // are hard errors, and Swift 6.1 does not honour the package-level
            // `swiftLanguageVersions` for a target that also carries
            // `swiftSettings` — so the mode is stated per target.
            //
            // `.unsafeFlags` were used before and are unreliable when the
            // package is consumed as a dependency, which is what this is.
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-strict-concurrency=minimal"])
            ]
        )
    ]
)
