package helder.css;

import helder.css.CssSheet;
#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type.TypedExpr;
import sys.FileSystem;
import sys.io.File;

using haxe.macro.ExprTools;
#end

// Style sheets compiled at build time: the CSS (a file's or a string
// constant's) parsed by the compiler and the sheet written as data
// (CssSheetData: selectors with their specificity, Bloom hashes and
// buckets, declarations as property ids and typed values, @media's
// queries, @import's sheets read beside the file), read back when first
// asked. A program that styles with these alone (CssCascade.themed) links
// no CSS tokenizer or parser, and one decoder whatever its sheets: as code
// (a constructor per value) html.css took 958 KB, as data 58 KB, parsed
// when the program runs 198 KB and 1.4 ms, read as data 0.13 ms. var()
// is substituted when styles are computed, as ever. The sheets have no
// URL: url()s stay as written.
//
//   var theme = CssTheme.file("theme.css");  // beside the calling file, else under a class path
//   var base = CssTheme.sheet("button { padding: 4px 8px }");
//   var styles = CssCascade.themed(doc, [base, theme]);
class CssTheme {
	// origin: UserAgent, User or Author (the default)
	public static macro function sheet(text:haxe.macro.Expr.ExprOf<String>, ?origin:haxe.macro.Expr.ExprOf<CssOrigin>):haxe.macro.Expr.ExprOf<CssSheet> {
		var s = constant(try Context.typeExpr(text) catch (_:Dynamic) null);
		if (s == null) Context.error("CssTheme.sheet: not a constant (CssSheet.parse reads CSS when the program runs)", text.pos);
		return build(s, Path.directory(Context.getPosInfos(text.pos).file), originOf(origin), text.pos);
	}

	public static macro function file(path:haxe.macro.Expr.ExprOf<String>, ?origin:haxe.macro.Expr.ExprOf<CssOrigin>):haxe.macro.Expr.ExprOf<CssSheet> {
		var p = constant(try Context.typeExpr(path) catch (_:Dynamic) null);
		if (p == null) Context.error("CssTheme.file: not a constant", path.pos);
		var f = locate(p, Path.directory(Context.getPosInfos(path.pos).file));
		if (f == null) Context.error('CssTheme.file("$p"): no such file beside the module or under a class path', path.pos);
		Context.registerModuleDependency(Context.getLocalModule(), f);
		return build(File.getContent(f), Path.directory(f), originOf(origin), path.pos);
	}

	#if macro
	static function build(text:String, dir:String, origin:CssOrigin, pos:Position):Expr {
		// (one static per sheet, made once)
		var name = "Theme" + haxe.crypto.Md5.encode(dir + "\x00" + origin + "\x00" + text).substr(0, 12);
		var exists = try Context.getType("helder.css.themes." + name) != null catch (_:Dynamic) false;
		if (!exists) {
			var module = Context.getLocalModule();
			var load = (url:String) -> {
				var f = StringTools.startsWith(url, "file://") ? url.substr("file://".length) : null;
				if (f == null || !FileSystem.exists(f)) return null;
				Context.registerModuleDependency(module, f);
				File.getContent(f);
			};
			var sheet = try CssSheet.parse(text, origin, {url: "file://" + FileSystem.fullPath(dir) + "/", load: load})
				catch (e:Dynamic) Context.error('CssTheme: $e', pos);
			// (the sheet as CssSheetData's string, read when first asked)
			Context.defineType({
				pack: ["helder", "css", "themes"],
				name: name,
				pos: pos,
				kind: TDClass(),
				fields: [
					{name: "cache", access: [AStatic], kind: FVar(macro :Null<helder.css.CssSheet>, macro null), pos: pos},
					{
						name: "get",
						access: [APublic, AStatic],
						kind: FFun({args: [], ret: macro :helder.css.CssSheet, expr: macro return cache ??= helder.css.CssSheetData.decode($v{CssSheetData.encode(sheet, false)})}),
						pos: pos
					}
				]
			});
		}
		return macro @:pos(pos) $p{["helder", "css", "themes", name]}.get();
	}

	static function originOf(e:Null<Expr>):CssOrigin
		return switch e == null ? "null" : e.toString().split(".").pop() {
			case "null" | "Author": Author;
			case "User": User;
			case "UserAgent": UserAgent;
			case o: Context.error('CssTheme: "$o" is no origin (UserAgent, User, Author)', e.pos);
		}

	// (beside the calling module, else under a class path)
	static function locate(path:String, dir:String):Null<String> {
		if (Path.isAbsolute(path)) return FileSystem.exists(path) ? path : null;
		for (d in [dir, try Path.directory(FileSystem.fullPath(dir + "/.")) catch (_:Dynamic) dir]) {
			var beside = Path.join([d, path]);
			if (FileSystem.exists(beside)) return beside;
		}
		return try Context.resolvePath(path) catch (_:Dynamic) null;
	}

	// (the string a typed expression always is, else null: SvgBuild's)
	static function constant(t:Null<TypedExpr>):Null<String> {
		if (t == null) return null;
		return switch t.expr {
			case TConst(TString(s)): s;
			case TParenthesis(e) | TCast(e, null): constant(e);
			case TBinop(OpAdd, a, b):
				var x = constant(a), y = constant(b);
				x != null && y != null ? x + y : null;
			case _: null;
		}
	}
	#end
}
