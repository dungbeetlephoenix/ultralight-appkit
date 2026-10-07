// swift-tools-version: 5.9
import PackageDescription

var releaseLinkerFlags = ["-Xlinker", "-const_selrefs", "-Xlinker", "-objc_stubs_small",
                          "-Xlinker", "-mllvm", "-Xlinker", "-enable-linkonceodr-outlining",
                          "-Xlinker", "-mllvm", "-Xlinker", "-machine-outliner-reruns=1",
                          "-Xlinker", "-dead_strip", "-Xlinker", "-x"]
for (original, packed) in [("__const", "__text_const"), ("__cstring", "__cstring"),
                           ("__objc_classname", "__objc_classname"),
                           ("__objc_methlist", "__objc_methlist")] {
    for argument in ["-rename_section", "__TEXT", original, "__DATA_CONST", packed] {
        releaseLinkerFlags += ["-Xlinker", argument]
    }
}

let package = Package(
    name: "ultralight",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Ultralight",
            path: "Sources/Ultralight",
            swiftSettings: [
                // AppState publishes object changes explicitly; the observation
                // gate verifies every property against native Combine ordering.
                // Debug builds retain reflection and normal debug information.
                .unsafeFlags(["-Osize", "-whole-module-optimization", "-gnone",
                              "-Xfrontend", "-enable-single-module-llvm-emission",
                              "-Xfrontend", "-disable-reflection-metadata"],
                             .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(releaseLinkerFlags,
                             .when(configuration: .release))
            ]
        )
    ]
)
