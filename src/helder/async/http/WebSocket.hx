package helder.async.http;

import haxe.Exception;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.http.Http;

#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
import helder.async.http.AppleHttp.AppleWebSocket;
#end
#if (hxmc.target == "wasm32-wasi")
import helder.async.http.WebHttp.WebWebSocket;
#end
#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
import helder.async.http.WinHttp.WinWebSocket;
#end
#if (target.name == "hxmc" && (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64"))
import helder.async.http.AndroidHttp.AndroidSocket;
#end

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
class WebSocket {
	public var closed(default, null) = false;

	// where frames are written (the socket, or TLS on it), and how the connection ends
	final out:helder.async.Stream.Sink;
	final shut:() -> Void;
	final reader:Reader;
	// a client masks what it sends
	final client:Bool;
	final lock = new Lock();

	function new(out, shut, reader, client) {
		this.out = out;
		this.shut = shut;
		this.reader = reader;
		this.client = client;
	}

	// whether the request asks for a WebSocket
	public static function wants(req:Request):Bool
		return (req.header("upgrade") ?? "").toLowerCase() == "websocket" && req.header("sec-websocket-key") != null;

	// the request's connection taken over (Http.serve's handler returns null after)
	@:coroutine public static function upgrade(req:Request):WebSocket {
		if (!wants(req)) throw new Exception("not a WebSocket request");
		var accept = haxe.crypto.Base64.encode(haxe.crypto.Sha1.make(Bytes.ofString(req.header("sec-websocket-key") + GUID)));
		req.socket.writeString('HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: $accept\r\n\r\n');
		var s = req.socket;
		return new WebSocket(s, () -> s.close(), req.reader, false);
	}

	// a server's WebSocket on a connection of its own (TLS on an accepted
	// socket: TlsSocket.server): the upgrade request read from io, answered
	@:coroutine public static function accept(io:helder.async.Stream.Source, out:helder.async.Stream.Sink, shut:() -> Void):WebSocket {
		var r = new Reader(io), key:Null<String> = null;
		var line = r.readLine();
		if (line == null) throw new Exception("no WebSocket request");
		while ((line = r.readLine()) != null && line != "") {
			var colon = line.indexOf(":");
			if (colon > 0 && StringTools.trim(line.substr(0, colon)).toLowerCase() == "sec-websocket-key") key = StringTools.trim(line.substr(colon + 1));
		}
		if (key == null) {
			shut();
			throw new Exception("not a WebSocket request");
		}
		var accept = haxe.crypto.Base64.encode(haxe.crypto.Sha1.make(Bytes.ofString(key + GUID)));
		var reply = Bytes.ofString('HTTP/1.1 101 Switching Protocols\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-accept: $accept\r\n\r\n');
		out.write(reply, 0, reply.length);
		return new WebSocket(out, shut, r, false);
	}

	// a client's WebSocket to host:port at path (ws)
	@:coroutine public static function connect(host:String, port:Int, path = "/"):WebSocket {
		var s = Socket.connect(host, port);
		return handshake(s, s, () -> s.close(), '$host:$port', path);
	}

	// a client's WebSocket to a ws or wss url: the system's stack where there
	// is one (NSURLSession on macOS and iOS, WinHTTP on Windows, Java's
	// sockets under these frames on Android); else, or with a ca (PEM), wss
	// over mbedtls's TLS (TlsSocket: the system's roots, or ca's)
	@:coroutine public static function open(url:String, ?ca:String):WebSocket {
		#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
		// (macOS and iOS: NSURLSession's, the system's stack; a ca given: helder's own TLS)
		if (ca == null) {
			var ws = new WebSocket(null, () -> {}, null, true);
			ws.apple = AppleWebSocket.open(url);
			return ws;
		}
		#end
		// (the browser: the page's WebSocket)
		#if (hxmc.target == "wasm32-wasi")
		var ws = new WebSocket(null, () -> {}, null, true);
		ws.web = WebWebSocket.open(url);
		return ws;
		#end
		// (Windows: WinHTTP's; a ca given: helder's own TLS)
		#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
		if (ca == null) {
			var ws = new WebSocket(null, () -> {}, null, true);
			ws.win = WinWebSocket.open(url);
			return ws;
		}
		#end
		var u = Client.Url.parse(url);
		var host = u.host + (u.port == (u.secure ? 443 : 80) ? "" : ":" + u.port);
		// (Android: Java's sockets, its TLS, under these frames; a ca given: helder's own TLS)
		#if (target.name == "hxmc" && (hxmc.target == "android-arm64" || hxmc.target == "android-x86_64"))
		if (ca == null) {
			var s = AndroidSocket.connect(u.host, u.port, u.secure);
			return handshake(s, s, () -> s.close(), host, u.path);
		}
		#end
		var s = Socket.connect(u.host, u.port);
		if (!u.secure) return handshake(s, s, () -> s.close(), host, u.path);
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		var tls = try TlsSocket.client(s, u.host, ca == null ? null : sys.ssl.Certificate.fromString(ca)) catch (e:Exception) {
			s.close();
			throw e;
		}
		return handshake(tls, tls, () -> tls.abort(), host, u.path);
		#else
		s.close();
		throw new Exception('wss needs a native target here: $url');
		#end
	}

	@:coroutine static function handshake(io:helder.async.Stream.Source, out:helder.async.Stream.Sink, shut:() -> Void, host:String,
			path:String):WebSocket {
		var key = haxe.crypto.Base64.encode(Bytes.ofString(Std.string(Math.random()).substr(0, 16)));
		var req = Bytes.ofString('GET $path HTTP/1.1\r\nhost: $host\r\nupgrade: websocket\r\nconnection: Upgrade\r\nsec-websocket-key: $key\r\nsec-websocket-version: 13\r\n\r\n');
		out.write(req, 0, req.length);
		var r = new Reader(io);
		var status = r.readLine();
		if (status == null || status.indexOf(" 101 ") < 0) {
			shut();
			throw new Exception('WebSocket to $host$path: $status');
		}
		while (true) {
			var h = r.readLine();
			if (h == null || h == "") break;
		}
		return new WebSocket(out, shut, r, true);
	}

	#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
	// (the system's WebSocket, NSURLSession's, in place of the frames here)
	var apple:Null<AppleWebSocket> = null;
	#end

	#if (hxmc.target == "wasm32-wasi")
	var web:Null<WebWebSocket> = null;
	#end

	#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
	var win:Null<WinWebSocket> = null;
	#end

	// the next message; null once closed
	@:coroutine public function receive():Null<String> {
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) {
			var m = web.receive();
			if (m == null) closed = true;
			return m;
		}
		#end
		#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
		if (apple != null) {
			var m = apple.receive();
			if (m == null) closed = true;
			return m;
		}
		#end
		#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
		if (win != null) {
			var m = win.receive();
			if (m == null) closed = true;
			return m;
		}
		#end
		var parts:Null<haxe.io.BytesBuffer> = null;
		while (!closed) {
			var head = try reader.readBytes(2) catch (e:haxe.io.Eof) null;
			if (head == null) {
				end();
				return null;
			}
			var fin = head.get(0) & 0x80 != 0, op = head.get(0) & 0x0F;
			var masked = head.get(1) & 0x80 != 0;
			var n = head.get(1) & 0x7F;
			if (n == 126) {
				var e = reader.readBytes(2);
				n = (e.get(0) << 8) | e.get(1);
			} else if (n == 127) {
				var e = reader.readBytes(8);
				n = (e.get(4) << 24) | (e.get(5) << 16) | (e.get(6) << 8) | e.get(7);
			}
			var mask = masked ? reader.readBytes(4) : null;
			var data = n > 0 ? reader.readBytes(n) : Bytes.alloc(0);
			if (mask != null) for (i in 0...n)
				data.set(i, data.get(i) ^ mask.get(i & 3));
			switch op {
				case 0x8:
					if (!closed) frame(0x8, data);
					end();
					return null;
				case 0x9:
					frame(0xA, data);
				case 0xA:
				case _:
					if (fin && parts == null) return data.toString();
					parts ??= new haxe.io.BytesBuffer();
					parts.add(data);
					if (fin) return parts.getBytes().toString();
			}
		}
		return null;
	}

	@:coroutine public function send(text:String):Void {
		#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
		if (apple != null) return apple.send(text);
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) return web.send(text);
		#end
		#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
		if (win != null) return win.send(text);
		#end
		frame(0x1, Bytes.ofString(text));
	}

	@:coroutine public function ping():Void {
		#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
		if (apple != null) return apple.ping();
		#end
		#if (hxmc.target == "wasm32-wasi")
		// (the browser's WebSocket answers pings itself and sends none of its own)
		if (web != null) return;
		#end
		// (WinHTTP sends its own pings, and no other)
		#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
		if (win != null) return;
		#end
		frame(0x9, Bytes.alloc(0));
	}

	// a close sent (the other side's answer ends receive), the connection closed
	@:coroutine public function close(code = 1000):Void {
		if (closed) return;
		#if (target.name == "hxmc" && (hxmc.target == "macos-arm64" || hxmc.target == "macos-x86_64" || hxmc.target == "ios-arm64" || hxmc.target == "ios-sim-arm64"))
		if (apple != null) {
			closed = true;
			apple.close(code);
			return;
		}
		#end
		#if (hxmc.target == "wasm32-wasi")
		if (web != null) {
			closed = true;
			web.close(code);
			return;
		}
		#end
		#if (target.name == "hxmc" && (hxmc.target == "windows-x86_64" || hxmc.target == "windows-arm64"))
		if (win != null) {
			closed = true;
			win.close(code);
			return;
		}
		#end
		var b = Bytes.alloc(2);
		b.set(0, code >> 8);
		b.set(1, code & 0xFF);
		try frame(0x8, b) catch (_:Exception) {}
		end();
	}

	function end() {
		closed = true;
		shut();
	}

	@:coroutine function frame(op:Int, data:Bytes):Void {
		if (closed) throw new Exception("WebSocket closed");
		var n = data.length;
		var ext = n < 126 ? 0 : n < 65536 ? 2 : 8;
		var b = Bytes.alloc(2 + ext + (client ? 4 : 0) + n);
		b.set(0, 0x80 | op);
		b.set(1, (client ? 0x80 : 0) | (ext == 0 ? n : ext == 2 ? 126 : 127));
		if (ext == 2) {
			b.set(2, n >> 8);
			b.set(3, n & 0xFF);
		} else if (ext == 8) for (i in 0...4)
			b.set(6 + i, (n >> (24 - 8 * i)) & 0xFF);
		var at = 2 + ext;
		if (client) {
			for (i in 0...4)
				b.set(at + i, Std.random(256));
			for (i in 0...n)
				b.set(at + 4 + i, data.get(i) ^ b.get(at + (i & 3)));
		} else b.blit(at, data, 0, n);
		lock.acquire();
		try out.write(b, 0, b.length) catch (e:Exception) {
			lock.release();
			throw e;
		}
		lock.release();
	}

	static inline var GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
}
