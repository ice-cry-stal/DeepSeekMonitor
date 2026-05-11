// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekMonitor",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekMonitor",
            path: "Sources"
        )
    ]
)
