// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lumen",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Lumen",
            path: "Sources/Lumen",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)