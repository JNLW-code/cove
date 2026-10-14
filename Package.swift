// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cove",
    platforms: [.macOS("26.0")],
    dependencies: [
        // In-app updates (the framework Control Centre-style apps such as iTerm and Transmit use). Pinned to a release.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Cove",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/Cove",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The hook helper: reads one Claude Code hook event on stdin, forwards the little the app needs, exits.
        .executableTarget(
            name: "cove-hook",
            path: "Sources/CoveHook",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
