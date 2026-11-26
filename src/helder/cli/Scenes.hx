package helder.cli;

import haxe.io.Path;
import helder.syntax.Document;
import helder.syntax.Scanner.Lang;
import sys.FileSystem;
import sys.io.File;

using StringTools;

// A TypeScript project's scenarios (its *.scenario.ts(x) files' exported
// scenario({...}) calls), and the main that runs the app at one of them
// (helder.scenario.Player): BOOT holds the app's root (hold()) before the
// app's modules run, the entry imports every scenario and the app's main,
// then plays one (name), else (null) the one the page's ?scenario= names,
// else the app from its start. The studio's Play from here writes it as
// PLAY; a share's web build (helder share) as SHARE: one build, every scene.
class Scenes {
	public static inline var PLAY = ".helder-play.tsx";
	public static inline var SHARE = ".helder-share.tsx";
	public static inline var BOOT = ".helder-play-boot.tsx";

	// the scenarios under dir (bin/ and node_modules/ left out), in path order, each in the order written
	public static function find(dir:String):Array<{name:String, binding:String, file:String}> {
		var out = [];
		function walk(d:String) {
			var names = FileSystem.readDirectory(d);
			names.sort(Reflect.compare);
			for (n in names) {
				if (n == "bin" || n == "node_modules" || n.startsWith(".")) continue;
				var p = '$d/$n';
				if (FileSystem.isDirectory(p)) walk(p) else if (~/\.scenario\.tsx?$/.match(n)) out = out.concat(of(p, File.getContent(p)));
			}
		}
		walk(dir);
		return out;
	}

	// a scenario file's scenarios bound to an exported name
	public static function of(file:String, text:String):Array<{name:String, binding:String, file:String}> {
		var doc = Document.parse(text, Lang.of(file)), out = [];
		for (c in doc.calls("scenario")) {
			var lit = c.object(0)?.field("name")?.literal();
			if (lit == null || c.name == null) continue;
			var t = lit.text(doc.text);
			out.push({name: t.length >= 2 ? t.substring(1, t.length - 1) : t, binding: c.name, file: file});
		}
		return out;
	}

	// the main written at dir/entry (PLAY or SHARE), BOOT beside it; main: the app's main file
	public static function entry(dir:String, entry:String, main:String, list:Array<{name:String, binding:String, file:String}>, name:Null<String>,
			why:String):String {
		var imports = [], names = [];
		for (k => s in list) {
			imports.push('import { ${s.binding} as s$k } from "${module(dir, s.file)}";');
			names.push('s$k');
		}
		save('$dir/$BOOT', '// $why: the app\'s root held for its scenarios ($entry)\nimport { hold } from "helder/scenario";\n\nhold();\n');
		var out = '$dir/$entry';
		save(out, '// $why: the app at a scenario\'s moment (written by helder, not to be edited)\n'
			+ 'import "./${Path.withoutExtension(BOOT)}";\n' + imports.join("\n") + '\nimport "${module(dir, main)}";\nimport { play } from "helder/scenario";\n\n'
			+ 'play([${names.join(", ")}]${name == null ? "" : ", " + haxe.Json.stringify(name)});\n');
		return out;
	}

	// (a file of the project as a module beside the entry: "./app.scenario")
	static function module(dir:String, file:String):String {
		var d = Path.normalize(FileSystem.fullPath(dir)), f = Path.normalize(FileSystem.fullPath(file));
		var rel = f.startsWith(d + "/") ? f.substr(d.length + 1) : Path.withoutDirectory(f);
		return "./" + Path.withoutExtension(rel);
	}

	static function save(path:String, text:String)
		if (!FileSystem.exists(path) || File.getContent(path) != text) File.saveContent(path, text);
}
