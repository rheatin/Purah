// swift-tools-version: 6.0
import PackageDescription

// Strict concurrency is a property of the code this repo owns. Passing these
// on the command line with `-Xswiftc` applies them to every target in the
// graph, including the vendored SwiftTerm, which is Swift 5 code that cannot
// satisfy them — CI then reports hundreds of errors in a dependency nobody is
// editing. Declaring them here scopes them to the three targets that must
// comply, and keeps the build description identical no matter which tool
// invokes the build: a flag passed on the command line is part of the build
// fingerprint, so one bare `swift build` (no flag) or an editor's background
// build re-dirties every module — including SwiftTerm — and the next
// `./build.sh` recompiles it from scratch.
let firstPartyStrictness: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete", "-warnings-as-errors"])
]

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
            ],
            swiftSettings: firstPartyStrictness
        ),
        .target(
            name: "PurahUI",
            dependencies: [
                "PurahCore",
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            swiftSettings: firstPartyStrictness
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
            swiftSettings: firstPartyStrictness,
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
