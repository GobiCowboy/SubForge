// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SubForge",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "SubForge",
            path: "Sources"
        ),
    ]
)
