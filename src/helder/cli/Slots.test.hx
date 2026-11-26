package helder.cli;

import helder.cli.Slots;
import helder.test.Test;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// The machine-wide job limit (Slots): slots taken and given back, no limit
// when off, a dead or reused holder's slot freed, and the limit kept between
// processes (node's slots.mjs, the same directories) and threads at once
function tests() {
	#if (hxmc.target != "wasm32-wasi")
	describe("Slots", () -> {
		// (helder test runs this under a slot of its own: HELDER_SLOT=1)
		beforeAll(() -> Sys.putEnv(Slots.HELD, null));
		test("taken and released", () -> {
			var s = fresh(2);
			var a = require(s.tryTake()), b = require(s.tryTake());
			equals(s.busy(), 2);
			equals(s.tryTake(), null);
			a.release();
			equals(s.busy(), 1);
			var c = require(s.tryTake());
			b.release();
			c.release();
			equals(s.busy(), 0);
			equals(FileSystem.readDirectory(s.dir).length, 0);
		});
		test("off: HELDER_JOBS=0, or under a holder's slot", () -> {
			equals(new Slots(dir(), 0).take(), null);
			Sys.putEnv(Slots.HELD, "1");
			var s = fresh(1).take();
			Sys.putEnv(Slots.HELD, null);
			equals(s, null);
		});
		test("a dead holder's slot is free again", () -> {
			var s = fresh(1);
			// (odd and past Linux's largest: no pid on any system)
			held(s, 4194305, Sys.time());
			require(s.tryTake()).release();
			equals(s.busy(), 0);
		});
		test("a reused pid's slot is free again, a live holder's kept", () -> {
			var s = fresh(1);
			held(s, Slots.pid(), Sys.time());
			equals(s.tryTake(), null);
			// (this process, started after the slot was taken: another one with its pid)
			held(s, Slots.pid(), 1000);
			require(s.tryTake()).release();
		});
		test("the limit kept by processes and threads at once", () -> {
			var s = fresh(2), marks = dir();
			FileSystem.createDirectory(marks);
			var url = "file://" + FileSystem.fullPath("src/helder/cli/slots.mjs").split("\\").join("/");
			var script = 'import {slots} from "$url"; import fs from "node:fs";'
				+ 'const [dir, marks] = process.argv.slice(1), s = slots(dir, 2); let max = 0;'
				+ 'for (let i = 0; i < 4; i++) { const release = s.take(), m = `$${marks}/$${process.pid}-$${i}`;'
				+ 'fs.writeFileSync(m, ""); max = Math.max(max, fs.readdirSync(marks).length);'
				+ 'Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 30); fs.rmSync(m); release() }'
				+ 'console.log(max)';
			var node = [for (_ in 0...3) new sys.io.Process(Sys.getEnv("NODE") ?? "node", ["--input-type=module", "-e", script, s.dir, marks])];
			var most = new sys.thread.Deque<Int>(), done = new sys.thread.Lock();
			for (t in 0...2)
				sys.thread.Thread.create(() -> {
					var max = 0;
					for (i in 0...4) {
						var slot = require(s.take(_ -> {}));
						var m = '$marks/haxe-$t-$i';
						File.saveContent(m, "");
						max = Std.int(Math.max(max, FileSystem.readDirectory(marks).length));
						Sys.sleep(0.03);
						FileSystem.deleteFile(m);
						slot.release();
					}
					most.add(max);
					done.release();
				});
			var seen = [];
			for (p in node) {
				seen.push(Std.parseInt(p.stdout.readAll().toString().trim()) ?? -1);
				equals(p.exitCode(), 0);
				p.close();
			}
			for (_ in 0...2) {
				done.wait();
				seen.push(most.pop(true));
			}
			for (n in seen) assert(n >= 1 && n <= 2, 'at most 2 at once, not $n');
			equals(s.busy(), 0);
		});
	});
	#end
}

// (a directory of its own for each test: not the machine's slots)
function dir():String
	return (Sys.getEnv("TMPDIR") ?? Sys.getEnv("TEMP") ?? "/tmp") + '/helder-slots-test-${Slots.pid()}-${Std.random(0x7fffffff)}';

function fresh(count:Int):Slots
	return new Slots(dir(), count);

// slot 0 held by pid since a time
function held(s:Slots, pid:Int, since:Float) {
	FileSystem.createDirectory('${s.dir}/0');
	File.saveContent('${s.dir}/0/owner', '$pid ${Std.int(since)} test');
}
