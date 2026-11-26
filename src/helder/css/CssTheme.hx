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
// constant's) parsed by the compiler and the sheet written as the
// expressions that make it again: selectors with their specificity, Bloom
// hashes and buckets, declarations as property ids and typed values,
// @media's queries, @import's sheets (read beside the file). A program
// that styles with these alone (CssCascade.themed) links no CSS tokenizer
// or parser; var() is substituted when styles are computed, as ever. The
// sheets have no URL: url()s stay as written.
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
			Context.defineType({
				pack: ["helder", "css", "themes"],
				name: name,
				pos: pos,
				kind: TDClass(),
				fields: [
					{name: "sheet", access: [APublic, AStatic, AFinal], kind: FVar(macro :helder.css.CssSheet, macro @:privateAccess ${value(sheet, pos)}), pos: pos}
				]
			});
		}
		return macro @:pos(pos) $p{["helder", "css", "themes", name, "sheet"]};
	}

	// (a value of the sheet's as the expression that makes it: enums by
	// their constructors, structures, arrays and maps as literals, the
	// classes a sheet holds by their constructors)
	static function value(v:Dynamic, pos:Position):Expr {
		inline function e(d:ExprDef):Expr
			return {expr: d, pos: pos};
		if (v == null) return macro null;
		return switch Type.typeof(v) {
			case TBool: e(EConst(CIdent(v ? "true" : "false")));
			case TInt: e(EConst(CInt(Std.string(v))));
			case TFloat: float(v, pos);
			case TEnum(en):
				var path = Type.getEnumName(en).split(".");
				// (an enum of another module's: its module named)
				var last = path.pop();
				if (MODULES.exists(last)) path.push(MODULES[last]);
				path.push(last);
				var c = macro $p{path.concat([Type.enumConstructor(v)])};
				var args = Type.enumParameters(v);
				args.length == 0 ? c : e(ECall(c, [for (a in args) value(a, pos)]));
			case TObject: e(EObjectDecl([for (f in Reflect.fields(v)) {field: f, expr: value(Reflect.field(v, f), pos)}]));
			case TClass(c):
				switch Type.getClassName(c) {
					case "String": e(EConst(CString(v)));
					case "Array": e(EArrayDecl([for (x in (v : Array<Dynamic>)) value(x, pos)]));
					case "haxe.ds.StringMap":
						var m:haxe.ds.StringMap<Dynamic> = v;
						var items = [for (k => x in m) macro $v{k} => ${value(x, pos)}];
						items.length == 0 ? macro new Map() : e(EArrayDecl(items));
					case "helder.css.CssSheet":
						var s:CssSheet = v;
						macro new helder.css.CssSheet(${value(s.origin, pos)}, null, ${value(s.rules, pos)});
					case "helder.css.CssSelector":
						var s:CssSelector = v;
						macro new helder.css.CssSelector(${value(s.compounds, pos)}, ${value(s.combinators, pos)}, ${value(s.relative, pos)},
							${value(s.pseudo, pos)}, cast ${value(s.specificity.toInt(), pos)}, ${value(s.hashes, pos)}, $v{s.local}, ${value(s.bucket, pos)});
					case "helder.css.CssAnB":
						var a:CssAnB = v;
						macro new helder.css.CssAnB($v{a.a}, $v{a.b});
					case "helder.css.CssToken":
						var t:CssToken = v;
						macro new helder.css.CssToken(${value(t.kind, pos)}, $v{t.start}, $v{t.end});
					case "helder.css.CssDeclaration":
						var d:CssDeclaration = v;
						macro new helder.css.CssDeclaration($v{d.name}, ${value(d.value, pos)}, $v{d.important}, ${value(d.text, pos)}, $v{d.start}, $v{d.end});
					case "helder.css.CssMedia":
						macro new helder.css.CssMedia(${value(@:privateAccess (v : CssMedia).queries, pos)});
					case n: Context.error('CssTheme: a $n in the sheet', pos);
				}
			case t: Context.error('CssTheme: a $t in the sheet', pos);
		}
	}

	static final MODULES = [
		"CssOrigin" => "CssSheet", "CssSheetRule" => "CssSheet", "CssSpecified" => "CssTerm", "CssTokenKind" => "CssToken", "CssCombinator" => "CssSelector",
		"CssNamespace" => "CssSelector", "CssSimple" => "CssSelector", "CssAttributeOp" => "CssSelector", "CssSensitivity" => "CssSelector",
		"CssPseudoClass" => "CssSelector", "CssPseudoElement" => "CssSelector", "CssBucket" => "CssSelector", "CssCalcNode" => "CssCalc",
		"CssMediaQuery" => "CssMedia", "CssMediaCondition" => "CssMedia"
	];

	static function float(f:Float, pos:Position):Expr {
		if (Math.isNaN(f)) return macro Math.NaN;
		if (!Math.isFinite(f)) return f > 0 ? macro Math.POSITIVE_INFINITY : macro Math.NEGATIVE_INFINITY;
		var s = Std.string(f);
		return {expr: EConst(CFloat(s.indexOf(".") < 0 && s.indexOf("e") < 0 ? s + ".0" : s)), pos: pos};
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
