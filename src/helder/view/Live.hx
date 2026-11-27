package helder.view;

// Live literals' compile-time half (helder.dev.Literals is the program's),
// shared by Haxe's markup macro and TypeScript's lowering: which literals
// are live (Plan asks Target.live), their ids, kinds and anchors, and the
// table of a source's live literals that `helder dev` compares a saved file
// with (-D helder.literals=<dir>: <dir>/<md5 of the source>.json, `{file,
// entries: [{id, start, end, form}]}`, byte offsets; form: quoted, number,
// text, flag): an edit that changes only those spans' values patches the
// running program instead of building (helder.cli.LiteralEdit). Plain
// Haxe: no macro API.
class Live {
	// attributes never live: identities, references, a part's slot and
	// variant, a role, the style's own, an icon's or a field's name and type
	public static final FIXED = ["key", "ref", "tag", "id", "slot", "variant", "states", "role", "style", "name", "type"];

	public static function fixed(attr:String):Bool
		return FIXED.indexOf(attr) >= 0 || (StringTools.startsWith(attr, "on") && attr.length > 2);

	// a value naming env() (env(safe-area-inset-top), calc(env(...) + 8px)):
	// never live, so that the renderer binds it to the safe area as a
	// release build does (ui's SafeArea); its slot's read would be set as is,
	// a padding of "calc(env(...) + 8px)" a NaN
	public static function env(value:String):Bool
		return value.indexOf("env(") >= 0;

	// a string's kind: a CSS colour, a length (or lengths: "4 6", 50%), else a string
	public static function stringKind(s:String):String {
		var t = StringTools.trim(s);
		if (~/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.match(t) || ~/^(rgb|rgba|hsl|hsla|oklch|oklab)\(.*\)$/.match(t)) return "color";
		if (~/^-?[0-9.]+(px|%|em|rem|vw|vh|pt|dp)?(\s+-?[0-9.]+(px|%|em|rem|vw|vh|pt|dp)?)*$/.match(t)) return "length";
		return "string";
	}

	// 1-based line and byte column of an offset
	public static function lineColumn(content:String, offset:Int):{line:Int, column:Int} {
		var line = 1, start = 0;
		for (i in 0...offset) if (StringTools.fastCodeAt(content, i) == "\n".code) {
			line++;
			start = i + 1;
		}
		return {line: line, column: offset - start + 1};
	}

	// a literal's id: <file>:<line>:<column>:<kind>
	public static function id(file:String, content:String, start:Int, kind:String):String {
		var p = lineColumn(content, start);
		return shown(file) + ":" + p.line + ":" + p.column + ":" + kind;
	}

	// a web build's -D hxmc.paths (helder.cli.Entry): its ids name a file as
	// the program's strings do, by label (<project>/app.tsx), as hxmc's
	// Lower.shown names them: the program's ids and the table's the same,
	// and no one reading a share learns where it was built
	public static function paths(define:Null<String>) {
		if (define == pathsOf) return;
		pathsOf = define;
		dirs = [];
		if (define != null)
			for (pair in define.split(",")) {
				var eq = pair.lastIndexOf("=");
				if (eq <= 0) continue;
				var dir = haxe.io.Path.removeTrailingSlashes(pair.substr(0, eq)), label = pair.substr(eq + 1);
				var all = [dir];
				#if sys
				if (!haxe.io.Path.isAbsolute(dir)) all.push(haxe.io.Path.removeTrailingSlashes(sys.FileSystem.absolutePath(dir)));
				#end
				for (d in all.copy())
					for (other in [d.split("\\").join("/"), d.split("/").join("\\")])
						if (!all.contains(other)) all.push(other);
				for (d in all) dirs.push({dir: d, label: label});
			}
		dirs.sort((a, b) -> b.dir.length - a.dir.length);
	}

	static var pathsOf:Null<String> = null;
	static var dirs:Array<{dir:String, label:String}> = [];

	// a path as the program names it (paths' labels in front)
	public static function shown(s:String):String {
		for (p in dirs) {
			if (s.indexOf(p.dir) < 0) continue;
			s = s.split(p.dir + "/").join(p.label + "/").split(p.dir + "\\").join(p.label + "/");
			if (s == p.dir) s = p.label;
		}
		return s;
	}

	// a literal's anchor: its line's source, the literal and the line's other values left out
	public static function anchor(content:String, start:Int, end:Int):String {
		var a = start, b = end;
		while (a > 0 && StringTools.fastCodeAt(content, a - 1) != "\n".code) a--;
		while (b < content.length && StringTools.fastCodeAt(content, b) != "\n".code) b++;
		var line = content.substring(a, start) + "\x01" + content.substring(end, b);
		line = ~/"[^"\n]*"|'[^'\n]*'|-?\b[0-9][0-9a-fA-FxX.]*\b/g.replace(line, "_");
		return StringTools.trim(line);
	}

	// --- the tables

	static final tables = new Map<String, {hash:String, entries:Array<Entry>, ids:Map<String, Bool>}>();
	static final contents = new Map<String, {stamp:Float, read:Float, content:String, hash:String}>();

	// a source's content as the compiler read it (null: not readable). Kept
	// across a compile server's builds while its modification time stays,
	// but read again while that time was within 2 s of the last read: a
	// time has whole seconds, and two saves in one second (the studio's
	// inspector: an edit, then its undo) keep it, the second's content
	// otherwise read as the first's (its literals' ids and anchors off, the
	// slots of two literals crossed)
	public static function content(file:String):Null<{content:String, hash:String}> {
		var stamp = try sys.FileSystem.stat(file).mtime.getTime() catch (_:Dynamic) return null;
		var c = contents.get(file);
		if (c == null || c.stamp != stamp || c.read - stamp < 2000) {
			var text = try sys.io.File.getContent(file) catch (_:Dynamic) return null;
			var now = Date.now().getTime();
			c = c != null && c.content == text ? {stamp: stamp, read: now, content: text, hash: c.hash} : {stamp: stamp, read: now, content: text,
				hash: haxe.crypto.Md5.encode(text)};
			contents.set(file, c);
		}
		return c;
	}

	// the tables changed since the last flush
	static final dirty = new Map<String, String>();

	// a live literal of file recorded in dir's table of its content (written by flush)
	public static function record(dir:String, file:String, hash:String, entry:Entry) {
		var t = tables.get(file);
		if (t == null || t.hash != hash) {
			t = {hash: hash, entries: [], ids: new Map()};
			tables.set(file, t);
		}
		if (t.ids.exists(entry.id)) return;
		t.ids.set(entry.id, true);
		t.entries.push(entry);
		dirty.set(file, dir);
	}

	// whether tables wait for flush
	public static function pending():Bool
		return dirty.keys().hasNext();

	// the tables recorded since the last flush, written (the end of a build's typing, or of its lowering)
	public static function flush() {
		for (file => dir in dirty) {
			var t = tables.get(file);
			try {
				if (!sys.FileSystem.exists(dir)) sys.FileSystem.createDirectory(dir);
				sys.io.File.saveContent(dir + "/" + t.hash + ".json", haxe.Json.stringify({file: file, entries: t.entries}));
			} catch (_:Dynamic) {}
		}
		dirty.clear();
	}
}

typedef Entry = {id:String, start:Int, end:Int, form:String};
