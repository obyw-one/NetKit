# Changelog

All notable changes to NetKit are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [3.0.0] — 2026-11-11

One release for the four PRs merged since 2.4.0: the PocketBase client and config
endpoint with the Linux split (#18), `URLSessionS3Transport` (#20), the umami read
endpoints (#21) and the Apache-2.0 relicence (#19).

**Major, because it breaks source:** `NetworkProtocol.createRequest(endPoint:)` now
throws and `NetworkError` gains two cases (see "`createRequest` no longer crashes"),
and DLNA / SSDP / `NetworkMonitor` / the Combine `sendRequest` move to the new
`NetKitApple` product (see "Linux and the `NetKitApple` split"). A consumer on
`from: "2.x"` does not pick this up by itself; each change below says what to edit.

### Added

- **`PocketEndPoint` and `PocketClient` — a generic PocketBase client, beside
  `UmamiEndPoint`.** Records (list with filter / sort / expand / fields /
  `skipTotal`, view, create, update, delete), password login, token refresh,
  password reset (request + confirm) and custom routes, over an injected
  `PocketConfig` and `PocketTransport`.

  - **No default URL.** `PocketConfig` is validated at construction; a missing
    endpoint is `PocketConfigError.missingEndpoint`, never a fallback. It is not
    `Codable` (it can hold a credential) and redacts it from its descriptions.
  - **One typed error, with the server's own body.** `PocketError` keeps
    PocketBase's `{status, message, data}` error body and the raw bytes.
    `NetworkProtocol.sendRequest` cannot do this: it throws on a non-2xx status
    before returning the body. 401/403, and a 400 from a login or refresh, are
    `.authentication`. Nothing is swallowed.
  - **Typed models only.** `PocketListContainer`, `PocketAuthResponse`,
    `PocketErrorBody`, `PocketPayload` (over `CoreKit.JSONValue`),
    `PocketQuery`. PocketBase dates go through the fleet strategy.
  - **`PocketFilter.literal(_:)`** for a safe filter value. Interpolating a raw
    value is a filter injection (measured: `x' || title != '` matches every
    record). A backslash is refused: PocketBase 0.25.9 and 0.40.6 disagree on
    what it means.
  - **`decodePocketDateIfPresent(forKey:)`.** PocketBase serialises an unset
    date as `""`, which the fleet date strategy rejects, so a plain `Date?`
    fails the whole record.
  - **`MockPocketTransport`**, a scripted actor for tests of anything built on
    the client. A request with no queued reply fails loudly.
  - `PocketEndPoint` is also an `EndPoint`, so a consumer that calls
    `networkService.sendRequest(endpoint:)` keeps that call shape.

  Requests are built without `NetworkProtocol.createRequest`'s hazards: path
  segments and query values are percent-encoded, `..` and empty segments are
  refused, bodies carry `Content-Type: application/json` (the shared builder
  sends none, so URLSession labels the JSON `application/x-www-form-urlencoded`
  and PocketBase answers "Cannot be blank"), and an update is a PATCH (PocketBase
  has no PUT route for records: it answers 404).

  Verified against a real PocketBase (0.25.9, then 0.40.6) started by
  `scripts/pocketbase-live.sh -- kagami test --all --strict`.

- **`PocketConfigEndpoint` — CoreKit's `ConfigEndpoint` over PocketBase.**
  Fetches the server-driven `AppConfig` from a PocketBase collection (one
  record per app and environment, filtered with `PocketFilter.literal`),
  decoding `PocketListContainer<AppConfig>` from the snake_case record, throwing
  `ConfigEndpointError.notFound` when there is none and every other failure
  unchanged as a `PocketError`. The collection is injected; the bearer token is
  asked for on each fetch, so a refreshed login is picked up. Runs CoreKit's
  `ConfigEndpointConformance` over a fake server (offline) and over a real
  PocketBase 0.25.9 (live scope), and drives CoreKit's `AppConfigService`.

- **`URLSessionS3Transport`** — the `URLSession` transport for CoreKit's
  `S3ObjectStoreClient`, moved here from CoreKit (spec d3f8a1b2). CoreKit keeps
  `S3Transport`, `AWSSignatureV4` and the request/response types and ships no
  transport; the caller injects this one. Its two ends are pure functions
  (`urlRequest(for:)`, `response(data:response:operation:)`) and the loader is
  injected, so it is tested by return value, not by intercepting the network.
  New public type.

- **The umami READ endpoints**, extracted from the standalone UmamiKit
  (`shikki-io/UmamiKit`, which has no consumer and cannot build outside one
  machine). Reading an event back is what lets "did it land?" be asserted by a
  test instead of by a dashboard visit — a `200` from `/api/send` proves
  nothing, since umami answers `200 {"beep":"boop"}` when its bot filter
  discards an event.
  - `UmamiReadConfig` — endpoint, website id and an INJECTED bearer token. No URL
    is baked in. The token is redacted from `description`, `debugDescription`
    and `dump`.
  - `UmamiReadEndPoint` — `stats`, `pageViews`, `metrics`, `events`,
    `eventSeries`, `active`. Every case is a `GET` carrying the bearer.
  - `UmamiReadClient` — typed calls over any `NetworkProtocol`, plus
    `eventCount(named:in:)`.
  - `UmamiMetricRow`, `UmamiReadStats`, `UmamiEventPage` and friends.
  - Named `UmamiRead*` so nothing collides with `UmamiEndPoint`, `UmamiConfig`
    or `UmamiAnswer`.
- The send path is untouched and stays unauthenticated (BR-UMA-04):
  `UmamiEndPoint.track` accepts only a `UmamiConfig`, which a read token cannot
  be put into.

Not extracted from UmamiKit, on purpose: dashboards, A/B experiments, revenue,
attribution, the provisioner and `CMSClient` are product surface, not a network
kit's job.

### Changed

- **CoreKit is `https://github.com/obyw-one/CoreKit.git` from `0.16.0`** (was the
  `FJ-Studios` URL from `0.1.0`). `ConfigEndpoint` and its conformance suite shipped
  in 0.14.0; 0.16.0 is the first release without CoreKit's own
  `URLSessionS3Transport`. The test target gains `CoreKitTestSupport`. The one
  caller of the deprecated `Data.prettyJson` (a debug log line) now uses
  `prettyJSON()`.
- **Platforms: visionOS 1 added.** Whatever builds for iOS builds for visionOS;
  the macOS gate builds the package for macOS and the visionOS Simulator too.
- **Dispatch queue labels are `one.obyw.netkit.*`** (were `net.netkit.*`), from one
  `NetKitQueueLabel` enum instead of five literals.
- **The TypeScript sibling is `@obyw-one/netkit-web`, Apache-2.0** (was
  `@fj-studios/netkit-web`, MIT; never published under either name).
- **The macOS gate is one `kagami test --all --strict`** under
  `scripts/pocketbase-live.sh`, which now runs the official PocketBase binary
  (default 0.40.6, checksum-pinned) with no container and no system temp
  directory.
- **`UmamiEndPoint` and `UmamiReadEndPoint` are checked `Sendable`**, no longer
  `@unchecked`: every associated value is `Sendable`, so the compiler now proves it
  instead of being told to skip the check.
- **Licence: Apache-2.0** (was AGPL-3.0, #19). Libraries other people link are
  Apache-2.0; the copyright holder is OBYW.one SASU. See `NOTICE`.

### `createRequest` no longer crashes or drops a body (API change)

`NetworkProtocol.createRequest(endPoint:)` is now `throws(NetworkError)`.

- Before: a host/path that forms no URL hit `preconditionFailure` and crashed the
  app at runtime (nothing forces an endpoint to be well formed: the protocol has a
  default implementation), and a body that failed to encode was `try?`'d away, so the
  request went out WITHOUT its body. That is how a PocketBase login got a 400 "Cannot
  be blank" with no local error.
- Now: `NetworkError.invalidURL(description:)` names scheme, host and path (never the
  query), and `NetworkError.bodyEncodingFailed(_:)` carries the cause. A body that
  `JSONSerialization` would raise an Objective-C exception for (a `Date`, `NaN`) is
  checked first and reported the same way, instead of crashing. Nothing is sent.
- Every caller propagates it: the `async` and closure `sendRequest` (the closure gets
  `.failure`), `MockNetworkService` (nothing is captured), the Combine publisher
  (`Fail`), and so the Umami use case (`TrackUseCaseError.networkError`).
- `WebSocketClient`'s reconnect no longer reconnects after its sleep is cancelled.

**API break, listed:**
1. A direct caller of `createRequest(endPoint:)` must now write `try`.
2. `NetworkError` gains two cases (`invalidURL`, `bodyEncodingFailed`), so an
   exhaustive `switch` over it needs them (or a `default`).
3. An external conformer that implemented the old non-throwing `createRequest` still
   compiles (a non-throwing function satisfies a throwing requirement) but keeps
   its old behaviour; only the default implementation changed.

### Linux and the `NetKitApple` split

NetKit now builds on Linux. The Apple-only code moved to a second product,
**`NetKitApple`** (the way CoreKit keeps `CoreKitUI` apart): DLNA / SSDP
(`DLNABrowser`, `DLNAServer`, `SSDPAdvertiser`, `SSDPSearchResponder`,
`SSDPBrowser`, `ContentDirectory`, `DLNAMediaItem`, `SSDPMessage`),
`NetworkMonitor`, and the Combine publisher form of `sendRequest`. Every source
is wrapped in `#if canImport(Network)` / `canImport(Combine)`, so the module is
empty off Apple. The `NetKit` product (EndPoint, `NetworkProtocol`,
`NetworkService`, `MockNetworkService`, Umami, PocketBase, the config endpoint,
WebSocket) is platform-neutral. `.woodpecker/linux-build.yml` runs the build and
the offline suites on `swift:6.3-jammy`.

**What changes for an Apple consumer**

- Using DLNA, SSDP or `NetworkMonitor`: add the `NetKitApple` product to the
  target's dependencies and `import NetKitApple` (no other source change).
- Using the Combine form `sendRequest(endpoint:type:) -> AnyPublisher`: it is no
  longer a `NetworkProtocol` requirement but an extension in `NetKitApple`;
  `import NetKitApple`. A custom conformer that implemented it keeps compiling
  (it is now an ordinary method), but a call through `any NetworkProtocol` runs
  the extension's URLSession implementation.
- `DLNAServer.onReady` is now `@Sendable` (it is called from the server's queue).
- Added: `MockNetworkService.response(for:)`, `ContentDirectory.isEmpty`.
- Everything else is source-compatible.

### Concurrency

No `@unchecked Sendable` remains in `Sources/`.

- `MockNetworkService`, `ContentDirectory`, `SSDPAdvertiser`,
  `SSDPSearchResponder`, `SSDPBrowser`, `DLNABrowser`, `DLNAServer`: mutable
  state is one value behind the platform's own Sendable lock
  (`OSAllocatedUnfairLock`; `Synchronization.Mutex` off Apple for the mock), so
  the compiler checks the claim. Delegates and callbacks are called outside the
  lock. These classes were racy before: `start()`, `stop()`, `servers` and `port`
  touched state from the caller's thread while the Network callbacks wrote it on
  a queue. Restarting now cancels the previous connection or listener instead of
  leaking it.
- `DLNAServer.ChunkState` is gone: the byte count left to send travels by value
  through each chunk's completion handler.
- `UmamiEndPoint` never needed `@unchecked`: its payload is `UmamiConfig` and
  `[String: String]`, both Sendable.

### Notes

- `EndPoint.swift`, `WebSocketClient.swift` and the tests import
  `FoundationNetworking` where `URLRequest` is used.
- The PocketBase files and the whole core build and pass their offline tests on
  Linux (Swift 6.3).

## [2.4.0] — 2026-10-28

### Added

- **`UmamiAnswer.beep` and `UmamiAnswer.acceptance`** — a 2xx is not a
  delivery.

  umami answers HTTP **200** with `{"beep":"boop"}` when its bot filter
  DISCARDS an event. Before this release that body decoded to the same all-nil
  `UmamiAnswer` as a genuine acceptance, so **no consumer could tell them
  apart** — the information was destroyed at decode, and no amount of
  consumer-side policy could recover it.

  `acceptance` returns `.accepted` / `.botRejected` / `.unrecognised`.
  Rejection is checked first, so a discard can never read as delivered because
  some other key happened to be present.

### Fixed

- **The v2.2.1 header was wrong, and it was the most expensive sentence in the
  file.** It said `/api/send` answering with a bare token, `{}` or an empty
  body meant "every one of those … the event was ACCEPTED". A consumer
  following this type's own documentation would ack a bot-rejection and delete
  the payload. That is exactly what shikki did (shikki#1862), losing a
  telemetry buffer before the cause was found on 2026-10-28.

### Notes

- **Additive and non-breaking.** `beep` defaults to `nil`, so every pre-2.4.0
  caller compiles unchanged and classifies as it did. `T-ACC-07` pins that.
- Extracted from shikki#1864 at the operator's direction: what a body MEANS is
  the wire contract and is identical for every consumer, so it belongs here —
  WabiSabi uses this primitive too. What to DO about it (ack a journal, keep a
  payload) stays the consumer's policy, which this type's header has always
  reserved correctly.
- Measured against a live umami on 2026-10-28, six User-Agent variants: every
  one lacking an OS token came back `{"beep":"boop"}` with HTTP 200.


## [2.3.0] — 2026-10-28

### Added

- **`UmamiEndPoint.track(name:)`** — an optional top-level `name`, emitted only
  when set. This is the key that promotes a `/api/send` row from a PAGEVIEW to
  a named CUSTOM EVENT, and it is what umami's Events view groups by. Until
  now there was no parameter to emit it: `body` wrote `title` and `url` and
  nothing else that could carry an event name.

  That shape is right for a mobile app — a screen IS a page — and wrong for a
  CLI, where the verb is the event and every invocation otherwise lands as an
  unnamed pageview no funnel can group.

  Measured against a live umami, 2026-10-28, the same payload twice one key
  apart: with `"name"` it is accepted and appears under Events; without, the
  same answer and the same session, and it stays a pageview. So `name` is a
  documented top-level key and does NOT provoke the HTTP 500 that `os` and
  `browser` do there — which is why those two keep their regression comments
  in `body` and this one needs none.

  Additive and non-breaking: every pre-2.3.0 caller is byte-identical.
  `T-NAME-02` asserts the key is absent by default, because emitting an empty
  name would silently reclassify every existing screen view as a custom event.
  `T-NAME-03` asserts adding a name adds exactly one key and removes none.

  Found by shikki spec `9e1c4a77` W3 (shikki-io/shikki#1864), which could name
  its own events and then had nowhere to put the name on the wire. The gap had
  been there since v1.0.0 — zero occurrences of a top-level `name` in any tag
  `v1.0.0..v2.2.1`. Reported upstream rather than forked or vendored.


### Added

- **Umami primitive** (`Sources/NetworkKit/Umami/`): upstreamed the umami wire
  contract from WabiSabi. The new API is Foundation-only — the app-specific
  helpers (`Env.current.trackingHost`, `DeviceInfo.*`) are gone; every value
  is injected by the caller (BR-UMA-01, BR-UMA-02).
  - `UmamiConfig` — validated at `init` (scheme `https`, or `http` with an
    explicit `allowInsecureHTTP: true`; non-empty host). Invalid endpoints
    throw `UmamiConfigError` at construction rather than silently killing
    telemetry at flush time (BR-UMA-03).
  - `UmamiEndPoint.track(config:url:title:referrer:tag:params:)` — the
    endpoint carries its config, so the enum has no global state.
    `Authorization` is opt-in via `UmamiConfig.authorization`; `/api/send`
    sends none by default (BR-UMA-04). `os` and `browser` remain OUT of the
    top-level payload (kept as a regression test — umami returns HTTP 500).
  - `UmamiAnswer` — typed response (`cache`, `sessionId`, `visitId`).
  - `UmamiTrackUseCase(networkService:config:)` — routes through the
    injected `NetworkProtocol` and maps any `NetworkError` to
    `TrackUseCaseError.networkError`.
  - `TrackUseCaseProtocol` / `TrackInfoProtocol` / `TrackUseCaseError` —
    the test seam consumers use (single HTTP protocol, no second one).

### Notes

- No changes to existing types. `NetKit` product membership is unchanged;
  the new sources are added to the same `NetKit` target.
- Existing consumers stay on the `EndPoint` / `NetworkProtocol` surface;
  the umami primitive is additive.

## Prior history

See git log for changes before the CHANGELOG was introduced.
