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
            name: "MirrorRelayProtocol",
            path: "Sources/MirrorRelayProtocol"
        ),
        .target(
            name: "MirrorCore",
            dependencies: ["MirrorRelayProtocol"],
            path: "Sources/MirrorCore"
        ),
        .executableTarget(
            name: "MirrorRelayApp",
            dependencies: ["MirrorCore", "MirrorRelayProtocol"],
            path: "Sources/MirrorRelayApp"
        ),
        .executableTarget(
            name: "MirrorRelayCLI",
            dependencies: ["MirrorRelayProtocol"],
            path: "Sources/MirrorRelayCLI"
        ),
        .testTarget(
            name: "MirrorCoreTests",
            dependencies: ["MirrorCore", "MirrorRelayProtocol"],
            path: "Tests/MirrorCoreTests"
        ),
        .testTarget(
            name: "MirrorRelayProtocolTests",
            dependencies: ["MirrorRelayProtocol"],
            path: "Tests/MirrorRelayProtocolTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
