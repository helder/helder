package lanes;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

class Tools {
	public static final TOOL = Sys.getEnv("HAXE") ?? (Sys.systemName() == "Windows" ? "haxe.cmd" : "haxe");

	// (markup's braces read as code, as every helder build does: helder.cli.Compiler.markup)
	public static final MARKUP = ["-D", "hxmc.markup-braces"];

	public static final NODE = Sys.getEnv("NODE") ?? "node";
	public static final HOST = hostTarget();
	public static final GFX_TARGET = Sys.getEnv("GFX_TARGET") ?? HOST;
	public static final AUDIO_TARGET = Sys.getEnv("AUDIO_TARGET") ?? HOST;
	public static final BLESS = Sys.getEnv("BLESS") != null && Sys.getEnv("BLESS") != "";

	// xvfb-run, returning once its X server is gone (tests/xvfb-run.sh: the
	// next one's display is not the last one's still letting go)
	public static final XVFB = "sh " + FileSystem.fullPath("tests/xvfb-run.sh");

	public static var shardIndex = 0;
	public static var shardTotal = 1;
	public static var workerCount:Null<Int> = null;
	public static var buildOnly = false;
	public static var usePrebuilt = false;

	public static function shardArgs():Array<String>
		return ["--shard", '$shardIndex/$shardTotal'];

	// (the CLI's own build, as `bun run helder` makes it)
	public static function helderCli():String {
		// (built by the run that started this lane: -j's)
		if (Sys.getEnv("RUN_CLI_BUILT") == "1" && FileSystem.exists(exePath("bin/cli/helder", HOST))) return exePath("bin/cli/helder", HOST);
		exe("bin/cli/helder", cps(["src"]).concat(["-main", "helder.cli.Cli"]));
		return exePath("bin/cli/helder", HOST);
	}

	public static function copy(from:String, to:String) {
		mkdirs(to);
		for (n in FileSystem.readDirectory(from))
			if (FileSystem.isDirectory('$from/$n')) copy('$from/$n', '$to/$n') else File.copy('$from/$n', '$to/$n');
	}

	// (the examples' directories of gfx's, which its tests use)
	public static final GFX_EXAMPLES = [for (e in ["triangle", "cube", "instances", "mips", "formats"]) 'examples/$e'];

	public static function gfxCp()
		return cps(["src", "tests/gfx"].concat(GFX_EXAMPLES));

	public static final SCENE_EXAMPLES = [for (e in ["gltf-viewer", "orbits", "showroom", "falling", "walker", "chains", "glow"]) 'examples/$e'];

	// the glTF samples packed for the packed scenes (the asset step)
	public static final PACKED = ["examples/gltf-viewer/sample.glb", "tests/3d/skinned.glb", "examples/showroom/normals.glb", "examples/showroom/morph.glb"];

	public static function sceneCp()
		return gfxCp().concat(cps(SCENE_EXAMPLES.concat(["tests/3d", "tests/physics"])));

	public static function pack() {
		mkdirs("bin/3d");
		// (the sample scene with its primitives' trees: Pack --bvh, the packed scene's probe)
		for (glb in PACKED)
			interp(sceneCp(), "helder.scene.gltf.Pack", [glb, "bin/3d/" + Path.withoutExtension(Path.withoutDirectory(glb)) + ".hxm3d"].concat(Path.withoutDirectory(glb) == "sample.glb" ? ["--bvh"] : []));
		// (the textured sample's texture compressed for the GPU: BC1, ASTC 4x4)
		for (t in ["bc", "astc"])
			interp(sceneCp(), "helder.scene.gltf.Pack", ["tests/3d/textured.glb", 'bin/3d/textured.$t.hxm3d', "--textures", t]);
	}

	public static function sceneTsPaths():Array<String>
		return [for (d in ["tests/3d/ts", "tests/gfx"].concat(GFX_EXAMPLES))
			for (a in ["--cp", d]) a];

	// a file's lines repeated to n lines (and a last line break); unique:
	// each repetition's lines but the first's marked with its number (no
	// two lines alike: none laid out once for both)
	public static function repeatedLines(path:String, n:Int, unique = false):String {
		var src = File.getContent(path).split("\n"), out = [];
		if (src[src.length - 1] == "") src.pop();
		while (out.length < n) {
			var l = src[out.length % src.length], k = Std.int(out.length / src.length);
			out.push(unique && k > 0 && StringTools.trim(l) != "" ? l + " /* " + k + " */" : l);
		}
		return out.join("\n") + "\n";
	}

	public static function uiCp()
		return cps(["src", "tests/gfx", "tests/ui", "examples/counter", "examples/todo", "examples/mail"]);

	// AccessApp's screens, each with what its tree must have ("role:name", as
	// AT-SPI names roles; the other platforms' probes map them)
	public static final ACCESS_SCREENS = [
		["todo", '"entry:What needs to be done?"', '"push button:Add"', '"check box:Write the docs"', '"check box:Ship it"', '"label:2 items left"'],
		["mail", '"list:Folders"', '"list item:Inbox 3"', '"list:Messages"', '"entry:Search messages"', '"push button:Archive"'],
		["guide", '"push button:+"', '"label:Total: € 60"', '"push button:Delete"', '"push button:Search"', '"entry:Subject"', '"entry:Body"', '"entry:Text"',
			'"password text:Password"']
	];

	// (DejaVu Sans: fonts-dejavu-core's, else fontconfig's)
	public static function dejavu():String {
		var known = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf";
		if (FileSystem.exists(known)) return known;
		var f = output("fc-match", ["-f", "%{file}", "DejaVu Sans"]).trim();
		if (!f.endsWith("DejaVuSans.ttf")) throw new Failed("bench: no DejaVu Sans (fonts-dejavu-core)");
		return f;
	}

	public static function cpuName():String {
		try {
			for (l in File.getContent("/proc/cpuinfo").split("\n"))
				if (l.startsWith("model name")) return l.substr(l.indexOf(":") + 1).trim() + ", " + cpus() + " cores";
		} catch (_) {}
		return HOST;
	}

	// a program's standard output (it must succeed; mayFail: null if it does not)
	public static function output(cmd:String, args:Array<String>, mayFail = false):Null<String> {
		args = nodeArgs(cmd, args);
		var p = new Process(cmd, args);
		var out = drain(p).out;
		var code = p.exitCode();
		p.close();
		if (code != 0 && mayFail) return null;
		if (code != 0) throw new Failed('${[cmd].concat(args).join(" ")}: exit code $code');
		return out;
	}

	public static function cps(dirs:Array<String>):Array<String>
		return [for (d in dirs) for (a in ["-cp", d]) a];

	// the compiler on Eval: `--run main args`
	public static function interp(cp:Array<String>, main:String, ?args:Array<String>, ?env:Map<String, String>)
		run(TOOL, MARKUP.concat(cp).concat(["--run", main]).concat(args ?? []), env);

	public static function js(out:String, args:Array<String>) {
		mkdirs(Path.directory(out));
		run(TOOL, MARKUP.concat(args).concat(["-js", out]));
	}

	// a program for this machine, for wasm32-wasi, for a target (Linux: the
	// dynamic glibc mode, which loads the GPU's and the sound's drivers)
	public static function exe(out:String, args:Array<String>)
		hxmc(exePath(out, HOST), args);

	public static function wasm(out:String, args:Array<String>)
		hxmc(out, args.concat(targetArgs("wasm32-wasi")));

	public static function native(out:String, args:Array<String>, target:String)
		hxmc(exePath(out, target), args.concat(targetArgs(target)));

	public static function targetArgs(target:String):Array<String>
		return ["-D", 'hxmc.target=$target'].concat(target.startsWith("linux-") ? ["-D", "hxmc.libc=glibc"] : []);

	// helder.os, as the CLI gives it (helder.compiler.Os): the build's
	// target's system, its shared code typed for that one only
	public static function os(args:Array<String>):Array<String> {
		if (Lambda.exists(args, a -> a.startsWith("helder.os="))) return [];
		var t = Lambda.find(args, a -> a.startsWith("hxmc.target="));
		t = t == null ? HOST : t.substr("hxmc.target=".length);
		return ["-D", "helder.os=" + (t.startsWith("macos-catalyst-") ? "ios" : t.startsWith("wasm32-") ? "web" : t.split("-")[0])];
	}

	public static function exePath(out:String, target:String):String
		return target.startsWith("windows-") ? '$out.exe' : out;

	// a build by hxmc, its log beside the output (printed when it fails); the
	// same output with the same arguments built once a run (prebuild's, then
	// the lane's own call; the CLI's, by every lane that runs it)
	public static final built = new Map<String, Bool>();

	public static final builtLock = new sys.thread.Mutex();

	public static function hxmc(out:String, args:Array<String>) {
		var key = out + "\x00" + args.join("\x00");
		builtLock.acquire();
		var done = built.exists(key);
		builtLock.release();
		if (done && FileSystem.exists(out)) return;
		mkdirs(Path.directory(out));
		var r = build(args.concat(os(args)).concat(["--custom-target", 'hxmc=$out']), '$out.log');
		if (r.code != 0) {
			Sys.println(r.log);
			throw new Failed('$out: the build failed');
		}
		Sys.println('$out (${Math.round(r.seconds * 10) / 10}s)');
		builtLock.acquire();
		built.set(key, true);
		builtLock.release();
	}

	// builds made at once (parallel: half the cores' worth), before the lane's
	// own calls, which then find them built (hxmc's memo); a failed one is
	// built again by its call, its log printed there
	public static function prebuild(builds:Array<{out:String, args:Array<String>}>) {
		var t0 = Sys.time();
		parallel(builds, b -> try hxmc(b.out, b.args) catch (_:Failed) {});
		Sys.println('prebuilt ${builds.length} in ${Math.round(Sys.time() - t0)} s');
	}

	public static function build(args:Array<String>, log:String, ?tool:String):{code:Int, log:String, seconds:Float} {
		var t0 = Sys.time();
		var p = new Process(tool ?? TOOL, tool == null ? MARKUP.concat(args) : args);
		var r = drain(p), out = r.out, err = r.err;
		var code = p.exitCode();
		p.close();
		mkdirs(Path.directory(log));
		File.saveContent(log, out + err);
		return {code: code, log: out + err, seconds: Sys.time() - t0};
	}

	// both pipes read at once: a program filling one while the other is read
	// waits forever (helder build's warnings are on stdout, the compiler's on
	// stderr)
	public static function drain(p:Process):{out:String, err:String} {
		var err = new sys.thread.Deque<String>();
		sys.thread.Thread.create(() -> err.add(p.stderr.readAll().toString()));
		var out = p.stdout.readAll().toString();
		return {out: out, err: err.pop(true)};
	}

	public static function wasi(module:String)
		run(NODE, ["--stack-size=65500", "tests/wasi.mjs", module]);

	// node's fast API calls off: WASI's fd_write is one, and a V8 collection
	// started inside it segfaults once a module's memory is large (node 22;
	// tests/bench/results/jobs.md)
	public static function nodeArgs(cmd:String, args:Array<String>):Array<String>
		return cmd == NODE && args.indexOf("--no-turbo-fast-api-calls") < 0 ? ["--no-turbo-fast-api-calls"].concat(args) : args;

	public static function run(cmd:String, args:Array<String>, ?env:Map<String, String>) {
		args = nodeArgs(cmd, args);
		var saved = new Map<String, Null<String>>();
		if (env != null) for (k => v in env) {
			saved.set(k, Sys.getEnv(k));
			Sys.putEnv(k, v);
		}
		var code = Sys.command(cmd, args);
		// (null: unset again, not left empty: the variables as they were before)
		for (k => v in saved) Sys.putEnv(k, v);
		if (code != 0) throw new Failed('${[cmd].concat(args).join(" ")}: exit code $code');
	}

	public static function shell(cmd:String)
		run("sh", ["-c", cmd]);

	// a program's output must contain `text`
	// (and exit with `want`, 0 by default; env's variables set for it, then
	// given back their values)
	public static function expect(cmd:String, args:Array<String>, env:Map<String, String>, text:String, want = 0) {
		var saved = new Map<String, Null<String>>();
		for (k => v in env) {
			saved.set(k, Sys.getEnv(k));
			Sys.putEnv(k, v);
		}
		var p = new Process(cmd, args);
		var r = drain(p), out = r.out + r.err;
		var code = p.exitCode();
		p.close();
		// (null: unset again, not left empty: the variables as they were before)
		for (k => v in saved) Sys.putEnv(k, v);
		Sys.print(out);
		if (code != want || !out.contains(text)) throw new Failed('${[cmd].concat(args).join(" ")}: expected "$text" (exit code $code, not $want)');
	}

	// each item in a thread, half the cores' worth at once (each build is parallel itself)
	public static function parallel<T>(items:Array<T>, f:T->Void) {
		var jobs = workerCount ?? Std.int(Math.max(1, cpus() / 2));
		var queue = items.copy();
		var mutex = new sys.thread.Mutex();
		var done = new sys.thread.Lock();
		var workers = Std.int(Math.min(jobs, queue.length));
		for (_ in 0...workers)
			sys.thread.Thread.create(() -> {
				while (true) {
					mutex.acquire();
					var item = queue.shift();
					mutex.release();
					if (item == null) break;
					f(item);
				}
				done.release();
			});
		for (_ in 0...workers) done.wait();
	}

	public static function cpus():Int {
		var n = Std.parseInt(Sys.getEnv("NUMBER_OF_PROCESSORS") ?? "");
		if (n != null) return n;
		try {
			var p = new Process("getconf", ["_NPROCESSORS_ONLN"]);
			n = Std.parseInt(p.stdout.readAll().toString().trim());
			p.close();
		} catch (_) {}
		return n ?? 4;
	}

	// hxmc's name of this machine
	public static function hostTarget():String {
		var os = switch Sys.systemName() {
			case "Windows": "windows";
			case "Mac": "macos";
			case _: "linux";
		}
		var arch = if (os == "windows") Sys.getEnv("PROCESSOR_ARCHITECTURE") ?? "AMD64" else {
			var p = new Process("uname", ["-m"]);
			var m = p.stdout.readAll().toString().trim();
			p.close();
			m;
		}
		return os + "-" + (["aarch64", "arm64", "ARM64"].contains(arch) ? "arm64" : "x86_64");
	}

	public static function mkdirs(dir:String)
		if (dir != "" && !FileSystem.exists(dir)) FileSystem.createDirectory(dir);

	// (only under bin/; a link is removed, never followed: a link to the
	// checkout once took the checkout with it)
	public static function rmrf(path:String) {
		// (bin/ there first: fullPath fails on a path that is not, a job's first lane's rmrf)
		mkdirs("bin");
		var bin = FileSystem.fullPath("bin");
		var parent = FileSystem.fullPath(Path.directory(FileSystem.absolutePath(path)));
		if (bin == null || parent == null || !(parent + "/").startsWith(bin + "/") && parent != bin)
			throw new Failed('rmrf: $path is not under bin/');
		removeTree(path);
	}

	public static function removeTree(path:String) {
		if (!FileSystem.exists(path)) return;
		var abs = FileSystem.absolutePath(path);
		var real = FileSystem.fullPath(abs);
		var parent = FileSystem.fullPath(Path.directory(abs));
		// (compared normalised: Windows' slashes and its drive letter's case may differ)
		inline function same(a:String, b:String)
			return Sys.systemName() == "Windows" ? Path.normalize(a).toLowerCase() == Path.normalize(b).toLowerCase() : a == b;
		if (!same(real, Path.join([parent, Path.withoutDirectory(abs)]))) {
			FileSystem.deleteFile(abs); // a link: the link alone
			return;
		}
		if (FileSystem.isDirectory(abs)) {
			for (f in FileSystem.readDirectory(abs)) removeTree('$abs/$f');
			FileSystem.deleteDirectory(abs);
		} else FileSystem.deleteFile(abs);
	}
}
