// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "iso-pixel",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "iso-pixel",
            path: "Sources/iso-pixel"
        )
    ]
)
