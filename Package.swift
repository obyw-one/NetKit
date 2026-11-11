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
        // visionOS runs iOS 17 code, so whatever builds for iOS must build there too (operator rule,
        // 2026-11-08). visionOS 1 is the iOS 17 generation. CoreKit declares no visionOS and so builds at
        // SwiftPM's default floor, which is below this one; Network, Combine and os all exist on visionOS.
        .visionOS(.v1),
    ],
    products: [
        // The platform-neutral core: EndPoint, NetworkProtocol, Umami, PocketBase,
        // the config endpoint, WebSocket. Builds on Linux.
        .library(
            name: "NetKit",
            targets: ["NetKit"]
        ),
        // The Apple-only surface (DLNA / SSDP, NetworkMonitor, the Combine
        // publisher form of sendRequest) — the way CoreKit keeps CoreKitUI apart
        // from CoreKit. Every source is wrapped in `#if canImport(Network)` /
        // `canImport(Combine)`, so the module is empty (not half-typed) off Apple.
        .library(
            name: "NetKitApple",
            targets: ["NetKitApple"]
        ),
    ],
    dependencies: [
        // 0.16.0 is the first CoreKit WITHOUT its own URLSessionS3Transport
        // (obyw-one/CoreKit#34): 0.14/0.15 declare the type too, and this
        // target's copy is then "ambiguous for type lookup" (measured). 0.14.0
        // is where `S3Transport` itself appeared. Canonical org is obyw-one;
        // `FJ-Studios/CoreKit` only resolved through GitHub's transfer redirect.
        // ConfigEndpoint and its conformance suite (used by PocketConfigEndpoint) shipped in 0.14.0.
        .package(url: "https://github.com/obyw-one/CoreKit.git", from: "0.16.0"),
    ],
    targets: [
        .target(
            name: "NetKit",
            dependencies: ["CoreKit"],
            path: "Sources/NetworkKit"
        ),
        .target(
            name: "NetKitApple",
            dependencies: ["NetKit"],
            path: "Sources/NetKitApple"
        ),
        .testTarget(
            name: "NetKitTests",
            dependencies: [
                "NetKit",
                "NetKitApple",
                .product(name: "CoreKitTestSupport", package: "CoreKit"),
            ],
            path: "Tests/NetworkKitTests"
        ),
    ]
)
