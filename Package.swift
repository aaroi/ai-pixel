// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ai-pixel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ai-pixel",
            path: "Sources/ai-pixel"
        )
    ]
)
