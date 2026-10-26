// swift-tools-version: 6.0
import PackageDescription

// Strict concurrency is a property of the code this repo owns. Passing it on
// the command line with `-Xswiftc` applies it to every target in the graph,
// including the vendored SwiftTerm, which is Swift 5 code that cannot satisfy
// it — CI then reports hundreds of errors in a dependency nobody is editing.
// Declaring it here scopes it to the three targets that must comply.
let firstPartyStrictness: [SwiftSetting] = [
    .unsafeFlags(["-strict-concurrency=complete"])
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
