package studio;

import haxe.crypto.Md5;
import haxe.io.Path;

using StringTools;

// The project's files as a frame's key reads them (Stills), in one walk:
// each source's text hashed and its local imports read (TypeScript's
// relative ones; Haxe's import and using by its class paths, and the files
// of its own package, which it reads unimported), the rest (assets,
// package.json, styles) and helder's files the screens are built with as
// one part. A screen's key: that part, its story file and what it imports
// in turn, its name; an edit to one story's file leaves the others' keys.
class Sources {
	public final base:String;
	final hashes = new Map<String, String>();
	final imports = new Map<String, Array<String>>();

	public static function of(project:Project):Sources
		return new Sources(project.dir, project.entry?.classPaths ?? [], project.mainFile());

	// (the program's main: what a scenario runs, in its key with its file)
	final main:Null<String>;

	public function new(root:String, classPaths:Array<String>, ?main:String) {
		this.main = main == null ? null : norm(main);
		var parts = ['format ${helder.ui.draw.FrameArchive.VERSION}', 'helder ${tools()}'];
		var dir = norm(root), roots = [dir].concat([for (c in classPaths) norm(c)]);
		function go(d:String)
			for (n in Files.list(d)) {
				// (what the studio writes itself, its canvas' places and the agent's notes, draws nothing of a story)
				if (n == "bin" || n == "node_modules" || n.startsWith(".") || n.endsWith(".helder") || n.endsWith(".md")) continue;
				var p = '$d/$n';
				if (Files.isDirectory(p)) {
					go(p);
					continue;
				}
				var st = try sys.FileSystem.stat(p) catch (_:Dynamic) null;
				if (st == null) continue;
				var rel = p.substr(dir.length);
				if (st.size < 1 << 20 && ~/\.(hx|tsx?)$/.match(n) && !n.endsWith(".d.ts")) {
					var text = sys.io.File.getContent(p);
					hashes.set(p, rel + " " + Md5.encode(text));
					imports.set(p, n.endsWith(".hx") ? hxImports(p, text, roots) : tsImports(p, text));
				} else {
					// (a style's or a manifest's text: a save of the same is the same; an asset's size and time)
					var text = st.size < 1 << 20 && ~/\.(json|css)$/.match(n);
					parts.push(rel + " " + (text ? Md5.encode(sys.io.File.getContent(p)) : stamp(p)));
				}
			}
		go(dir);
		parts.sort(Reflect.compare);
		base = Md5.encode(parts.join("\n"));
	}

	// a screen's key: the shared part, its story file and its imports', its name
	public function key(file:String, name:String):String {
		var story = norm(file), seen = new Map<String, Bool>(), todo = [story], out = [];
		if (Project.isScenario(story) && main != null) todo.push(main);
		// (a story file not read: every source)
		if (!hashes.exists(story)) return all(name);
		while (todo.length > 0) {
			var f = todo.pop();
			if (seen.exists(f)) continue;
			seen.set(f, true);
			// (a file outside the project: not walked, as helder's own)
			var h = hashes.get(f);
			if (h == null) continue;
			out.push(h);
			for (i in imports.get(f) ?? [])
				if (!seen.exists(i)) todo.push(i);
		}
		out.sort(Reflect.compare);
		return Md5.encode(base + "\n" + out.join("\n") + "\n" + name);
	}

	function all(name:String):String {
		var out = [for (h in hashes) h];
		out.sort(Reflect.compare);
		return Md5.encode(base + "\n" + out.join("\n") + "\n" + name);
	}

	// (relative imports and re-exports: ./x, ../y, resolved as TypeScript does)
	static final tsImport = ~/(?:\bfrom|\bimport|\bimport\s*\()\s*["'](\.{1,2}\/[^"']+)["']/;

	static function tsImports(file:String, text:String):Array<String> {
		var out = [], dir = Path.directory(file);
		while (tsImport.match(text)) {
			var spec = tsImport.matched(1);
			text = tsImport.matchedRight();
			var base = Path.normalize('$dir/$spec');
			if (base.endsWith(".js")) base = base.substr(0, base.length - 3);
			for (c in [base, '$base.ts', '$base.tsx', '$base/index.ts', '$base/index.tsx'])
				if (!Files.isDirectory(c) && sys.FileSystem.exists(c)) {
					out.push(c);
					break;
				}
		}
		return out;
	}

	static final hxImport = ~/^\s*(?:import|using)\s+([A-Za-z0-9_.]+)(\.\*)?\s*(?:as\s+\w+\s*)?;/m;

	// (its package's files, and those imported or used: a module's, or a package's all)
	static function hxImports(file:String, text:String, roots:Array<String>):Array<String> {
		var dir = Path.directory(file);
		var out = [for (n in Files.list(dir)) if (n.endsWith(".hx") && '$dir/$n' != file) '$dir/$n'];
		while (hxImport.match(text)) {
			var parts = hxImport.matched(1).split("."), star = hxImport.matched(2) != null;
			text = hxImport.matchedRight();
			for (r in roots) {
				if (star) {
					var d = r + "/" + parts.join("/");
					if (Files.isDirectory(d)) for (n in Files.list(d))
						if (n.endsWith(".hx")) out.push('$d/$n');
					continue;
				}
				// (a.b.C, or a.b.C.Sub: a type of the module C)
				for (k in [parts.length, parts.length - 1])
					if (k > 0) {
						var f = r + "/" + parts.slice(0, k).join("/") + ".hx";
						if (sys.FileSystem.exists(f)) out.push(f);
					}
			}
		}
		return out;
	}

	static function norm(p:String):String
		return Path.normalize(sys.FileSystem.fullPath(p)).split("\\").join("/");

	// (helder's files the screens are built with: their sizes and times, a
	// walk of a few ms kept for a moment: a save's patch asks again)
	static var helderKey = "";
	static var helderAt = -10.0;

	static function tools():String {
		var now = haxe.Timer.stamp();
		if (now - helderAt < 2) return helderKey;
		var parts = [];
		function go(d:String)
			for (n in Files.list(d)) {
				var p = '$d/$n';
				if (Files.isDirectory(p)) go(p) else parts.push(p + " " + stamp(p));
			}
		go(BuildInfo.helderSrc() + "/helder");
		parts.sort(Reflect.compare);
		helderAt = now;
		return helderKey = Md5.encode(parts.join("\n"));
	}

	static function stamp(p:String):String {
		var st = try sys.FileSystem.stat(p) catch (_:Dynamic) null;
		return st == null ? "-" : st.size + ":" + st.mtime.getTime();
	}
}
