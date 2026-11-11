// swift-tools-version: 6.1

import PackageDescription

// AetherEngine with its optional components turned on, re-exported for the apps. XcodeGen can't set
// a package's traits, so the apps depend on this package instead, the way AetherEngine's docs suggest
// (docs/installation.md, "Optional components").
//
// - TrueHDObjectAudio: TrueHD Atmos with its height channels (LoadOptions.objectAudioRendering).
// - DTSXObjectAudio: DTS:X with its height channels (the same option).
// - DolbyVisionFelCurves: a Profile 7 FEL source's enhancement layer folded into the Profile 8.1 RPU on
//   the native route; on whenever built in.
//
// These components may be subject to third-party patent licensing; whoever builds and distributes the
// app with them is responsible for their own licensing.
let package = Package(
    name: "AetherEngineFeatures",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
    ],
    products: [
        .library(name: "AetherEngineFeatures", targets: ["AetherEngineFeatures"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            exact: "7.62.1",
            traits: ["TrueHDObjectAudio", "DTSXObjectAudio", "DolbyVisionFelCurves"]
        ),
    ],
    targets: [
        .target(
            name: "AetherEngineFeatures",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
