// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "MirrorBridge",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MirrorCore", targets: ["MirrorCore"]),
        .executable(name: "mirror-bridge", targets: ["MirrorBridge"]),
        .executable(name: "mirror-relay", targets: ["MirrorRelayApp"]),
        .executable(name: "mirror-relayctl", targets: ["MirrorRelayCLI"])
    ],
    targets: [
        .target(
            name: "MirrorCore",
            path: "Sources/MirrorCore"
        ),
        .executableTarget(
            name: "MirrorBridge",
            dependencies: ["MirrorCore"],
            path: "Sources/MirrorBridge"
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
