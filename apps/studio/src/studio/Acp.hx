package studio;

import haxe.Exception;
import haxe.Json;
import haxe.coro.Coroutine;
import haxe.coro.IContinuation;
import haxe.io.Bytes;
import helder.async.*;
import helder.async.Stream;

using StringTools;

// A JSON-RPC 2.0 peer over newline-delimited JSON (the Agent Client
// Protocol's stdio transport): requests sent and their responses matched by
// id, notifications both ways, the other side's requests answered by the
// handler of their method (none: -32601). It knows nothing of agents
// (AcpAgent speaks ACP through it). Natively it runs a process
// (Acp.spawn: its stdin and stdout the messages', its stderr lines logs);
// any Source and Sink do (the tests' chunks).
//
//   var a = Acp.spawn("npx", ["-y", "some-agent"], {cwd: dir});
//   Async.launch(task -> a.run(task));
//   var r = a.request("initialize", {protocolVersion: 1});
class Acp {
	final input:Source;
	final output:Sink;
	#if !(hxmc.target == "wasm32-wasi")
	final process:Null<Process>;
	#end
	final pending = new Map<Int, IContinuation<Dynamic>>();
	final methods = new Map<String, Coroutine<Dynamic->Dynamic>>();
	final writing = new Lock();
	var next = 0;
	public var closed(default, null) = false;
	// why it closed (the process' exit, an error reading)
	public var ended(default, null) = "";
	// the other side's notifications, its log lines (stderr), it closed
	public var onNotification:Null<(method:String, params:Dynamic) -> Void> = null;
	public var onLog:Null<String->Void> = null;
	public var onClose:Null<Void->Void> = null;

	public function new(input:Source, output:Sink #if !(hxmc.target == "wasm32-wasi"), ?process:Process #end) {
		this.input = input;
		this.output = output;
		#if !(hxmc.target == "wasm32-wasi")
		this.process = process;
		#end
	}

	#if !(hxmc.target == "wasm32-wasi")
	public static function spawn(cmd:String, args:Array<String>, ?options:Process.ProcessOptions):Acp {
		var p = new Process(cmd, args, options);
		return new Acp(p.stdout, p.stdin, p);
	}
	#end

	// a method of the other side's requests answered by f (its result; an
	// exception an error: an AcpError's code, else -32603)
	public function handle(method:String, f:Coroutine<Dynamic->Dynamic>)
		methods.set(method, f);

	// a request: its result, else its error (an AcpError)
	@:coroutine public function request(method:String, params:Dynamic):Dynamic {
		if (closed) throw new AcpError(-32000, 'closed: $ended');
		var id = ++next, pending = pending;
		send({jsonrpc: "2.0", id: id, method: method, params: params});
		if (closed) throw new AcpError(-32000, 'closed: $ended');
		return Async.suspendCancellable(cont -> {
			pending.set(id, cont);
			return _ -> pending.remove(id);
		});
	}

	@:coroutine public function notify(method:String, params:Dynamic) {
		if (closed) return;
		send({jsonrpc: "2.0", method: method, params: params});
	}

	@:coroutine function send(m:Dynamic) {
		var b = Bytes.ofString(Json.stringify(m) + "\n");
		writing.acquire();
		try output.write(b, 0, b.length) catch (e:Exception) {
			writing.release();
			throw e;
		}
		writing.release();
	}

	// the messages read until the other side ends (its requests answered in
	// tasks of their own: a permission waits for the user); then closed,
	// what waits failed, the process stopped
	@:coroutine public function run(task:Node) {
		var lines = new Reader(input);
		#if !(hxmc.target == "wasm32-wasi")
		var p = process, self = this;
		var logs = p == null ? null : task.async(_ -> self.logs(p));
		#end
		try {
			var line;
			while ((line = lines.readLine()) != null) {
				var m:Dynamic = try Json.parse(line) catch (_:Exception) null;
				if (m == null || !Reflect.isObject(m)) {
					if (line.trim() != "" && onLog != null) onLog(line);
					continue;
				}
				dispatch(task, m);
			}
			ended = "the end of its output";
		} catch (e:Exception) {
			ended = e.message;
		}
		#if !(hxmc.target == "wasm32-wasi")
		if (p != null) {
			try {
				if (logs != null) Async.timeout(1, _ -> logs.await());
			} catch (_:Exception) {}
			var code = p.stop();
			p.close();
			ended = 'exit code $code';
		}
		#end
		finish();
	}

	#if !(hxmc.target == "wasm32-wasi")
	@:coroutine function logs(p:Process) {
		var r = new Reader(p.stderr), line;
		while ((line = r.readLine()) != null)
			if (onLog != null) onLog(line);
	}
	#end

	function dispatch(task:Node, m:Dynamic) {
		var method:Null<String> = m.method;
		if (method == null) {
			var id:Dynamic = m.id;
			var cont = Std.isOfType(id, Int) || Std.isOfType(id, Float) ? pending.get(Std.int(id)) : null;
			if (cont == null) return;
			pending.remove(Std.int(id));
			var err:Dynamic = m.error;
			Async.resumeLater(cont, err == null ? m.result : null, err == null ? null : new AcpError(err.code ?? -32603, err.message ?? "error", err.data));
			return;
		}
		if (m.id == null) {
			if (onNotification != null) onNotification(method, m.params);
			return;
		}
		var self = this;
		task.async(_ -> self.answer(m));
	}

	@:coroutine function answer(m:Dynamic) {
		var id:Dynamic = m.id, method:String = m.method;
		var f = methods.get(method);
		var reply:Dynamic = if (f == null) {
			{jsonrpc: "2.0", id: id, error: {code: -32601, message: 'no method $method'}};
		} else try {
			var r = f(m.params);
			{jsonrpc: "2.0", id: id, result: r ?? {}};
		} catch (e:AcpError) {
			{jsonrpc: "2.0", id: id, error: {code: e.code, message: e.message}};
		} catch (e:Exception) {
			{jsonrpc: "2.0", id: id, error: {code: -32603, message: e.message}};
		}
		if (!closed) try send(reply) catch (_:Exception) {}
	}

	function finish() {
		if (closed) return;
		closed = true;
		var waiting = [for (c in pending) c];
		pending.clear();
		for (c in waiting)
			Async.resumeLater(c, null, new AcpError(-32000, 'closed: $ended'));
		if (onClose != null) onClose();
	}

	// no more messages: its input closed and the process asked to end (run
	// reaps it, then fails what waits)
	public function close() {
		#if !(hxmc.target == "wasm32-wasi")
		if (process != null) {
			process.closeStdin();
			process.signal(ProcessSignal.SIGTERM);
			return;
		}
		#end
		finish();
	}
}

class AcpError extends Exception {
	public final code:Int;
	public final data:Dynamic;

	public function new(code:Int, message:String, ?data:Dynamic) {
		super(message);
		this.code = code;
		this.data = data;
	}
}
