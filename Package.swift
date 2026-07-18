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
        .target(name: "EvolvingImpressionistCore", path: "Sources/EvolvingImpressionistCore"),
        .executableTarget(
            name: "EvolvingImpressionist",
            dependencies: ["EvolvingImpressionistCore"],
            path: "Sources/EvolvingImpressionist"
        ),
        .executableTarget(
            name: "EvolvingImpressionistVerify",
            dependencies: ["EvolvingImpressionistCore"],
            path: "Sources/EvolvingImpressionistVerify"
        )
    ]
)
