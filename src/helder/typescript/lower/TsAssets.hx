package helder.typescript.lower;

import haxe.io.Path;
import sys.FileSystem;
import sys.io.File;
import helder.asset.AssetPath;
import helder.asset.Bundle;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;
import helder.typescript.check.Project;
import helder.typescript.lower.Definitions;

// helder/asset's definitions in TypeScript (image(path), font, model,
// sound, bytes; `import x from "./x.png" with {type: "image"}`): the file a
// path names, beside the program's file or in the project (-D helder.root,
// else the working directory), as Haxe's AssetMacro finds it under the
// class paths; and bundled as AssetMacro bundles it, when the build
// starts (Frontend.prepare: the executable's resources are the build's
// before it is typed): on desktop its bytes a resource of the executable
// (not in dev builds, which read it from disk; not when helder's CLI keeps
// it out, -D helder.asset.keep), for the web copied beside the module.
class TsAssets {
	public static final KINDS = ["image", "font", "model", "sound", "bytes", "strings"];

	// (an import's type attribute: the kind; the extensions each takes)
	public static final EXTENSIONS = [
		"image" => ["png", "jpg", "jpeg", "gif", "webp"], "font" => ["ttf", "otf"], "model" => ["glb", "gltf"], "sound" => ["wav", "ogg"]
	];

	// path's file (at: the call, its errors there; null when quiet and not found)
	public static function find(src:Project, kind:String, path:String, at:Node, defined:String->Null<String>, quiet = false):Null<String> {
		var what = 'Asset.$kind("$path")';
		var e = AssetPath.error(path);
		if (e != null) return quiet ? null : src.fail(at, '$what: $e');
		var root = Path.removeTrailingSlashes(root(defined));
		var roots = [Path.removeTrailingSlashes(Path.directory(FileSystem.fullPath(at.file.path))), root];
		var other = null;
		var f = Bundle.locate(path, roots, d -> try FileSystem.readDirectory(d) catch (_:Dynamic) null, c -> if (other == null) other = c);
		if (f != null && FileSystem.isDirectory(f) == (kind == "strings")) return f;
		if (quiet) return null;
		if (f != null) return src.fail(at, kind == "strings" ? '$what: expected a directory' : '$what: a directory');
		if (other != null) return src.fail(at, '$what: "${other.part}" is "${other.actual}" on disk (paths are case-sensitive on Android and the web)');
		return src.fail(at, '$what: no such file beside the program\'s file or in the project ($root)');
	}

	static function root(defined:String->Null<String>):String {
		var r = defined("helder.root");
		return r != null && r != "" ? r : Sys.getCwd();
	}

	// the call's arguments: the key's marker (Bundle's: the output has it
	// while the code naming it is there), the file where the program reads
	// it from disk (a dev build)
	public static function marker(path:String, sync = false):String
		return Bundle.MARK + (sync ? "now:" : "key:") + path + "\x01";

	public static function devFile(file:String, defined:String->Null<String>):Null<String>
		return defined("hxmc.dev") != null ? FileSystem.fullPath(file).split("\\").join("/") : null;

	// ---- when the build starts: the program's assets bundled

	// each asset the program names (a call of helder/asset's, an import of a
	// file with a type), as AssetMacro.bundle would
	public static function bundle(com:context.Common.CommonContext, src:Project) {
		function defined(name:String):Null<String>
			return core.Define.rawDefined(com.defines, name) ? core.Define.rawDefinedValueSafe(com.defines, name, "1") : null;
		if (defined("hxmc.dev") != null) return;
		var t = defined("hxmc.target") ?? "", keep = defined("helder.asset.keep");
		var kept:Null<Array<String>> = keep == null || keep == "" ? null : try haxe.Json.parse(File.getContent(keep)) catch (_:Dynamic) null;
		var seen = new Map<String, Bool>(), early = [];
		function add(key:String, file:String, sync:Bool) {
			if (sync && !early.contains(key)) early.push(key);
			if (seen.exists(key)) return;
			seen.set(key, true);
			if (t == "" || StringTools.startsWith(t, "linux-") || StringTools.startsWith(t, "macos-") || StringTools.startsWith(t, "windows-")) {
				if (kept != null && !kept.contains(key)) return;
				var header = haxe.io.Bytes.ofString(Bundle.MARK + "res:" + key + "\x01"), data = File.getBytes(file);
				var b = haxe.io.Bytes.alloc(header.length + data.length);
				b.blit(0, header, 0, header.length);
				b.blit(header.length, data, 0, data.length);
				com.resources.replace(Bundle.PREFIX + key, b);
			} else if (t == "wasm32-wasi" && keep == null && com.file != null && com.file != "") {
				var dest = Path.join([Path.directory(com.file), AssetPath.bundled(key)]);
				mkdirs(Path.directory(dest));
				File.copy(file, dest);
			}
		}
		for (a in uses(src)) {
			var file = find(src, a.kind, a.path, a.at, defined, true);
			if (file == null) continue;
			if (a.kind == "strings") {
				for (entry in catalogue(src, a.path, file, a.at, defined, false).files) add(entry.key, entry.file, true);
			} else add(a.path, file, false);
		}
		if (t == "wasm32-wasi" && keep == null && early.length > 0 && com.file != null && com.file != "")
			File.saveContent(com.file + ".assets.json", haxe.Json.stringify([for (key in early) AssetPath.bundled(key)]));
	}

	public static function catalogue(src:Project, path:String, folder:String, at:Node, defined:String->Null<String>, warn:Bool):helder.asset.StringFiles.StringProject {
		var base = root(defined);
		var prefix = Path.addTrailingSlash(FileSystem.fullPath(base)).split("\\").join("/");
		var full = FileSystem.fullPath(folder).split("\\").join("/");
		var key = StringTools.startsWith(full, prefix) ? full.substr(prefix.length) : path;
		return try helder.asset.StringFiles.read(key, folder, base, message -> {
			if (warn) Sys.stderr().writeString('Asset.strings("$path"): $message\n');
		}) catch (error:Dynamic) src.fail(at, 'Asset.strings("$path"): $error');
	}

	static function mkdirs(d:String)
		if (d != "" && !FileSystem.exists(d)) {
			mkdirs(Path.directory(d));
			FileSystem.createDirectory(d);
		}

	// the program's assets: its calls of helder/asset's kinds with a string, its imports of a file with a type
	public static function uses(src:Project):Array<{kind:String, path:String, at:Node}> {
		var out = [];
		for (sf in src.files) {
			for (i in 1...sf.count) if (sf.kindAt(i) == KindCallExpression) {
				var n = sf.node(i), callee = n.expression();
				if (callee.kind != KindIdentifier) continue;
				var from = Scope.imported(sf, callee.text);
				var args = n.arguments() ?? [];
				if (from == null || from.module != "helder/asset" || !KINDS.contains(from.name) || args.length != 1 || args[0].kind != KindStringLiteral) continue;
				out.push({kind: from.name, path: args[0].text, at: n});
			}
			for (s in sf.root.statements()) {
				var imp = imported(s);
				if (imp != null) out.push(imp);
			}
		}
		return out;
	}

	// an import of an asset: its kind (the type attribute), its path (null: not one)
	public static function imported(s:Node):Null<{kind:String, path:String, at:Node}> {
		if (s.kind != KindImportDeclaration) return null;
		var spec = s.moduleSpecifier().text;
		var kind:Null<String> = null;
		if (s.attributes() != null) {
			for (e in s.attributes().elements())
				if (e.name() != null && e.name().text == "type" && e.value() != null && e.value().kind == KindStringLiteral) kind = e.value().text;
		}
		if (kind == null) {
			// (the attributes from the source, where the tree has none of them)
			var text = s.file.slice(s.file.skipTrivia(s.pos), s.end);
			var r = ~/\bwith\s*\{\s*type\s*:\s*["']([a-z]+)["']\s*\}/;
			if (r.match(text)) kind = r.matched(1);
		}
		if (kind == null || kind == "strings" || !KINDS.contains(kind)) return null;
		return {kind: kind, path: StringTools.startsWith(spec, "./") ? spec.substr(2) : spec, at: s};
	}
}
