package helder.css;

import haxe.ds.IntMap;
import helder.css.CssColors;
import helder.css.CssComputed;
import helder.css.CssProperty;
import helder.css.CssSheet;
import helder.css.CssTerm;

// A declaration in an element's cascade: what it sets, and where it
// stands (Cascade 5 §6): rank (origin and importance: UA, user, author
// normal, then author, user, UA important), attached (a style
// attribute's), layer (its order, reversed for important ones),
// specificity, order (the rule's, then the declaration's).
typedef CssCandidate = {d:CssDeclared, rank:Int, attached:Bool, layer:Int, specificity:Int, order:Int}

// One element's computed values worked out from its cascade (Cascade 5
// §4), as terms, each when first asked: a CSS-wide keyword resolved
// (revert to the origin below, revert-layer to the layer below), var()
// substituted (Variables 1: a cycle and a missing name without a fallback
// make the value invalid at computed-value time, as unset), then computed
// as CssComputed does, with the element's font size and colour; unset
// properties inherit (the parent style's) or take their initial value.
// CssStyles makes one when no style made before fits, and keeps what it
// works out in the element's groups.
class CssResolver {
	final styles:CssStyles;
	final parent:Null<CssStyle>;
	final pseudo:Null<String>;
	final root:Bool;
	// (a flex or grid container's child, its parent box past display: contents: CssStyles knows)
	final item:Bool;
	// (by physical property: logical ones mapped once direction is known)
	public final cascaded = new IntMap<Array<CssCandidate>>();
	public final customCandidates = new Map<String, Array<CssCandidate>>();
	final cache = new IntMap<Array<CssTerm>>();
	final customs = new Map<String, Null<Array<CssValue>>>();
	final resolving = new Map<String, Bool>();
	final cyclic = new Map<String, Bool>();
	var pairing = false;

	public function new(styles:CssStyles, parent:Null<CssStyle>, pseudo:Null<String>, root:Bool, item:Bool) {
		this.styles = styles;
		this.parent = parent;
		this.pseudo = pseudo;
		this.root = root;
		this.item = item;
	}

	// The property's computed value.
	public function get(p:CssProperty):Array<CssTerm> {
		var v = cache.get(p);
		if (v == null) cache.set(p, v = adjust(p, value(p, 0)));
		return v;
	}

	// (every value worked out but direction's, before the rest of the cascade is in)
	public function forget() {
		var d = cache.get(Direction);
		cache.clear();
		if (d != null) cache.set(Direction, d);
	}

	public inline function declares(p:CssProperty):Bool
		return cascaded.exists(p);

	// (computed values that read other properties: float position's,
	// display the box's place, CSS 2.1 §9.7, Display 3 §2.7; content the
	// pseudo-element's. A border's width under a none style is its own:
	// Borders 4 zeroes the used one, not the computed one)
	function adjust(p:CssProperty, v:Array<CssTerm>):Array<CssTerm> {
		return switch p {
			case Float: positioned() ? NONE : v;
			case Display: blockify(v);
			// (normal on ::before and ::after is none, Content 3 §1, and on a page's margin boxes, Paged Media 3 §4.2)
			case Content if (pseudo == "before" || pseudo == "after" || pseudo != null && pseudo.charAt(0) == "@" && pseudo != "@page"): v.length == 1 && v[0].match(Keyword("normal")) ? NONE : v;
			case _: v;
		}
	}

	static final NONE = [Keyword("none")];

	public function positioned():Bool {
		var p = keyword(Position);
		return p == "absolute" || p == "fixed";
	}

	// (a value that is one keyword: it; else null)
	public function keyword(p:CssProperty):Null<String>
		return switch get(p) {
			case [Keyword(k)]: k;
			case _: null;
		}

	// (display before blockification, when blockify changed it)
	public var unblockified(default, null):Null<Array<CssTerm>>;

	function blockify(v:Array<CssTerm>):Array<CssTerm> {
		unblockified = null;
		if (pseudo == "marker") return v;
		if (!root && !positioned() && keyword(Float) == "none" && !item) return v;
		var text = CssText.join(v, CssText.term);
		var to = root && text == "contents" ? "block" : BLOCKIFIED.get(text);
		if (to == null) return v;
		unblockified = v;
		return [for (w in to.split(" ")) Keyword(w)];
	}

	// (inline-level displays as block-level, layout-internal ones as block;
	// inline-block as block, as CSS 2.1's table and browsers have it)
	static final BLOCKIFIED = [
		"inline" => "block", "inline-block" => "block", "inline-table" => "table", "inline-flex" => "flex", "inline-grid" => "grid",
		"inline-grid-lanes" => "grid-lanes", "inline grid-lanes" => "grid-lanes", "inline list-item" => "list-item",
		"inline flow-root list-item" => "flow-root list-item", "ruby" => "block ruby", "run-in" => "block", "run-in flow-root" => "flow-root",
		"run-in flex" => "flex", "run-in grid" => "grid", "run-in table" => "table", "run-in ruby" => "block ruby", "run-in list-item" => "list-item",
		"run-in flow-root list-item" => "flow-root list-item", "table-row-group" => "block", "table-header-group" => "block",
		"table-footer-group" => "block", "table-row" => "block", "table-cell" => "block", "table-column-group" => "block",
		"table-column" => "block", "table-caption" => "block", "ruby-base" => "block", "ruby-text" => "block",
		"ruby-base-container" => "block", "ruby-text-container" => "block"
	];

	// The line height in px (lh's); normal's the first available font's, null without fonts.
	function lineHeight():Null<Float>
		return switch get(LineHeight) {
			case [Dimension(v, "px")]: v;
			case [Number(n, _)]: n * fontSize();
			case _: fontMetrics()?.lineHeight;
		}

	function fontSize():Float
		return switch get(FontSize) {
			case [Dimension(v, "px")]: v;
			case _: 16;
		}

	var metrics:Null<CssFontMetrics> = null;
	var measuring = false;

	// (the element's first available font's metrics, from its font properties;
	// none while they are worked out: their initial values are computed too)
	function fontMetrics():Null<CssFontMetrics> {
		if (metrics != null || measuring) return metrics;
		measuring = true;
		metrics = try styles.fontMetrics(get, fontSize()) catch (e:haxe.Exception) {
			measuring = false;
			throw e;
		}
		measuring = false;
		return metrics;
	}

	// ---- the cascade's value

	function value(p:CssProperty, from:Int):Array<CssTerm> {
		var cands = cascaded.get(p);
		if (cands == null || from >= cands.length) return defaulted(p);
		var c = cands[from];
		return wide(p, c.d.value, cands, from) ?? switch c.d.value {
			case Unresolved(_):
				var v = substitute(c.d.values ?? []);
				// (invalid at computed-value time: as unset)
				if (v == null) return defaulted(p);
				// (a logical longhand's value read as it was declared)
				var spec = rereader == null ? null : rereader(c.d.property, c.d.shorthand, v);
				switch spec {
					case null: defaulted(p);
					// (a CSS-wide keyword substituted is that keyword where the declaration stands)
					case Wide(_): wide(p, spec, cands, from) ?? defaulted(p);
					case Terms(t): compute(p, t);
					case Unresolved(_): defaulted(p);
				}
			case Terms(t): compute(p, t);
			case Wide(_): defaulted(p);
		}
	}

	// (a CSS-wide keyword's value; null for another value)
	function wide(p:CssProperty, v:CssSpecified, cands:Array<CssCandidate>, from:Int):Null<Array<CssTerm>> {
		var c = cands[from];
		return switch v {
			case Wide("initial"): initial(p);
			case Wide("inherit"): inherit(p);
			case Wide("unset"): defaulted(p);
			case Wide("revert"):
				var next = below(cands, from, x -> x.rank != c.rank && origin(x.rank) != origin(c.rank));
				next < 0 ? defaulted(p) : value(p, next);
			case Wide("revert-layer"):
				var next = below(cands, from, x -> x.rank != c.rank || x.layer != c.layer);
				next < 0 ? defaulted(p) : value(p, next);
			case _: null;
		}
	}

	static function below(cands:Array<CssCandidate>, from:Int, ok:CssCandidate->Bool):Int {
		for (k in from + 1...cands.length) if (ok(cands[k])) return k;
		return -1;
	}

	// (0 UA, 1 user, 2 author, whatever the importance)
	static function origin(rank:Int):Int
		return rank <= 2 ? rank : 5 - rank;

	// (a value with var() read again by its grammar once substituted:
	// installed where such values can be, CssCascade.styles and a compiled
	// sheet that has one (CssTheme, CssModule), so that a program whose
	// sheets have none links no grammar matcher)
	static var rereader:Null<(property:String, shorthand:Null<String>, values:Array<CssValue>) -> Null<CssSpecified>> = null;

	public static function rereads() {
		rereader = (p, shorthand, v) -> shorthand != null ? fromShorthand(shorthand, p, v) : read(p, v);
		CssValues.reading = CssValues.read;
	}

	// (a substituted value read once for every element that has it)
	static function read(p:String, v:Array<CssValue>):Null<CssSpecified> {
		var key = p + ":" + Css.serialize(v);
		if (READS.exists(key)) return READS.get(key);
		var s = CssValues.read(p, v);
		READS.set(key, s);
		return s;
	}

	static final READS = new Map<String, Null<CssSpecified>>();

	static function fromShorthand(shorthand:String, p:String, v:Array<CssValue>):Null<CssSpecified> {
		var s = read(shorthand, v);
		return switch s {
			case Terms(t):
				var parts = CssShorthands.expand(shorthand, t);
				parts == null || !parts.exists(p) ? null : Terms(parts[p]);
			case Wide(_): s;
			case _: null;
		}
	}

	function defaulted(p:CssProperty):Array<CssTerm>
		return CssProperties.inherits(p) ? inherit(p) : initial(p);

	function inherit(p:CssProperty):Array<CssTerm>
		return parent != null ? parent.terms(p) : initial(p);

	function initial(p:CssProperty):Array<CssTerm> {
		var t = styles.initialTerms(p);
		return t == null ? [] : compute(p, t);
	}

	function compute(p:CssProperty, t:Array<CssTerm>):Array<CssTerm> {
		switch [p, t] {
			// (legacy alone: the parent's legacy with a direction, else normal, Align 3 §6.1)
			case [JustifyItems, [Keyword("legacy")]]:
				var from = parent == null ? [] : parent.terms(p);
				return from.length == 2 && from[0].match(Keyword("legacy")) ? from : [Keyword("normal")];
			// (match-parent: the parent's, start and end as its direction's sides)
			case [TextAlignAll, [Keyword("match-parent")]]:
				if (parent == null) return [Keyword("start")];
				var from = parent.terms(p);
				var rtl = parent.inheritedText.direction == Rtl;
				return switch from {
					case [Keyword("start")]: [Keyword(rtl ? "right" : "left")];
					case [Keyword("end")]: [Keyword(rtl ? "left" : "right")];
					case _: from;
				}
			// (visible beside a scrolling axis computes to auto, Overflow 3 §3; browsers keep clip)
			case [OverflowX | OverflowY, [Keyword("visible")]] if (!pairing):
				// (the other axis's own value, before its pairing)
				pairing = true;
				var other = value(p == OverflowX ? OverflowY : OverflowX, 0);
				pairing = false;
				if (other.length == 1 && !other[0].match(Keyword("visible" | "clip"))) return [Keyword("auto")];
			// (bolder and lighter: from the parent's weight, Fonts 4 §2.2's table)
			case [FontWeight, [Keyword(k = "bolder" | "lighter")]]:
				var w = parent == null || Math.isNaN(parent.font.fontWeight) ? 400 : parent.font.fontWeight;
				return [Number(k == "bolder" ? bolder(w) : lighter(w), false)];
			case _:
		}
		// (currentcolor in color itself is the inherited colour, Color 4 §3.3; a relative colour's too)
		if (p == Color && Lambda.exists(t, x -> switch x {
			case Color(c): c.keyword == "currentcolor";
			case _: false;
		})) return inherit(p);
		if (p == Color && t.length == 1) switch t[0] {
			case Color(c) if (c.from != null && CssColors.absolute(c) == null):
				var pc = parent?.color(Color);
				var inherited:CssColorValue = pc == null || pc.keyword != null ? {space: "rgb", c: [0, 0, 0], alpha: 1} : {space: "srgb", c: [pc.r, pc.g, pc.b], alpha: pc.a};
				t = [Color(CssColors.current(c, inherited))];
			case _:
		}
		var name = CssProperties.name(p);
		return CssComputed.terms(name, CssCanonical.terms(name, t), context(p));
	}

	static function bolder(w:Float):Float
		return w < 350 ? 400 : w < 550 ? 700 : w < 900 ? 900 : w;

	static function lighter(w:Float):Float
		return w < 100 ? w : w < 550 ? 100 : w < 750 ? 400 : 700;

	function context(p:CssProperty):CssComputeContext {
		var parentSize = parent != null ? parent.fontSize() : 16;
		// (color's em and font-size's colour are their parent's: neither depends on the
		// other; em in the font properties is the parent's, Values 4 §6.1.1)
		var own = p != FontSize && p != Color;
		// (lh and rlh in font-size and line-height are the parent's and the
		// initial value's, Values 4 §6.1.1; color's the parent's too)
		var metric = p == FontSize || p == LineHeight;
		var name = CssProperties.name(p);
		// (the root's rem and rlh are its own, but in font-size, initial's)
		var top = parent == null;
		return {
			fontSize: own && !StringTools.startsWith(name, "font-") ? fontSize() : parentSize,
			parentFontSize: parentSize,
			rootFontSize: !top ? styles.rootFontSize() : p == FontSize ? 16 : fontSize(),
			lineHeight: !metric && p != Color ? lineHeight() : parent?.lineHeight(),
			rootLineHeight: !top ? styles.rootLineHeight() : metric ? null : lineHeight(),
			viewport: styles.viewport(),
			color: null,
			// (the font properties' ex and ch the parent's font's, as their em)
			metrics: own && !StringTools.startsWith(name, "font-") ? fontMetrics() : parent?.fontMetrics(),
			rootMetrics: !top ? styles.rootMetrics() : own && !StringTools.startsWith(name, "font-") ? fontMetrics() : null
		};
	}

	// ---- custom properties

	// Every custom property this element declares, computed; the parent's
	// map when it declares none.
	public function allCustoms():Map<String, Null<Array<CssValue>>> {
		var inherited = parent?.customs;
		if (Lambda.count(customCandidates) == 0) return inherited ?? EMPTY;
		var out = inherited == null ? new Map() : inherited.copy();
		for (name in customCandidates.keys()) out.set(name, custom(name));
		return out;
	}

	static final EMPTY = new Map<String, Null<Array<CssValue>>>();

	// A custom property's computed value: its tokens, var() substituted;
	// null for the guaranteed-invalid value (unset, a cycle's, a missing name's).
	public function custom(name:String):Null<Array<CssValue>> {
		if (customs.exists(name)) return customs.get(name);
		if (resolving.exists(name)) {
			// (a cycle: every property in it invalid)
			for (k in resolving.keys()) cyclic.set(k, true);
			return null;
		}
		resolving.set(name, true);
		var v = customValue(name, 0);
		resolving.remove(name);
		if (cyclic.exists(name)) v = null;
		customs.set(name, v);
		return v;
	}

	function inheritedCustom(name:String):Null<Array<CssValue>>
		return parent?.customs.get(name);

	function customValue(name:String, from:Int):Null<Array<CssValue>> {
		var cands = customCandidates.get(name);
		if (cands == null || from >= cands.length) return inheritedCustom(name);
		var c = cands[from];
		var values = c.d.values ?? [];
		var keyword = switch [for (v in values) if (!v.match(Token(_.kind => Whitespace))) v] {
			case [Token(_.kind => Ident(w))]: Css.lower(w);
			case _: null;
		}
		return switch keyword {
			case "initial": null;
			case "inherit" | "unset": inheritedCustom(name);
			case "revert":
				var next = below(cands, from, x -> origin(x.rank) != origin(c.rank));
				next < 0 ? inheritedCustom(name) : customValue(name, next);
			case "revert-layer":
				var next = below(cands, from, x -> x.rank != c.rank || x.layer != c.layer);
				next < 0 ? inheritedCustom(name) : customValue(name, next);
			case _:
				var v = substitute(values);
				// (a CSS-wide keyword substituted: that keyword where the declaration stands)
				var w = v == null ? null : switch [for (x in v) if (!x.match(Token(_.kind => Whitespace))) x] {
					case [Token(_.kind => Ident(k))] if (["initial", "inherit", "unset", "revert", "revert-layer"].contains(Css.lower(k))): Css.lower(k);
					case _: null;
				}
				switch w {
					case null: v;
					case "initial": null;
					case "inherit" | "unset": inheritedCustom(name);
					case "revert":
						var next = below(cands, from, x -> origin(x.rank) != origin(c.rank));
						next < 0 ? inheritedCustom(name) : customValue(name, next);
					case _:
						var next = below(cands, from, x -> x.rank != c.rank || x.layer != c.layer);
						next < 0 ? inheritedCustom(name) : customValue(name, next);
				}
		}
	}

	// Values with var() and env() replaced (Variables 1 §3); null when one
	// can't be: a missing name without a fallback, a cycle.
	public function substitute(values:Array<CssValue>):Null<Array<CssValue>> {
		var out = [];
		for (v in values) switch v {
			case Function(name, args, open, close):
				var n = Css.lower(name);
				if (n == "var" || n == "env") {
					var items = args;
					var comma = -1;
					for (k in 0...items.length) if (comma < 0 && items[k].match(Token(_.kind => Comma))) comma = k;
					var head = [for (x in (comma < 0 ? items : items.slice(0, comma))) if (!x.match(Token(_.kind => Whitespace))) x];
					var fallback = comma < 0 ? null : items.slice(comma + 1);
					// (a fallback that is a {} block alone is its contents, Values 5 §3)
					if (fallback != null) {
						var f = [for (x in fallback) if (!x.match(Token(_.kind => Whitespace))) x];
						if (f.length == 1) switch f[0] {
							case Block(o, inner, _) if (o.kind.match(OpenCurly)): fallback = inner;
							case _:
						}
					}
					var got:Null<Array<CssValue>> = null;
					if (head.length == 1) switch head[0] {
						case Token(_.kind => Ident(w)) if (n == "var" && StringTools.startsWith(w, "--")): got = custom(w);
						case Token(_.kind => Ident(w)) if (n == "env"): got = env(w);
						case _:
					}
					if (got == null && fallback != null) got = substitute(fallback);
					if (got == null) return null;
					for (x in got) out.push(x);
				} else {
					var inner = substitute(args);
					if (inner == null) return null;
					out.push(Function(name, inner, open, close));
				}
			case Block(open, inner, close):
				var s = substitute(inner);
				if (s == null) return null;
				out.push(Block(open, s, close));
			case _: out.push(v);
		}
		return out;
	}

	// (a page's environment: no insets)
	static function env(name:String):Null<Array<CssValue>>
		return StringTools.startsWith(name, "safe-area-") ? [Token(new CssToken(Dimension(0, true, "0", "px"), 0, 3))] : null;
}
