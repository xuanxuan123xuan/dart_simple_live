// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleLiveTVOSCore",
    products: [
        .library(name: "SimpleLiveTVOSCore", targets: ["SimpleLiveTVOSCore"]),
    ],
    targets: [
        .target(name: "SimpleLiveTVOSCore"),
        .testTarget(
            name: "SimpleLiveTVOSCoreTests",
            dependencies: ["SimpleLiveTVOSCore"]
        ),
    ]
)
