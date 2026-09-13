// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "CodexUsageCard",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CodexUsageCard",
            path: "Sources/CodexUsageCard",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
