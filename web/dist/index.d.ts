/**
 * index.ts — NetKit Web public API
 *
 * Re-exports every public symbol from @obyw-one/netkit-web.
 * Import granularly for tree-shaking:
 *
 *   import { HTTPClient } from "@obyw-one/netkit-web";
 *   import type { EndPoint } from "@obyw-one/netkit-web";
 */
export { NetworkError, type NetworkErrorKind, type NetworkErrorVariant, type RequestFailedError, type UnexpectedStatusCodeError, type InvalidDataError, type JsonParsingFailedError, type WsError, type UnknownError, } from "./NetworkError.js";
export { buildURL, buildRequest, type EndPoint, type RequestMethod, type QueryParams, type QueryParamValue, } from "./EndPoint.js";
export { HTTPClient, type HTTPClientOptions, type RetryOptions, } from "./HTTPClient.js";
export { JSONCoder, defaultCoder, epochCoder, type DateEncodingStrategy, type DateDecodingStrategy, type JSONCoderOptions, } from "./JSONCoder.js";
export { WebSocketClient, WebSocketMessage, WebSocketState, type WebSocketClientOptions, type WebSocketMessageKind, type TextMessage, type DataMessage, type WebSocketState as WebSocketStateType, type MessageListener, type ErrorListener, type StateChangeListener, } from "./WebSocketClient.js";
