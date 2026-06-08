// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexTokenBar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "CodexTokenBar", targets: ["CodexTokenBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/narner/TiktokenSwift.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CodexTokenBar",
            dependencies: ["TiktokenSwift"],
            path: "Sources/CodexTokenBar"
        )
    ]
)
