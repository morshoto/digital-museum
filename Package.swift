// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvolvingImpressionist",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EvolvingImpressionist", targets: ["EvolvingImpressionist"]),
        .library(name: "EvolvingImpressionistCore", targets: ["EvolvingImpressionistCore"])
    ],
    targets: [
        .target(
            name: "EvolvingImpressionistCore",
            path: "application/EvolvingImpressionistCore",
            resources: [.copy("Resources/Paintings")]
        ),
        .executableTarget(
            name: "EvolvingImpressionist",
            dependencies: ["EvolvingImpressionistCore"],
            path: "application/EvolvingImpressionist"
        ),
        .executableTarget(
            name: "EvolvingImpressionistVerify",
            dependencies: ["EvolvingImpressionistCore"],
            path: "application/EvolvingImpressionistVerify"
        )
    ]
)
