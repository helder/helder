package helder.typescript.check;

import haxe.io.Path;
import sys.FileSystem;
import helder.typescript.check.Ast;
import helder.typescript.check.Kind;
import helder.typescript.check.Kind.*;

using StringTools;

// What Project.walk asks of an import's target: whether a declaration file
// is helder's (its API, called through the manifest) or a package's types,
// which module system a package's JavaScript is written in, what to call it.
class Packages {
	// helder's own declaration files: under its sources, generated (they name
	// the Haxe they declare) or in the helder package
	public static function helders(file:String, globals:String):Bool {
		var src = Path.directory(Path.directory(Path.directory(globals)));
		if (file.startsWith(Path.addTrailingSlash(src))) return true;
		var text = sys.io.File.getContent(file);
		if (text.indexOf("__module") >= 0 || text.indexOf("__haxe") >= 0) return true;
		var json = manifest(file);
		return json != null && json.name == "helder";
	}

	// (the package.json of the package a file is in)
	static function manifest(file:String):Null<Dynamic> {
		var d = Path.directory(file);
		while (d != "" && Path.withoutDirectory(d) != "node_modules") {
			if (FileSystem.exists('$d/package.json')) return try haxe.Json.parse(sys.io.File.getContent('$d/package.json')) catch (_:Dynamic) null;
			var up = Path.directory(d);
			if (up == d) break;
			d = up;
		}
		return null;
	}

	// A package's entry by its `module` field, as bundlers read it, where it
	// has no `exports` (TypeScript reads `main`)
	public static function moduleField(specifier:String, file:String):String {
		if (specifier.startsWith(".") || specifier.startsWith("/") || name(specifier, "") != specifier) return file;
		var d = Path.directory(file);
		while (d != "" && !FileSystem.exists('$d/package.json')) {
			var up = Path.directory(d);
			d = up == d ? "" : up;
		}
		if (d == "" || !d.endsWith("/" + specifier)) return file;
		var json:Dynamic = try haxe.Json.parse(sys.io.File.getContent('$d/package.json')) catch (_:Dynamic) null;
		if (json == null || json.exports != null || !Std.isOfType(json.module, String)) return file;
		var entry = Path.normalize(Path.join([d, json.module]));
		return FileSystem.exists(entry) ? entry : file;
	}

	// a package's name from a specifier (`@scope/name/sub`, `name/sub`), else the file's path
	public static function name(specifier:String, file:String):String {
		if (specifier.startsWith(".") || specifier.startsWith("/")) return file;
		var parts = specifier.split("/");
		return specifier.startsWith("@") && parts.length > 1 ? parts[0] + "/" + parts[1] : parts[0];
	}

	// a file in CommonJS: .cjs, or no import or export of its own and a
	// `require(...)`, `module.exports` or `exports.x`
	public static function commonJS(sf:SourceFile):Bool {
		if (sf.path.endsWith(".cjs")) return true;
		if (!sf.path.endsWith(".js")) return false;
		for (n in sf.root.statements()) switch n.kind {
			case KindImportDeclaration | KindExportDeclaration | KindExportAssignment: return false;
			case _ if (Lambda.exists(n.modifiers() ?? [], m -> m.kind == KindExportKeyword)): return false;
			case _:
		}
		for (i in 1...sf.count) switch sf.kindAt(i) {
			case KindCallExpression:
				var callee = sf.node(i).expression();
				if (callee.kind == KindIdentifier && callee.text == "require") return true;
			case KindPropertyAccessExpression:
				var o = sf.node(i).expression();
				if (o.kind == KindIdentifier && (o.text == "exports" || o.text == "module" && sf.node(i).name().text == "exports")) return true;
			case _:
		}
		return false;
	}

	// an import or export of types only (`import type`, every name `type`)
	public static function typeOnly(n:Node):Bool {
		if (n.kind == KindExportDeclaration) return n.isTypeOnly();
		var clause = n.importClause();
		if (clause == null) return false;
		if (clause.isTypeOnly()) return true;
		var named = clause.namedBindings();
		return clause.name() == null && named != null && named.kind == KindNamedImports && named.elements().length > 0
			&& Lambda.foreach(named.elements(), e -> e.isTypeOnly());
	}

	// a declaration file that declares values (one of types only has nothing to run)
	public static function declaresValues(sf:SourceFile):Bool {
		for (n in sf.root.statements()) switch n.kind {
			case KindVariableStatement | KindFunctionDeclaration | KindClassDeclaration | KindEnumDeclaration | KindExportAssignment: return true;
			// (`export {}` makes a module of it)
			case KindExportDeclaration if (!n.isTypeOnly() && (n.moduleSpecifier() != null || n.exportClause() == null || n.exportClause().elements().length > 0)): return true;
			case KindModuleDeclaration if (n.name().kind != KindStringLiteral): return true;
			case _:
		}
		return false;
	}
}
