# @obyw-one/netkit-web

TypeScript HTTP and WebSocket networking — the TS sibling of [obyw-one/NetKit](../README.md) (Swift).

Mirrors the Swift `NetworkKit` surface symbol-for-symbol:

| Swift (NetKit)       | TypeScript (@obyw-one/netkit-web) |
|----------------------|-------------------------------------|
| `EndPoint` protocol  | `EndPoint` interface                |
| `RequestMethod` enum | `RequestMethod` union               |
| `NetworkError` enum  | `NetworkError` class (discriminated union) |
| `NetworkService`     | `HTTPClient` class                  |
| `WebSocketClient` actor | `WebSocketClient` class          |
| `WebSocketMessage`   | `WebSocketMessage` type             |
| `WebSocketState`     | `WebSocketState` type               |

Zero runtime dependencies. ~6 KB gzipped. ES2022 + DOM.

---

## Install

```bash
npm install @obyw-one/netkit-web
```

---

## Usage

### HTTPClient

```ts
import { HTTPClient } from "@obyw-one/netkit-web";
import type { EndPoint } from "@obyw-one/netkit-web";

// Define an endpoint (implement the EndPoint interface)
const listUsers: EndPoint = {
  host: "api.example.com",
  scheme: "https",
  apiPath: "/api/v1",
  path: "/users",
  method: "GET",
  header: { Authorization: "Bearer token123" },
};

const client = new HTTPClient({
  timeoutMs: 10_000,
  retry: { maxAttempts: 3, baseDelayMs: 200 },
  defaultHeaders: { "X-App-Version": "1.0.0" },
});

interface User { id: number; name: string; }
const users = await client.sendRequest<User[]>(listUsers);
```

### EndPoint

```ts
import { buildURL, buildRequest } from "@obyw-one/netkit-web";
import type { EndPoint } from "@obyw-one/netkit-web";

const search: EndPoint = {
  host: "api.example.com",
  path: "/search",
  method: "GET",
  queryParams: { q: "hello", page: 1 },
};

const url = buildURL(search);
// → https://api.example.com/search?q=hello&page=1
```

### NetworkError

```ts
import { NetworkError } from "@obyw-one/netkit-web";

try {
  await client.sendRequest(endpoint);
} catch (err) {
  if (err instanceof NetworkError) {
    switch (err.variant.kind) {
      case "unexpectedStatusCode":
        console.error(`HTTP ${err.variant.statusCode}`);
        break;
      case "requestFailed":
        console.error(`Transport error: ${err.variant.description}`);
        break;
      case "jsonParsingFailed":
        console.error("Decode failed:", err.variant.cause);
        break;
    }
  }
}
```

### JSONCoder

```ts
import { JSONCoder, epochCoder } from "@obyw-one/netkit-web";

// Default: iso8601 dates
const coder = new JSONCoder();
const json = coder.encode({ createdAt: new Date() });
// → '{"createdAt":"2024-06-15T12:00:00.000Z"}'

// Epoch ms dates
const ms = epochCoder.encode({ createdAt: new Date() });
// → '{"createdAt":1718452800000}'
```

### WebSocketClient

```ts
import { WebSocketClient, WebSocketMessage } from "@obyw-one/netkit-web";

const ws = new WebSocketClient("wss://example.com/ws");

ws.onMessage = (msg) => {
  if (msg.kind === "text") {
    console.log("received:", msg.value);
  }
};

ws.onStateChange = (state) => {
  console.log("state:", state.kind);
};

await ws.connect();

ws.sendText(JSON.stringify({ event: "ping" }));

// Later:
ws.disconnect();
```

---

## API Reference

### `HTTPClient`

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `timeoutMs` | `number` | `30_000` | Per-attempt abort timeout |
| `retry.maxAttempts` | `number` | `3` | Max total attempts (1 = no retry) |
| `retry.baseDelayMs` | `number` | `200` | Base exponential-backoff delay |
| `retry.retryableStatusCodes` | `number[]` | `[429,500,502,503,504]` | Status codes that trigger retry |
| `defaultHeaders` | `Record<string,string>` | `{}` | Merged into every request |
| `fetchImpl` | `typeof fetch` | `globalThis.fetch` | Override for testing |

### `NetworkError` variants

| Variant | Mirrors Swift case | Payload |
|---------|-------------------|---------|
| `requestFailed` | `.requestFailed(description:)` | `description: string` |
| `unexpectedStatusCode` | `.unexpectedStatusCode(_:headers:)` | `statusCode: number; headers?: string` |
| `invalidData` | `.invalidData` | — |
| `jsonParsingFailed` | `.jsonParsingFailed(_:)` | `cause: unknown` |
| `wsError` | `.wsError(description:)` | `description: string` |
| `unknown` | `.unknown(_:)` | `cause: unknown` |

### `WebSocketClient`

| Method | Description |
|--------|-------------|
| `connect()` | Opens the connection, returns `Promise<void>` |
| `disconnect()` | Gracefully closes (code 1000) |
| `send(message)` | Sends text or binary message |
| `sendText(text)` | Convenience text sender |
| `sendData(data)` | Convenience binary sender |

---

## Development

```bash
cd web/
npm install
npm run typecheck   # tsc --noEmit
npm run build       # rollup → dist/index.js
npm run test        # vitest run (83 tests across 6 files)
```

---

## License

Apache-2.0 — see [LICENSE](../LICENSE) (the same licence as Swift NetKit).

Swift parent docs: [../README.md](../README.md)
