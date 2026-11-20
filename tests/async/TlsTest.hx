import haxe.io.Bytes;
import helder.async.*;

// helder.async's TLS by mbedtls (TlsSocket), natively, in one process: a
// server on 127.0.0.1 with tests/async/tls's certificate for localhost, a
// client trusting it: the handshake both ways, messages each way (one larger
// than a record), the end of the stream after the server's close; a client
// trusting only the system's roots refused (the certificate is
// self-signed); a name the certificate does not have refused; https through
// Client.request and wss through WebSocket.open, trusting it.
//   TlsTest
class TlsTest {
	static var failed = 0;
	static var checks = 0;

	static function check(what:String, ok:Bool, ?detail:String) {
		checks++;
		if (!ok) {
			failed++;
			Sys.println('TlsTest: FAIL: $what' + (detail == null ? "" : ": " + detail));
		}
	}

	static function main() {
		var root = Sys.getEnv("TLS_DIR") ?? "tests/async/tls";
		var cert = sys.ssl.Certificate.loadFile('$root/cert.pem'), key = sys.ssl.Key.loadFile('$root/key.pem');
		Async.run(task -> {
			var server = Server.listen("127.0.0.1", 0), port = server.port;
			var big = Bytes.alloc(100000);
			for (i in 0...big.length)
				big.set(i, i * 7 & 255);
			task.async(_ -> {
				var s = TlsSocket.server(server.accept(), cert, key);
				var r = new Reader(s);
				var line = r.readLine();
				s.writeString('echo $line\n');
				var got = r.readBytes(big.length);
				s.writeString(got.compare(big) == 0 ? "same\n" : "different\n");
				s.close();
			});
			var c = TlsSocket.client(Socket.connect("127.0.0.1", port), "localhost", cert);
			c.writeString("hello\n");
			var r = new Reader(c);
			check("a line echoed over TLS", r.readLine() == "echo hello");
			c.write(big, 0, big.length);
			check("100 KB across records, intact", r.readLine() == "same");
			check("the end after the server's close", r.readLine() == null);
			c.close();

			// (the system's roots: a self-signed certificate refused)
			task.async(_ -> try TlsSocket.server(server.accept(), cert, key) catch (_) null);
			var refused = try {
				TlsSocket.client(Socket.connect("127.0.0.1", port), "localhost");
				false;
			} catch (e) true;
			check("a self-signed certificate refused against the system's roots", refused);

			// (a name the certificate does not have)
			task.async(_ -> try TlsSocket.server(server.accept(), cert, key) catch (_) null);
			var wrongName = try {
				TlsSocket.client(Socket.connect("127.0.0.1", port), "example.com", cert);
				false;
			} catch (e) true;
			check("another name refused", wrongName);
			// (https through Client.request, its own roots given: a POST, its body back)
			var pem = sys.io.File.getContent('$root/cert.pem');
			task.async(_ -> {
				var t = TlsSocket.server(server.accept(), cert, key);
				var r = new Reader(t), line, length = 0;
				var first = r.readLine();
				while ((line = r.readLine()) != null && line != "")
					if (StringTools.startsWith(line.toLowerCase(), "content-length:")) length = Std.parseInt(StringTools.trim(line.substr(15)));
				var body = r.readBytes(length).toString();
				var text = '$first|$body';
				t.writeString('HTTP/1.1 200 OK\r\ncontent-type: text/plain\r\ncontent-length: ${Bytes.ofString(text).length}\r\n\r\n$text');
				t.close();
			});
			var reply = helder.async.http.Client.request('https://localhost:$port/echo', {method: "POST", text: "hi", ca: pem});
			check("https through Client.request", reply.status == 200 && reply.text() == "POST /echo HTTP/1.1|hi", reply.status + " " + reply.text());

			// (wss through WebSocket.open: messages both ways, a close)
			task.async(_ -> {
				var t = TlsSocket.server(server.accept(), cert, key);
				var ws = helder.async.http.WebSocket.accept(t, t, () -> t.abort());
				var m;
				while ((m = ws.receive()) != null)
					ws.send("echo " + m);
			});
			var ws = helder.async.http.WebSocket.open('wss://localhost:$port/ws', pem);
			ws.send("one");
			check("wss: a message echoed", ws.receive() == "echo one");
			var long = StringTools.lpad("", "x", 70000);
			ws.send(long);
			check("wss: a long message echoed", ws.receive() == "echo " + long);
			ws.close();
			server.close();
		});
		Sys.println('TlsTest: $checks checks' + (failed == 0 ? ", ok" : ', $failed failed'));
		Sys.exit(failed == 0 && checks >= 8 ? 0 : 1);
	}
}
