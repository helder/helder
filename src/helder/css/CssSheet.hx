package helder.css;

import helder.css.CssSelector;
import helder.css.CssTerm;

using Lambda;
using StringTools;

enum CssOrigin {
	UserAgent;
	User;
	Author;
}

// A declaration compiled for the cascade: a longhand (a shorthand's
// expanded, an alias as its property), its specified value, its
// importance. values: a custom property's or a value to substitute's
// component values; shorthand: the shorthand a pending-substitution
// value came from (the longhand is taken from it once substituted).
typedef CssDeclared = {property:String, value:CssSpecified, important:Bool, ?values:Array<CssValue>, ?shorthand:String}

// An @page rule: its selectors (a name and :first, :left, :right, :blank),
// its declarations (the page's properties) and descriptors (size,
// marks, bleed, page-orientation: as written), its margin boxes' (by
// name: top-left, ...). For the paged layout to cascade.
typedef CssPageRule = {
	selectors:Array<{name:Null<String>, pseudos:Array<String>}>,
	declarations:Array<CssDeclared>,
	descriptors:Array<CssDeclaration>,
	margins:Map<String, Array<CssDeclared>>,
	origin:CssOrigin,
	order:Int
}

// @font-face's and @counter-style's descriptors as written, for the
// font and list stages.
typedef CssFontFace = {descriptors:Array<CssDeclaration>, url:Null<String>}
typedef CssCounterStyle = {name:String, descriptors:Array<CssDeclaration>}

enum CssSheetRule {
	Style(selectors:Array<CssSelector>, declarations:Array<CssDeclared>);
	Media(media:CssMedia, rules:Array<CssSheetRule>);
	// a layer's full name (a.b); null: an anonymous one; rules null: the statement form
	Layer(name:Null<String>, rules:Null<Array<CssSheetRule>>);
	Import(sheet:CssSheet, media:CssMedia, layer:Null<String>, anonymous:Bool);
	Page(rule:CssPageRule);
	FontFace(face:CssFontFace);
	CounterStyle(style:CssCounterStyle);
}

typedef CssSheetOptions = {
	// the sheet's URL, what @import and url() resolve against
	?url:String,
	// an @import's text, by its absolute URL (null: not loaded)
	?load:(url:String) -> Null<String>
}

// A style sheet parsed once for the cascade (Cascade 5, Conditional 3):
// its style rules' selectors and compiled declarations, @media and
// @layer as blocks around them, @supports evaluated now, @import loaded
// through the caller's function (once each, in order), @namespace for
// the selectors; @page, @font-face and @counter-style kept as data.
// Invalid rules and declarations are dropped, as the spec says.
class CssSheet {
	public final origin:CssOrigin;
	public final url:Null<String>;
	public final rules:Array<CssSheetRule>;

	function new(origin:CssOrigin, url:Null<String>, rules:Array<CssSheetRule>) {
		this.origin = origin;
		this.url = url;
		this.rules = rules;
	}

	public static function parse(text:String, origin:CssOrigin, ?options:CssSheetOptions):CssSheet
		return new Builder(origin, options ?? {}, 0).sheet(Css.sheet(text));

	// A style attribute's declarations (author, compiled).
	public static function attribute(text:String):Array<CssDeclared>
		return compile(Css.declarations(text));

	public static function compile(declarations:Array<CssDeclaration>):Array<CssDeclared> {
		var out = [];
		for (d in declarations) for (c in declared(d)) out.push(c);
		return out;
	}

	// A declaration as the longhands it sets, none when invalid.
	public static function declared(d:CssDeclaration):Array<CssDeclared> {
		if (d.name.startsWith("--")) return [{property: d.name, value: Unresolved(d.text ?? Css.serialize(d.value)), important: d.important, values: d.value}];
		var name = Css.lower(d.name);
		var p = CssGrammars.property(name);
		if (p == null) return [];
		var value = CssValues.read(name, d.value);
		if (value == null) return [];
		// (a legacy name is its property; page-break-* sets break-*, Break 3 §3.4)
		if (p.alias != null) name = p.alias;
		if (name.startsWith("page-break-")) return pageBreak(name, value, d.important);
		if (!CssShorthands.isShorthand(name)) return [{property: name, value: value, important: d.important, values: value.match(Unresolved(_)) ? d.value : null}];
		var longhands = CssShorthands.longhands(name);
		return switch value {
			case Wide(_): [for (l in longhands) {property: l, value: value, important: d.important}];
			case Unresolved(_): [for (l in longhands) {property: l, value: value, important: d.important, values: d.value, shorthand: name}];
			case Terms(terms):
				var parts = CssShorthands.expand(name, terms);
				parts == null ? [] : [for (l in longhands) if (parts.exists(l)) {property: l, value: Terms(parts[l]), important: d.important}];
		}
	}

	static function pageBreak(name:String, value:CssSpecified, important:Bool):Array<CssDeclared> {
		var to = "break-" + name.substr("page-break-".length);
		return switch value {
			case Terms([Keyword("always")]): [{property: to, value: Terms([Keyword("page")]), important: important}];
			case Terms([Keyword("avoid")]) if (to == "break-inside"): [{property: to, value: Terms([Keyword("avoid")]), important: important}];
			case _: [{property: to, value: value, important: important}];
		}
	}
}

private class Builder {
	final origin:CssOrigin;
	final options:CssSheetOptions;
	final depth:Int;
	var namespaces:CssNamespaces = {prefixes: new Map()};
	var anonymous = 0;
	var imports = true;

	public function new(origin:CssOrigin, options:CssSheetOptions, depth:Int) {
		this.origin = origin;
		this.options = options;
		this.depth = depth;
	}

	public function sheet(rules:Array<CssRule>):CssSheet
		return @:privateAccess new CssSheet(origin, options.url, block(rules, null, true));

	// (layer: the enclosing layer's name, for a nested one's)
	function block(rules:Array<CssRule>, layer:Null<String>, top:Bool):Array<CssSheetRule> {
		var out = [];
		for (r in rules) {
			switch r {
				case Qualified(prelude, declarations, _):
					// (nested style rules are CSS Nesting's, past checkpoint 1: the rule's own declarations only)
					imports = false;
					var selectors = CssSelector.list(prelude, namespaces);
					if (selectors != null) out.push(Style(selectors, CssSheet.compile(declarations)));
				case At(name, prelude, body):
					var n = Css.lower(name);
					if (n != "import" && n != "layer" && n != "charset" && n != "namespace") imports = false;
					var rule = at(n, prelude, body, layer, top);
					if (rule != null) for (x in rule) out.push(x);
				case Declarations(_):
			}
		}
		return out;
	}

	function at(name:String, prelude:Array<CssValue>, body:Null<Array<CssRule>>, layer:Null<String>, top:Bool):Null<Array<CssSheetRule>> {
		return switch name {
			case "media" if (body != null): [Media(CssMedia.parse(prelude), block(body, layer, false))];
			case "supports" if (body != null): CssSupports.test(prelude) ? block(body, layer, false) : [];
			case "layer":
				var names = layerNames(prelude);
				if (names == null) return [];
				var full = [for (n in names) layer == null ? n : '$layer.$n'];
				if (body == null) [for (f in full) Layer(f, null)] else {
					if (full.length > 1) return [];
					var name = full.length == 1 ? full[0] : (layer == null ? "" : layer + ".") + '#${anonymous++}';
					[Layer(name, block(body, name, false))];
				}
			case "import" if (top && imports && body == null): load(prelude);
			case "namespace" if (top && body == null):
				var items = [for (v in prelude) if (!v.match(Token(_.kind => Whitespace))) v];
				var uri = items.length > 0 ? url(items[items.length - 1]) : null;
				if (uri != null) {
					if (items.length == 2) switch items[0] {
						case Token(_.kind => Ident(p)): namespaces.prefixes.set(p, uri);
						case _:
					} else if (items.length == 1) namespaces.defaultNamespace = uri;
				}
				[];
			case "page" if (body != null): [Page(page(prelude, body))];
			case "font-face" if (body != null): [FontFace({descriptors: declarations(body), url: options.url})];
			case "counter-style" if (body != null):
				var items = [for (v in prelude) if (!v.match(Token(_.kind => Whitespace))) v];
				switch items {
					case [Token(_.kind => Ident(n))] if (!["none", "decimal", "disc", "circle", "square", "inherit", "initial", "unset"].contains(Css.lower(n))):
						[CounterStyle({name: n, descriptors: declarations(body)})];
					case _: [];
				}
			case _: [];
		}
	}

	static function declarations(body:Array<CssRule>):Array<CssDeclaration> {
		var out = [];
		for (r in body) switch r {
			case Declarations(ds): for (d in ds) out.push(d);
			case _:
		}
		return out;
	}

	// @import url [layer | layer(name)] [supports(...)] [media]
	function load(prelude:Array<CssValue>):Array<CssSheetRule> {
		var items = [for (v in prelude) if (!v.match(Token(_.kind => Whitespace))) v];
		if (items.length == 0 || options.load == null || depth > 16) return [];
		var href = url(items[0]);
		if (href == null) return [];
		var k = 1, layer:Null<String> = null, anon = false;
		if (k < items.length) switch items[k] {
			case Token(_.kind => Ident(w)) if (Css.lower(w) == "layer"):
				anon = true;
				layer = '#import${anonymous++}';
				k++;
			case Function(f, args, _, _) if (Css.lower(f) == "layer"):
				var n = layerNames(args);
				if (n == null || n.length != 1) return [];
				layer = n[0];
				k++;
			case _:
		}
		if (k < items.length) switch items[k] {
			case Function(f, args, _, _) if (Css.lower(f) == "supports"):
				// (a declaration alone, or a condition)
				var d = Css.declaration(Css.serialize(args));
				var ok = d != null ? CssSupports.text('(${Css.serialize(args)})') : CssSupports.test(args);
				if (!ok) return [];
				k++;
			case _:
		}
		// (the media list: all after what was read)
		var media = CssMedia.parse(prelude.slice(prelude.indexOf(items[k - 1]) + 1));
		var absolute = CssUrl.resolve(options.url, href);
		var text = options.load(absolute);
		if (text == null) return [];
		var sheet = new Builder(origin, {url: absolute, load: options.load}, depth + 1).sheet(Css.sheet(text));
		return [Import(sheet, media, layer, anon)];
	}

	static function url(v:CssValue):Null<String>
		return switch v {
			case Token(_.kind => Str(s)) | Token(_.kind => Url(s)): s;
			case Function(f, args, _, _) if (Css.lower(f) == "url"):
				var a = [for (x in args) if (!x.match(Token(_.kind => Whitespace))) x];
				a.length >= 1 ? switch a[0] {
					case Token(_.kind => Str(s)): s;
					case _: null;
				} : null;
			case _: null;
		}

	// (layer names: idents joined by dots, comma-separated)
	static function layerNames(prelude:Array<CssValue>):Null<Array<String>> {
		var out = [], cur = "";
		var expectName = true;
		for (v in prelude) switch v {
			case Token(t): switch t.kind {
					case Whitespace:
						if (cur != "") expectName = false;
					case Ident(w):
						if (!expectName && cur != "") return null;
						if (["initial", "inherit", "unset", "revert", "revert-layer", "default"].contains(Css.lower(w))) return null;
						cur += w;
						expectName = false;
					case Delim("."):
						if (cur == "" || expectName) return null;
						cur += ".";
						expectName = true;
					case Comma:
						if (cur == "" || expectName) return null;
						out.push(cur);
						cur = "";
						expectName = true;
					case _: return null;
				}
			case _: return null;
		}
		if (cur != "") {
			if (expectName) return null;
			out.push(cur);
		} else if (out.length > 0) return null;
		return out;
	}

	function page(prelude:Array<CssValue>, body:Array<CssRule>):CssPageRule {
		var selectors = [];
		for (part in Css.list(Css.serialize(prelude))) {
			var name:Null<String> = null, pseudos = [];
			var k = 0;
			var items = [for (v in part) if (!v.match(Token(_.kind => Whitespace))) v];
			while (k < items.length) {
				switch items[k] {
					case Token(_.kind => Ident(n)) if (k == 0): name = n;
					case Token(_.kind => Colon) if (k + 1 < items.length):
						switch items[k + 1] {
							case Token(_.kind => Ident(p)): pseudos.push(Css.lower(p));
							case _:
						}
						k++;
					case _:
				}
				k++;
			}
			if (name != null || pseudos.length > 0) selectors.push({name: name, pseudos: pseudos});
		}
		var declared = [], descriptors = [], margins = new Map<String, Array<CssDeclared>>();
		for (r in body) switch r {
			case Declarations(ds):
				for (d in ds) {
					var c = CssSheet.declared(d);
					if (c.length > 0) for (x in c) declared.push(x) else descriptors.push(d);
				}
			case At(n, _, b) if (b != null && MARGINS.contains(Css.lower(n))): margins.set(Css.lower(n), CssSheet.compile(declarations(b)));
			case _:
		}
		return {selectors: selectors, declarations: declared, descriptors: descriptors, margins: margins, origin: origin, order: 0};
	}

	static final MARGINS = [
		"top-left-corner", "top-left", "top-center", "top-right", "top-right-corner", "bottom-left-corner", "bottom-left", "bottom-center", "bottom-right",
		"bottom-right-corner", "left-top", "left-middle", "left-bottom", "right-top", "right-middle", "right-bottom"
	];
}
