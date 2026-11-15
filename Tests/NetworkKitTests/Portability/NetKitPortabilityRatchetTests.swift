import CoreKitTestSupport
import Foundation
import Testing
@testable import NetKit

/// Spec c8fa126c W4 — T-L-03 and T-L-04 over the portable NetKit target.
///
/// The spec's gate for this wave reads: *"T-L-04 over `Sources/NetworkKit`; the
/// counted Apple-only import list for the portable NetKit target is 0"*. Until
/// this suite existed, nothing measured it: `NetKit` cross-built for musl, which
/// is BR-L-01, and a cross build cannot see a GUARDED Apple import — the
/// compiler simply takes the other arm. `Sources/NetworkKit/LockedState.swift`
/// carried `#if canImport(os)` + `import os` for two releases, correctly, and
/// invisibly.
///
/// Same shape as CoreKit's `CorePortabilityRatchetTests`, deliberately: one
/// subtree (`Platform/`) is excluded BY PATH, and the allowance is itself a test
/// so it is a measured contract rather than a reviewer's memory
/// ([[a-source-text-ratchet-must-measure-the-thing-it-names]]).
@Suite("NetKit core portability ratchet")
struct NetKitPortabilityRatchetTests {
    /// Apple frameworks with no Linux counterpart. `Darwin` is absent: it is one
    /// arm of the `Darwin`/`Glibc`/`Musl` libc triple every POSIX target has.
    private static let forbidden = [
        "SwiftUI", "Combine", "Network", "UIKit", "AppKit", "os", "Metal", "Security", "CryptoKit",
    ]

    /// The one subtree where a platform condition and an Apple import may live.
    private static let platformSubtree = "Platform"

    private static func sourcesRoot() -> URL {
        // The module is `NetKit`; its directory is `Sources/NetworkKit`, which is
        // why this cannot use `sourcesRoot(ofModule:)` with the module name.
        TestPackagePaths.sourcesRoot().appending(path: "NetworkKit", directoryHint: .isDirectory)
    }

    @Test("no Apple-only import in Sources/NetworkKit outside Platform/, guarded or not (T-L-04)")
    func portableNetKitHasNoAppleImport() throws {
        let root = Self.sourcesRoot()
        let files = try Self.swiftFiles(under: root).filter { !Self.isInPlatformSubtree($0, root: root) }
        #expect(files.count > 10, "ratchet scanned too few files — locator drift?")

        var offenders: [String] = []
        for file in files {
            for (index, raw) in try Self.lines(of: file).enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("import ") else { continue }
                let module = line.dropFirst("import ".count).trimmingCharacters(in: .whitespaces)
                if Self.forbidden.contains(module) {
                    offenders.append("\(Self.relative(file, root: root)):\(index + 1) import \(module)")
                }
            }
        }
        #expect(
            offenders.isEmpty,
            """
            Apple-only imports in the portable NetKit target: \(offenders).
            An Apple-only type belongs in Sources/NetKitApple; a platform PRIMITIVE \
            (a lock, a libc call) belongs in Sources/NetworkKit/Platform.
            """
        )
    }

    @Test("no Apple-capability condition in Sources/NetworkKit outside Platform/ (T-L-03)")
    func portableNetKitHasNoPlatformCondition() throws {
        let root = Self.sourcesRoot()
        let files = try Self.swiftFiles(under: root).filter { !Self.isInPlatformSubtree($0, root: root) }

        var offenders: [String] = []
        for file in files {
            for (index, raw) in try Self.lines(of: file).enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("#if") || line.hasPrefix("#elseif"), Self.isAppleCapabilityCondition(line) else { continue }
                offenders.append("\(Self.relative(file, root: root)):\(index + 1) \(line)")
            }
        }
        #expect(offenders.isEmpty, "Apple-capability conditions outside Sources/NetworkKit/Platform/: \(offenders)")
    }

    /// `canImport(FoundationNetworking)` is the one conditional import the spec
    /// names as CORRECT — it is upstream Foundation's own split, not ours — and
    /// it appears in several portable NetKit files. A classifier that flagged it
    /// would make the portable target unwritable, so the allowance is pinned.
    @Test("FoundationNetworking stays allowed, and is actually present in the portable target")
    func foundationNetworkingIsAllowedAndUsed() throws {
        #expect(!Self.isAppleCapabilityCondition("#if canImport(FoundationNetworking)"))

        let root = Self.sourcesRoot()
        let users = try Self.swiftFiles(under: root).filter { file in
            try Self.lines(of: file).contains { $0.contains("canImport(FoundationNetworking)") }
        }
        #expect(
            !users.isEmpty,
            "NetKit speaks URLSession, which is FoundationNetworking off Apple — if nothing guards for it, the Linux build is relying on luck"
        )
    }

    @Test("the allowance is exactly libc, Foundation's own split, DEBUG and non-Apple targets")
    func conditionClassifierIsExact() {
        for line in [
            "#if canImport(os)", "#if canImport(Network)", "#if canImport(Combine)",
            "#if os(macOS)", "#elseif os(iOS)", "#if canImport(Darwin) && canImport(os)",
        ] {
            #expect(Self.isAppleCapabilityCondition(line), "should be banned: \(line)")
        }
        for line in [
            "#if DEBUG", "#if canImport(Darwin)", "#if canImport(Glibc)", "#elseif canImport(Musl)",
            "#if canImport(FoundationNetworking)", "#if canImport(FoundationXML)",
            "#if os(Windows)", "#if os(Linux)",
        ] {
            #expect(!Self.isAppleCapabilityCondition(line), "should be allowed: \(line)")
        }
    }

    /// The vocabulary unification W4 performs, pinned: `NetworkMonitor`'s
    /// `InterfaceType` is CoreKit's enum, not a second declaration of the same
    /// five cases.
    @Test("NetKit does not declare a second interface-type vocabulary")
    func interfaceTypeIsCoreKitsOwn() throws {
        let appleRoot = TestPackagePaths.sourcesRoot().appending(path: "NetKitApple", directoryHint: .isDirectory)
        var declarations: [String] = []
        for file in try Self.swiftFiles(under: appleRoot) + Self.swiftFiles(under: Self.sourcesRoot()) {
            for (index, raw) in try Self.lines(of: file).enumerated() {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix("public enum InterfaceType") || line.hasPrefix("enum InterfaceType") {
                    declarations.append("\(file.lastPathComponent):\(index + 1)")
                }
            }
        }
        #expect(
            declarations.isEmpty,
            "InterfaceType is declared in NetKit at \(declarations); it must be a typealias to CoreKit.NetworkInterfaceType"
        )
    }

    // MARK: - Scanner

    static func isAppleCapabilityCondition(_ line: String) -> Bool {
        for framework in forbidden where line.contains("canImport(\(framework))") {
            return true
        }
        for osName in ["macOS", "iOS", "tvOS", "watchOS", "visionOS"] where line.contains("os(\(osName))") {
            return true
        }
        return false
    }

    private static func lines(of file: URL) throws -> [String] {
        try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
    }

    private static func relative(_ file: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return file.lastPathComponent }
        return String(filePath.dropFirst(rootPath.count))
    }

    private static func isInPlatformSubtree(_ file: URL, root: URL) -> Bool {
        relative(file, root: root)
            .split(separator: "/", omittingEmptySubsequences: true)
            .contains(Substring(platformSubtree))
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
