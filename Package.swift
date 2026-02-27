// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ultralight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ultralight",
            path: "Sources/Ultralight",
            swiftSettings: [
                .unsafeFlags(["-Osize", "-whole-module-optimization"])
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-dead_strip", "-Xlinker", "-x"])
            ]
        )
    ]
)
