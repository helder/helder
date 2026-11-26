package helder.css;

import haxe.io.Path;
import helder.css.CssDiagnostic;
import helder.css.CssSheet;
import helder.css.CssToken;

using StringTools;

typedef CssScopeOptions = {
	// the project's folder: names are hashed by their file's path from it
	// (default: the working directory), so a build anywhere scopes alike
	?root:String,
	// a file's text, null when there is none (default: read from disk)
	?read:String->Null<String>
}

// A CSS module compiled (CssScope.compile): its file, its key (the file's
// name and hash, every scoped name's), the names it exports (as written, in
// order of appearance, to their scoped names, composed ones after them,
// space-joined), its rules scoped (composes taken out), the modules it
// composes from (their sheets go first), what went wrong (its own; the
// whole compile's at the top), and every file read.
typedef CssScoped = {
	file:String,
	key:String,
	names:Array<{name:String, value:String}>,
	rules:Array<CssRule>,
	composes:Array<CssScoped>,
	diagnostics:Array<CssDiagnostic>,
	files:Array<String>
}

// What TypeScript's frontend makes of a module imported (`import s from
// "./card.module.css"`): the module's source (its names, frozen, exactly
// typed) and its declaration (that type, as a .d.ts); the Haxe class
// holding its sheet (CssModule.define makes it: its install() registers the
// sheets, call it when the module is first imported); the diagnostics; the
// files read (a composed module's change changes this one).
typedef CssScopeTypeScript = {
	source:String,
	declaration:String,
	haxeType:String,
	diagnostics:Array<CssDiagnostic>,
	files:Array<String>
}

// CSS modules (as css-loader and Vite have them): a file's class names and
// ids scoped to it, `<file>_<name>_<hash>`, the hash of its path from the
// project; `:global(...)` leaves a selector's names as written,
// `:local(...)` scopes them again; `composes: a b`, `composes: a from
// "./other.module.css"` and `composes: a from global` in a rule of one
// class add those classes to its name. A missing name or file, and a
// cycle, are errors. It reads rules, not text, where it can: plain Haxe,
// run by the compiler (CssModule's macros, TypeScript's frontend) and by
// dev builds swapping a module's sheet.
class CssScope {
	public static function compile(file:String, ?options:CssScopeOptions):CssScoped {
		var b = new ScopeBuild(options ?? {});
		var m = b.module(Path.normalize(file), null);
		m.diagnostics = b.all;
		m.files = b.files;
		return m;
	}

	// the module's sheet, author, its rules compiled (an @import read beside it)
	public static function sheet(m:CssScoped, ?read:String->Null<String>):CssSheet {
		var load = (url:String) -> {
			var f = url.startsWith("file://") ? url.substr("file://".length) : null;
			f == null ? null : (read ?? ScopeBuild.disk)(f);
		};
		return CssSheet.of(m.rules, Author, {url: "file://" + Path.directory(sys.FileSystem.fullPath(m.file)) + "/", load: load});
	}

	// the Haxe class CssModule.define makes for it
	public static function typeName(m:CssScoped):String
		return "helder.css.modules.Css_" + m.key.replace("-", "_");

	// TypeScript's frontend's entry point: one per module file imported
	public static function typescript(file:String, ?options:CssScopeOptions):CssScopeTypeScript {
		var m = compile(file, options);
		var type = "{" + [for (n in m.names) 'readonly ${key(n.name)}: string'].join("; ") + "}";
		var value = "{" + [for (n in m.names) '${key(n.name)}: ${haxe.Json.stringify(n.value)}'].join(", ") + "}";
		var name = Path.withoutDirectory(m.file);
		return {
			source: '// $name: its names, scoped by helder.css (CssScope); its sheet is ${typeName(m)}\'s\n'
				+ 'const names: $type = Object.freeze($value);\nexport default names;\n',
			declaration: '// $name (helder.css: CssScope)\ndeclare const names: $type;\nexport default names;\n',
			haxeType: typeName(m),
			diagnostics: m.diagnostics,
			files: m.files
		};
	}

	// (a property key: an identifier as is, else quoted)
	static function key(name:String):String
		return ~/^[A-Za-z_$][A-Za-z0-9_$]*$/.match(name) ? name : haxe.Json.stringify(name);
}

private typedef Composing = {
	cls:String,
	names:Array<{name:String, start:Int, end:Int}>,
	// null: this file; "global": as written; else a module's path
	from:Null<String>,
	start:Int,
	end:Int
}

private class ScopeBuild {
	public final all:Array<CssDiagnostic> = [];
	public final files:Array<String> = [];
	final root:String;
	final read:String->Null<String>;
	final done = new Map<String, CssScoped>();
	final stack:Array<String> = [];

	public function new(options:CssScopeOptions) {
		root = Path.removeTrailingSlashes(Path.normalize(options.root ?? Sys.getCwd()));
		read = options.read ?? disk;
	}

	public static function disk(file:String):Null<String>
		return sys.FileSystem.exists(file) && !sys.FileSystem.isDirectory(file) ? sys.io.File.getContent(file) : null;

	// (site: where another module asked for it, for its errors)
	public function module(file:String, site:Null<{file:String, lines:CssLines, start:Int, end:Int}>):CssScoped {
		var known = done.get(file);
		if (known != null) return known;
		var base = Path.withoutDirectory(file), dot = base.indexOf(".");
		var stem = ~/[^A-Za-z0-9_-]/g.replace(dot > 0 ? base.substr(0, dot) : base, "_");
		if (stem == "" || ~/^[0-9-]/.match(stem)) stem = "_" + stem;
		var relative = file.startsWith(root + "/") ? file.substr(root.length + 1) : file;
		var hash = haxe.crypto.Md5.encode(relative).substr(0, 6);
		var m:CssScoped = {file: file, key: '${stem}_$hash', names: [], rules: [], composes: [], diagnostics: [], files: []};
		if (stack.contains(file)) {
			var trail = stack.slice(stack.indexOf(file)).concat([file]).map(f -> Path.withoutDirectory(f));
			if (site != null) error(m, site.file, site.lines, site.start, site.end, 'composes: a cycle: ${trail.join(" → ")}');
			return m;
		}
		var text = read(file);
		if (text == null) {
			if (site != null) error(m, site.file, site.lines, site.start, site.end, 'composes: no file ${Path.withoutDirectory(file)}')
			else error(m, file, new CssLines(""), 0, 0, 'no file $file');
			return m;
		}
		files.push(file);
		stack.push(file);
		new ModuleBuild(this, m, text, stem, hash).run();
		stack.pop();
		done.set(file, m);
		return m;
	}

	public function error(m:CssScoped, file:String, lines:CssLines, start:Int, end:Int, message:String) {
		var at = lines.at(start);
		var d:CssDiagnostic = {file: file, line: at.line, column: at.column, start: start, end: end, message: message, severity: Error};
		m.diagnostics.push(d);
		all.push(d);
	}
}

private class ModuleBuild {
	final build:ScopeBuild;
	final m:CssScoped;
	final lines:CssLines;
	final stem:String;
	final hash:String;
	// (local names in order of appearance; scoped name to name)
	final locals:Array<String> = [];
	final names = new Map<String, String>();
	final composing:Array<Composing> = [];
	final expanded = new Map<String, Array<String>>();

	public function new(build:ScopeBuild, m:CssScoped, text:String, stem:String, hash:String) {
		this.build = build;
		this.m = m;
		this.lines = new CssLines(text);
		this.stem = stem;
		this.hash = hash;
		m.rules = rules(Css.sheet(text));
	}

	public function run() {
		m.names = [for (n in locals) {name: n, value: expand(n, []).join(" ")}];
	}

	function scoped(name:String):String {
		var s = '${stem}_${name}_$hash';
		if (!names.exists(s)) {
			names.set(s, name);
			locals.push(name);
		}
		return s;
	}

	function error(start:Int, end:Int, message:String)
		build.error(m, m.file, lines, start, end, message);

	// (at-rules whose blocks hold style rules; @keyframes', @page's, @font-face's are not)
	static final GROUPING = ["media", "supports", "layer", "container", "scope", "starting-style"];

	function rules(list:Array<CssRule>):Array<CssRule>
		return [for (r in list) switch r {
			case Qualified(prelude, declarations, nested):
				var p = selector(prelude, false);
				var kept = [];
				for (d in declarations)
					if (Css.lower(d.name) == "composes") composes(p, d) else kept.push(d);
				Qualified(p, kept, rules(nested));
			case At(name, prelude, block) if (block != null && GROUPING.contains(Css.lower(name))): At(name, prelude, rules(block));
			case _: r;
		}];

	// (a selector's names scoped, unless global: :global(...) and :local(...) unwrapped)
	function selector(values:Array<CssValue>, global:Bool):Array<CssValue> {
		var out = [], k = 0;
		while (k < values.length) {
			var v = values[k], next = k + 1 < values.length ? values[k + 1] : null;
			switch v {
				case Token(c) if (c.kind.match(Colon) && next != null):
					switch next {
						case Function(f, args, _, _) if (["global", "local"].contains(Css.lower(f))):
							for (x in selector(args, Css.lower(f) == "global")) out.push(x);
							k += 2;
							continue;
						case Token(t) if (t.kind.match(Ident(_)) && ["global", "local"].contains(Css.lower(ident(t)))):
							var f = Css.lower(ident(t));
							error(c.start, t.end, ':$f takes a selector: :$f(.name)');
							k += 2;
							continue;
						case _:
							out.push(v);
					}
				case Token(d) if (!global && d.kind.match(Delim(".")) && next != null && next.match(Token(_.kind => Ident(_)))):
					var t = switch next {
						case Token(t): t;
						case _: throw "unreachable";
					}
					out.push(v);
					out.push(Token(new CssToken(Ident(scoped(ident(t))), t.start, t.end)));
					k += 2;
					continue;
				case Token(t) if (!global && t.kind.match(Hash(_, true))):
					var n = switch t.kind {
						case Hash(n, _): n;
						case _: "";
					}
					out.push(Token(new CssToken(Hash(scoped(n), true), t.start, t.end)));
				case Function(f, args, open, close):
					out.push(Function(f, selector(args, global), open, close));
				case Block(open, args, close) if (!open.kind.match(OpenSquare)):
					out.push(Block(open, selector(args, global), close));
				case _:
					out.push(v);
			}
			k++;
		}
		return out;
	}

	static function ident(t:CssToken):String
		return switch t.kind {
			case Ident(n): n;
			case _: "";
		}

	// (`composes: a b [from "path" | from global]`, in a rule of one class)
	function composes(prelude:Array<CssValue>, d:CssDeclaration) {
		var solid = [for (v in prelude) if (!v.match(Token(_.kind => Whitespace))) v];
		var cls = switch solid {
			case [Token(_.kind => Delim(".")), Token(_.kind => Ident(s))] if (names.exists(s)): names.get(s);
			case _: null;
		}
		if (cls == null) return error(d.start, d.end, "composes: only in a rule of one class (.name { composes: ... })");
		var items = [for (v in d.value) if (!v.match(Token(_.kind => Whitespace))) v];
		var c:Composing = {cls: cls, names: [], from: null, start: d.start, end: d.end}, k = 0;
		while (k < items.length) switch items[k] {
			case Token(t) if (t.kind.match(Ident(_)) && Css.lower(ident(t)) != "from"):
				c.names.push({name: ident(t), start: t.start, end: t.end});
				k++;
			case _:
				break;
		}
		if (c.names.length == 0) return error(d.start, d.end, "composes: no class named (composes: name)");
		if (k < items.length) {
			var ok = switch items.slice(k) {
				case [Token(_.kind => Ident(f)), Token(_.kind => Str(path))] if (Css.lower(f) == "from"):
					c.from = path;
					true;
				case [Token(_.kind => Ident(f)), Token(_.kind => Ident(g))] if (Css.lower(f) == "from" && Css.lower(g) == "global"):
					c.from = "global";
					true;
				case _: false;
			}
			if (!ok) return error(d.start, d.end, 'composes: names, then from "./file.module.css" or from global');
		}
		composing.push(c);
	}

	// (a class's scoped name and those it composes, in order, each once)
	function expand(name:String, trail:Array<String>):Array<String> {
		var known = expanded.get(name);
		if (known != null) return known;
		var out = ['${stem}_${name}_$hash'];
		function add(v:String)
			if (!out.contains(v)) out.push(v);
		for (c in composing)
			if (c.cls == name)
				for (n in c.names)
					switch c.from {
						case null if (!locals.contains(n.name)):
							error(n.start, n.end, 'composes: no class .${n.name} in this file');
						case null if (trail.contains(n.name) || n.name == name):
							var cycle = trail.concat([name, n.name]);
							error(n.start, n.end, 'composes: a cycle: ${[for (x in cycle.slice(cycle.indexOf(n.name))) "." + x].join(" → ")}');
						case null:
							for (v in expand(n.name, trail.concat([name])))
								add(v);
						case "global":
							add(n.name);
						case path:
							var file = Path.normalize(Path.isAbsolute(path) ? path : Path.join([Path.directory(m.file), path]));
							var other = build.module(file, {file: m.file, lines: lines, start: c.start, end: c.end});
							if (!m.composes.contains(other) && other.rules.length + other.names.length > 0) m.composes.push(other);
							if (other.names.length == 0 && other.rules.length == 0) continue;
							var found = Lambda.find(other.names, x -> x.name == n.name);
							if (found == null) error(n.start, n.end, 'composes: no class .${n.name} in $path') else for (v in found.value.split(" "))
								add(v);
					}
		expanded.set(name, out);
		return out;
	}
}
