package helder.typescript.check;

import haxe.io.Path;
import helder.css.CssDiagnostic;
import helder.css.CssScope;
import sys.FileSystem;

using StringTools;

private typedef Candidate = {source:Null<String>, module:Null<CssScopeTypeScript>};

class CssModules {
	public final root:String;
	public final overlay:Dynamic = {};
	public var revision(default, null) = 0;
	public final active:Map<String, CssScopeTypeScript> = [];
	final candidates:Map<String, Candidate> = [];
	final virtualSources:Map<String, Bool> = [];

	public function new(root:String) this.root = FileSystem.fullPath(root);

	public function synthetic(file:String):Bool return virtualSources.exists(file);

	// Seed the virtual declarations where tsgo will look for them. Its
	// resolver still decides which substitution or fallback wins.
	public function discover(importer:String, name:String, options:Dynamic) {
		if (Path.isAbsolute(name)) add(name);
		else if (name.startsWith("./") || name.startsWith("../")) add(Path.join([Path.directory(importer), name]));
		else {
			var paths:Dynamic = options.paths;
			var base:Null<String> = options.baseUrl;
			if (paths != null) {
				var key = name, capture = "";
				if (!Reflect.hasField(paths, key)) {
					key = null;
					var longest = -1;
					for (pattern in Reflect.fields(paths)) {
						var star = pattern.indexOf("*");
						if (star <= longest) continue;
						var prefix = pattern.substr(0, star), suffix = pattern.substr(star + 1);
						if (name.length < prefix.length + suffix.length || !name.startsWith(prefix) || !name.endsWith(suffix)) continue;
						key = pattern;
						longest = star;
						capture = name.substr(star, name.length - star - suffix.length);
					}
				}
				if (key != null) {
					var directory = base ?? options.pathsBasePath ?? Sys.getCwd();
					var substitutions:Array<String> = Reflect.field(paths, key);
					for (path in substitutions) {
						var star = path.indexOf("*");
						if (star >= 0) path = path.substr(0, star) + capture + path.substr(star + 1);
						add(Path.isAbsolute(path) ? path : Path.join([directory, path]));
					}
				}
			}
			if (base != null) add(Path.join([base, name]));
		}
	}

	function add(path:String) {
		if (!path.endsWith(".css") || !FileSystem.exists(path) || FileSystem.isDirectory(path)) return;
		path = Path.normalize(path);
		var declaration = path.substr(0, path.length - 4) + ".d.css.ts";
		if (candidates.exists(declaration)) return;
		var css = path.endsWith(".module.css") ? CssScope.typescript(Path.normalize(FileSystem.fullPath(path)), {root: root}) : null;
		var source = css == null ? null : Path.normalize(FileSystem.fullPath(path)) + ".helder.ts";
		if (source != null) while (FileSystem.exists(source)) source += ".ts";
		candidates.set(declaration, {source: source, module: css});
		Reflect.setField(overlay, declaration, css == null ? "export {};" : css.declaration);
		if (source != null) {
			virtualSources.set(source, true);
			Reflect.setField(overlay, source, css.source);
		}
		revision++;
	}

	public function resolve(target:String, watch:Array<String>, fail:String->Dynamic):Null<String> {
		var candidate = candidates.get(target);
		if (candidate == null) return null;
		var css = candidate.module;
		if (css == null) return fail('only *.module.css imports are supported');
		if (active.exists(candidate.source)) return candidate.source;
		active.set(candidate.source, css);
		for (file in css.files) if (!watch.contains(file)) watch.push(file);
		return candidate.source;
	}

	public function report() {
		var errors = [];
		for (css in active) for (d in css.diagnostics) {
			var message = '${Project.relative(d.file)}:${d.line}:${d.column}: TSHX001: ${d.message}';
			if (d.severity == Error) errors.push(message) else Sys.stderr().writeString(message + "\n");
		}
		if (errors.length > 0) throw errors.join("\n");
	}
}
