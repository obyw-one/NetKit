# Changelog

All notable changes to NetKit are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [Unreleased]

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
