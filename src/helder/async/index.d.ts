// helder.async for TypeScript programs (helder.typescript): a program's
// promises and timers already run on helder.async's loop (its async
// functions as the graph's async computations, typescript's README); these are
// helder.async's own tasks, each a promise to the program (a Task<T> is a
// Promise<T>). Its HTTP client and server are a whole package: their
// coroutines are the program's async functions (helder.typescript.api.Coroutines).
//
// Generated from helder's Haxe types (helder.typescript.api.Declarations: node
// src/helder/typescript/api/declarations.mjs); edit the Haxe, not this file.

declare const __haxe: {Client: "helder.async.http.Client", Reply: "helder.async.http.Client.Reply", Url: "helder.async.http.Client.Url", Http: "helder.async.http.Http", Request: "helder.async.http.Http.Request", Response: "helder.async.http.Http.Response", WebSocket: "helder.async.http.WebSocket", delay: "helder.async.Tasks.delay", readBytes: "helder.async.Tasks.bytes", __module: "helder.async.TypeScript"};

export type RequestOptions = { method?: string; headers?: unknown; body?: Uint8Array; text?: string; contentType?: string; ca?: string };

// An HTTP/1.1 client on helder.async's TCP (one connection a request): the
// body read by Content-Length, chunked or until the server closes. No
// redirects, no compression asked for. An https URL goes to the system's
// stack where there is one: NSURLSession on macOS and iOS (helder.async.http.apple.Http: its
// TLS, redirects, HTTP/2 and cache); elsewhere natively this client over
// mbedtls's TLS (TlsSocket: the system's roots, or the ca given); in the
// browser the page's fetch for every url (helder.async.http.web.Http).
//
//   var res = Client.request("http://127.0.0.1:4983/", {method: "POST", body: '{"type":"init"}',
//     headers: ["content-type" => "application/json"]});
//   trace(res.status, res.text());
export declare class Client {
	static request(url: string, options?: RequestOptions): Promise<Reply>;
}

export declare class Reply {
	constructor(status: number, headers: unknown, body: Uint8Array);
	readonly status: number;
	// names in lower case
	readonly headers: unknown;
	readonly body: Uint8Array;
	header(name: string): string | null;
	text(): string;
}

export declare class Url {
	// an http, https, ws or wss url (ws: http's, wss: https's)
	static parse(url: string): Url;
	readonly host: string;
	readonly port: number;
	readonly path: string;
	readonly secure: boolean;
}

// A minimal HTTP/1.1 server on helder.async's TCP: enough for a dev server.
// Each connection is a child task of the caller's; its requests (kept alive)
// go to the handler in turn, whose Response is written back; a null one
// means the handler took the connection over (WebSocket.upgrade). Bodies
// by Content-Length (no chunked requests); an error in the handler is a 500
// and the connection closed, the server going on.
//
//   var server = Server.listen("127.0.0.1", 8080);
//   Http.serve(server, req -> Http.file("public", req.path) ?? Response.text("not found", 404));
export declare class Http {
	// the file at root + path (its index.html for a directory), as a response
	// with its type; null when there is none (or the path leaves root)
	static file(root: string, path: string): Response | null;
	static mime(path: string): string;
}

export declare class Request {
	readonly method: string;
	// decoded, without the query
	readonly path: string;
	readonly query: string;
	readonly version: string;
	// names in lower case
	readonly headers: unknown;
	readonly body: Uint8Array;
	header(name: string): string | null;
	keepAlive(): boolean;
}

export declare class Response {
	constructor(status?: number, body?: Uint8Array);
	static text(s: string, status?: number, type?: string): Response;
	status: number;
	// names in lower case
	readonly headers: unknown;
	body: Uint8Array;
}

// A WebSocket (RFC 6455) on a connection: a server's, from an HTTP request
// (upgrade), or a client's (connect). Messages are text (binary ones come
// as their bytes' string); pings are answered, fragments joined, a close
// answered. Sends are whole messages, one at a time (a Lock), so several
// tasks may send while one receives.
//
//   Http.serve(server, req -> {
//     if (req.path != "/ws") return Http.file("public", req.path);
//     var ws = WebSocket.upgrade(req);
//     var m; while ((m = ws.receive()) != null) ws.send("echo " + m);
//     null;
//   });
export declare class WebSocket {
	// whether the request asks for a WebSocket
	static wants(req: Request): boolean;
	// the request's connection taken over (Http.serve's handler returns null after)
	static upgrade(req: Request): Promise<WebSocket>;
	// a client's WebSocket to host:port at path (ws)
	static connect(host: string, port: number, path?: string): Promise<WebSocket>;
	// a client's WebSocket to a ws or wss url: the system's stack where there
	// is one (NSURLSession on macOS and iOS, WinHTTP on Windows, Java's
	// sockets under these frames on Android); else, or with a ca (PEM), wss
	// over mbedtls's TLS (TlsSocket: the system's roots, or ca's)
	static open(url: string, ca?: string): Promise<WebSocket>;
	readonly closed: boolean;
	// the next message; null once closed
	receive(): Promise<string | null>;
	send(text: string): Promise<void>;
	ping(): Promise<void>;
	// a close sent (the other side's answer ends receive), the connection closed
	close(code?: number): Promise<void>;
}

// done after that many seconds
export declare function delay(seconds: number): Promise<void>;
// a file's bytes: natively read, in the browser fetched (Fetch.bytes)
export declare function readBytes(path: string): Promise<Uint8Array>;

export {};
