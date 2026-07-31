// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "auhanson-vst",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AuhansonVST", targets: ["AuhansonVST"])
    ],
    targets: [
        .executableTarget(
            name: "AuhansonVST",
            path: "Sources/AuhansonVST"
        )
    ]
)
