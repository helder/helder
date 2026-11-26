package helder.cli;

import helder.cli.Style.Tone;
import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import sys.FileSystem;

using StringTools;

// The compiler: helder's (hxmc's with helder's frontends: TypeScript, markup
// in any function), built from helder's sources by typescript(); without
// them (or node to build it), hxmc's native one from the platform package beside
// @hxmc/cli (node_modules/@hxmc/<os>-<cpu>, found from the working
// directory up, then from the CLI's own directory up), given what
// @hxmc/cli's launcher (hxmc/bootstrap/launcher.mjs) gives it: upstream's
// std (HAXE_STD_PATH) and hxmc's (HXMC_STD), so that no node runs (the
// runtime objects it finds itself). HAXE names another one
// (run as it is); without a platform package, node_modules/.bin/haxe (the
// launcher, under node), else `haxe` on the PATH.
class Compiler {
	static var found:Null<String> = null;

	// markup's braces read as code, as JSX (hxmc.markup-braces: <x y={a < b} />),
	// in every build but one given -D helder.markup-stock (Haxe's own reading)
	public static function markup(defines:Array<String>):Array<String>
		return Lambda.exists(defines, d -> d == "helder.markup-stock" || d.startsWith("helder.markup-stock=")) ? [] : ["-D", "hxmc.markup-braces"];

	public static function tool():String {
		if (found == null) found = find();
		return found;
	}

	// (the compiler another process chose: helder build's server, BuildServer)
	public static function use(tool:String)
		found = tool;

	static function find():String {
		runtimes();
		var env = Sys.getEnv("HAXE");
		if (env != null && env != "") return env;
		var prebuilt = Sys.getEnv("HELDER_COMPILER");
		if (prebuilt != null && FileSystem.exists(prebuilt)) return helders = prebuilt;
		var hxmc = native();
		var build = locate("src/helder/compiler/build.mjs") ?? locate("node_modules/helder/src/helder/compiler/build.mjs");
		if (build == null) return hxmc;
		return try own(Path.directory(Path.directory(Path.directory(build)))) catch (err:Dynamic) {
			Term.err(Style.status("warning", Warn, '$err\nhxmc\'s compiler instead: markup only in classes that implement helder.view.Markup'));
			hxmc;
		}
	}

	static var helders:Null<String> = null;

	static function native():String {
		var win = Sys.systemName() == "Windows";
		var cli = locate("node_modules/@hxmc/cli/package.json");
		if (cli != null) {
			var dir = Path.directory(Path.directory(cli));
			if ((Sys.getEnv("HXMC_STD") ?? "") == "") Sys.putEnv("HXMC_STD", '$dir/cli/hxmc/bootstrap/hxmc-std');
			var plat = platformPackage(), exe = '$dir/$plat/' + (win ? "haxe.exe" : "haxe");
			if (FileSystem.exists(exe)) {
				if ((Sys.getEnv("HAXE_STD_PATH") ?? "") == "") Sys.putEnv("HAXE_STD_PATH", '$dir/cli/haxe/upstream/std');
				// (the runtime objects: the compiler finds its own beside itself,
				// <its dir>/<target>/rt.o, and the other platform packages of its
				// version, cross builds', HXMC_RT_DIR's added: hxmc #93; Android's,
				// not on npm, fetched by Runtime.ensure into HXMC_RT_DIR)
				return exe;
			}
		}
		var bin = locate("node_modules/.bin/" + (win ? "haxe.cmd" : "haxe"));
		Term.err(Style.status("warning", Warn, 'no native compiler (node_modules/@hxmc/${platformPackage()}): ${bin ?? "haxe"} instead, through node'));
		return bin ?? (win ? "haxe.cmd" : "haxe");
	}

	// (the platform packages' runtime objects added to HXMC_RT_DIR, as the
	// launcher does: helder's compiler, in the cache, finds none beside itself,
	// and a build under the launcher (bun run test) inherits its HXMC_RT_DIR)
	static function runtimes() {
		var cli = locate("node_modules/@hxmc/cli/package.json");
		if (cli == null) return;
		var dir = Path.directory(Path.directory(cli)), sep = Sys.systemName() == "Windows" ? ";" : ":";
		var dirs = [for (d in (Sys.getEnv("HXMC_RT_DIR") ?? "").split(sep)) if (d != "") d];
		for (p in ["linux-x64", "linux-arm64", "darwin-arm64", "darwin-x64", "win32-x64", "win32-arm64"]) {
			var d = '$dir/$p';
			if (dirs.indexOf(d) < 0 && FileSystem.exists(d) && FileSystem.isDirectory(d) && Lambda.exists(FileSystem.readDirectory(d), t -> FileSystem.exists('$d/$t/rt.o')))
				dirs.push(d);
		}
		if (dirs.length > 0) Sys.putEnv("HXMC_RT_DIR", dirs.join(sep));
	}

	// helder's compiler in tool()'s place (TypeScript programs, helder.typescript):
	// hxmc's compiler with helder's hooks and frontends (helder.compiler),
	// built once per hxmc version and per its sources into the user's cache by
	// src/helder/compiler/build.mjs
	// (node: it fetches hxmc's compiler sources until npm ships them)
	public static function typescript(helder:String) {
		tool();
		if (helders != null) return;
		found = own(helder);
	}

	// (helder's compiler, built by build.mjs from helder's sources; hxmc's
	// native compiler's environment set first: its std). One that does not
	// build is the build's failure: its errors, and exit code 1 (not hxmc's
	// compiler in its place, which would build the program another way);
	// node not there to run build.mjs, a thrown error: find's warning and hxmc's
	static function own(helder:String):String {
		var node = Sys.getEnv("HELDER_NODE") ?? "node";
		var p = new sys.io.Process(node, ['$helder/helder/compiler/build.mjs']);
		// (stderr read beside stdout: a failed build's errors fill its pipe
		// before build.mjs ends, which would wait for stdout's reader forever)
		var errs = new sys.thread.Deque<String>();
		sys.thread.Thread.create(() -> errs.add(try p.stderr.readAll().toString() catch (_:Dynamic) ""));
		var exe = StringTools.trim(p.stdout.readAll().toString()), err = errs.pop(true), code = p.exitCode();
		p.close();
		if (code != 0 || !FileSystem.exists(exe)) {
			if (err.trim() != "") Term.err(err.trim());
			Term.err(Style.status("error", Fail, 'helder\'s compiler does not build (src/helder/compiler/build.mjs exited with $code)'));
			Sys.exit(1);
		}
		// (its first build in this cache: what it fetched and built)
		for (line in err.split("\n")) if (line != "") Term.err(Style.status("compiler", Info, line));
		helders = exe;
		return exe;
	}

	// hxmc's std, which a compilation server's builds are given last (as the
	// compiler gives its own builds: hxmc.HaxeMain), null if not known
	public static function hxmcStd():Null<String> {
		tool();
		var d = Sys.getEnv("HXMC_STD");
		return d != null && d != "" && FileSystem.exists(d) ? d : null;
	}

	// the first rel under the working directory or one above it, else under the CLI's directory or one above
	public static function locate(rel:String):Null<String> {
		for (start in [Sys.getCwd(), Path.directory(Sys.programPath())]) {
			var d = FileSystem.fullPath(start);
			while (d != null && d != "") {
				var p = Path.join([d, rel]);
				if (FileSystem.exists(p)) return p;
				var up = Path.directory(d);
				if (up == d || up == "") break;
				d = up;
			}
		}
		return null;
	}

	// npm's name of this machine's platform package (linux-x64)
	static function platformPackage():String {
		var t = hostTarget().split("-");
		return ["linux" => "linux", "macos" => "darwin", "windows" => "win32"][t[0]] + "-" + (t[1] == "arm64" ? "arm64" : "x64");
	}

	// hxmc's name of this machine (linux-x86_64)
	public static function hostTarget():String {
		#if (target.name == "hxmc")
		var os = ["linux", "macos", "windows", "wasi"][hxmc.Platform.os()];
		return os + "-" + (hxmc.Platform.arm() ? "arm64" : "x86_64");
		#else
		return (Sys.systemName() == "Windows" ? "windows" : Sys.systemName() == "Mac" ? "macos" : "linux") + "-x86_64";
		#end
	}

	// a compilation server for `--connect` (`haxe --wait <port>`): its port and
	// process (`process.stop()` ends it), null if none started
	@:coroutine public static function start():Null<{port:Int, process:Process}> {
		// (a free port: one the system gives, closed again)
		var s = Server.listen("127.0.0.1", 0);
		var port = s.port;
		s.close();
		var p = try new Process(tool(), ["--wait", Std.string(port)]) catch (_:haxe.Exception) return null;
		p.closeStdin();
		// (ready once it accepts a connection: one without a request leaves it running)
		for (_ in 0...50) {
			try {
				Socket.connect("127.0.0.1", port).close();
				return {port: port, process: p};
			} catch (_:haxe.Exception) {}
			Async.delay(0.1);
		}
		p.stop();
		p.close();
		return null;
	}
}

// The compiler as a resident compilation server the CLI drives, as
// @hxmc/cli's dev.mjs does: helder.compiler.service's (Service, Server: the
// compiler as a library, the studio's path too), what a build printed shown
// here. A request at a time.
class CompileServer {
	public final service:helder.compiler.service.Service;
	// the server's own output, the last of it (when it stops)
	public var output(get, never):String;

	function get_output():String
		return service.server.output;

	function new(service)
		this.service = service;

	// started, and connected (null: it did not connect)
	@:coroutine public static function start(task:Node):Null<CompileServer> {
		// (tool() first: it sets the compiler's variables, the std's)
		var tool = Compiler.tool(), env = Process.environment();
		BuildPhases.environment(env);
		var s = helder.compiler.service.Service.start(task, {tool: tool, env: env, std: Compiler.hxmcStd()}, m -> Term.err(Style.status("error", Fail, m)));
		if (s == null) return null;
		s.server.onOutput = BuildPhases.line;
		return new CompileServer(s);
	}

	// a build: its words, run in cwd; whether it compiled, its messages (errors and warnings)
	@:coroutine public function request(words:Array<String>, cwd:String):{ok:Bool, messages:String} {
		var r = service.build(words, cwd);
		BuildPhases.requested(r.ms);
		if (r.printed != "") Term.write(r.printed);
		return {ok: r.ok, messages: r.messages};
	}

	// a file changed: the server compares a file's time, which two saves in one second share
	@:coroutine public function invalidate(file:String, cwd:String)
		service.server.invalidate(file, cwd);

	@:coroutine public function stop()
		service.stop();
}
