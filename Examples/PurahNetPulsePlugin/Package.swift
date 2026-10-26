// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurahNetPulsePlugin",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "PurahNetPulsePlugin",
            type: .dynamic,
            targets: ["PurahNetPulsePlugin"]
        )
    ],
    targets: [
        // Zero host dependencies: only SwiftUI / AppKit / Darwin.
        .target(
            name: "PurahNetPulsePlugin",
            dependencies: []
        )
    ]
)
