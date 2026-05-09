// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DisplayPower",
    defaultLocalization: "de",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "DisplayPower",
            path: "Sources/DisplayPower",
            resources: [.process("Resources")]
        )
    ]
)
