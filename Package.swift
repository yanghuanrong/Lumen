// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v13)],
    dependencies: [
        // 自动更新框架（用户已确认引入）
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Peek",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Peek",
            swiftSettings: [.swiftLanguageMode(.v5)],
            // 打包后 Sparkle.framework 位于 .app/Contents/Frameworks
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        )
    ]
)