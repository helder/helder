package studio;

#if !(hxmc.target == "wasm32-wasi")
import haxe.Json;
import helder.async.Async;
import helder.async.http.WebSocket;

// A request to the program helder dev runs, through its devtools (a tool's
// WebSocket at /__helder/devtools, helder.cli.Devtools relaying it): its
// answer ({result} or {error}); null when none came within seconds
class DevCall {
	@:coroutine public static function call(url:String, method:String, params:Dynamic, seconds = 10.0):Null<Dynamic> {
		var ws = try WebSocket.open(url) catch (_:Dynamic) null;
		if (ws == null) return null;
		var answer:Dynamic = null, done = false;
		// (no answer: the socket closed under its read)
		Async.launch(_ -> {
			Async.delay(seconds);
			if (!done) try ws.close() catch (_:Dynamic) {}
		});
		try {
			ws.send(Json.stringify({jsonrpc: "2.0", id: 1, method: method, params: params}));
			while (answer == null) {
				var m = ws.receive();
				if (m == null) break;
				var j:Dynamic = try Json.parse(m) catch (_:Dynamic) null;
				if (j != null && j.id == 1) answer = j;
			}
		} catch (_:Dynamic) {}
		done = true;
		try ws.close() catch (_:Dynamic) {}
		return answer;
	}
}
#end
