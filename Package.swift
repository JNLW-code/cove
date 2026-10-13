// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Cove",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Cove",
            path: "Sources/Cove",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
