// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexNotifier",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CodexNotifierCore",
            targets: ["CodexNotifierCore"]
        ),
        .executable(
            name: "CodexNotifierApp",
            targets: ["CodexNotifierApp"]
        ),
        .executable(
            name: "codex-notifier-helper",
            targets: ["CodexNotifierHelper"]
        )
    ],
    targets: [
        .target(
            name: "CodexNotifierCore",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .executableTarget(
            name: "CodexNotifierApp",
            dependencies: ["CodexNotifierCore"],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("UserNotifications")
            ]
        ),
        .executableTarget(
            name: "CodexNotifierHelper",
            dependencies: ["CodexNotifierCore"]
        ),
        .testTarget(
            name: "CodexNotifierCoreTests",
            dependencies: ["CodexNotifierCore"]
        ),
        .testTarget(
            name: "CodexNotifierAppTests",
            dependencies: ["CodexNotifierApp"]
        )
    ]
)
