package helder.cli;

import haxe.io.Bytes;
import haxe.io.Path;
import helder.async.*;
import helder.async.http.WebSocket;
import helder.compiler.service.LiteralEdit.Sources;
import helder.ui.draw.FrameArchive;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// `helder share --live`: a share kept live while this runs (helder.build's
// PLAN.md 2.7, S2), its owner the room's socket (wss://<api>/api/share/<name>/live,
// its first message the write key). The project's sources watched: a save
// that changed only live literals' values (LiteralEdit, against the tables
// the share's dev build wrote) is sent as patches, applied in Play at once;
// any other change builds and publishes the share's next version (ship),
// which helder.build tells the viewers of. The studio's frames file
// watched: each scene that changed is uploaded as a frames file of its
// own and named to the room, the Board swapping it in; the fonts the
// release's frames file stores (release: the Board read it) left out.
class Live {
	final socketUrl:String;
	final blobUrl:String;
	final key:String;
	final sources:Sources;
	final frames:Null<String>;
	final release:Null<String>;
	final roots:Array<String>;
	// a new version built and published (its number; null: it failed)
	final ship:Ship;
	var version:Int;
	var ws:Null<WebSocket> = null;
	// each scene's frames as last sent (its own file's sha256)
	var scenes = new Map<String, String>();
	var framesStamp = 0.0;

	public function new(api:String, name:String, key:String, version:Int, literals:String, frames:Null<String>, release:Null<String>,
			roots:Array<String>, ship:Ship) {
		socketUrl = ~/^http/.replace(api, "ws") + '/api/share/$name/live';
		blobUrl = api + '/api/share/$name/blob/';
		this.key = key;
		this.version = version;
		sources = new Sources(literals);
		sources.update();
		this.frames = frames;
		this.release = release;
		this.roots = roots;
		this.ship = ship;
	}

	@:coroutine public function run():Int {
		if (frames != null && FileSystem.exists(frames)) {
			framesStamp = FileSystem.stat(frames).mtime.getTime();
			for (s in split(File.getBytes(frames), had())) scenes.set(s.name, s.sha);
		}
		Async.scope(task -> {
			task.async(_ -> connect());
			var w = new SampledWatcher(0.05, 0.05);
			watch(w);
			while (true) {
				var changed = w.next();
				if (frames != null && changed.contains(frames)) pushFrames();
				var rest = [for (f in changed) if (f != frames) f];
				if (rest.length == 0) continue;
				var all = [], why = null;
				for (f in rest) {
					var p = FileSystem.exists(f) ? sources.patches(f, x -> why = x) : null;
					if (p == null) {
						all = null;
						break;
					}
					all = all.concat(p);
				}
				if (all != null) {
					if (all.length > 0 && send({t: "literals", build: version, patches: all})) {
						sources.took(all);
						Term.out(Style.status("patched", Ok, '${all.length} literal${all.length == 1 ? "" : "s"}' + Style.dim(Style.sep() + "nothing built")));
					}
					continue;
				}
				Term.out(Style.status("build", Info, Style.dim(why ?? "a change")));
				var v = ship();
				if (v != null) {
					version = v;
					sources.update();
				}
				watch(w);
			}
			null;
		});
		return 0;
	}

	// the room's socket, opened again when it closes
	@:coroutine function connect() {
		while (true) {
			var s = try WebSocket.open(socketUrl) catch (e:Dynamic) {
				Term.err(Style.status("live", Fail, 'the room: $e'));
				null;
			}
			if (s != null) {
				s.send(haxe.Json.stringify({t: "owner", key: key}));
				var m:Null<String>;
				while ((m = s.receive()) != null) {
					var j:Dynamic = try haxe.Json.parse(m) catch (_:Dynamic) null;
					if (j?.t == "ready") {
						ws = s;
						Term.out(Style.status("live", Ok, 'v${j.version}' + Style.dim(Style.sep() + "Play and the Board follow this project while this runs")));
					} else if (j?.t == "error") Term.err(Style.status("live", Fail, Std.string(j.why)));
				}
				ws = null;
				Term.out(Style.status("live", Info, Style.dim("the room's socket closed: again in 2 s")));
			}
			Async.delay(2);
		}
	}

	@:coroutine function send(m:Dynamic):Bool {
		var s = ws;
		if (s == null) return false;
		try s.send(haxe.Json.stringify(m)) catch (_:Dynamic) return false;
		return true;
	}

	// the scenes that changed in the studio's frames file: each uploaded as a file of its own, then named
	@:coroutine function pushFrames() {
		var t = FileSystem.exists(frames) ? FileSystem.stat(frames).mtime.getTime() : 0.0;
		if (t == framesStamp) return;
		framesStamp = t;
		var now = split(try File.getBytes(frames) catch (_:Dynamic) return, had());
		var changed:haxe.DynamicAccess<Null<String>> = {}, n = 0;
		var seen = new Map<String, Bool>();
		for (s in now) {
			seen.set(s.name, true);
			if (scenes.get(s.name) == s.sha) continue;
			var r = Publish.http("PUT", blobUrl + s.sha, ["Authorization: Bearer " + key, "Content-Type: application/octet-stream"], s.bytes);
			if (r.code != 200 && r.code != 201) {
				Term.err(Style.status("live", Fail, '${s.name}\'s frames: HTTP ${r.code} ${r.body.trim().substr(0, 200)}'));
				continue;
			}
			changed.set(s.name, s.sha);
			n++;
		}
		for (k in scenes.keys())
			if (!seen.exists(k)) {
				changed.set(k, null);
				n++;
			}
		if (n == 0 || !send({t: "frames", scenes: changed})) return;
		for (k => v in changed) if (v == null) scenes.remove(k) else scenes.set(k, v);
		Term.out(Style.status("frames", Ok, '$n scene${n == 1 ? "" : "s"}' + Style.dim(Style.sep() + [for (k in changed.keys()) k].join(", "))));
	}

	// the fonts the release's frames file stores
	function had():String->Bool {
		var a = release == null ? null : try FrameArchive.decode(File.getBytes(release)) catch (_:Dynamic) null;
		return a == null ? _ -> false : a.has;
	}

	// a frames file's scenes, each a portable file of its own (its fonts in it, but those had) and its sha256
	static function split(b:Bytes, had:String->Bool):Array<{name:String, sha:String, bytes:Bytes}> {
		var a = FrameArchive.decode(b);
		if (a == null) return [];
		return [
			for (n in a.names()) {
				var one = new FrameArchive();
				one.take(a, n, a.key(n) ?? "");
				var bytes = one.portable(had).encode();
				{name: n, sha: haxe.crypto.Sha256.make(bytes).toHex(), bytes: bytes};
			}
		];
	}

	// the sources under the project's roots (bin, node_modules and dotfiles left out), and the frames file
	function watch(w:SampledWatcher) {
		var files = [], dirs = [];
		function walk(d:String)
			for (n in (try FileSystem.readDirectory(d) catch (_:Dynamic) [])) {
				var p = '$d/$n';
				if (n.startsWith(".") || n == "bin" || n == "node_modules") continue;
				if (FileSystem.isDirectory(p)) {
					dirs.push(p);
					walk(p);
				} else if (n.endsWith(".hx") || ~/\.(m|c)?tsx?$/.match(n)) files.push(p);
			}
		for (r in roots) {
			dirs.push(r);
			walk(r);
		}
		if (frames != null) files.push(frames);
		w.watch(files, dirs, n -> n.endsWith(".hx") || ~/\.(m|c)?tsx?$/.match(n));
	}
}

// a new version built and published: its number (null: it failed)
typedef Ship = haxe.coro.Coroutine<Void->Null<Int>>;
