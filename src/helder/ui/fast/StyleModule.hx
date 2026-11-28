package helder.ui.fast;

#if macro
import haxe.io.Path;
import haxe.macro.Context;
import haxe.macro.Expr;
import helder.css.CssDeclaration;
import helder.css.CssRule;
import helder.css.CssToken;
import helder.css.CssValue;
import sys.FileSystem;

using StringTools;
#end

// CSS modules for fast nodes: StyleModule.load("card.module.css") (beside
// the calling file, else under a class path) is the module's classes as
// Styles, compiled when the program is: {final card:Style, final
// cardTitle:Style}, a dashed name camelCased, a misspelt one a type error.
// A rule is a class alone or with one of its own states (:hover, :active,
// :focus, :focus-visible, :disabled, :checked, [data-state=checked],
// [data-state=selected], ::placeholder (a field's), and as nested rules
// &:hover); a class under
// @media (prefers-color-scheme: dark) is its dark variant; composes: names
// classes of the same file, merged under it. Values are CSS's (lengths in
// px, percentages, colours, var(--name): a token of the theme file given
// as its second argument, checked there for its type, a fallback taken
// where it has none). A descendant or
// sibling selector, another at-rule or property, or a value a style can't
// hold is an error of the build, at its line and column in the file. No CSS
// parser is linked: the file is read when the program is built.
//
//   static final s = StyleModule.load("card.module.css", "app.theme.css");
//   <view style={s.card}>...</view>
class StyleModule {
	public static macro function load(path:ExprOf<String>, ?theme:ExprOf<String>):Expr {
		var p = switch path.expr {
			case EConst(CString(s, _)): s;
			case _: Context.error("StyleModule.load: a string literal", path.pos);
		}
		var file = @:privateAccess helder.css.CssModule.locate(p, Path.directory(Context.getPosInfos(path.pos).file));
		if (file == null) Context.error('StyleModule.load("$p"): no such file beside the module or under a class path', path.pos);
		file = FileSystem.fullPath(file);
		Context.registerModuleDependency(Context.getLocalModule(), file);
		var t = switch theme {
			case null | {expr: EConst(CIdent("null"))}: null;
			case {expr: EConst(CString(s, _))}: ThemeFile.of(Theme.locate(s, theme.pos));
			case _: Context.error("StyleModule.load: the theme's path a string literal", theme.pos);
		}
		return new Compile(file, sys.io.File.getContent(file), t).module(path.pos);
	}
}

#if macro
// (a module compiled: its classes in order, each one's declarations by state)
private class Compile {
	final file:String;
	final text:String;
	final order:Array<String> = [];
	// (class -> state ("" its own, "dark", "hover"...) -> its declarations in order)
	final classes = new Map<String, Map<String, Array<CssDeclaration>>>();
	final composed = new Map<String, Array<{name:String, at:Int}>>();

	final theme:Null<ThemeFile>;

	public function new(file:String, text:String, theme:Null<ThemeFile>) {
		this.file = file;
		this.text = text;
		this.theme = theme;
	}

	// (var(--name[, fallback]): the theme's token of that kind, else its fallback's value)
	function token(v:CssValue, args:Array<CssValue>, d:CssDeclaration, kind:ThemeFile.ThemeKind, fallback:CssValue->Expr):Expr {
		var text = flat(args).trim(), comma = text.indexOf(","), n = (comma < 0 ? text : text.substr(0, comma)).trim();
		if (!n.startsWith("--")) fail(Parser.startOf(v), "var(--name): a theme's token");
		var name = n.substr(2), t = theme?.tokens.get(name);
		if (t != null) {
			if (t.kind != kind) fail(Parser.startOf(v), '${d.name}: --$name is a ${t.kind}, not a $kind');
			return switch kind {
				case Color: macro(new helder.ui.fast.Token<helder.gfx.Color>($v{name}) : helder.ui.fast.Style.Tint);
				case _: macro new helder.ui.fast.Token<helder.ui.fast.Token.Length>($v{name});
			}
		}
		if (comma >= 0) {
			var rest = words(args), k = Lambda.findIndex(rest, x -> x.match(Token({kind: Comma})));
			if (k + 2 == rest.length) return fallback(rest[k + 1]);
		}
		return fail(Parser.startOf(v), theme == null ? 'var(--$name): the theme is StyleModule.load\'s second argument' : 'var(--$name): no such token in ${theme.path}');
	}

	public function module(pos:Position):Expr {
		var rules = new helder.css.Parser(text).sheet();
		for (r in rules) rule(r, false);
		var fields:Array<ObjectField> = [];
		for (c in order) fields.push({field: camel(c, pos), expr: macro helder.ui.fast.Style.of(${style(c, [])})});
		return {expr: EObjectDecl(fields), pos: pos};
	}

	function rule(r:CssRule, dark:Bool)
		switch r {
			case Qualified(prelude, decls, nested):
				var sel = selector(prelude);
				var state = dark ? (sel.state == "" ? "dark" : fail(start(prelude), 'a fast style\'s dark variant has no states yet (.${sel.name}${sel.state})')) : sel.state;
				add(sel.name, state, decls);
				for (n in nested) switch n {
					case Qualified(np, nd, _):
						var s = nestedState(np);
						if (dark) fail(start(np), "a fast style's dark variant has no states yet");
						add(sel.name, s, nd);
					case Declarations(d):
						add(sel.name, state, d);
					case At(name, prelude, _):
						fail(start(prelude), 'a fast style: no @$name inside a rule');
				}
			case At("media", prelude, block):
				var q = flat(prelude);
				if (dark || q.indexOf("prefers-color-scheme") < 0 || q.indexOf("dark") < 0 || block == null)
					fail(start(prelude), "a fast style's @media is (prefers-color-scheme: dark) alone");
				for (b in block) rule(b, true);
			case At(name, prelude, _):
				fail(start(prelude), 'a fast style: no @$name (a class alone, its states, @media (prefers-color-scheme: dark))');
			case Declarations(d):
				if (d.length > 0) fail(d[0].start, "a fast style: declarations outside a rule");
		}

	function add(name:String, state:String, decls:Array<CssDeclaration>) {
		if (!classes.exists(name)) {
			classes.set(name, new Map());
			order.push(name);
		}
		var c = classes.get(name);
		if (!c.exists(state)) c.set(state, []);
		for (d in decls) if (d.name == "composes") {
			if (state != "") fail(d.start, "composes: in a class's own rule alone");
			if (!composed.exists(name)) composed.set(name, []);
			for (v in words(d.value)) switch v {
				case Token({kind: Ident("from")}) | Token({kind: Str(_)}):
					fail(d.start, "composes: classes of the same file alone, for fast styles");
				case Token({kind: Ident(n)}): composed.get(name).push({name: n, at: d.start});
				case _:
			}
		} else c.get(state).push(d);
	}

	// (.name, then at most one state of its own)
	function selector(prelude:Array<CssValue>):{name:String, state:String} {
		var t = tokens(prelude), k = 0;
		if (t.length < 2 || !t[0].kind.match(Delim(".")))
			fail(t.length > 0 ? t[0].start : 0, "a fast style's rule is a class alone (.name), with one of its states");
		var name = switch t[1].kind {
			case Ident(n): n;
			case _: fail(t[1].start, "a class's name");
		}
		var state = stateOf(t, 2);
		return {name: name, state: state};
	}

	function nestedState(prelude:Array<CssValue>):String {
		var t = tokens(prelude);
		if (t.length == 0 || !t[0].kind.match(Delim("&"))) fail(t.length > 0 ? t[0].start : 0, "a nested rule of a fast style is one of its states (&:hover)");
		var s = stateOf(t, 1);
		if (s == "") fail(t[0].start, "a nested rule of a fast style is one of its states (&:hover)");
		return s;
	}

	function stateOf(t:Array<CssToken>, k:Int):String {
		if (k >= t.length) return "";
		var state = switch t[k].kind {
			case Colon if (k + 2 < t.length && t[k + 1].kind.match(Colon)):
				switch t[k + 2].kind {
					case Ident("placeholder"):
						if (k + 3 < t.length) fail(t[k + 3].start, "a fast style's rule is a class alone with one state");
						return "placeholder";
					case _: fail(t[k + 2].start, "a fast style's pseudo-element is ::placeholder alone");
				}
			case Colon if (k + 1 < t.length):
				switch t[k + 1].kind {
					case Ident("hover"): "hover";
					case Ident("active"): "pressed";
					case Ident("focus") | Ident("focus-visible"): "focus";
					case Ident("disabled"): "disabled";
					case Ident("checked"): "checked";
					case _: fail(t[k + 1].start, "a fast style's state is :hover, :active, :focus, :focus-visible, :disabled, :checked or [data-state=...]");
				}
			case OpenSquare:
				var s = [for (x in t.slice(k + 1)) switch x.kind {
					case Ident(v) | Str(v): v;
					case Delim(d): d;
					case _: "";
				}].join("");
				switch s {
					case "data-state=checked": "checked";
					case "data-state=selected" | "aria-selected=true": "selected";
					case "data-state=disabled": "disabled";
					case _: fail(t[k].start, 'a fast style\'s state: no [$s]');
				}
			case _: fail(t[k].start, "a fast style's rule is a class alone (.name): no descendant, child or sibling selector");
		}
		// (anything after the state: a compound or a combinator)
		var end = t[k].kind.match(OpenSquare) ? Lambda.findIndex(t, x -> x.kind.match(CloseSquare)) + 1 : k + 2;
		if (end < t.length) fail(t[end].start, "a fast style's rule is a class alone with one state: no descendant, child or sibling selector");
		return state;
	}

	// (a class's style: its own, the classes it composes under it, its states' variants)
	function style(name:String, seen:Array<String>):Expr {
		if (seen.indexOf(name) >= 0) fail(0, 'composes: .$name composes itself');
		var c = classes.get(name), fields:Array<ObjectField> = [];
		var base = new Map<String, Expr>();
		for (k in composed.get(name) ?? []) {
			if (!classes.exists(k.name)) fail(k.at, 'composes: no class .${k.name} in this file');
			switch style(k.name, seen.concat([name])).expr {
				case EObjectDecl(fs): for (f in fs) base.set(f.field, f.expr);
				case _:
			}
		}
		for (f in props(c.get("") ?? [])) base.set(f.field, f.expr);
		for (s in ["hover", "pressed", "focus", "disabled", "selected", "checked", "placeholder", "dark"]) {
			var d = c.get(s);
			if (d != null) base.set(s, {expr: EObjectDecl(props(d)), pos: Context.currentPos()});
		}
		for (k => v in base) fields.push({field: k, expr: v});
		return {expr: EObjectDecl(fields), pos: Context.currentPos()};
	}

	// (declarations as a style's fields, each at its place in the file)
	function props(decls:Array<CssDeclaration>):Array<ObjectField> {
		var out = new Map<String, Expr>(), sides = new Map<String, Array<Expr>>(), outline = new OutlineParts();
		function side(field:String, k:Int, v:Expr) {
			var s = sides.get(field) ?? (switch out.get(field) {
				case {expr: EArrayDecl(a)} if (a.length == 4): a.copy();
				case _: [macro 0, macro 0, macro 0, macro 0];
			});
			s[k] = v;
			sides.set(field, s);
			out.set(field, macro $a{s});
		}
		for (d in decls) {
			var pos = at(d.start, d.end), w = words(d.value);
			inline function set(f:String, e:Expr)
				out.set(f, e);
			switch d.name {
				case "display": set("display", word(w, d, ["flex" => "Flex", "block" => "Block", "none" => "None", "grid" => "Grid"], "helder.ui.Display"));
				case "flex-direction":
					set("flexDirection", word(w, d, ["row" => "Row", "column" => "Column", "row-reverse" => "RowReverse", "column-reverse" => "ColumnReverse"], "helder.ui.Direction"));
				case "flex-wrap": set("flexWrap", macro $v{flat(d.value).trim() != "nowrap"});
				case "align-items": set("alignItems", align(w, d));
				case "align-self": set("alignSelf", align(w, d));
				case "justify-content":
					set("justifyContent", word(w, d, ["flex-start" => "Start", "start" => "Start", "flex-end" => "End", "end" => "End", "center" => "Center",
						"space-between" => "SpaceBetween", "space-around" => "SpaceAround", "space-evenly" => "SpaceEvenly", "normal" => "Normal"], "helder.ui.Justify"));
				case "flex-grow": set("flexGrow", num(w, d));
				case "flex-shrink": set("flexShrink", num(w, d));
				case "flex-basis": set("flexBasis", length(w[0], d));
				case "flex":
					if (w.length >= 1) set("flexGrow", num([w[0]], d));
					if (w.length >= 2) set("flexShrink", num([w[1]], d));
					if (w.length >= 3) set("flexBasis", length(w[2], d));
				case "gap":
					set("rowGap", px(w[0], d));
					set("columnGap", px(w.length > 1 ? w[1] : w[0], d));
				case "row-gap": set("rowGap", px(w[0], d));
				case "column-gap": set("columnGap", px(w[0], d));
				case "width" | "height" | "min-width" | "min-height" | "max-width" | "max-height" | "top" | "right" | "bottom" | "left":
					set(camelName(d.name), length(w[0], d));
				case "inset":
					var e = edges(w, d);
					for (k in 0...4) set(["top", "right", "bottom", "left"][k], e[k]);
				case "padding" | "margin": set(d.name, macro $a{edges(w, d)});
				case "padding-top" | "padding-right" | "padding-bottom" | "padding-left" | "margin-top" | "margin-right" | "margin-bottom" | "margin-left":
					var parts = d.name.split("-");
					side(parts[0], ["top", "right", "bottom", "left"].indexOf(parts[1]), px(w[0], d));
				case "border-width": set("borderWidth", macro $a{edges(w, d)});
				case "border-top-width" | "border-right-width" | "border-bottom-width" | "border-left-width":
					side("borderWidth", ["top", "right", "bottom", "left"].indexOf(d.name.split("-")[1]), px(w[0], d));
				case "border":
					// (a width, a style and a colour, any order: none a width of 0)
					var width:Expr = macro 0, color:Null<Expr> = null;
					for (v in w) switch v {
						case Token({kind: Dimension(_) | Number(_)}): width = px(v, d);
						case Token({kind: Ident("none")}): width = macro 0;
						case Token({kind: Ident("solid" | "dashed" | "dotted")}): set("borderStyle", borderStyle([v], d));
						case _: color = colour(v, d);
					}
					set("borderWidth", width);
					if (color != null) set("borderColor", color);
				case "border-style": set("borderStyle", borderStyle(w, d));
				case "border-color": set("borderColor", colour(w[0], d));
				case "border-radius": set("borderRadius", macro $a{edges(w, d)});
				case "box-shadow": set("shadows", shadows(w, d));
				case "outline":
					// (a width, a style and a colour, any order: none no outline)
					for (v in w) switch v {
						case Token({kind: Dimension(_) | Number(_)}): outline.width = px(v, d);
						case Token({kind: Ident("none")}): outline.width = macro 0;
						case Token({kind: Ident("solid" | "dashed" | "dotted")}): outline.style = borderStyle([v], d);
						case _: outline.color = colour(v, d);
					}
					set("outline", outline.expr());
				case "outline-width":
					outline.width = px(w[0], d);
					set("outline", outline.expr());
				case "outline-style":
					outline.style = borderStyle(w, d);
					set("outline", outline.expr());
				case "outline-color":
					outline.color = colour(w[0], d);
					set("outline", outline.expr());
				case "outline-offset":
					outline.offset = px(w[0], d);
					set("outline", outline.expr());
				case "background" | "background-color": set("background", colour(w[0], d));
				case "color": set("color", colour(w[0], d));
				case "opacity": set("opacity", num(w, d));
				case "overflow":
					set("overflow", word(w, d, ["visible" => "Visible", "hidden" => "Hidden", "clip" => "Hidden", "scroll" => "Scroll", "auto" => "Scroll"], "helder.ui.Overflow"));
				case "position": set("position", word(w, d, ["relative" => "Relative", "absolute" => "Absolute", "sticky" => "Sticky"], "helder.ui.Position"));
				case "z-index": set("zIndex", int(w, d));
				case "font-size": set("fontSize", px(w[0], d));
				case "font-weight":
					set("fontWeight", switch w[0] {
						case Token({kind: Ident("bold")}): macro 700;
						case Token({kind: Ident("normal")}): macro 400;
						case _: int(w, d);
					});
				case "font-family": set("fontFamily", macro $v{flat(d.value).trim().replace("\"", "").replace("'", "")});
				case "font-style": set("fontStyle", word(w, d, ["normal" => "Normal", "italic" => "Italic", "oblique" => "Italic"], "helder.ui.FontStyle"));
				case "line-height":
					set("lineHeight", switch w[0] {
						case Token({kind: Number(n, _, _)}): macro $v{n};
						case _: fail(d.start, "a fast style's line-height is a number (a multiple of the font size)");
					});
				case "letter-spacing": set("letterSpacing", px(w[0], d));
				case "text-align":
					set("textAlign", word(w, d, ["left" => "Left", "start" => "Left", "center" => "Center", "right" => "Right", "end" => "Right", "justify" => "Justify"],
						"helder.ui.TextAlign"));
				case "white-space" | "text-wrap" | "text-wrap-mode": set("wrap", macro $v{flat(d.value).trim() != "nowrap"});
				case "text-overflow": set("textOverflow", word(w, d, ["clip" => "Clip", "ellipsis" => "Ellipsis"], "helder.ui.TextOverflow"));
				case "line-clamp" | "-webkit-line-clamp": set("lineClamp", int(w, d));
				case "text-decoration" | "text-decoration-line":
					var bits = 0;
					for (v in w) switch v {
						case Token({kind: Ident("underline")}): bits |= 1;
						case Token({kind: Ident("line-through")}): bits |= 2;
						case Token({kind: Ident("overline")}): bits |= 4;
						case Token({kind: Ident("none")}):
						case _: fail(Parser.startOf(v), "a fast style's text-decoration: its lines alone");
					}
					set("textDecoration", macro $v{bits});
				case "cursor": set("cursor", macro($v{flat(d.value).trim()} : helder.ui.Cursor));
				case "pointer-events": set("pointerEvents", word(w, d, ["auto" => "Auto", "none" => "None"], "helder.ui.PointerEvents"));
				case "direction": set("direction", word(w, d, ["ltr" => "Ltr", "rtl" => "Rtl"], "helder.ui.Dir"));
				case "font-variant-numeric":
					for (v in w) switch v {
						case Token({kind: Ident("normal" | "lining-nums" | "oldstyle-nums" | "proportional-nums" | "tabular-nums" | "diagonal-fractions"
							| "stacked-fractions" | "ordinal" | "slashed-zero")}):
						case _: fail(Parser.startOf(v), "font-variant-numeric: its keywords");
					}
					set("fontVariantNumeric", macro $v{flat(d.value).trim()});
				case "aspect-ratio":
					// (a number, or a / b)
					var nums = [for (v in w) switch v {
						case Token({kind: Number(n, _, _)}): n;
						case Token({kind: Delim("/")}): continue;
						case _: fail(Parser.startOf(v), "aspect-ratio: a number, or a / b");
					}];
					if (nums.length == 0 || nums.length > 2 || nums.length == 2 && nums[1] == 0) fail(d.start, "aspect-ratio: a number, or a / b");
					set("aspectRatio", macro $v{nums.length == 2 ? nums[0] / nums[1] : nums[0]});
				case "scrollbar-width": set("scrollbarWidth", word(w, d, ["auto" => "Auto", "thin" => "Thin", "none" => "None"], "helder.ui.ScrollbarWidth"));
				case name: fail(d.start, 'a fast style has no property $name');
			}
			// (where it was written: a value's type error there)
			var f = out.get(fieldOf(d.name));
			if (f != null && f.pos == Context.currentPos()) out.set(fieldOf(d.name), {expr: f.expr, pos: pos});
		}
		return [for (k => v in out) {field: k, expr: v}];
	}

	static function fieldOf(name:String):String
		return switch name {
			case "background-color": "background";
			case "border": "borderWidth";
			case "box-shadow": "shadows";
			case "outline-width" | "outline-style" | "outline-color" | "outline-offset": "outline";
			case "line-clamp" | "-webkit-line-clamp": "lineClamp";
			case "white-space" | "text-wrap" | "text-wrap-mode": "wrap";
			case "text-decoration-line": "textDecoration";
			case n: camelName(n);
		}

	// ---- values

	function word(w:Array<CssValue>, d:CssDeclaration, names:Map<String, String>, type:String):Expr {
		var v = switch w[0] {
			case Token({kind: Ident(i)}): names.get(i);
			case _: null;
		}
		if (v == null) fail(d.start, '${d.name}: ${[for (k in names.keys()) k].join(", ")}');
		var path = type.split(".").concat([v]);
		return macro $p{path};
	}

	function borderStyle(w:Array<CssValue>, d:CssDeclaration):Expr
		return word(w, d, ["solid" => "Solid", "dashed" => "Dashed", "dotted" => "Dotted"], "helder.ui.BorderStyle");

	// (box-shadow's list: each two to four lengths, inset, a colour (currentcolor where none))
	function shadows(w:Array<CssValue>, d:CssDeclaration):Expr {
		if (w.length == 1 && w[0].match(Token({kind: Ident("none")}))) return macro [];
		var list:Array<Expr> = [], lengths:Array<Expr> = [], inset = false, color:Expr = macro helder.ui.fast.Style.Tint.current;
		function end() {
			if (lengths.length < 2 || lengths.length > 4) fail(d.start, 'box-shadow: two to four lengths a shadow');
			var blur = lengths[2] ?? macro 0.0, spread = lengths[3] ?? macro 0.0;
			list.push(macro {x: ${lengths[0]}, y: ${lengths[1]}, blur: $blur, spread: $spread, color: $color, inset: $v{inset}});
			lengths = [];
			inset = false;
			color = macro helder.ui.fast.Style.Tint.current;
		}
		for (v in w) switch v {
			case Token({kind: Comma}): end();
			case Token({kind: Dimension(_) | Number(_)}): lengths.push(px(v, d));
			case Token({kind: Ident("inset")}): inset = true;
			case _: color = colour(v, d);
		}
		end();
		return macro $a{list};
	}

	function align(w:Array<CssValue>, d:CssDeclaration):Expr
		return word(w, d, ["flex-start" => "Start", "start" => "Start", "flex-end" => "End", "end" => "End", "center" => "Center", "stretch" => "Stretch",
			"baseline" => "Baseline", "auto" => "Auto", "normal" => "Stretch"], "helder.ui.Align");

	function num(w:Array<CssValue>, d:CssDeclaration):Expr
		return switch w[0] {
			case Token({kind: Number(n, _, _)}): macro $v{n};
			case _: fail(d.start, '${d.name}: a number');
		}

	function int(w:Array<CssValue>, d:CssDeclaration):Expr
		return switch w[0] {
			case Token({kind: Number(n, true, _)}): macro $v{Std.int(n)};
			case _: fail(d.start, '${d.name}: an integer');
		}

	function px(v:CssValue, d:CssDeclaration):Expr
		return switch v {
			case Function("var", args, _, _): macro(${token(v, args, d, Length, x -> px(x, d))} : helder.ui.fast.Style.Pixels);
			case Token({kind: Dimension(n, _, _, "px")}): macro $v{n};
			case Token({kind: Number(0, _, _)}): macro 0.0;
			case _: fail(Parser.startOf(v), '${d.name}: a length in px');
		}

	function length(v:CssValue, d:CssDeclaration):Expr
		return switch v {
			case Function("var", args, _, _): macro(${token(v, args, d, Length, x -> length(x, d))} : helder.ui.fast.Style.Size);
			case Token({kind: Dimension(n, _, _, "px")}): macro $v{n};
			case Token({kind: Number(0, _, _)}): macro 0.0;
			case Token({kind: Percentage(n, _, _)}): macro $v{n + "%"};
			case Token({kind: Ident("auto")}): macro "auto";
			case _: fail(Parser.startOf(v), '${d.name}: a length in px, a percentage or auto');
		}

	function edges(w:Array<CssValue>, d:CssDeclaration):Array<Expr> {
		var v = [for (x in w) px(x, d)];
		return switch v.length {
			case 1: [v[0], v[0], v[0], v[0]];
			case 2: [v[0], v[1], v[0], v[1]];
			case 3: [v[0], v[1], v[2], v[1]];
			case 4: v;
			case _: fail(d.start, '${d.name}: one to four lengths');
		}
	}

	function colour(v:CssValue, d:CssDeclaration):Expr {
		switch v {
			case Function("var", args, _, _):
				return token(v, args, d, Color, x -> colour(x, d));
			case Token({kind: Ident("currentColor" | "currentcolor")}):
				return macro helder.ui.fast.Style.Tint.current;
			case Token({kind: Ident("transparent")}):
				return macro 0;
			case _:
		}
		var c = helder.css.CssColors.parse(v);
		if (c == null) fail(Parser.startOf(v), '${d.name}: a colour, or var(--name)');
		var s = helder.css.CssColors.srgb(c);
		inline function byte(x:Float):Int
			return Std.int(Math.max(0, Math.min(255, Math.round(x))));
		var argb = byte(c.alpha * 255) << 24 | byte(s[0]) << 16 | byte(s[1]) << 8 | byte(s[2]);
		return macro $v{argb};
	}

	// ---- the file

	static function words(values:Array<CssValue>):Array<CssValue>
		return [for (v in values) switch v {
			case Token({kind: Whitespace}): continue;
			case _: v;
		}];

	static function tokens(values:Array<CssValue>):Array<CssToken> {
		var out = [];
		for (v in values) switch v {
			case Token(t) if (!t.kind.match(Whitespace)): out.push(t);
			case Block(open, vals, close):
				out.push(open);
				for (t in tokens(vals)) out.push(t);
				if (close != null) out.push(close);
			case _:
		}
		return out;
	}

	function flat(values:Array<CssValue>):String {
		if (values.length == 0) return "";
		var a = Parser.startOf(values[0]), last = values[values.length - 1];
		var b = switch last {
			case Token(t): t.end;
			case Function(_, _, _, close) | Block(_, _, close): close == null ? text.length : close.end;
		}
		return text.substring(a, b);
	}

	static function start(values:Array<CssValue>):Int
		return values.length == 0 ? 0 : Parser.startOf(values[0]);

	function at(a:Int, b:Int):Position {
		inline function bytes(k:Int)
			return haxe.io.Bytes.ofString(text.substr(0, k)).length;
		return Context.makePosition({file: file, min: bytes(a), max: bytes(Std.int(Math.max(b, a + 1)))});
	}

	function fail<T>(start:Int, message:String):T
		return Context.error('StyleModule: $message', at(start, start + 1));

	function camel(name:String, pos:Position):String {
		var f = camelName(name);
		if (!~/^[a-zA-Z_][a-zA-Z0-9_]*$/.match(f)) Context.error('StyleModule: .$name is no Haxe field name', pos);
		return f;
	}

	static function camelName(name:String):String {
		var parts = name.split("-"), out = parts[0];
		for (p in parts.slice(1)) if (p.length > 0) out += p.charAt(0).toUpperCase() + p.substr(1);
		return out;
	}
}

private typedef Parser = helder.css.Parser;

// (outline's longhands as they come, one Outline of them)
private class OutlineParts {
	public var width:Expr = macro 0.0;
	public var style:Null<Expr> = null;
	public var color:Expr = macro helder.ui.fast.Style.Tint.current;
	public var offset:Expr = macro 0.0;

	public function new() {}

	public function expr():Expr
		return style == null ? macro {width: $width, color: $color, offset: $offset} : macro {width: $width, color: $color, style: $style, offset: $offset};
}
#end
