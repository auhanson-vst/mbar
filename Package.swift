// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mbar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mbar", targets: ["Mbar"])
    ],
    targets: [
        .executableTarget(
            name: "Mbar",
            path: "Sources/Mbar"
        )
    ]
)
