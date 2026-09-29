// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MiniTranscribe",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MiniTranscribe",
            path: "Sources"
        )
    ]
)
