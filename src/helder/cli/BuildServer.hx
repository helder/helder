package helder.cli;

import haxe.io.Path;
import helder.async.*;
import helder.cli.Compiler.CompileServer;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder build`'s compilation server, kept warm between builds: the first
// build of a project starts it (this program again, `helder __build-server`,
// in the background: a CompileServer of its own) and builds through it;
// the builds after it within IDLE seconds of the last (HELDER_BUILD_SERVER_IDLE,
// default 300) are warm, then it ends. Found by a file in helder's cache,
// <cache>/build-server/<key>.json ({port, token}), its key the CLI, the
// compiler, the project's root and the environment the compiler reads
// (HAXE*, HXMC*, HELDER*, RT_*): another of these is another server.
//
// Not helder dev's: its server is warm for dev builds (-D hxmc.dev, the
// dev host's defines), and a build of other defines through it is as cold
// as one without it, and leaves dev's next build cold too (measured on
// Little Skies: a release build between two dev builds, 7 s each, where the
// dev build alone is warm in 3-4 s). This one is beside dev's: a release
// build while dev runs is cold the first time, warm after.
//
// A request: one JSON line {words, cwd, sources} on a connection, the answer
// one line {ok, printed, messages} (or {error}: the compiler stopped). The
// project's .hx files changed since the last build (under sources) are
// invalidated first: the server compares a file's time, which two saves in
// one second share. A request at a time, in the order they came.
//
// One at a time: a server started asks the others (other projects') to end.
// Off with HELDER_BUILD_SERVER=0, and in CI (CI set) unless it is 1; any
// failure (it does not start, answer, or the compiler stopped) is a build
// without it, as before.
class BuildServer {
	static inline var COMMAND = "__build-server";

	final key:String;
	final sources:Array<String>;

	function new(key, sources) {
		this.key = key;
		this.sources = sources;
	}

	// the server for a build of this entry (null: off)
	public static function of(e:Entry):Null<BuildServer> {
		var v = Sys.getEnv("HELDER_BUILD_SERVER") ?? "";
		if (v == "0" || v == "false") return null;
		var ci = Sys.getEnv("CI") ?? "";
		if (v != "1" && ci != "" && ci != "0" && ci != "false") return null;
		// (the compiler's environment: what the server's builds would read)
		var env = Process.environment(), seen = [];
		for (k => x in env) {
			var u = k.toUpperCase();
			if (u.startsWith("HAXE") || u.startsWith("HXMC") || (u.startsWith("HELDER") && !u.startsWith("HELDER_BUILD_SERVER") && u != "HELDER_JOBS" && u != Slots.HELD) || u.startsWith("RT_")) seen.push('$u=$x');
		}
		seen.sort(Reflect.compare);
		var self = Sys.programPath();
		var stamp = try FileSystem.stat(self).mtime.getTime() catch (_:Dynamic) 0.0;
		var key = haxe.crypto.Md5.encode([self, Std.string(stamp), Compiler.tool(), FileSystem.fullPath(e.root)].concat(seen).join("\n")).substr(0, 16);
		return new BuildServer(key, [for (s in e.sources) FileSystem.fullPath(s)]);
	}

	static function dir():String
		return DevCommand.cache() + "/build-server";

	function file():String
		return '${dir()}/$key.json';

	// a build through it: null when it could not (none started, it did not
	// answer, its compiler stopped): the caller builds without it
	@:coroutine public function build(words:Array<String>, cwd:String):Null<{ok:Bool, printed:String, messages:String}> {
		var s = connect();
		if (s == null) {
			try FileSystem.deleteFile(file()) catch (_:Dynamic) {}
			if (!spawn()) return null;
			s = connect();
			if (s == null) return null;
		}
		var answer:Dynamic = try {
			s.writeString(haxe.Json.stringify({words: words, cwd: cwd, sources: sources}) + "\n");
			var line = new Reader(s).readLine();
			line == null ? null : haxe.Json.parse(line);
		} catch (_:Dynamic) null;
		s.close();
		if (answer == null || answer.error != null) return null;
		return {ok: answer.ok == true, printed: answer.printed ?? "", messages: answer.messages ?? ""};
	}

	// (the server its file names, connected; a local port that is listening
	// answers at once, Windows takes 2 s to refuse one that is not)
	@:coroutine function connect():Null<Socket> {
		var j:Dynamic = try haxe.Json.parse(File.getContent(file())) catch (_:Dynamic) null;
		if (j == null || j.port == null) return null;
		var port:Int = j.port;
		return try Async.timeout(1, _ -> Socket.connect("127.0.0.1", port)) catch (_:Dynamic) null;
	}

	// (started in the background, this program again: on Windows a copy of
	// it, which the checkout's rebuild of bin/cli/helder can rename over;
	// whether its file came within 10 s. One at a time: the others, other
	// projects' (a resident compiler holds a GB or more), asked to end first)
	@:coroutine function spawn():Bool {
		var exe = Sys.programPath();
		try {
			TestCommand.mkdirs(dir());
			if (Sys.systemName() == "Windows") exe = copy(exe);
		} catch (_:Dynamic) return false;
		for (f in (try FileSystem.readDirectory(dir()) catch (_:Dynamic) []))
			if (f.endsWith(".json") && f != '$key.json') {
				var other = new BuildServer(f.substr(0, f.length - 5), []);
				var s = other.connect();
				if (s == null) {
					try FileSystem.deleteFile('${dir()}/$f') catch (_:Dynamic) {}
					continue;
				}
				try s.writeString(haxe.Json.stringify({stop: true}) + "\n") catch (_:Dynamic) {}
				s.close();
			}
		var token = haxe.crypto.Md5.encode(Std.string(Math.random()) + Std.string(Sys.time())).substr(0, 12);
		var env = Process.environment();
		env.set("HELDER_BUILD_SERVER_TOOL", Compiler.tool());
		// (its std handles not inherited, Windows': the server would hold this
		// program's output open after it ends, a pipe reading it would not end)
		Term.noInherit();
		var p = try new Process(exe, [COMMAND, file(), token], {env: env}) catch (_:haxe.Exception) return false;
		p.closeStdin();
		p.close();
		var t0 = haxe.Timer.stamp();
		while (haxe.Timer.stamp() - t0 < 10) {
			// (another build's server, started at the same time, as good as this one)
			var j:Dynamic = try haxe.Json.parse(File.getContent(file())) catch (_:Dynamic) null;
			if (j != null && j.port != null) return true;
			Async.delay(0.025);
		}
		return false;
	}

	// (this program copied into the cache once per build of it; the copies
	// of other builds removed, those not running)
	static function copy(self:String):String {
		var stamp = try FileSystem.stat(self).mtime.getTime() catch (_:Dynamic) 0.0;
		var name = "helder-" + haxe.crypto.Md5.encode(self + "\n" + stamp).substr(0, 12) + ".exe";
		var to = '${dir()}/$name';
		if (FileSystem.exists(to)) return to;
		for (f in FileSystem.readDirectory(dir()))
			if (f.startsWith("helder-") && f.endsWith(".exe")) try FileSystem.deleteFile('${dir()}/$f') catch (_:Dynamic) {}
		var tmp = to + "." + Std.random(1 << 30);
		File.copy(self, tmp);
		FileSystem.rename(tmp, to);
		return to;
	}

	public static function isCommand(args:Array<String>):Bool
		return args[0] == COMMAND;

	// the server itself (`helder __build-server <file> <token>`): its file
	// written once it listens, removed when it ends (when it is still its)
	@:coroutine public static function serve(task:Node, args:Array<String>):Int {
		var file = args[1], token = args[2];
		if (file == null || token == null) return 2;
		Term.noInherit();
		var tool = Sys.getEnv("HELDER_BUILD_SERVER_TOOL");
		if (tool != null && tool != "") Compiler.use(tool);
		var idle = Std.parseFloat(Sys.getEnv("HELDER_BUILD_SERVER_IDLE") ?? "");
		if (Math.isNaN(idle) || idle <= 0) idle = 300;
		var cs = CompileServer.start(task);
		if (cs == null) return 1;
		var srv = Server.listen("127.0.0.1", 0);
		try File.saveContent(file, haxe.Json.stringify({port: srv.port, token: token})) catch (_:Dynamic) {
			srv.close();
			cs.stop();
			return 1;
		}
		var last = -1.0;
		while (true) {
			var s = try Async.timeout(idle, _ -> srv.accept()) catch (_:Dynamic) null;
			if (s == null) break;
			var stopped = false;
			try {
				var line = new Reader(s).readLine();
				var req:Dynamic = line == null ? null : haxe.Json.parse(line);
				if (req != null && req.stop == true) stopped = true;
				else if (req != null) {
					var words:Array<String> = req.words, cwd:String = req.cwd, sources:Array<String> = req.sources == null ? [] : req.sources;
					var start = Sys.time();
					if (last >= 0) for (f in changed(sources, last - 2)) cs.invalidate(f, cwd);
					last = start;
					var answer:Dynamic = try {
						var r = cs.service.build(words, cwd);
						{ok: r.ok, printed: r.printed, messages: r.messages};
					} catch (e:haxe.Exception) {
						stopped = true;
						{error: e.message};
					}
					s.writeString(haxe.Json.stringify(answer) + "\n");
				}
			} catch (_:Dynamic) {}
			s.close();
			if (stopped) break;
		}
		srv.close();
		var mine = try (haxe.Json.parse(File.getContent(file)).token == token) catch (_:Dynamic) false;
		if (mine) try FileSystem.deleteFile(file) catch (_:Dynamic) {}
		try cs.stop() catch (_:Dynamic) {}
		return 0;
	}

	// the .hx files under dirs changed since a time (not bin/, node_modules/, dot directories)
	static function changed(dirs:Array<String>, since:Float):Array<String> {
		var out = [];
		function walk(d:String)
			for (n in (try FileSystem.readDirectory(d) catch (_:Dynamic) [])) {
				if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
				var p = '$d/$n';
				if (FileSystem.isDirectory(p)) walk(p) else if (n.endsWith(".hx")) try {
					if (FileSystem.stat(p).mtime.getTime() / 1000 >= since) out.push(p);
				} catch (_:Dynamic) {}
			}
		for (d in dirs) walk(d);
		return out;
	}
}
