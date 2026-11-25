package helder.async;

import haxe.Exception;
import helder.test.Test;

function tests() {
	describe("Errors", () -> {
		afterEach(() -> Errors.handler = null);
		test("guard rethrows with no handler", () -> {
			var threw = false;
			try Errors.guard(() -> throw "boom", "frame") catch (e:Exception) threw = true;
			assert(threw);
		});
		test("a handled error goes no further", () -> {
			var got = [];
			Errors.handler = (e, source) -> {
				got.push(source + ": " + e.message);
				true;
			};
			Errors.guard(() -> throw new Exception("boom"), "frame");
			equals(got, ["frame: boom"]);
		});
		test("an error in the handler is not handled", () -> {
			Errors.handler = (_, _) -> throw "again";
			var threw = false;
			try Errors.guard(() -> throw "boom", "event") catch (e:Exception) threw = true;
			assert(threw);
		});
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		test("a render's null access names its line", () -> {
			var ui = new helder.ui.Ui(null, 100, 100);
			var e = caught(() -> helder.view.Render.render(Views.broken(), ui.root));
			equals(e.message, "Null Access");
			equals(where(e), Views.at);
		});
		test("a render thread's error names its line, then where it was thrown again", () -> {
			var r = Views.rendered(_ -> Views.fault(null));
			var e = caught(() -> throw Errors.carried(r.error));
			equals(where(e), Views.at);
			equals(Errors.text(e).indexOf("\nRethrown at:\n") > 0, true);
		});
		test("kept: a value thrown again keeps its throw's line", () -> {
			var e = caught(() -> try Views.fault(null) catch (e:Exception) throw Errors.kept(e));
			equals(where(e), Views.at);
		});
		#end
		test("a task's unheard error is reported", () -> {
			var got = [];
			Errors.handler = (e, source) -> {
				got.push(source);
				true;
			};
			Async.launch(_ -> throw new Exception("lost"));
			Loop.current().runUntil(() -> got.length > 0);
			equals(got, ["task"]);
		});
	});
}

#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
// (the first frame Errors.text shows: its file's name and line)
private function where(e:Exception):String {
	var r = ~/\(([^()]*) line (\d+)\)$/;
	var first = Errors.text(e).split("\n")[1];
	if (!r.match(first)) return first;
	return haxe.io.Path.withoutDirectory(r.matched(1)) + ":" + r.matched(2);
}

private function caught(f:Void->Void):Exception {
	try f() catch (e:Exception) return e;
	throw "no error";
}

private class Box {
	public var x = 1.0;

	public function new() {}
}

private class Views implements helder.view.Markup {
	// (where fault throws: its file's name and line)
	public static var at = "";

	public static function broken()
		return <view opacity={() -> fault(null)}/>;

	// (one line: hxmc names a fault's frame by the instruction before it)
	public static function fault(b:Null<Box>):Float {
		at = here(); return b.x;
	}

	static function here(?p:haxe.PosInfos):String
		return haxe.io.Path.withoutDirectory(p.fileName) + ":" + p.lineNumber;

	// (f run on the render thread, a call of its commands)
	@:hxmc.unsafe(gc) public static function rendered(f:helder.gfx.Replay->Void):helder.gfx.Replay {
		var t = helder.gfx.RenderThread.acquire();
		var r = new helder.gfx.Replay(null), c = new helder.gfx.Commands();
		c.call(f);
		t.submit(r, c);
		t.wait();
		t.release();
		return r;
	}
}
#end
