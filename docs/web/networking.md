# Networking

HTTP requests and WebSockets go through each platform's own network stack, so they get its TLS, its certificates, its proxies and its rules. In the browser they are the page's own `fetch` and WebSocket. On a desktop you can also serve HTTP and WebSockets yourself.

| Platform | Requests | WebSockets |
|---|---|---|
| macOS, iOS | NSURLSession | NSURLSession |
| Windows | WinHTTP | WinHTTP |
| Android | HttpURLConnection | helder's frames over the system's TLS |
| Linux | helder's client over mbedtls | helder's, over mbedtls |
| Web | `fetch` | the browser's WebSocket |

```ts
import { Client, WebSocket } from "helder/async";

const res = await Client.request("https://api.example.com/items");
const items = JSON.parse(res.text());

const ws = await WebSocket.open("wss://chat.example.com/room");
await ws.send("hello");
const reply = await ws.receive();
```

```haxe
import helder.async.http.*;

// in a coroutine: no await
var res = Client.request("https://api.example.com/items");
var items = haxe.Json.parse(res.text());

var ws = WebSocket.open("wss://chat.example.com/room");
ws.send("hello");
var reply = ws.receive();
```

## What else

- **Async in Haxe:** coroutines with structured concurrency: tasks, cancellation, timeouts and timers on one loop per thread.
- **A server:** `Http.serve` for HTTP/1.1 and WebSocket upgrades, files served from a folder, as helder's own dev server does.
- **Sockets and processes** natively: TCP, child processes, file watching.
- **Work on other threads:** `helder.jobs` runs work off the main thread without blocking frames.
- **Coming:** network status and push notifications.

<Reference to="async,jobs"/>
