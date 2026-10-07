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
                // Keep type metadata: Combine's ObservableObject needs it.
                // Property names and compiler debug information are unnecessary
                // in a stripped release; debug builds remain fully inspectable.
                .unsafeFlags(["-Osize", "-whole-module-optimization", "-gnone",
                              "-Xfrontend", "-enable-single-module-llvm-emission",
                              "-Xfrontend", "-disable-reflection-names"],
                             .when(configuration: .release))
            ],
            linkerSettings: [
                .unsafeFlags(releaseLinkerFlags,
                             .when(configuration: .release))
            ]
        )
    ]
)
