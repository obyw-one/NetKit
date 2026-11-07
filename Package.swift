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
        .library(
            name: "NetKit",
            targets: ["NetKit"]
        ),
    ],
    dependencies: [
        // 0.16.0 is the first CoreKit WITHOUT its own URLSessionS3Transport
        // (obyw-one/CoreKit#34): 0.14/0.15 declare the type too, and this
        // target's copy is then "ambiguous for type lookup" (measured). 0.14.0
        // is where `S3Transport` itself appeared. Canonical org is obyw-one;
        // `FJ-Studios/CoreKit` only resolved through GitHub's transfer redirect.
        .package(url: "https://github.com/obyw-one/CoreKit.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "NetKit",
            dependencies: ["CoreKit"],
            path: "Sources/NetworkKit"
        ),
        .testTarget(
            name: "NetKitTests",
            dependencies: [
                "NetKit",
                .product(name: "CoreKitTestSupport", package: "CoreKit"),
            ],
            path: "Tests/NetworkKitTests"
        ),
    ]
)
