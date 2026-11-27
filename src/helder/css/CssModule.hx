package helder.css;

import helder.css.CssSheet;
#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.css.CssDiagnostic;
import helder.css.CssScope;
import sys.FileSystem;

using StringTools;
#end

// CSS modules in Haxe: `CssModule.load("card.module.css")` (beside the
// calling file, else under a class path) is the module's names, typed
// from the file: {final card:String, final title:String}, a dashed name
// camelCased (card-title: cardTitle), so a misspelt name is a type error.
// The file is scoped and compiled when the program is (CssScope, then
// CssTheme's prebuilt sheet: no parser linked) and its errors are the
// build's, at their line and column. Its sheet is registered once, when
// first loaded, after those it composes from: author sheets the cascade
// takes after a document's own (CssCascade.styles, themed). Under helder
// dev an edited module's sheet is swapped without a build (only dev
// builds link the parser for it); names it adds or drops need a build,
// and the log says so.
//
//   final card = CssModule.load("card.module.css");
//   el.className = card.title;   // "card_title_1a2b3c"
class CssModule {
	#if !macro
	static final list:Array<CssSheet> = [];
	static final at = new Map<String, Int>();
	static final watchers:Array<Void->Void> = [];

	// how many times the modules' sheets changed (one registered, or swapped)
	public static var version(default, null) = 0;

	// the modules' sheets registered, in order
	public static function sheets():Array<CssSheet>
		return list.copy();

	// f run after a module's sheet is registered or swapped; the function that stops it
	public static function watch(f:Void->Void):Void->Void {
		watchers.push(f);
		return () -> watchers.remove(f);
	}

	@:noCompletion public static function install(key:String, sheet:CssSheet) {
		if (at.exists(key)) return;
		at.set(key, list.length);
		list.push(sheet);
		changed();
	}

	static function changed() {
		version++;
		for (w in watchers.copy())
			w();
	}

	#if hxmc.dev
	// Composes can read sources on disk natively. Keep the current text where
	// the running app cannot read the project's files (the web or a device).
	static final devSources = new Map<String, String>();

	@:noCompletion public static function remember(file:String, text:String)
		devSources.set(file, text);
	#end

	// (helder dev, from the code CssModule makes in dev builds: the file's
	// new text scoped and compiled, the sheet swapped unless it has errors;
	// names: the build's, name=value lines. What it did, as the log says it)
	@:noCompletion public static function reload(key:String, file:String, root:String, names:String, text:String):String {
		#if hxmc.dev
		remember(file, text);
		#end
		var m = CssScope.compile(file, {root: root, read: f -> {
			if (f == file) return text;
			if (sys.FileSystem.exists(f)) return sys.io.File.getContent(f);
			#if hxmc.dev return devSources.get(f); #else return null; #end
		}});
		var base = haxe.io.Path.withoutDirectory(file), index = at.get(key);
		var errors = [for (d in m.diagnostics) if (d.severity == Error) '${d.file}:${d.line}:${d.column}: ${d.message}'];
		var said = if (index == null) '$base: not loaded by this build' else if (errors.length > 0) errors.concat(['$base not swapped: the last sheet stays']).join("\n") else {
			list[index] = CssScope.sheet(m);
			changed();
			var was = names == "" ? [] : [for (l in names.split("\n")) l.split("=")[0]], is = [for (n in m.names) n.name];
			var changes = [for (n in is) if (!was.contains(n)) "+" + n].concat([for (n in was) if (!is.contains(n)) "-" + n]);
			var now = CssScope.signature(m);
			if (now == names) '$base swapped, nothing built' else '$base swapped, but its names changed (${changes.length == 0 ? "what they compose" : changes.join(" ")}): rebuild to use them';
		}
		#if hxmc.dev
		for (l in said.split("\n"))
			Sys.stderr().writeString("helder.css: " + l + "\n");
		#end
		return said;
	}
	#end

	public static macro function load(path:haxe.macro.Expr.ExprOf<String>):haxe.macro.Expr {
		var p = switch path.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("CssModule.load: a string literal", path.pos);
		}
		var file = locate(p, Path.directory(Context.getPosInfos(path.pos).file));
		if (file == null) Context.error('CssModule.load("$p"): no such file beside the module or under a class path', path.pos);
		var type = define(file, path.pos);
		return macro @:pos(path.pos) $p{type.split(".").concat(["load"])}();
	}

	#if macro
	public static function defineTypeScript(files:Array<String>) {
		Context.onAfterInitMacros(() -> {
			var installs = [for (file in files) {
				var path = define(file, null, false).split(".").concat(["install"]);
				macro $p{path}();
			}];
			if (Context.defined("hxmc.dev")) installs.push(macro helder.typescript.js.Interop.hostLoop());
			var keep = macro class CssModuleKeep {
				static function __init__()
					if (helder.typescript.js.Interop.keeping()) $b{installs};
			};
			keep.pack = ["helder", "typescript"];
			// (nothing references it: full DCE would drop it, its __init__ with it)
			keep.meta = [{name: ":keep", pos: Context.currentPos()}];
			Context.defineType(keep);
		});
	}

	// The module's Haxe class made (once per file: its sheet, names, install()
	// registering it after those it composes from), its path; its errors the
	// build's. For TypeScript's frontend, CssScope.typescript's haxeType.
	public static function define(file:String, ?pos:Position, haxeNames = true):String {
		pos ??= Context.currentPos();
		var root = root(), m = CssScope.compile(FileSystem.fullPath(file), {root: root});
		if (haxeNames) for (f in m.files)
			Context.registerModuleDependency(Context.getLocalModule(), f);
		report(m.diagnostics, pos);
		if (haxeNames) checkFields(m, pos);
		return make(m, root, pos, !haxeNames);
	}

	static function make(m:CssScoped, root:String, pos:Position, typescript:Bool):String {
		var type = CssScope.typeName(m), name = type.split(".").pop();
		var exists = try Context.getType(type) != null catch (_:Dynamic) false;
		if (exists) return type;
		var deps = [for (d in m.composes) make(d, root, pos, typescript)];
		var fields:Array<Field> = [], values:Array<ObjectField> = [], seen = new Map<String, Bool>();
		for (n in m.names) {
			var f = field(n.name);
			if (f == null || seen.exists(f)) continue;
			seen.set(f, true);
			fields.push({name: f, access: [AFinal], kind: FVar(macro :String), pos: pos});
			values.push({field: f, expr: macro $v{n.value}});
		}
		var names:ComplexType = TAnonymous(fields);
		var sheet = macro helder.css.CssSheetData.decode($v{CssSheetData.encode(CssScope.sheet(m), false)});
		var installs = [for (d in deps) macro $p{d.split(".").concat(["install"])}()];
		if (Context.defined("hxmc.dev")) {
			var key = typescript ? CssScope.devKey(m.file) : assetKey(m.file, root);
			var dev = FileSystem.fullPath(m.file).split("\\").join("/");
			var text = sys.io.File.getContent(m.file);
			var lines = CssScope.signature(m);
			var marker = helder.asset.AssetMacro.key(key, false);
			installs.push(macro {
				helder.css.CssModule.remember($v{m.file}, $v{text});
				helder.asset.Assets.handle("css", $marker, _ -> helder.asset.Files.read($marker, $v{dev}), (_, fresh) -> {
					helder.css.CssModule.reload($v{m.key}, $v{m.file}, $v{root}, $v{lines}, fresh.toString());
					fresh;
				}, () -> haxe.io.Bytes.ofString($v{text}));
			});
		}
		var c = macro class $name {
			public static final names:$names = ${{expr: EObjectDecl(values), pos: pos}};
			public static final sheet:helder.css.CssSheet = @:privateAccess $sheet;
			static var installed = false;

			public static function install() {
				if (installed) return;
				installed = true;
				$b{installs};
				helder.css.CssModule.install($v{m.key}, sheet);
			}

			public static function load():$names {
				install();
				return names;
			}
		};
		c.pack = ["helder", "css", "modules"];
		c.meta = [{name: ":keep", pos: pos}];
		Context.defineType(c);
		return type;
	}

	// (errors the build's, at their file, line and column; warnings as warnings)
	static function report(list:Array<CssDiagnostic>, pos:Position) {
		var errors = [for (d in list) if (d.severity == Error) d];
		for (d in list)
			if (d.severity == Warning) Context.warning(d.message, position(d));
		for (k in 0...errors.length)
			if (k < errors.length - 1) Context.reportError(errors[k].message, position(errors[k])) else Context.error(errors[k].message, position(errors[k]));
	}

	// (a diagnostic's place as the compiler's: byte offsets in its file)
	static function position(d:CssDiagnostic):Position {
		var text = try sys.io.File.getContent(d.file) catch (_:Dynamic) "";
		inline function bytes(k:Int)
			return haxe.io.Bytes.ofString(text.substr(0, k)).length;
		return Context.makePosition({file: d.file, min: bytes(d.start), max: bytes(Std.int(Math.max(d.end, d.start + 1)))});
	}

	static function checkFields(m:CssScoped, pos:Position) {
		var seen = new Map<String, String>();
		for (n in m.names) {
			var f = field(n.name);
			if (f == null) Context.error('CssModule: .${n.name} (${Path.withoutDirectory(m.file)}) is no Haxe field name', pos);
			if (seen.exists(f)) Context.error('CssModule: .${n.name} and .${seen.get(f)} are both $f', pos);
			seen.set(f, n.name);
		}
		for (d in m.composes) checkFields(d, pos);
	}

	// (a name as a Haxe field: dashes camelCased; null when it can't be one)
	static function field(name:String):Null<String> {
		var parts = name.split("-"), out = parts[0];
		for (p in parts.slice(1))
			out += p.length == 0 ? "_" : p.charAt(0).toUpperCase() + p.substr(1);
		return ~/^[A-Za-z_][A-Za-z0-9_]*$/.match(out) && !KEYWORDS.contains(out) ? out : null;
	}

	static final KEYWORDS = [
		"abstract", "break", "case", "cast", "catch", "class", "continue", "default", "do", "dynamic", "else", "enum", "extends", "extern", "false", "final",
		"for", "function", "if", "implements", "import", "in", "inline", "interface", "macro", "new", "null", "operator", "overload", "override", "package",
		"private", "public", "return", "static", "switch", "this", "throw", "true", "try", "typedef", "untyped", "using", "var", "while"
	];

	// (the file's asset key, for helder dev's watcher: from the class path holding it, else the project)
	static function assetKey(file:String, root:String):String {
		var full = FileSystem.fullPath(file).split("\\").join("/");
		var cwd = Sys.getCwd();
		for (cp in Context.getClassPath().concat([root])) {
			var r = Path.removeTrailingSlashes((Path.isAbsolute(cp) ? cp : Path.join([cwd, cp])).split("\\").join("/"));
			r = try FileSystem.fullPath(r).split("\\").join("/") catch (_:Dynamic) r;
			if (full.startsWith(r + "/")) return full.substr(r.length + 1);
		}
		return full;
	}

	static function root():String {
		var r = Context.definedValue("helder.root");
		return FileSystem.fullPath(r != null && r != "" ? r : Sys.getCwd());
	}

	// (beside the calling module, a link to it followed, else under a class path)
	static function locate(path:String, dir:String):Null<String> {
		if (Path.isAbsolute(path)) return FileSystem.exists(path) ? path : null;
		for (d in [dir, try Path.directory(FileSystem.fullPath(dir + "/.")) catch (_:Dynamic) dir]) {
			var beside = Path.join([d, path]);
			if (FileSystem.exists(beside)) return beside;
		}
		return try Context.resolvePath(path) catch (_:Dynamic) null;
	}
	#end
}
