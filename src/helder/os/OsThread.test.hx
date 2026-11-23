package helder.os;

import helder.test.Test;

// OsThread: the program's loop on a thread of its own, calls handed to the
// main thread and back, nested both ways, an error coming back to the
// caller, a callback that came meanwhile run before the program's next
// call (soon), helder.async's loop the same on both (natively: threads).
function tests() {
	#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
	describe("OsThread", () -> {
		test("calls nest both ways, each on its thread", () -> {
			var seen = [];
			var id = () -> hxmc.NativeThread.current() == 1 ? "main" : "program";
			OsThread.start(() -> {
				seen.push(id());
				OsThread.run(() -> {
					seen.push(id());
					OsThread.back(() -> {
						seen.push(id());
						OsThread.run(() -> seen.push(id()));
					});
				});
				seen.push("" + OsThread.get(() -> hxmc.NativeThread.current()));
			});
			equals(seen, ["program", "main", "program", "main", "1"]);
			equals(OsThread.program, 0);
		});
		test("an error comes back to the caller", () -> {
			var caught = "";
			OsThread.start(() -> try OsThread.run(() -> throw "no") catch (e:Dynamic) caught = Std.string(e));
			equals(caught, "no");
		});
		test("what comes while the program runs on waits for its next call", () -> {
			var seen = [], read = false;
			OsThread.waitMain = () -> {
				if (!read) {
					read = true;
					OsThread.soon(() -> seen.push("soon"));
					seen.push("read");
				}
				false;
			};
			OsThread.start(() -> {
				while (!read)
					Sys.sleep(0.001);
				OsThread.run(() -> seen.push("call"));
				OsThread.soon(() -> seen.push("at once"));
			});
			OsThread.waitMain = null;
			equals(seen, ["read", "soon", "call", "at once"]);
		});
		test("the main thread's loop is the program's", () -> {
			var main = helder.async.Loop.current(), same = false;
			OsThread.start(() -> same = helder.async.Loop.current() == main);
			assert(same);
		});
	});
	#end
}
