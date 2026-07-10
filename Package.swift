// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipHistory",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClipHistory",
            path: "Sources"
        )
    ]
)
