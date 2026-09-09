# Changelog

All notable changes to NetKit are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
