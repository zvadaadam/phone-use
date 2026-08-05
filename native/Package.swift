// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "PhoneUse",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "phone-use-app", targets: ["PhoneUseApp"]),
        .executable(name: "phone-use", targets: ["PhoneUseCLI"])
    ],
    targets: [
        .target(
            name: "PhoneUseProtocol",
            path: "Sources/PhoneUseProtocol"
        ),
        .target(
            name: "PhoneUseCore",
            dependencies: ["PhoneUseProtocol"],
            path: "Sources/PhoneUseCore"
        ),
        .executableTarget(
            name: "PhoneUseApp",
            dependencies: ["PhoneUseCore", "PhoneUseProtocol"],
            path: "Sources/PhoneUseApp"
        ),
        .executableTarget(
            name: "PhoneUseCLI",
            dependencies: ["PhoneUseProtocol"],
            path: "Sources/PhoneUseCLI"
        ),
        .testTarget(
            name: "PhoneUseCoreTests",
            dependencies: ["PhoneUseCore", "PhoneUseProtocol"],
            path: "Tests/PhoneUseCoreTests"
        ),
        .testTarget(
            name: "PhoneUseProtocolTests",
            dependencies: ["PhoneUseProtocol"],
            path: "Tests/PhoneUseProtocolTests"
        ),
        .testTarget(
            name: "PhoneUseAppTests",
            dependencies: ["PhoneUseApp", "PhoneUseCore"],
            path: "Tests/PhoneUseAppTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
