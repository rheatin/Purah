// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Purah",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Purah", targets: ["PurahApp"]),
        .library(name: "PurahCore", targets: ["PurahCore"]),
        .library(name: "PurahUI", targets: ["PurahUI"])
    ],
    dependencies: [
        .package(path: "Packages/SwiftTerm")
    ],
    targets: [
        .target(
            name: "PurahCore",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
        .target(
            name: "PurahUI",
            dependencies: [
                "PurahCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ]
        ),
        .executableTarget(
            name: "PurahApp",
            dependencies: ["PurahCore", "PurahUI"],
            exclude: [
                "Resources/Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/PurahApp/Resources/Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "PurahCoreTests",
            dependencies: ["PurahCore", "PurahUI", "PurahApp"]
        )
    ]
)
