package lanes;

import sys.FileSystem;
import sys.io.File;
import lanes.Tools.*;

using StringTools;

class Bench {
	// (bun run test bench <name>: one of them; bench alone: the engine's)
	public static final LANES:Array<Lane> = [
		{name: "bench", about: "the engine's benchmarks and the examples' sizes", run: bench},
		{name: "bench image", about: "helder.image's decode speed against vips", run: imageBench},
		{name: "bench motion", about: "helder.ui.motion's budget measured", run: motionBench},
		{name: "bench code", about: "helder.ui.code's budgets measured", run: codeBench},
		{name: "bench million", about: "VirtualList over a million rows measured", run: millionBench},
		{name: "bench scene-markup", about: "3D in markup against the same scene in code", run: sceneMarkupBench},
		{name: "bench jobs", about: "background work against the main thread's frames", run: jobs},
		{name: "bench thread", about: "the page's thread against a worker, in browsers", run: threadWeb},
		{name: "bench effect", about: "post's effects a frame, headless", run: () -> scenes("EffectBench")},
		{name: "bench light", about: "the lighting features a frame, headless", run: () -> scenes("LightBench")},
		{name: "bench frame", about: "tests/3d's scenes timed, first frame and after", run: () -> scenes("FrameBench")},
		{name: "bench async", about: "helder.async's tasks, timers, switches and locks", run: () -> program("AsyncBench", cps(["src"]))},
		{name: "bench watch", about: "the watchers' cost a tick on a large tree", run: () -> program("WatchBench", cps(["src"]))},
		{name: "bench parallel", about: "helder.parallel's forms on a particle step (docs/design/parallel.md)", run: () -> program("ParallelBench", cps(["src", "tests/bench/parallel"]))},
		{name: "bench reduce", about: "helder.parallel's reductions on the GPU against reading back", run: () -> program("ReduceBench", cps(["src"]))},
		{name: "bench soft", about: "the CPU's canvas against the GPU on the same scenes", run: () -> {
			program("SoftBench", uiCp());
			run(exePath("bin/bench/SoftBench", HOST), [], ["HELDER_SOFT" => "1"]);
		}}
	];

	// a bench of tests/bench built natively and run
	static function program(main:String, cp:Array<String>) {
		exe('bin/bench/$main', cp.concat(cps(["tests/bench"])).concat(["-main", main]));
		run(exePath('bin/bench/$main', HOST), []);
	}

	// (tests/3d's scenes read the packed models: the 3d lane's pack)
	static function scenes(main:String) {
		pack();
		program(main, sceneCp());
	}

	static function threadWeb() {
		wasm("bin/bench/ThreadBench.wasm", uiCp().concat(cps(["tests/bench"])).concat(["-main", "ThreadBench"]));
		run(NODE, ["tests/bench/thread-bench.mjs", "bin/bench/ThreadBench.wasm", "--json", "bin/bench/thread-bench.json"]);
	}

	// (IMAGE_BENCH_JPEG, IMAGE_BENCH_PNG: the files, a photo and a large PNG;
	// by default examples' comparison.jpg and tests/ui/todo.png)
	static function imageBench() {
		exe("bin/bench/ImageBench", cps(["src", "tests/bench"]).concat(["-main", "ImageBench"]));
		run(NODE, ["tests/bench/image.mjs", exePath("bin/bench/ImageBench", HOST), Sys.getEnv("IMAGE_BENCH_JPEG") ?? "examples/gltf-showcase/comparison.jpg",
			Sys.getEnv("IMAGE_BENCH_PNG") ?? "tests/ui/todo.png"]);
	}

	static function motionBench() {
		var h = helderCli(), b = "bin/motion-bench";
		mkdirs(b);
		var rows = ["| 1,000 boxes | frames | ms median | ms p95 | retarget frames' ms median | GC bytes a frame (median) |", "|---|---|---|---|---|---|"];
		var gc = new Map<String, Float>();
		for (mode in ["still", "motion"]) {
			run(h, ["run", "--headless", "tests/bench/MotionStress.hx", "--script", "tests/bench/motion-stress.json", "--stats", '$b/$mode.json', "--", "1000"].concat(mode == "still" ? ["still"] : []));
			var frames:Array<Dynamic> = haxe.Json.parse(File.getContent('$b/$mode.json')).frames;
			// (once the boxes move: between their retargets, and the frames of them)
			var steady = [for (f in frames) if (f.t >= 0.6 && f.t < 3 && Math.abs((f.t - 0.5) % 0.25) > 0.02) f];
			var at = [for (f in frames) if (f.t >= 0.6 && f.t < 3 && Math.abs((f.t - 0.5) % 0.25) <= 0.001) f];
			function stat(fs:Array<Dynamic>, k:String, q:Float):Float {
				var v:Array<Float> = [for (f in fs) Reflect.field(f, k)];
				v.sort(Reflect.compare);
				return v.length == 0 ? 0 : v[Std.int(Math.min(v.length - 1, v.length * q))];
			}
			gc.set(mode, stat(steady, "gcBytes", 0.5));
			rows.push('| $mode | ${steady.length} | ${stat(steady, "ms", 0.5)} | ${stat(steady, "ms", 0.95)} | ${stat(at, "ms", 0.5)} | ${gc.get(mode)} |');
		}
		var table = rows.join("\n");
		Sys.println(table);
		File.saveContent('$b/results.md', table + "\n");
		if (gc.get("motion") > gc.get("still")) throw new Failed('motion-bench: the moving frames allocate ${gc.get("motion")} bytes, the still ones ${gc.get("still")}');
	}

	static function codeBench() {
		var h = helderCli(), b = "bin/code-bench";
		mkdirs(b);
		File.saveContent('$b/code.tsx', repeatedLines("examples/ts-todo/app.tsx", 10000, true));
		// (the script: focus, go to line 5,000's end, a key a frame; the wheel
		// down a frame at a time, then back up, at a place: a step aimed at a
		// node finds it in the tree, the harness's work, not the frame's)
		var ev:Array<Dynamic> = [{t: 0.2, type: "tap", tag: "code-view", ox: 300, oy: 10}, {t: 0.3, type: "key", name: "g", secondary: true},
			{t: 0.35, type: "type", text: "5000"}, {t: 0.45, type: "key", name: "Enter"}, {t: 0.5, type: "key", name: "End"}];
		var t = 0.6, dt = 1 / 60;
		for (k in 0...240) {
			ev.push(k % 40 == 39 ? {t: t, type: "key", name: "Enter"} : {t: t, type: "type", text: String.fromCharCode("a".code + k % 26)});
			t += dt;
		}
		var typed = t;
		t += 0.5;
		var down = t;
		for (_ in 0...600) {
			ev.push({t: t, type: "wheel", x: 450, y: 320, dy: 80});
			t += dt;
		}
		var up = t;
		for (_ in 0...600) {
			ev.push({t: t, type: "wheel", x: 450, y: 320, dy: -80});
			t += dt;
		}
		var idle = t;
		ev.push({t: t + 1, type: "mark", name: "end"});
		File.saveContent('$b/script.json', haxe.Json.stringify({events: ev}));
		File.saveContent('$b/phases.json', haxe.Json.stringify([
			{name: "keystroke (to its frame)", kind: "keys", from: 0.59, to: typed},
			{name: "wheel down (lines new)", kind: "wheels", from: down, to: up},
			{name: "wheel back up (steady state)", kind: "wheels", from: up, to: idle},
			{name: "idle (caret blinking)", kind: "idle", from: idle + 0.2, to: idle + 1}
		]));
		run(h, ["run", "--headless", "examples/code-editor", "--size", "900x640", "--script", '$b/script.json', "--stats", '$b/stats.json', "--", '$b/code.tsx']);
		run(NODE, ["tests/bench/code.mjs", '$b/stats.json', '$b/phases.json']);
		exe('$b/CodeBench', cps(["src", "tests/bench"]).concat(["-main", "CodeBench", "-D", "hxmc.libc=glibc"]));
		run(exePath('$b/CodeBench', HOST), ['$b/code.tsx']);
	}

	static function millionBench() {
		var h = helderCli(), b = "bin/million-bench";
		mkdirs(b);
		// (the wheel down 400 frames (rows new), back and forth over 1,200 px
		// 10 times (rows made before), End and Top 10 times, a row put in
		// above the view 30 times, Down 120 times, idle)
		var ev:Array<Dynamic> = [], t = 0.5, dt = 1 / 60;
		function at(name:String) {
			ev.push({t: t, type: "mark", name: name});
		}
		at("down");
		for (_ in 0...400) {
			ev.push({t: t, type: "wheel", x: 240, y: 300, dy: 60});
			t += dt;
		}
		at("again");
		for (k in 0...400) {
			ev.push({t: t, type: "wheel", x: 240, y: 300, dy: k % 40 < 20 ? 60 : -60});
			t += dt;
		}
		at("jumps");
		for (k in 0...20) {
			ev.push({t: t, type: "tap", tag: k % 2 == 0 ? "end" : "top"});
			t += 0.2;
		}
		at("inserts");
		for (_ in 0...30) {
			ev.push({t: t, type: "tap", tag: "insert"});
			t += 0.1;
		}
		ev.push({t: t, type: "tap", tag: "top"});
		t += 0.2;
		at("keys");
		for (_ in 0...120) {
			ev.push({t: t, type: "key", name: "ArrowDown"});
			t += dt * 2;
		}
		at("idle");
		t += 1;
		at("end");
		File.saveContent('$b/script.json', haxe.Json.stringify({events: ev}));
		run(h, ["run", "--headless", "examples/million", "--size", "480x640", "--script", '$b/script.json', "--stats", '$b/stats.json']);
		run(NODE, ["tests/bench/million.mjs", '$b/stats.json', '$b/script.json']);
		exe('$b/MillionBench', cps(["src", "tests/bench", "examples/million"]).concat(["-main", "MillionBench", "-D", "hxmc.libc=glibc"]));
		run(exePath('$b/MillionBench', HOST), []);
	}

	// (the programs whose size and compile time are tracked: ui and text, scene and physics)
	static final BENCH_BUILDS = [{dir: "examples/todo", main: "Todo"}, {dir: "examples/walker", main: "Walker"}];

	// tests/bench/Bench.hx natively and as wasm32-wasi (BENCH: the workloads,
	// by name, separated by spaces; each in a process of its own), then the
	// examples above built for both: a table
	static function bench() {
		var font = "bin/bench/DejaVuSans.ttf";
		mkdirs("bin/bench");
		File.saveBytes(font, File.getBytes(dejavu()));
		var cp = cps(["src", "tests/bench"]).concat(["-main", "Bench"]);
		// (each built twice: from nothing (-D hxmc.no-module-cache), then with
		// the module cache. The last build is the one run)
		var builds = [];
		function timed(what:String, target:String, out:String, args:Array<String>) {
			var times = [];
			var nothing = ["-D", "hxmc.no-module-cache"];
			for (extra in [nothing, []]) {
				var t0 = Sys.time();
				if (target == HOST) native(out, args.concat(extra), HOST) else wasm(out, args.concat(extra));
				times.push(Sys.time() - t0);
			}
			builds.push({what: what, target: target, out: target == HOST ? exePath(out, HOST) : out, times: times});
		}
		timed("Bench", HOST, "bin/bench/Bench", cp);
		timed("Bench", "wasm32-wasi", "bin/bench/Bench.wasm", cp);
		var names = (Sys.getEnv("BENCH") ?? "").split(" ").filter(n -> n != "");
		if (names.length == 0) names = [for (l in output(exePath("bin/bench/Bench", HOST), [font, "list"]).split("\n")) if (l.trim() != "") l.trim()];
		var md = ["# Benchmarks", "", 'tests/bench/Bench.hx (`bun run test bench`), ${Date.now().toString().substr(0, 10)}, ${cpuName()}.', ""];
		md.push("Milliseconds per run (median, p99, max), GC heap bytes allocated per run, collections (all runs; majors), the longest time collecting in one run (hxmc.GcStats' pauses, natively and on wasm32).");
		for (target in [HOST, "wasm32-wasi"]) {
			md = md.concat(["", '## $target', "", "| workload | runs | median | p99 | max | KB/run | GCs | majors | longest GC |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]);
			for (n in names) {
				var wasi = ["--stack-size=65500", "tests/bench/wasi.mjs", "bin/bench/Bench.wasm", font, n];
				var out = target == HOST ? output(exePath("bin/bench/Bench", HOST), [font, n]) : output(NODE, wasi, true), mark = "";
				// (wasm32's runtime crashes in a major collection with arrays of tens
				// of MB, scene.world.100k's: again with an old space it fits in, and
				// node's own stack size, where the overflow is an error, not a crash)
				if (out == null) {
					out = output("env", ["RT_OLD_MB=512", NODE].concat(wasi.slice(1)));
					mark = " (RT_OLD_MB=512)";
				}
				for (l in out.split("\n")) {
					var c = l.trim().split(" ");
					if (c[0] != "bench") continue;
					var kb = Math.round(Std.parseFloat(c[6]) / 1024 * 10) / 10;
					md.push('| ${c[1]}$mark | ${c[2]} | ${c[3]} | ${c[4]} | ${c[5]} | $kb | ${c[7]} | ${c[8]} | ${c[9]} |');
					Sys.println('$target ${c[1]}: ${c[3]} ms median, ${c[4]} p99, $kb KB/run, ${c[7]} GCs');
				}
			}
		}
		for (b in BENCH_BUILDS) {
			var args = cps(["src", b.dir]).concat(["-main", b.main]);
			timed(b.main, HOST, 'bin/bench/${b.main}', args);
			timed(b.main, "wasm32-wasi", 'bin/bench/${b.main}.wasm', args.concat(["-D", "hxmc.wasm-eh=legacy"]));
		}
		md = md.concat([
			"", "## Builds", "",
			"Seconds to compile, without a compilation server: from nothing (-D hxmc.no-module-cache) and with the module cache on disk.",
			"", "| program | target | size (KB) | build | cached |", "| --- | --- | ---: | ---: | ---: |"
		]);
		for (b in builds)
			md.push('| ${b.what} | ${b.target} | ${Math.round(FileSystem.stat(b.out).size / 1024)} | ' + [for (t in b.times) Math.round(t * 10) / 10].join(" | ") + " |");
		File.saveContent("bin/bench/results.md", md.join("\n") + "\n");
		Sys.println(md.join("\n"));
	}

	// tests/bench/SceneMarkupBench.hx: each variant at 1,000 and 10,000 nodes,
	// RUNS times (each a process), the medians of each column; a table of
	// them with each frame's ratio to code's (bin/bench/scene-markup.md)
	static function sceneMarkupBench() {
		var b = "bin/bench", cp = cps(["src", "tests/bench"]).concat(["-main", "SceneMarkupBench"]);
		exe('$b/SceneMarkupBench', cp);
		wasm('$b/SceneMarkupBench.wasm', cp);
		var runs = Std.parseInt(Sys.getEnv("RUNS") ?? "3");
		var variants = (Sys.getEnv("SCENE_BENCH") ?? "code constant signals steps").split(" ").filter(v -> v != "");
		var md = ["# 3D in markup against code", "", 'tests/bench/SceneMarkupBench.hx (`bun run test scene-markup-bench`), ${Date.now().toString().substr(0, 10)}, ${cpuName()}; the median of $runs runs.', "",
			"A frame: every node moved (the markup's share: the writes, the clock's steps and the flush), then the renderer's pass recorded (natively, a headless device; wasm32-wasi has no GPU, its nodes are bare). Idle: of 100 frames with nothing changed, those asking for a redraw. Left: the world's nodes after unmounting, over its count before mounting."];
		for (target in [HOST, "wasm32-wasi"]) {
			md = md.concat(["", '## $target', "", "| variant | nodes | mount ms | mount KB | frame ms | x code | B a frame | pass ms | with the pass, x code | idle drawing | unmount ms | left |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"]);
			for (n in [1000, 10000]) {
				var code = 0.0, codeAll = 0.0;
				for (v in variants) {
					var rows:Array<Array<Float>> = [];
					for (_ in 0...runs) {
						var out = target == HOST ? output(exePath('$b/SceneMarkupBench', HOST), [v, '$n']) : output(NODE, ["--stack-size=65500", "tests/bench/wasi.mjs", '$b/SceneMarkupBench.wasm', v, '$n']);
						for (l in out.split("
")) {
							var c = l.trim().split(" ");
							if (c[0] == "scene-markup") rows.push([for (k in 3...c.length) Std.parseFloat(c[k])]);
						}
					}
					if (rows.length == 0) throw new Failed('scene-markup-bench: $v $n printed no result');
					var m = [for (k in 0...rows[0].length) {
						var col = [for (r in rows) r[k]];
						col.sort(Reflect.compare);
						col[col.length >> 1];
					}];
					// (mount ms, mount KB, frame ms, frame B, pass ms, pass B, idle, unmount ms, left)
					if (v == "code") {
						code = m[2];
						codeAll = m[2] + m[4];
					}
					var ratio = code > 0 ? Math.round(m[2] / code * 100) / 100 : 0.0, all = codeAll > 0 ? Math.round((m[2] + m[4]) / codeAll * 100) / 100 : 0.0;
					md.push('| $v | $n | ${m[0]} | ${Math.round(m[1])} | ${m[2]} | ${v == "code" ? "1" : Std.string(ratio)} | ${m[3]} | ${m[4]} | ${v == "code" ? "1" : Std.string(all)} | ${m[6]} | ${m[7]} | ${m[8]} |');
					Sys.println('scene-markup-bench $target $v $n: mount ${m[0]} ms, frame ${m[2]} ms (${ratio}x code), ${m[3]} B a frame, idle ${m[6]}, left ${m[8]}');
				}
			}
		}
		File.saveContent('$b/scene-markup.md', md.join("
") + "
");
		Sys.println(md.join("
"));
	}

	// tests/bench/Jobs.hx: each variant RUNS times, each in a process of its
	// own, the medians and the spread of its columns; the job alone; what
	// each variant adds to the program's size and build; JobsWasm.wasm with a
	// worker instance (tests/bench/jobs.mjs). JOBS: the variants (all)
	static final JOB_VARIANTS = ["none", "a", "b", "d", "d0"];

	static function jobs() {
		var dir = "bin/jobs", font = '$dir/DejaVuSans.ttf', png = '$dir/photo.png';
		mkdirs(dir);
		File.saveBytes(font, File.getBytes(dejavu()));
		if (!FileSystem.exists(png)) run(NODE, ["tests/bench/photo.mjs", png]);
		var cp = cps(["src", "tests/bench"]);
		exe('$dir/Jobs', cp.concat(["-main", "Jobs"]));
		wasm('$dir/JobsWasm.wasm', cp.concat(["-main", "JobsWasm"]));
		var bin = exePath('$dir/Jobs', HOST);
		run(bin, [font, png, "check"]);
		var runs = Std.parseInt(Sys.getEnv("RUNS") ?? "") ?? 5;
		var variants = (Sys.getEnv("JOBS") ?? "").split(" ").filter(v -> v != "");
		if (variants.length == 0) variants = JOB_VARIANTS;
		// (a column's median, and its spread when it has one)
		function cell(rows:Array<Array<String>>, c:Int):String {
			var v = [for (r in rows) Std.parseFloat(r[c])];
			v.sort(Reflect.compare);
			var m = v[v.length >> 1], r = (x:Float) -> Std.string(Math.round(x * 100) / 100);
			return v[0] == v[v.length - 1] ? r(m) : '${r(m)} (${r(v[0])}-${r(v[v.length - 1])})';
		}
		function lines(cmd:String, args:Array<String>):Array<Array<String>>
			return [for (_ in 0...runs) for (l in output(cmd, args).split("\n")) if (l.startsWith("jobs ")) l.split(" ")];
		var md = ["# Jobs", "", 'tests/bench/Jobs.hx (`bun run test jobs-bench`), ${Date.now().toString().substr(0, 10)}, ${cpuName()}; $runs runs of each, medians (and their spread).', ""];
		for (mode in ["probe", "natural"]) {
			md = md.concat([
				"", '## $HOST, ${mode == "probe" ? "a collection at every frame of the job" : "collections from the garbage alone"}', "",
				"| variant | frame median | p99 | max | longest pause | pauses | GCs | majors | decode | longest stop | GC heap KB/frame |",
				"| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
			]);
			for (v in variants) {
				var rows = lines(bin, [font, png, v].concat(mode == "probe" ? ["probe"] : []));
				md.push('| $v | ' + [for (c in 3...13) cell(rows, c)].join(" | ") + " |");
				Sys.println('$mode $v: longest pause ${cell(rows, 6)} ms, frame max ${cell(rows, 5)} ms');
			}
		}
		md = md.concat(["", "## The job alone", "", "| job | ms | min | max | GC heap growth | worker's allocation |", "| --- | ---: | ---: | ---: | ---: | ---: |"]);
		for (v in ["b", "d"]) {
			var c = output(bin, [font, png, "alone", v]).split("\n").filter(l -> l.startsWith("alone "))[0].split(" ");
			md.push('| $v | ${c[2]} | ${c[3]} | ${c[4]} | ${c[5]} | ${c[6]} |');
		}
		// (each variant alone in the program, with the ui and without it:
		// sizes, and builds from nothing and with the module cache)
		md = md.concat(["", "## Sizes and builds", "", "| variant | size (KB) | without the ui | build (s) | cached |", "| --- | ---: | ---: | ---: | ---: |"]);
		for (v in ["none", "a", "b", "d"]) {
			var args = cp.concat(["-main", "Jobs", "-D", 'jobs_only=$v']), out = '$dir/only/Jobs-$v';
			var times = [];
			for (extra in [["-D", "hxmc.no-module-cache"], []]) {
				var t0 = Sys.time();
				native(out, args.concat(extra), HOST);
				times.push(Math.round((Sys.time() - t0) * 100) / 100);
			}
			native('$out-bare', args.concat(["-D", "jobs_bare"]), HOST);
			var kb = (f:String) -> Math.round(FileSystem.stat(exePath(f, HOST)).size / 1024 * 10) / 10;
			md.push('| $v | ${kb(out)} | ${kb('$out-bare')} | ${times[0]} | ${times[1]} |');
		}
		md = md.concat([
			"", "## wasm32-wasi, a worker instance", "",
			"| variant | frame median | p99 | max | GCs | decode | worker's copy out | main's copy in | longest task |", "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
		]);
		// (node's WASI allocates in its fast API calls, which can collect
		// meanwhile and crash V8 once linear memory is large: no fast calls)
		for (v in ["none", "a", "b"]) {
			var rows = lines(NODE, ["--no-turbo-fast-api-calls", "--stack-size=65500", "tests/bench/jobs.mjs", '$dir/JobsWasm.wasm', font, png, v]);
			md.push('| $v | ' + [for (c in 3...11) cell(rows, c)].join(" | ") + " |");
		}
		// (the same through helder.jobs: frames on helder.async's loop, ImageJobs' job, a job's round trip)
		exe('$dir/JobsApi', cp.concat(["-main", "JobsApi"]));
		wasm('$dir/JobsApi.wasm', cp.concat(["-main", "JobsApi"]));
		var api = exePath('$dir/JobsApi', HOST);
		var wasi = ["--no-warnings", "--no-turbo-fast-api-calls", "--stack-size=65500", "src/helder/test/wasi.mjs", '$dir/JobsApi.wasm'];
		md = md.concat(["", "## Through helder.jobs (JobsApi.hx)", "", "| target | variant | frame median | p99 | max | longest pause | decode |", "| --- | --- | ---: | ---: | ---: | ---: | ---: |"]);
		for (mode in ["probe", "natural", "wasm"])
			for (v in ["none", "inline", "job", "gc"]) {
				var a = [font, png, v].concat(mode == "probe" ? ["probe"] : []);
				var rows = [for (_ in 0...runs) for (l in (mode == "wasm" ? output(NODE, wasi.concat(a)) : output(api, a)).split("\n")) if (l.startsWith("api ")) l.split(" ")];
				md.push('| ${mode == "wasm" ? "wasm32-wasi" : '$HOST, $mode'} | $v | ' + [for (c in 3...8) cell(rows, c)].join(" | ") + " |");
			}
		var o = (l:String) -> [for (x in l.split("\n")) if (x.startsWith("overhead ")) x.split(" ")][0];
		var on = o(output(api, ["overhead"])), ow = o(output(NODE, wasi.concat(["overhead"])));
		md = md.concat(["", "A job's round trip, from the awaiting task (µs):", "", "| target | GC-free | GC | on the loop |", "| --- | ---: | ---: | ---: |",
			'| $HOST | ${on[1]} | ${on[2]} | ${on[3]} |', '| wasm32-wasi | ${ow[1]} | ${ow[2]} | ${ow[3]} |']);
		File.saveContent('$dir/results.md', md.join("\n") + "\n");
		Sys.println(md.join("\n"));
	}
}
