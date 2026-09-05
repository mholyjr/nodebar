// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "NodeBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "NodeBar", targets: ["NodeBar"])
    ],
    targets: [
        .executableTarget(
            name: "NodeBar",
            path: "Sources/NodeBar"
        )
    ]
)
