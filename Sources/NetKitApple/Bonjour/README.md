# NetKit — Bonjour / mDNS

Generic Bonjour/mDNS discovery and advertisement layer extracted from
BrainyTubeKit (2026-06-21) and generalized for any consumer.

---

## API Surface

| Type | Description |
|------|-------------|
| `BonjourTXTRecord` | Parse / encode TXT record `Data` ↔ `[String: String]` |
| `BonjourServiceDescriptor` | Pre-resolution service identity (name, type, domain) |
| `BonjourResolvedService` | Fully resolved service (host, port, TXT record) |
| `BonjourDiscoveryError` | Typed errors for discovery / resolution failures |
| `BonjourNetworkBrowsing` | Protocol seam over `NetServiceBrowser` |
| `BonjourNetworkBrowsingDelegate` | Delegate callbacks in NetKit types |
| `BonjourServiceResolving` | Protocol seam over `NetService` resolution |
| `SystemBonjourBrowser` | Production `NetServiceBrowser` adapter |
| `SystemBonjourResolver` | Production `NetService` async/await adapter |
| `MDNSBrowser` | Generic discovery browser (`NetServiceBrowser`-based; macOS + Linux) |
| `MDNSAdvertiser` | Generic service advertiser (`NetService`-based; Apple platforms) |
| `MDNSNWBrowser` | `NWBrowser`-based browser exposing raw `NWBrowser.Result` (Apple only) |

---

## Service ID Conventions

The advertiser and browser accept **any** Bonjour service type. Callers are
responsible for choosing a service ID that is unique to their application.

### Recommended service IDs for shikki consumers

| Service | Recommended ID | Notes |
|---------|---------------|-------|
| shikki NATS broker | `_shi-nats._tcp` | Primary mDNS ID for shikki mesh-discovery |
| shikki agent worker | `_shi-worker._tcp` | Worker process advertising presence |
| shikki HTTP API | `_shi-api._tcp` | REST/WebSocket endpoint discovery |

### BrainyTube service IDs (do NOT use in shikki)

| Service | ID | Owner |
|---------|----|-------|
| DLNA/BrainyTube server | `_brainytube._tcp.` | BrainyTubeKit |
| BrainyTube push receiver | `_brainytube-receiver._tcp` | BrainyTubeKit |

---

## Usage

### Discovery (NetServiceBrowser — macOS + Linux-Darwin)

```swift
import NetKit

let browser = MDNSBrowser(serviceType: "_shi-nats._tcp.")
let services = try await browser.discover(timeout: 10)
for svc in services {
    print("\(svc.name) @ \(svc.hostName):\(svc.port)")
    // TXT keys:
    print(svc.txtRecord["version"] ?? "?")
}
```

### Advertisement

```swift
import NetKit

let advertiser = MDNSAdvertiser(
    serviceType: "_shi-nats._tcp",
    name: "My NATS Broker",
    port: 4222,
    txtRecord: [
        "version": "1",
        "cluster": "shikki-dev",
    ]
)
advertiser.start()
// …on teardown:
advertiser.stop()
```

### Discovery (NWBrowser — Apple platforms only)

```swift
import NetKit
import SwiftUI

@State private var browser = MDNSNWBrowser(serviceType: "_shi-nats._tcp")

var body: some View {
    List(browser.endpoints, id: \.endpoint) { result in
        Text(result.endpoint.debugDescription)
    }
    .onAppear { browser.start() }
    .onDisappear { browser.stop() }
}
```

---

## Testing

The `BonjourNetworkBrowsing` and `BonjourServiceResolving` protocol seams
allow full unit testing without real networking:

```swift
let mockBrowser = MockBonjourBrowser()
let mockResolver = MockBonjourResolver(results: [
    "TestBroker": BonjourResolvedService(
        name: "TestBroker",
        hostName: "test.local",
        port: 4222,
        txtRecord: ["version": "1"]
    )
])

let browser = MDNSBrowser(
    serviceType: "_shi-nats._tcp.",
    networkBrowser: mockBrowser,
    resolver: mockResolver
)

// Inject services without touching the network:
mockBrowser.simulateFound(
    BonjourServiceDescriptor(name: "TestBroker", type: "_shi-nats._tcp.", domain: "local.")
)

let results = try await browser.discover(timeout: 2)
assert(results.first?.hostName == "test.local")
```

---

## Architecture Notes

- **`NetServiceBrowser` path** (`MDNSBrowser`, `SystemBonjourBrowser`,
  `SystemBonjourResolver`) works on **macOS + Linux-Darwin** (Foundation
  ships with `NetServiceBrowser` on Darwin; on Linux use the
  swift-corelibs-foundation shim).

- **`NWBrowser` path** (`MDNSNWBrowser`) is **Apple-only**
  (`Network.framework`). It is conditionally compiled under
  `#if canImport(Network) && (os(iOS) || os(tvOS) || os(macOS))`.

- The advertiser uses `NetService.publish()` (not `NWListener.service`)
  so it is decoupled from the socket that actually owns the port.

- `NetService.resolve()` requires a pumping `RunLoop`. Both
  `SystemBonjourBrowser` and `SystemBonjourResolver` schedule on
  `RunLoop.main` with `.common` mode.

---

## Origin

Extracted from:
- `BrainyTubeKit/Services/BonjourBrowser.swift`
- `BrainyTubeKit/Features/PushTargets/BonjourReceiverAdvertiser.swift`
- `BrainyTubeKit/Features/PushTargets/PushTargetBrowser.swift`

Extraction commit: `feat/netkit-bonjour-mdns-extraction-2026-06-21`  
Operator greenlight: 2026-06-21  
Consumer intent: shikki kernel mesh-discovery via `_shi-nats._tcp.local`
