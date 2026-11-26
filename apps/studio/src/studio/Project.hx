package studio;

import haxe.io.Path;
#if !(hxmc.target == "wasm32-wasi")
import helder.cli.Entry;
import sys.FileSystem;
#end
import helder.syntax.Document;
import helder.syntax.Scanner.Lang;
import helder.view.graph.Graph.signal;

using StringTools;

// A project opened in the studio: its entry (helder.cli.Entry: what
// `helder dev` would build), its screens, and the program the studio builds
// of them.
//
// Screens (README.md, "Screens"): a project's screens are its stories,
// story({name: "Flow/Screen", width, height, render}) in its *.story.hx
// (Haxe) and *.story.tsx / *.story.ts (TypeScript) files, found under the
// project's directory; a screen's flow is its name's part before the last
// "/" (none: "Screens"), its size the story's (a phone's, 390x844, without).
// A project without stories has one screen: its own main's window, the flow
// "App". The stories are read from their text (helder.syntax), not built:
// the canvas lays them out before anything compiled; a story file's again
// when it changes (story: Studio's, then a build of the new host). A design file's frames
// (*.helder: DesignFile) are screens too, a flow a file, drawn by the
// studio itself (Designs: interpreted, nothing built); a project of design
// files alone has no program, nor an App screen.
//
// The program: a dev build (-D hxmc.dev: live literals, the devtools'
// agent, node <-> source mapping) for a headless run (-D helder.headless:
// offscreen, its frames to a file), its main the screens' host
// (helder.story.Screens over the stories: bin/studio/<name>/gen/StudioScreens.hx
// with the story files linked beside it as test files are, Foo_story.hx;
// TypeScript: bin/studio/<name>/screens.tsx importing them).
//
// In the browser (apps/studio/web) a project is the page's: its files a
// copy kept in OPFS (Files), its program a preview module for the web
// (helder.story.web.Preview over its stories) the page has, built where it
// came from (an example's, bundled with the page) or by the compiler's
// worker; links maps the build's paths (its sources' paths where it was
// built, which its live literals' ids and its nodes' sources name) to the
// project's.
class Project {
	// the project's directory (full path), its name
	public final dir:String;
	public final name:String;
	#if !(hxmc.target == "wasm32-wasi")
	// (null: a project of design files alone)
	public final entry:Null<Entry>;
	#end
	public final typescript:Bool;
	public final screens:Array<ScreenInfo> = [];
	// bumped when the screens change (a design file's frames added, removed,
	// renamed, moved or resized; a story file's stories: read again from its
	// text, Studio.changed)
	public final version = signal(0);
	// (the design files, their frames' screens; the story files, their stories)
	final designs:Array<String> = [];
	final frames = new Map<String, Array<ScreenInfo>>();
	final stories = new Map<String, Array<ScreenInfo>>();
	// (it has a program: its App screen when it has no stories)
	var program = false;
	// the live frames' places by their design files (DesignFile.places)
	final places = new Map<String, Array<DesignFile.Place>>();
	// where the studio's files for it go: <root>/bin/studio/<name>
	public final out:String;
	// the story files' links (Haxe): linked path to real path
	public final links = new Map<String, String>();

	#if (hxmc.target == "wasm32-wasi")
	// the preview's live literals' tables ({file: its built path, content, entries})
	public final tables:Array<Dynamic>;

	// (the page's project: studio.web.StudioWeb.project's)
	function new(info:Dynamic) {
		tables = info.tables ?? [];
		dir = info.dir;
		name = info.name;
		out = '$dir/bin/studio/$name';
		var l:haxe.DynamicAccess<String> = info.links ?? {};
		for (k => v in l)
			links.set(k, v);
		// (no App screen for design files alone: a new project's, an example's)
		findScreens(found(dir), info.preview == true || Lambda.exists(sources(), f -> !f.endsWith(".helder")));
		typescript = Lambda.exists(screens, s -> StringTools.endsWith(s.file, ".tsx") || StringTools.endsWith(s.file, ".ts"));
	}

	// the page's project (null: none opened)
	public static function opened():Null<Project> {
		var h = studio.web.StudioWeb.project();
		return h == 0 ? null : new Project(haxe.Json.parse(studio.web.StudioWeb.WebText.take(h)));
	}
	#else
	function new(dir:String) {
		var full = FileSystem.fullPath(dir).split("\\").join("/");
		// (a design file opened: its folder the project)
		this.dir = full.endsWith(".helder") && !FileSystem.isDirectory(full) ? Path.directory(full) : full;
		var files = found(this.dir);
		// (a folder of design files alone, or an empty one: a new project's, the blank sheet's)
		entry = try Entry.resolve(this.dir) catch (e:Dynamic) {
			if (!Lambda.exists(files, f -> f.endsWith(".helder")) && !empty(this.dir)) throw e;
			null;
		}
		typescript = entry != null && entry.typescript != null;
		name = entry?.name ?? Path.withoutDirectory(this.dir);
		// (the package's root, when the project is in it; else the project's own folder: an entry
		// outside any package has the working directory as its root, the CLI's, not the studio's)
		var root = entry == null ? this.dir : FileSystem.fullPath(entry.root).split("\\").join("/");
		if (root != this.dir && !this.dir.startsWith(root + "/")) root = this.dir;
		out = root + '/bin/studio/$name';
		findScreens(files, entry != null);
	}

	// (nothing in it but dotfiles: .git, .claude)
	static function empty(dir:String):Bool
		return !Lambda.exists(Files.list(dir), n -> !n.startsWith("."));

	// the project in dir (a thrown message: not one)
	public static function open(dir:String):Project
		return new Project(dir);
	#end

	// the story and design files under the project's directory, in path order
	public static function found(dir:String):Array<String> {
		var files = [];
		walk(dir, files);
		files.sort(Reflect.compare);
		return files;
	}

	// the design files' frames (each file a page, in path order), then the
	// stories of the story files, in path order, each in the order written;
	// the project's own main the App screen when it has one and no stories
	// (program: it has one)
	function findScreens(files:Array<String>, program:Bool) {
		this.program = program;
		for (f in files) {
			if (f.endsWith(".helder")) {
				designs.push(f);
				var d = try new DesignFile(Files.read(f)) catch (e:Dynamic) {
					Sys.println('studio: $f: $e');
					null;
				}
				frames.set(f, d == null ? [] : framesOf(f, d));
				if (d != null) places.set(f, d.places);
				continue;
			}
			var l = storiesOf(f, Files.read(f));
			if (l.length > 0) stories.set(f, l);
		}
		order();
	}

	// a story file's stories, read from its text (in the order written)
	function storiesOf(file:String, text:String):Array<ScreenInfo> {
		var doc = Document.parse(text, Lang.of(file)), out:Array<ScreenInfo> = [];
		var scenarios = isScenario(file);
		for (c in doc.calls(scenarios ? "scenario" : "story")) {
			var o = c.object(0);
			if (o == null) continue;
			// (a scenario's size: its own, else its main's <Surface>'s, else a phone's)
			var size = scenarios ? sizeOf(o, doc) ?? surface() : null;
			var n = o.field("name");
			var lit = n == null ? null : n.literal();
			if (lit == null) continue;
			var name = unquote(lit.text(doc.text));
			var cut = name.lastIndexOf("/");
			out.push({
				name: name,
				flow: cut < 0 ? "Screens" : name.substr(0, cut),
				label: cut < 0 ? name : name.substr(cut + 1),
				width: size?.width ?? num(o, "width", doc) ?? 390,
				height: size?.height ?? num(o, "height", doc) ?? 844,
				loop: seconds(o, "loop", doc),
				file: file,
				source: Story(c.name)
			});
		}
		return out;
	}

	// a story file's text now (null: it is gone): its stories read again;
	// whether the program's screens changed (a story added, removed,
	// renamed, resized or bound to another export: a build of a new host's)
	public function story(file:String, text:Null<String>):Bool {
		var was = key(live());
		// (the places of the screens whose names stay, their <Frame story> naming an export renamed: kept)
		var kept = [for (s in live()) if (s.at != null) s.name => s.at];
		var l = text == null ? [] : storiesOf(file, text);
		var before = stories.get(file);
		if (l.length == 0) stories.remove(file) else stories.set(file, l);
		order(kept);
		if (key(live()) == was) {
			// (the same screens: the ones the views have kept)
			if (before == null) stories.remove(file) else stories.set(file, before);
			order();
			return false;
		}
		version(v -> v + 1);
		return true;
	}

	static function key(l:Array<ScreenInfo>):String
		return [for (s in l) '${s.name}|${s.width}|${s.height}|${s.file}|${s.source}|${s.loop}'].join("\n");

	// whether a file holds stories (by its name)
	// the line (from 1) of a story's or scenario's call in its file's text, else 1
	public static function lineOf(file:String, text:String, name:String):Int {
		var doc = Document.parse(text, Lang.of(file));
		for (c in doc.calls(isScenario(file) ? "scenario" : "story")) {
			var lit = c.object(0)?.field("name")?.literal();
			if (lit != null && unquote(lit.text(doc.text)) == name) return doc.lineCol(c.callee.start).line;
		}
		return 1;
	}

	public static function isStory(f:String):Bool
		return f.endsWith(".story.hx") || f.endsWith(".story.tsx") || f.endsWith(".story.ts") || isScenario(f);

	// whether a file holds scenarios (helder.scenario: the program's main at its moments)
	public static function isScenario(f:String):Bool
		return f.endsWith(".scenario.hx") || f.endsWith(".scenario.tsx") || f.endsWith(".scenario.ts");

	// (size: [w, h])
	static function sizeOf(o:ObjectLit, doc:Document):Null<{width:Int, height:Int}> {
		var f = o.field("size");
		if (f == null) return null;
		var re = ~/^\[\s*(\d+)\s*,\s*(\d+)\s*\]$/;
		return re.match(doc.text.substring(f.first.start, f.last.end)) ? {width: Std.parseInt(re.matched(1)), height: Std.parseInt(re.matched(2))} : null;
	}

	// main's <Surface>'s width and height, read from its text (a number, or a
	// constant of one in main or a file it imports: W = 480); null: not said so
	function surface():Null<{width:Int, height:Int}> {
		var main = mainFile();
		if (main == null || !Files.exists(main)) return null;
		var text = Files.read(main);
		var tag = ~/<Surface\b([^>]*)>/;
		if (!tag.match(text)) return null;
		var attrs = tag.matched(1), texts = [text];
		var imp = ~/from\s*["'](\.{1,2}\/[^"']+)["']/, rest = text;
		while (imp.match(rest)) {
			rest = imp.matchedRight();
			for (ext in ["", ".ts", ".tsx", ".hx"]) {
				var f = Path.normalize(Path.directory(main) + "/" + imp.matched(1) + ext);
				if (Files.exists(f) && !Files.isDirectory(f)) {
					texts.push(Files.read(f));
					break;
				}
			}
		}
		function value(name:String):Null<Int> {
			var a = new EReg(name + "\\s*=\\s*\\{?\\s*([A-Za-z_0-9.]+)", "");
			if (!a.match(attrs)) return null;
			var v = a.matched(1), n = Std.parseInt(v);
			if (n != null) return n;
			for (t in texts) {
				var c = new EReg("\\b" + v + "\\s*(?::\\s*\\w+\\s*)?=\\s*(\\d+)", "");
				if (c.match(t)) return Std.parseInt(c.matched(1));
			}
			return null;
		}
		var w = value("width"), h = value("height");
		return w == null || h == null ? null : {width: w, height: h};
	}

	// the program's main file (TypeScript's entry; Haxe's main class's file), null: none
	public function mainFile():Null<String> {
		#if (hxmc.target == "wasm32-wasi")
		var m = Lambda.find(Files.list(dir), n -> ~/^main\.tsx?$/.match(n));
		return m == null ? null : '$dir/$m';
		#else
		if (entry == null) return null;
		if (entry.typescript != null) return entry.typescript;
		var a = entry.args(), k = a.indexOf("-main");
		if (k < 0) return null;
		for (c in entry.classPaths) {
			var f = c + "/" + a[k + 1].split(".").join("/") + ".hx";
			if (Files.exists(f)) return FileSystem.fullPath(f).split("\\").join("/");
		}
		return null;
		#end
	}

	// a design file's frames as screens: each named by the file's path and
	// its own name (app.helder#Home: no story's name, Flow/Screen, is one),
	// its page the file's path
	function framesOf(file:String, d:DesignFile):Array<ScreenInfo> {
		var page = file.substr(dir.length + 1), out:Array<ScreenInfo> = [];
		for (k in 0...d.frames.length) {
			var fr = d.frames[k], label = fr.name, n = 1;
			// (two frames of one name: the second's id its own)
			while (Lambda.exists(out, s -> s.label == label))
				label = '${fr.name} ${++n}';
			// (a group's frames placed by it: its first at the group's place, the others after it)
			var g = fr.group == null ? null : Lambda.find(d.groups, g -> g.title == fr.group);
			var first = g != null && !Lambda.exists(out, s -> s.group == fr.group);
			out.push({
				name: page + "#" + label,
				flow: page,
				label: label,
				width: fr.width,
				height: fr.height,
				file: file,
				source: Design(k),
				at: g == null ? fr.at : first ? g.at ?? fr.at : null,
				start: fr.start,
				cover: fr.cover,
				group: fr.group
			});
		}
		return out;
	}

	function order(?kept:Map<String, {x:Float, y:Float}>) {
		screens.resize(0);
		for (d in designs)
			for (s in frames.get(d))
				screens.push(s);
		var files = [for (f in stories.keys()) f];
		files.sort(Reflect.compare);
		var rest = [for (f in files) for (s in stories.get(f)) s];
		if (rest.length == 0 && program) rest.push({
			name: name,
			flow: "App",
			label: name,
			width: 0,
			height: 0,
			file: #if (hxmc.target == "wasm32-wasi") "" #else entry.typescript ?? "" #end,
			source: App
		});
		for (s in rest) {
			var p = placeOf(s);
			s.at = p?.at ?? (p == null ? kept?.get(s.name) : null);
			s.place = p == null ? null : {file: p.file, start: p.start};
			s.cover = p?.cover == true;
			screens.push(s);
		}
	}

	// a story's or the app's place: the first <Frame story> naming its file and
	// its export's or its own name (from that design file's folder), or <Frame app>
	function placeOf(s:ScreenInfo):Null<{file:String, at:Null<{x:Float, y:Float}>, start:Int, cover:Bool}> {
		for (d in designs) {
			var l = places.get(d);
			if (l != null)
				for (p in l)
					if (matches(d, p.ref, s)) return {file: d, at: p.at, start: p.start, cover: p.cover};
		}
		return null;
	}

	// (whether a place's reference names a screen)
	function matches(design:String, ref:String, s:ScreenInfo):Bool {
		if (ref == "app") return s.source.match(App);
		var hash = ref.lastIndexOf("#");
		if (hash < 0) return false;
		var file = Path.normalize(Path.directory(design) + "/" + ref.substr(0, hash)), name = ref.substr(hash + 1);
		return s.file == file && switch s.source {
			case Story(binding): binding == name || s.name == name;
			case _: false;
		}
	}

	// a story's or the app's reference from a design file (<Frame story=...>'s; "app")
	public function refOf(design:String, s:ScreenInfo):String
		return switch s.source {
			case Story(binding): studio.FileTree.relativeTo(Path.directory(design), s.file) + "#" + (binding ?? s.name);
			case _: "app";
		}

	// a design file's text now (null: it is gone): its frames read again
	// (one that does not read keeps the last ones, its frames show why);
	// the frames renamed (same place in the file, a new name) when their
	// names changed (one added, removed or renamed), else null
	public function design(file:String, text:Null<String>):Null<Array<{from:String, to:String}>> {
		var was = frames.get(file);
		var placed = places.get(file);
		var now = if (text == null) [] else {
			var d = try new DesignFile(text) catch (_:Dynamic) null;
			if (d == null) return null;
			places.set(file, d.places);
			framesOf(file, d);
		}
		if (text == null) places.remove(file);
		var moved = haxe.Json.stringify(placed) != haxe.Json.stringify(places.get(file));
		if (was != null && same(was, now) && !moved) return null;
		if (was == null) {
			designs.push(file);
			designs.sort(Reflect.compare);
		}
		if (text == null) {
			designs.remove(file);
			frames.remove(file);
		} else frames.set(file, now);
		order();
		version(v -> v + 1);
		// (moved or resized alone: nothing for the studio to follow)
		if (was != null && [for (s in was) s.name].join("\n") == [for (s in now) s.name].join("\n")) return null;
		var renamed = [];
		if (was != null)
			for (k in 0...Std.int(Math.min(was.length, now.length)))
				if (was[k].name != now[k].name) renamed.push({from: was[k].name, to: now[k].name});
		return renamed;
	}

	static function same(a:Array<ScreenInfo>, b:Array<ScreenInfo>):Bool {
		if (a.length != b.length) return false;
		for (k in 0...a.length) {
			var x = a[k], y = b[k];
			if (x.name != y.name || x.width != y.width || x.height != y.height || x.start != y.start || x.at?.x != y.at?.x || x.at?.y != y.at?.y
				|| x.group != y.group) return false;
		}
		return true;
	}

	// the design files (the pages drawn by the studio)
	public function designFiles():Array<String>
		return designs.copy();

	// the screens the project's program draws (its stories, or its App; not a design's frames)
	public function live():Array<ScreenInfo>
		return [for (s in screens) if (!s.source.match(Design(_))) s];

	static function walk(d:String, into:Array<String>) {
		for (n in Files.list(d)) {
			if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
			var p = '$d/$n';
			if (Files.isDirectory(p)) walk(p, into) else if (isStory(n) || n.endsWith(".helder")) into.push(p);
		}
	}

	// (a number literal's field, or null)
	static function seconds(o:ObjectLit, key:String, doc:Document):Null<Float> {
		var f = o.field(key);
		var l = f == null ? null : f.literal();
		var v = l == null ? Math.NaN : Std.parseFloat(l.text(doc.text));
		return Math.isNaN(v) || v <= 0 ? null : v;
	}

	static function num(o:ObjectLit, key:String, doc:Document):Null<Int> {
		var f = o.field(key);
		var l = f == null ? null : f.literal();
		return l == null ? null : Std.parseInt(l.text(doc.text));
	}

	static function unquote(s:String):String
		return s.length >= 2 && (s.charAt(0) == '"' || s.charAt(0) == "'") ? s.substring(1, s.length - 1) : s;

	// the project's cover (DESIGN.md §2): the screen whose <Frame> is flagged
	// cover (a design's, a story's or the app's), else the first: a design's
	// frame, else a story, else the app's
	public function cover():Null<ScreenInfo>
		return Lambda.find(screens, s -> s.cover == true) ?? screens[0];

	public function screen(name:String):Null<ScreenInfo>
		return Lambda.find(screens, s -> s.name == name);

	// the pages in order (a design file each, a story flow each, the App), each its screens
	public function flows():Array<{name:String, screens:Array<ScreenInfo>}> {
		version();
		var out:Array<{name:String, screens:Array<ScreenInfo>}> = [], keys = [];
		for (s in screens) {
			// (a design's page and a story's flow of one name are two)
			var key = (s.source.match(Design(_)) ? "design:" : "flow:") + s.flow, k = keys.indexOf(key);
			if (k < 0) {
				keys.push(key);
				out.push({name: s.flow, screens: []});
				k = out.length - 1;
			}
			out[k].screens.push(s);
		}
		return out;
	}

	#if !(hxmc.target == "wasm32-wasi")
	// the compiler's words for the screens' program into exe (its host's files written)
	// (web: the program for the browser, helder.story.Screens there the
	// preview host of a worker, helder.story.web.Preview: WebExport's)
	public function words(exe:String, web = false):Array<String> {
		var was = entry.target;
		if (web) entry.target = "web";
		var w = entry.args();
		entry.target = was;
		var host = Lambda.exists(screens, s -> s.source.match(Story(_)));
		if (host && typescript) {
			var main = writeTypescriptHost();
			w = [for (x in w) x.startsWith("helder.typescript=") ? 'helder.typescript=$main' : x];
		} else if (host) {
			var k = w.indexOf("-main");
			var roots = [];
			var gen = writeHaxeHost(w[k + 1], roots);
			w[k + 1] = "StudioScreens";
			w = ["-cp", gen].concat([for (r in roots) for (x in ["-cp", r]) x]).concat(w);
		}
		if (Lambda.exists(screens, s -> isScenario(s.file))) w = w.concat(["-D", "helder.scenarios"]);
		return w.concat(["-D", "hxmc.dev", "-D", "disable-hxb-cache"])
			.concat(web ? [] : ["-D", "helder.headless"])
			.concat(["-D", 'helder.name=$name', "--custom-target", 'hxmc=$exe']);
	}

	// (Haxe) the story files linked as modules (Foo.story.hx: Foo_story) and a
	// main over their stories; roots: the class paths of story files under
	// none of the project's (tests/viewer's: tests, by their package)
	function writeHaxeHost(main:String, roots:Array<String>):String {
		var gen = '$out/gen';
		var modules = [], acts = [];
		for (f in storyFiles()) {
			var cp = Lambda.find(entry.classPaths.map(c -> FileSystem.fullPath(c).split("\\").join("/")), c -> f.startsWith(c + "/")) ?? rootOf(f);
			if (cp == null) throw '$f: not under the project\'s class paths (${entry.classPaths.join(", ")}), and its package is not its folder';
			if (!entry.classPaths.contains(cp) && !roots.contains(cp)) roots.push(cp);
			var rel = f.substr(cp.length + 1), dirs = Path.directory(rel);
			var module = Path.withoutDirectory(rel);
			var scenario = isScenario(f);
			module = module.substr(0, module.length - (scenario ? ".scenario.hx" : ".story.hx").length) + (scenario ? "_scenario" : "_story");
			var linked = '$gen/' + (dirs == "" ? "" : dirs + "/") + module + ".hx";
			helder.cli.TestCommand.mkdirs(Path.directory(linked));
			helder.cli.Link.make(f, linked);
			links.set(linked, f);
			(scenario ? acts : modules).push(dirs == "" ? module : dirs.split("/").join(".") + "." + module);
		}
		var all = [for (m in modules) 'helder.story.Stories.of("$m")'].concat([for (m in acts) 'helder.scenario.Scenarios.of("$m")']);
		var args = '[${all.slice(0, modules.length).join(", ")}].flatten()' + (acts.length == 0 ? "" : ', [${all.slice(modules.length).join(", ")}].flatten()');
		// (main run once, first: its UiWindow.run keeps its root for the scenarios, -D helder.scenarios)
		var first = acts.length == 0 ? "" : '\t\t@:privateAccess $main.main();\n';
		save('$gen/StudioScreens.hx', '// helder studio\'s screens: the project\'s stories and scenarios (generated)\nusing Lambda;\n\nclass StudioScreens {\n\tstatic function main() {\n$first\t\thelder.story.Screens.run($args);\n\t}\n}\n');
		return gen;
	}

	// (a file's class path by its package line: the folder its package's folders are in; null: they are not its)
	static function rootOf(f:String):Null<String> {
		var re = ~/^\s*package\s+([\w.]*)\s*;/m;
		var pack = re.match(Files.read(f)) ? re.matched(1) : "";
		var dir = Path.directory(f), parts = pack == "" ? [] : pack.split(".");
		parts.reverse();
		for (p in parts) {
			if (Path.withoutDirectory(dir) != p) return null;
			dir = Path.directory(dir);
		}
		return dir;
	}

	// (TypeScript) a main importing the stories and the scenarios (each bound
	// to an exported name), and the program's main as a function (program.tsx)
	function writeTypescriptHost():String {
		helder.cli.TestCommand.mkdirs(out);
		var lines = ['// helder studio\'s screens: the project\'s stories and scenarios (generated)', 'import { screens } from "helder/story";'];
		var byFile = new Map<String, Array<String>>();
		var order = [], stories = [], scenarios = [], k = 0;
		for (s in screens) {
			var binding = switch s.source {
				case Story(b): b;
				case _: continue;
			}
			if (binding == null) throw '${s.file}: "${s.name}" is not bound to an exported name (export const x = ${isScenario(s.file) ? "scenario" : "story"}({...}))';
			if (!byFile.exists(s.file)) {
				byFile.set(s.file, []);
				order.push(s.file);
			}
			var alias = 's${k++}';
			byFile.get(s.file).push('$binding as $alias');
			(isScenario(s.file) ? scenarios : stories).push(alias);
		}
		for (f in order)
			lines.push('import { ${byFile.get(f).join(", ")} } from "${spec(f)}";');
		// (main run once, first: its UiWindow.run keeps its root for the scenarios, -D helder.scenarios)
		if (scenarios.length > 0) {
			lines.insert(2, 'import "${spec(entry.typescript)}";');
			lines.push('screens([${stories.join(", ")}], [${scenarios.join(", ")}]);');
		} else
			lines.push('screens([${stories.join(", ")}]);');
		var main = '$out/screens.tsx';
		save(main, lines.join("\n") + "\n");
		return main;
	}

	// (an import's specifier of a project's file from out)
	function spec(f:String):String {
		var rel = helder.cli.Link.relative(f, out);
		if (!rel.startsWith(".")) rel = "./" + rel;
		return ~/\.tsx?$/.replace(rel, "");
	}

	#end

	function storyFiles():Array<String> {
		var out = [];
		for (s in screens) if (s.source.match(Story(_)) && !out.contains(s.file)) out.push(s.file);
		return out;
	}

	// a source's path as the project's (a linked story file's: its real one)
	public function real(file:String):String
		return links.get(file) ?? file;

	// the project's source files (the code view's list): .hx, .ts, .tsx, .helder under its directory
	public function sources():Array<String> {
		var out = [];
		function go(d:String)
			for (n in Files.list(d)) {
				if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
				var p = '$d/$n';
				if (Files.isDirectory(p)) go(p) else if ((n.endsWith(".hx") || n.endsWith(".tsx") || n.endsWith(".ts") || n.endsWith(".helder")) && !n.endsWith(".d.ts")) out.push(p);
			}
		go(dir);
		out.sort(Reflect.compare);
		return out;
	}

	static function save(path:String, text:String)
		if (!Files.exists(path) || Files.read(path) != text) Files.save(path, text);
}

typedef ScreenInfo = {
	// the story's name (Flow/Screen), its flow and its own part
	name:String,
	flow:String,
	label:String,
	// points (0: the program's own window's)
	width:Int,
	height:Int,
	// its file (a story's, a design's), what draws it
	file:String,
	source:Source,
	// where it is on the canvas (canvas:at: a design's frame's own, a story's
	// or the app's from its <Frame story> or <Frame app>; null: laid out after
	// the placed ones); a design frame's element's offset
	?at:Null<{x:Float, y:Float}>,
	?start:Int,
	// (a story's or the app's: the design file and offset of its <Frame> placing it; null: none yet)
	?place:Null<{file:String, start:Int}>,
	// (its <Frame> flagged cover)
	?cover:Bool,
	// (a design's frame in a <Group>: its title)
	?group:Null<String>,
	// (a story's loop: seconds from its moment played while its frame is hovered)
	?loop:Null<Float>,
}

// What a screen's content is: a story of the program (the name it is bound
// to: TypeScript's import), the program's own main, a design file's frame
// (its index in the file: DesignFile.frames), interpreted by the studio
enum Source {
	Story(binding:Null<String>);
	App;
	Design(frame:Int);
}
