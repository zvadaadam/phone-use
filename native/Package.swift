// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MirrorRelay",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "mirror-relay", targets: ["MirrorRelayApp"]),
        .executable(name: "mirror-relayctl", targets: ["MirrorRelayCLI"])
    ],
    targets: [
        .target(
            name: "MirrorCore",
            path: "Sources/MirrorCore"
        ),
        .executableTarget(
            name: "MirrorRelayApp",
            dependencies: ["MirrorCore"],
            path: "Sources/MirrorRelayApp"
        ),
        .executableTarget(
            name: "MirrorRelayCLI",
            dependencies: ["MirrorCore"],
            path: "Sources/MirrorRelayCLI"
        ),
        .testTarget(
            name: "MirrorCoreTests",
            dependencies: ["MirrorCore"],
            path: "Tests/MirrorCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
