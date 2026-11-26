package helder.async.http;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.io.BytesBuffer;
import helder.async.*;
import helder.async.Errors;

// An HTTP/1.1 client on helder.async's TCP (one connection a request): the
// body read by Content-Length, chunked or until the server closes. No
// redirects, no compression asked for. An https URL goes to the system's
// stack where there is one: NSURLSession on macOS and iOS (helder.async.http.apple.Http: its
// TLS, redirects, HTTP/2 and cache); elsewhere natively this client over
// mbedtls's TLS (TlsSocket: the system's roots, or the ca given); in the
// browser the page's fetch for every url (helder.async.http.web.Http). In a
// scenario's screen its fixtures answer instead (Fixtures: a scenario's http).
//
//   var res = Client.request("http://127.0.0.1:4983/", {method: "POST", body: '{"type":"init"}',
//     headers: ["content-type" => "application/json"]});
//   trace(res.status, res.text());
class Client {
	@:coroutine public static function request(url:String, ?options:RequestOptions):Reply {
		// (a scenario's screen: its fixtures answer, nothing goes out: Fixtures)
		var fixtures:Null<Fixtures> = helder.view.graph.Atoms.current?.http;
		if (fixtures != null) return fixtures.answer((options?.method ?? "GET").toUpperCase(), url);
		// (the browser: its fetch, for every url: no sockets there)
		#if (hxmc.target == "wasm32-wasi")
		return helder.async.http.web.Http.request(url, options);
		#end
		// (Windows: WinHTTP, http and https, the system's proxies and certificates; a ca given: helder's own TLS)
		#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
		if (options?.ca == null) return helder.async.http.windows.Http.request(url, options);
		#end
		// (Android: HttpURLConnection, the app's network security config; a ca given: helder's own TLS)
		#if (target.name == "hxmc" && (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64"))
		if (options?.ca == null) return helder.async.http.android.Http.request(url, options);
		#end
		// (https: the system's stack where there is one; macOS and iOS: helder.async.http.apple.Http)
		if (StringTools.startsWith(url, "https://")) {
			#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
			if (options?.ca == null) return helder.async.http.apple.Http.request(url, options);
			#elseif (target.name != "hxmc" || hxmc.target == "wasm32-wasi")
			throw new Exception('https needs a native target here: $url');
			#end
		}
		var u = Url.parse(url);
		var method = options?.method ?? "GET";
		var body = options?.body ?? (options?.text != null ? Bytes.ofString(options.text) : Bytes.alloc(0));
		var head = new StringBuf();
		head.add('$method ${u.path} HTTP/1.1\r\nhost: ${u.host}${u.port == (u.secure ? 443 : 80) ? "" : ":" + u.port}\r\nconnection: close\r\n');
		final given = options?.headers ?? new Map();
		for (k => v in given)
			head.add('$k: $v\r\n');
		if (options?.contentType != null && !given.exists("content-type")) head.add('content-type: ${options.contentType}\r\n');
		if (body.length > 0 || method != "GET") head.add('content-length: ${body.length}\r\n');
		head.add("\r\n");
		var s = Socket.connect(u.host, u.port);
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		// (https: TLS on the connection, mbedtls's)
		var tls:Null<TlsSocket> = null;
		if (u.secure) {
			try {
				tls = TlsSocket.client(s, u.host, options?.ca == null ? null : sys.ssl.Certificate.fromString(options.ca));
			} catch (e:Exception) {
				s.close();
				throw Errors.kept(e);
			}
		}
		var io:helder.async.Stream.Source = tls ?? s, out:helder.async.Stream.Sink = tls ?? s;
		#else
		var io:helder.async.Stream.Source = s, out:helder.async.Stream.Sink = s;
		#end
		try {
			var h = Bytes.ofString(head.toString());
			var all = Bytes.alloc(h.length + body.length);
			all.blit(0, h, 0, h.length);
			all.blit(h.length, body, 0, body.length);
			out.write(all, 0, all.length);
			var reply = read(new Reader(io), method == "HEAD");
			close(s #if (target.name == "hxmc" && hxmc.target != "wasm32-wasi"), tls #end);
			return reply;
		} catch (e:Exception) {
			close(s #if (target.name == "hxmc" && hxmc.target != "wasm32-wasi"), tls #end);
			throw Errors.kept(e);
		}
	}

	@:coroutine static function close(s:Socket #if (target.name == "hxmc" && hxmc.target != "wasm32-wasi"), tls:Null<TlsSocket> #end) {
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		if (tls != null) {
			tls.close();
			return;
		}
		#end
		s.close();
	}

	@:coroutine static function read(r:Reader, head:Bool):Reply {
		var line = r.readLine();
		if (line == null) throw new Exception("no response");
		var parts = line.split(" ");
		var status = Std.parseInt(parts[1] ?? "");
		if (status == null) throw new Exception("bad status line");
		var headers = new Map<String, String>();
		while (true) {
			var h = r.readLine();
			if (h == null) throw new Exception("end of headers missing");
			if (h == "") break;
			var i = h.indexOf(":");
			if (i <= 0) continue;
			var k = h.substr(0, i).toLowerCase(), v = StringTools.trim(h.substr(i + 1));
			headers.set(k, headers.exists(k) ? headers.get(k) + ", " + v : v);
		}
		if (head || status == 204 || status == 304) return new Reply(status, headers, Bytes.alloc(0));
		var length = headers.get("content-length");
		if (length != null) return new Reply(status, headers, r.readBytes(Std.parseInt(length) ?? 0));
		if ((headers.get("transfer-encoding") ?? "").toLowerCase().indexOf("chunked") >= 0) return new Reply(status, headers, chunked(r));
		return new Reply(status, headers, r.readAll());
	}

	@:coroutine static function chunked(r:Reader):Bytes {
		var out = new BytesBuffer();
		while (true) {
			var size = r.readLine();
			if (size == null) throw new Exception("chunk missing");
			var semi = size.indexOf(";");
			var n = Std.parseInt("0x" + StringTools.trim(semi < 0 ? size : size.substr(0, semi)));
			if (n == null) throw new Exception("bad chunk size");
			if (n == 0) {
				// (trailers until the blank line)
				while (true) {
					var t = r.readLine();
					if (t == null || t == "") break;
				}
				return out.getBytes();
			}
			out.add(r.readBytes(n));
			r.readLine();
		}
	}
}

typedef RequestOptions = {
	?method:String,
	// names as given, sent as they are
	?headers:Map<String, String>,
	?body:Bytes,
	// the body as text (UTF-8), when body is not given
	?text:String,
	// its content-type header ("application/json")
	?contentType:String,
	// https: the roots trusted instead of the system's (PEM): a test's own
	// certificate; helder's own TLS then, also where the system has a stack
	?ca:String
}

class Reply {
	public final status:Int;
	// names in lower case
	public final headers:Map<String, String>;
	public final body:Bytes;

	public function new(status, headers, body) {
		this.status = status;
		this.headers = headers;
		this.body = body;
	}

	public inline function header(name:String):Null<String>
		return headers.get(name.toLowerCase());

	public function text():String
		return body.toString();
}

class Url {
	public final host:String;
	public final port:Int;
	public final path:String;
	public final secure:Bool;

	function new(host, port, path, secure) {
		this.host = host;
		this.port = port;
		this.path = path;
		this.secure = secure;
	}

	// an http, https, ws or wss url (ws: http's, wss: https's)
	public static function parse(url:String):Url {
		var scheme = url.indexOf("://");
		var secure = switch scheme < 0 ? "" : url.substr(0, scheme).toLowerCase() {
			case "http" | "ws": false;
			case "https" | "wss": true;
			case _: throw new Exception('only http, https, ws and wss urls: $url');
		}
		var rest = url.substr(scheme + 3);
		var slash = rest.indexOf("/");
		var authority = slash < 0 ? rest : rest.substr(0, slash);
		var path = slash < 0 ? "/" : rest.substr(slash);
		var colon = authority.lastIndexOf(":");
		if (colon < 0) return new Url(authority, secure ? 443 : 80, path, secure);
		var port = Std.parseInt(authority.substr(colon + 1));
		if (port == null) throw new Exception('bad port: $url');
		return new Url(authority.substr(0, colon), port, path, secure);
	}
}
