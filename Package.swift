// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SpaceMinder",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SpaceMinder", targets: ["SpaceMinder"])
    ],
    targets: [
        .executableTarget(name: "SpaceMinder", path: "Sources/SpaceMinder")
    ]
)
