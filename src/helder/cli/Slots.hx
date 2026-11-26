package helder.cli;

import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

using StringTools;

// A machine-wide limit on heavy work: compiles, test programs' runs, browser
// runs. Every worktree and session on the machine shares HELDER_JOBS slots in
// helder's cache (<cache>/slots), by default a quarter of the cores (at least
// one); HELDER_JOBS=0 is no limit (CI's runners are single-tenant).
//
// A slot is a directory <n> holding its holder's pid, when it was taken and a
// token of its own.
// It is made by renaming a directory of one's own onto <n>: a rename onto a
// directory that is not empty fails on every system, the one atomic exclusive
// step Haxe's sys API has (it has no O_EXCL, and its mkdir makes parents).
// A slot whose pid is gone, or now names a process started after the slot was
// taken (the pid reused), is free again. A child of a holder (HELDER_SLOT=1)
// runs under its parent's slot, so a holder never waits on itself.
//
// A load limit, not a lock: two processes freeing one dead slot at once can
// let one more in for a moment. src/helder/cli/slots.mjs is the same for
// node's scripts.
class Slots {
	public static inline var HELD = "HELDER_SLOT";

	public final dir:String;
	public final count:Int;
	// (read once: the lanes set HELDER_SLOT for their own children)
	final under = Sys.getEnv(HELD) == "1";

	public function new(dir:String, count:Int) {
		this.dir = dir;
		this.count = count;
	}

	public static function shared():Slots
		return new Slots(cache() + "/slots", jobs());

	// helder's cache, DevCommand.cache's (here too: the lanes type this file
	// on Eval, without the CLI)
	static function cache():String {
		var env = Sys.getEnv("HELDER_CACHE");
		if (env != null && env != "") return env.split("\\").join("/");
		var home = Sys.getEnv("HOME") ?? Sys.getEnv("USERPROFILE") ?? ".";
		return switch Sys.systemName() {
			case "Windows": (Sys.getEnv("LOCALAPPDATA") ?? '$home/AppData/Local').split("\\").join("/") + "/helder";
			case "Mac": '$home/Library/Caches/helder';
			case _: (Sys.getEnv("XDG_CACHE_HOME") ?? '$home/.cache') + "/helder";
		}
	}

	// HELDER_JOBS, else a quarter of the cores (at least one)
	public static function jobs():Int {
		var n = Std.parseInt(Sys.getEnv("HELDER_JOBS") ?? "");
		if (n != null && n >= 0) return n;
		return Std.int(Math.max(1, Math.floor(cores() / 4)));
	}

	public function off():Bool
		return count == 0 || under;

	// a slot now, else null (every slot held)
	public function tryTake():Null<Slot> {
		if (!FileSystem.exists(dir)) FileSystem.createDirectory(dir);
		var token = Std.string(Std.random(0x7fffffff)), mine = '$dir/.new-${pid()}-$token';
		FileSystem.createDirectory(mine);
		File.saveContent('$mine/owner', '${pid()} ${Std.int(Sys.time())} $token');
		try {
			for (pass in 0...2) {
				for (n in 0...count) if (rename(mine, '$dir/$n')) return new Slot('$dir/$n', token);
				// (all held: free the dead ones, then once more)
				var freed = false;
				for (n in 0...count) if (reclaim('$dir/$n')) freed = true;
				if (!freed) break;
			}
		} catch (e:haxe.Exception) {
			remove(mine);
			throw e;
		}
		remove(mine);
		return null;
	}

	// the slots held now (of every count's: another process' HELDER_JOBS may differ)
	public function busy():Int
		return !FileSystem.exists(dir) ? 0 : [for (f in FileSystem.readDirectory(dir)) if (~/^\d+$/.match(f)) f].length;

	// a slot, waiting for one (told once, with how many are busy); null: no limit
	public function take(?told:Int->Void):Null<Slot> {
		if (off()) return null;
		var delay = 0.05, said = false;
		while (true) {
			var s = tryTake();
			if (s != null) return s;
			if (!said) {
				said = true;
				if (told != null) told(busy()) else Sys.stderr().writeString('waiting for a build slot (${busy()} busy)\n');
			}
			Sys.sleep(delay);
			delay = Math.min(delay * 2, 1);
		}
	}

	// f under a slot, released after it whatever happens
	public function hold(f:Void->Void) {
		var s = take();
		try f() catch (e:haxe.Exception) {
			s?.release();
			throw e;
		}
		s?.release();
	}

	// (a dead holder's slot freed: renamed away first, so that one taken again
	// meanwhile is put back, not removed)
	function reclaim(slot:String):Bool {
		var o = owner(slot);
		if (o == null ? !old(slot) : alive(o.pid, o.since)) return false;
		var away = '$dir/.dead-${pid()}-${Std.random(0x7fffffff)}';
		if (!rename(slot, away)) return false;
		var now = owner(away);
		if (now?.token != o?.token) {
			rename(away, slot);
			return false;
		}
		remove(away);
		return true;
	}

	// (no owner a minute on: not a slot of ours)
	static function old(slot:String):Bool
		return try Date.now().getTime() - FileSystem.stat(slot).mtime.getTime() >= 60000 catch (_:Dynamic) false;

	public static function owner(slot:String):Null<{pid:Int, since:Float, token:String}> {
		var w = try File.getContent('$slot/owner').trim().split(" ") catch (_:haxe.Exception) return null;
		var p = Std.parseInt(w[0]), t = Std.parseFloat(w[1] ?? "");
		return p == null || Math.isNaN(t) || w.length < 3 ? null : {pid: p, since: t, token: w[2]};
	}

	// whether pid runs, and started before since (else the pid was reused);
	// a system that cannot say keeps it alive
	public static function alive(pid:Int, since:Float):Bool {
		var start:Null<Float> = try started(pid) catch (_:haxe.Exception) return true;
		return start != null && start <= since + 2;
	}

	// when pid started (seconds since 1970), null: not running
	static function started(pid:Int):Null<Float> {
		switch Sys.systemName() {
			case "Linux":
				var stat = '/proc/$pid/stat';
				if (!FileSystem.exists(stat)) return null;
				// (field 22, after the command's parenthesis: clock ticks since boot, 100 a second)
				var s = File.getContent(stat), f = s.substr(s.lastIndexOf(")") + 2).split(" ");
				var boot = ~/btime (\d+)/;
				if (!boot.match(File.getContent("/proc/stat"))) throw "no btime";
				return Std.parseFloat(boot.matched(1)) + Std.parseFloat(f[19]) / 100;
			case "Windows":
				var out = output("powershell", ["-NoProfile", "-Command",
					'$$p = Get-Process -Id $pid -ErrorAction SilentlyContinue; if ($$p) { ([DateTimeOffset]$$p.StartTime).ToUnixTimeSeconds() }']);
				return out == "" ? null : Std.parseFloat(out);
			case _:
				// (ps' elapsed time, [[dd-]hh:]mm:ss)
				var out = output("ps", ["-o", "etime=", "-p", Std.string(pid)]);
				if (out == "") return null;
				var secs = 0.0, days = out.split("-");
				for (p in days[days.length - 1].split(":")) secs = secs * 60 + Std.parseFloat(p);
				if (days.length > 1) secs += Std.parseFloat(days[0]) * 86400;
				return Sys.time() - secs;
		}
	}

	static var self:Null<Int> = null;

	// this process' pid
	public static function pid():Int {
		if (self != null) return self;
		#if (target.name == "hxmc" && hxmc.target != "wasm32-wasi")
		return self = hxmc.rt.Uv.getPid();
		#else
		// (Eval has none: the shell's parent)
		var out = Sys.systemName() == "Windows"
			? output("powershell", ["-NoProfile", "-Command", '(Get-CimInstance Win32_Process -Filter "ProcessId=$$PID").ParentProcessId'])
			: output("sh", ["-c", "echo $PPID"]);
		return self = Std.parseInt(out) ?? throw "no pid";
		#end
	}

	static function cores():Int {
		var n = Std.parseInt(Sys.getEnv("NUMBER_OF_PROCESSORS") ?? "");
		if (n != null) return n;
		return Std.parseInt(try output("getconf", ["_NPROCESSORS_ONLN"]) catch (_:haxe.Exception) "") ?? 4;
	}

	static function output(cmd:String, args:Array<String>):String {
		var p = new Process(cmd, args);
		var out = p.stdout.readAll().toString().trim();
		p.exitCode();
		p.close();
		return out;
	}

	static function rename(from:String, to:String):Bool
		return try {
			FileSystem.rename(from, to);
			true;
		} catch (_:Dynamic) false;

	static function remove(d:String) {
		try {
			for (f in FileSystem.readDirectory(d)) FileSystem.deleteFile('$d/$f');
			FileSystem.deleteDirectory(d);
		} catch (_:haxe.Exception) {}
	}
}

// A slot held (Slots.take): released by release(), or freed once its process ends
class Slot {
	public final path:String;
	final token:String;
	var released = false;

	public function new(path, token) {
		this.path = path;
		this.token = token;
	}

	public function release() {
		if (released) return;
		released = true;
		// (still ours: renamed away first, then removed)
		var o = Slots.owner(path);
		if (o == null || o.token != token) return;
		var away = haxe.io.Path.directory(path) + '/.done-$token';
		try FileSystem.rename(path, away) catch (_:Dynamic) return;
		try {
			for (f in FileSystem.readDirectory(away)) FileSystem.deleteFile('$away/$f');
			FileSystem.deleteDirectory(away);
		} catch (_:haxe.Exception) {}
	}
}
