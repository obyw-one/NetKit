#if canImport(Network)
import Foundation

/// The label of every dispatch queue NetKit creates, spelled once.
///
/// #18 review: the five queues were labelled `net.netkit.…` at five call sites. That
/// prefix named no domain anyone owns. NetKit is an OBYW.one package, and OBYW.one
/// products use the `one.obyw.<product>` reverse-DNS root, so the prefix is
/// ``prefix`` and each queue is a case, never a literal at its call site.
enum NetKitQueueLabel: String, CaseIterable, Sendable {
    case ssdpAdvertiser = "ssdp.advertiser"
    case ssdpSearchResponder = "ssdp.searchResponder"
    case ssdpBrowser = "ssdp.browser"
    case dlnaServer = "dlna.server"
    case dlnaBrowser = "dlna.browser"

    /// OBYW.one's reverse-DNS root for NetKit.
    static let prefix = "one.obyw.netkit"

    /// The full label, as Instruments and crash logs show it.
    var label: String { "\(Self.prefix).\(rawValue)" }

    /// A serial queue carrying this label.
    func makeQueue() -> DispatchQueue { DispatchQueue(label: label) }
}
#endif
