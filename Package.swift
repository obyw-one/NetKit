// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "NetKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        // tvOS was never declared, so it built at SwiftPM's oldest tvOS
        // version. That made NetKit the weakest link in the chain
        // BrainyTube -> NetKit -> CoreKit: once CoreKit correctly declared
        // .tvOS(.v18) (obyw-one/CoreKit#19), resolution failed with
        //
        //   The package product 'CoreKit' requires minimum platform version
        //   18.0 for the tvOS platform, but this target supports 17.0
        //   (in target 'NetKit' from project 'NetKit')
        //
        // A dependency's floor must be at least its own dependencies'. The
        // consuming app cannot paper over this — SwiftPM resolves each package
        // at that package's declared minimum.
        .tvOS(.v18),
    ],
    products: [
        // v2.0.0 (2026-07-20): the generic module name `NetKit` is RESTORED.
        // The v1.0.0 `ShiNetKit` rename was an aberration to dodge a collision
        // with fuzzy-swift's forked NetKit; fuzzy now consumes NetKit directly
        // (name-restoration epic), so no collision remains and the branded
        // name is undone.
        .library(name: "NetKit", targets: ["NetKit"]),
        // Deprecated compatibility: `import ShiNetKit` re-exports NetKit for
        // one cycle so unknown external consumers don't hard-break at v2.0.0.
        .library(name: "ShiNetKit", targets: ["ShiNetKitShim"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FJ-Studios/CoreKit.git", from: "0.1.0"),
    ],
    targets: [
        .target(
            name: "NetKit",
            dependencies: ["CoreKit"],
            path: "Sources/NetworkKit",
            exclude: ["Bonjour/README.md"]
        ),
        .target(
            name: "ShiNetKitShim",
            dependencies: ["NetKit"],
            path: "Sources/ShiNetKitShim"
        ),
        .testTarget(
            name: "NetKitTests",
            dependencies: ["NetKit"],
            path: "Tests/NetworkKitTests"
        ),
    ]
)
