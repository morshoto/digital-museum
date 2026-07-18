// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EvolvingImpressionist",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "EvolvingImpressionist", targets: ["EvolvingImpressionist"])
    ],
    targets: [
        .executableTarget(name: "EvolvingImpressionist", path: "Sources/EvolvingImpressionist")
    ]
)
