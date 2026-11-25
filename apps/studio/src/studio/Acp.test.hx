package studio;

import haxe.Json;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.Stream;
import helder.test.Test;
import studio.Acp;

// ACP's JSON-RPC peer on chunks of bytes: lines split anywhere, several in a
// chunk; requests answered by method (-32601 without one); responses
// matched by id, errors thrown, what waits failed when it closes
function tests() {
	describe("Acp", () -> {
		test("lines split anywhere, several a chunk", async(() -> {
			var out = new Written();
			var a = new Acp(new Chunks([
				'{"jsonrpc":"2.0","method":"note","params":{"n":1}}\n{"jsonrpc":"2.0","me',
				'thod":"note","params":{"n":2}}',
				'\n\n{"jsonrpc":"2.0","method":"note","params":{"n":"é"}}\n{"jsonrpc":"2.0","method":"note","params":{"n":4}}'
			]), out);
			var got = [];
			a.onNotification = (m, p) -> got.push(m + p.n);
			Async.scope(task -> a.run(task));
			equals(got, ["note1", "note2", "noteé", "note4"]);
			assert(a.closed);
		}));
		test("requests answered by method", async(() -> {
			var out = new Written();
			var a = new Acp(new Chunks([
				'{"jsonrpc":"2.0","id":7,"method":"echo","params":{"x":1}}\n',
				'{"jsonrpc":"2.0","id":"k","method":"nope"}\n{"jsonrpc":"2.0","id":8,"method":"fail"}\n'
			]), out);
			a.handle("echo", p -> p);
			a.handle("fail", _ -> throw new AcpError(-32002, "gone"));
			Async.scope(task -> a.run(task));
			var replies:Array<Dynamic> = [for (l in out.text.split("\n")) if (l != "") Json.parse(l)];
			replies.sort((x, y) -> Std.string(x.id) < Std.string(y.id) ? -1 : 1);
			equals([replies[0].jsonrpc, replies[0].id, replies[0].result], ["2.0", 7, {x: 1}]);
			equals([replies[1].id, replies[1].error.code], [8, -32002]);
			equals([replies[2].id, replies[2].error.code], ["k", -32601]);
		}));
		test("responses by id, errors thrown, what waits failed at the end", async(() -> {
			var loop = new Loopback();
			var a = new Acp(loop, loop);
			Async.scope(task -> {
				task.async(t -> a.run(t));
				var never = task.async(_ -> try {
					a.request("never", {});
					"answered";
				} catch (e:AcpError) e.message);
				equals(a.request("add", {a: 1, b: 2}), 3);
				var e:Dynamic = throwsAsync(() -> a.request("fail", {}));
				equals((e : AcpError).code, -5);
				loop.end();
				equals(never.await(), "closed: the end of its output");
			});
		}));
	});
}

// (a source of these chunks, one a read, then the end)
private class Chunks implements Source {
	final chunks:Array<String>;

	public function new(chunks)
		this.chunks = chunks;

	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int {
		Async.yield();
		var c = chunks.shift();
		if (c == null) return 0;
		var bytes = Bytes.ofString(c);
		b.blit(pos, bytes, 0, bytes.length);
		return bytes.length;
	}
}

private class Written implements Sink {
	public var text = "";

	public function new() {}

	@:coroutine public function write(b:Bytes, pos:Int, len:Int)
		text += b.getString(pos, len);
}

// (a peer answering "add" with the sum, "fail" with an error, nothing else)
private class Loopback implements Source implements Sink {
	final queue:Array<String> = [];
	var ended = false;

	public function new() {}

	public function end()
		ended = true;

	@:coroutine public function write(b:Bytes, pos:Int, len:Int) {
		var m:Dynamic = Json.parse(b.getString(pos, len));
		if (m.method == "add") queue.push(Json.stringify({jsonrpc: "2.0", id: m.id, result: m.params.a + m.params.b}) + "\n");
		if (m.method == "fail") queue.push(Json.stringify({jsonrpc: "2.0", id: m.id, error: {code: -5, message: "no"}}) + "\n");
	}

	@:coroutine public function read(b:Bytes, pos:Int, len:Int):Int {
		while (queue.length == 0 && !ended)
			Async.delay(0.001);
		if (queue.length == 0) return 0;
		var bytes = Bytes.ofString(queue.shift());
		b.blit(pos, bytes, 0, bytes.length);
		return bytes.length;
	}
}
