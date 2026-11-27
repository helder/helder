package helder.ui.box;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.css.CssSheet;
import helder.css.CssTerm;

using haxe.macro.ExprTools;
#end

// A document as an app has it: styled by sheets compiled at build time
// alone (CssTheme's, CssUserAgentTheme.app()), laid out by the formatting
// contexts those sheets can make. The macro reads the sheets when the
// program is compiled, finds the display values they set, and links only
// those contexts (flex, grid, table; block flow always): a program whose
// sheets never say grid links no GridFlow. A sheet it can't read (not a
// CssTheme.file, CssTheme.sheet or the app's user agent sheet), an
// @import, or a display through var() gives every context. CSS modules'
// sheets, which CssCascade.themed adds, are not read: a display they set
// that the sheets don't lays out as flow, noted.
//
//   var page = DocumentApp.node(doc, [CssUserAgentTheme.app(), CssTheme.file("app.css")]);
//   var view = DocumentApp.view(doc, [CssUserAgentTheme.app(), CssTheme.file("app.css")], {fonts: fonts});
class DocumentApp {
	public static macro function node(doc:ExprOf<helder.dom.Document>, sheets:ExprOf<Array<helder.css.CssSheet>>, ?options:ExprOf<DocumentView.DocumentViewOptions>):ExprOf<DocumentNode>
		return make(macro helder.ui.box.DocumentNode, doc, sheets, options);

	public static macro function view(doc:ExprOf<helder.dom.Document>, sheets:ExprOf<Array<helder.css.CssSheet>>, ?options:ExprOf<DocumentView.DocumentViewOptions>):ExprOf<DocumentView>
		return make(macro helder.ui.box.DocumentView, doc, sheets, options);

	#if macro
	static function make(type:Expr, doc:Expr, sheets:Expr, options:Null<Expr>):Expr {
		var items = switch sheets.expr {
			case EArrayDecl(xs): xs;
			case _: Context.error("DocumentApp: the sheets as an array literal ([CssUserAgentTheme.app(), CssTheme.file(...)])", sheets.pos);
		}
		var kinds = new Map<String, Bool>(), every = false;
		for (e in items) {
			var found = displays(e);
			if (found == null) every = true else for (k in found) kinds.set(k, true);
		}
		var flow = macro flow;
		var made:Array<Expr> = [];
		if (every || kinds.exists("flex")) made.push(macro c.flex = new helder.ui.flow.FlexFlow($flow));
		if (every || kinds.exists("grid")) made.push(macro c.grid = new helder.ui.flow.GridFlow($flow));
		if (every || kinds.exists("table")) made.push(macro c.table = new helder.ui.flow.TableFlow($flow));
		var opts = options == null || options.expr.match(EConst(CIdent("null"))) ? macro {} : options;
		var path = switch type.expr {
			case EField(_, _): type.toString().split(".");
			case _: [];
		}
		var tp:TypePath = {pack: path.slice(0, path.length - 1), name: path[path.length - 1]};
		return macro {
			var sheets:Array<helder.css.CssSheet> = $sheets;
			var o:helder.ui.box.DocumentView.DocumentViewOptions = $opts;
			var flow = new helder.ui.flow.BlockFlow();
			var c = new helder.ui.flow.Contexts(flow);
			$b{made};
			o.contexts = c;
			new $tp($doc, (d, media, _) -> helder.css.CssCascade.themed(d, sheets, {media: media}), o);
		}
	}

	// (the inner displays a sheet expression's rules can set: flex, grid,
	// table; null: unknown, every one)
	static function displays(e:Expr):Null<Array<String>> {
		var call = switch e.expr {
			case ECall(f, args): {name: f.toString(), args: args};
			case _: return null;
		}
		var dir = Path.directory(Context.getPosInfos(e.pos).file);
		var text:Null<String> = null;
		if (StringTools.endsWith(call.name, "CssUserAgentTheme.app")) text = read(Context.resolvePath("helder/css/ua/app.css"));
		else if (StringTools.endsWith(call.name, "CssTheme.file") && call.args.length > 0) {
			var p = constant(call.args[0]);
			var f = p == null ? null : @:privateAccess helder.css.CssTheme.locate(p, dir);
			if (f != null) text = read(f);
		} else if (StringTools.endsWith(call.name, "CssTheme.sheet") && call.args.length > 0) text = constant(call.args[0]);
		if (text == null) return null;
		var out = [];
		return scan(CssSheet.parse(text, Author).rules, out) ? out : null;
	}

	static function read(file:String):String {
		Context.registerModuleDependency(Context.getLocalModule(), file);
		return sys.io.File.getContent(file);
	}

	static function constant(e:Expr):Null<String>
		return switch e.expr {
			case EConst(CString(s, _)): s;
			case _: null;
		}

	// (false: something only the running program knows, an @import or a display through var())
	static function scan(rules:Array<CssSheetRule>, out:Array<String>):Bool {
		for (r in rules) switch r {
			case Style(_, declarations):
				for (d in declarations) if (d.property == "display") switch d.value {
					case Terms(ts):
						for (t in ts) switch t {
							case Keyword("flex" | "inline-flex"): out.push("flex");
							case Keyword("grid" | "inline-grid"): out.push("grid");
							case Keyword(k) if (StringTools.startsWith(k, "table") || k == "inline-table"): out.push("table");
							case _:
						}
					case Wide("initial"):
					case Wide(_) | Unresolved(_): return false;
				}
			case Media(_, rules) | Layer(_, rules) if (rules != null):
				if (!scan(rules, out)) return false;
			case Import(_, _, _, _): return false;
			case _:
		}
		return true;
	}
	#end
}
