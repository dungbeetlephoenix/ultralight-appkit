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
                // Keep type metadata: Combine's ObservableObject needs it.
                // Property names and compiler debug information are unnecessary
                // in a stripped release; debug builds remain fully inspectable.
                .unsafeFlags(["-Osize", "-whole-module-optimization", "-gnone",
                              "-Xfrontend", "-enable-single-module-llvm-emission",
                              "-Xfrontend", "-disable-reflection-names"],
                             .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-const_selrefs",
                              "-Xlinker", "-dead_strip", "-Xlinker", "-x"],
                             .when(configuration: .release))
            ]
        )
    ]
)
