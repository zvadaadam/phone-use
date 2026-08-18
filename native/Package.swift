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
        .executableTarget(
            name: "PhoneUseApp",
            dependencies: ["PhoneUseProtocol"],
            path: "Sources/PhoneUseApp"
        ),
        .executableTarget(
            name: "PhoneUseCLI",
            dependencies: ["PhoneUseProtocol"],
            path: "Sources/PhoneUseCLI"
        ),
        .testTarget(
            name: "PhoneUseProtocolTests",
            dependencies: ["PhoneUseProtocol"],
            path: "Tests/PhoneUseProtocolTests"
        ),
        .testTarget(
            name: "PhoneUseAppTests",
            dependencies: ["PhoneUseApp", "PhoneUseProtocol"],
            path: "Tests/PhoneUseAppTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
