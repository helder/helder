package reference;

// #321's cascade as it was merged (bee738a8), frozen: the oracle that
// computed styles through CssStyle's groups are checked against.

import helder.css.*;
import reference.RefSheet;
import reference.RefStyles;
import reference.RefCascade;
import reference.RefUserAgent;
import reference.RefHints;
import helder.css.CssTerm;
import helder.css.CssCalc;
import helder.css.CssComputed;

import helder.css.CssComputed;
import helder.css.CssTerm;
import helder.dom.Element;

// A declaration in an element's cascade: what it sets, and where it
// stands (Cascade 5 §6): rank (origin and importance: UA, user, author
// normal, then author, user, UA important), attached (a style
// attribute's), layer (its order, reversed for important ones),
// specificity, order (the rule's, then the declaration's).
typedef RefCandidate = {d:RefDeclared, rank:Int, attached:Bool, layer:Int, specificity:Int, order:Int}

// An element's (or a pseudo-element's) style: its cascaded values, each
// property computed when first asked (Cascade 5 §4): a CSS-wide keyword
// resolved (revert to the origin below, revert-layer to the layer
// below), var() substituted (Variables 1: a cycle and a missing name
// without a fallback make the value invalid at computed-value time, as
// unset), then the value computed as CssComputed does, with this
// element's font size and colour. Unset properties inherit or take their
// initial value.
class RefStyle {
	public final element:Element;
	// null, "before", "after", "marker"
	public final pseudo:Null<String>;
	public final parent:Null<RefStyle>;
	final styles:RefStyles;
	final cascaded:Map<String, Array<RefCandidate>>;
	// (computed values by property id: what was declared here, and initial values a context changes)
	final cache = new haxe.ds.IntMap<Array<CssTerm>>();
	final customs = new Map<String, Null<Array<CssValue>>>();
	final resolving = new Map<String, Bool>();
	final cyclic = new Map<String, Bool>();
	var pairing = false;
	// (the ids of the properties declared here, a bit each)
	final declared:haxe.ds.Vector<Int>;
	final inheritedValues:haxe.ds.Vector<Array<CssTerm>>;

	@:allow(reference.RefStyles)
	function new(styles:RefStyles, element:Element, pseudo:Null<String>, parent:Null<RefStyle>, cascaded:Map<String, Array<RefCandidate>>) {
		this.styles = styles;
		this.element = element;
		this.pseudo = pseudo;
		this.parent = parent;
		this.cascaded = cascaded;
		table();
		declared = new haxe.ds.Vector((count >> 5) + 1);
		for (k in 0...declared.length) declared[k] = 0;
		// (an element declaring no inherited property has its parent's inherited values: their slots shared)
		var own = parent == null;
		for (k in cascaded.keys()) {
			var id = ids.get(k);
			if (id != null) declared[id >> 5] |= 1 << (id & 31);
			if (StringTools.startsWith(k, "--") || id != null && slot[id] >= 0) own = true;
		}
		inheritedValues = own ? new haxe.ds.Vector(inheritedCount) : parent.inheritedValues;
	}

	// (every longhand's id; an inherited one's slot, else -1; a fixed initial value's, once known)
	static var ids:Null<Map<String, Int>>;
	static var names:Array<String>;
	static var slot:Array<Int>;
	static var fixed:Array<Null<Array<CssTerm>>>;
	// (0: not known yet, 1: fixed, 2: depends on the context)
	static var fixedness:Array<Int>;
	// (the properties whose computed value reads another's: adjust())
	static var dependent:Array<Bool>;
	static var displayId = -1;
	static var count = 0;
	static var inheritedCount = 0;

	static function table() {
		if (ids != null) return;
		ids = new Map();
		names = [];
		slot = [];
		for (p in CssData.properties) if (p.longhands.length == 0 && p.alias == null) {
			ids.set(p.name, names.length);
			names.push(p.name);
			slot.push(p.inherited == true ? inheritedCount++ : -1);
		}
		count = names.length;
		fixed = [for (_ in names) null];
		fixedness = [for (_ in names) 0];
		dependent = [for (n in names) DEPENDENT.contains(n)];
		displayId = ids.get("display");
	}

	// The property's computed value, as terms (a longhand's).
	public function get(property:String):Array<CssTerm> {
		table();
		var id = ids.get(property);
		return id == null ? value(property, 0) : at(id);
	}

	// (by id: a value not declared here is the parent's when it inherits, or the shared initial one)
	function at(id:Int):Array<CssTerm> {
		if (declared[id >> 5] & (1 << (id & 31)) == 0) {
			var s = slot[id];
			if (s >= 0) {
				var v = inheritedValues[s];
				if (v == null) inheritedValues[s] = v = parent != null ? parent.at(id) : initial(names[id]);
				return v;
			}
			var f = fixed[id];
			if (f != null) {
				if (!dependent[id]) return f;
				// (an initial value another property changes: kept when changed, and
				// display always, since a child's reads its parent's)
				var c = cache.get(id);
				if (c != null) return c;
				var a = adjust(names[id], f);
				if (a != f || id == displayId) cache.set(id, a);
				return a;
			}
		}
		var v = cache.get(id);
		if (v == null) cache.set(id, v = dependent[id] ? adjust(names[id], value(names[id], 0)) : value(names[id], 0));
		return v;
	}

	// (computed values that read other properties: a border's or outline's
	// width its style's, float position's, display the box's place, CSS 2.1
	// §9.7, Display 3 §2.7; content the pseudo-element's)
	function adjust(p:String, v:Array<CssTerm>):Array<CssTerm> {
		return switch p {
			case "border-top-width" | "border-right-width" | "border-bottom-width" | "border-left-width":
				switch get(p.substr(0, p.length - 5) + "style") {
					case [Keyword("none" | "hidden")]: ZERO;
					case _: v;
				}
			case "outline-width":
				switch get("outline-style") {
					case [Keyword("none")]: ZERO;
					case _: v;
				}
			case "float":
				positioned() ? NONE : v;
			case "display":
				blockify(v);
			// (normal on ::before and ::after is none, Content 3 §1)
			case "content" if (pseudo == "before" || pseudo == "after"):
				v.length == 1 && v[0].match(Keyword("normal")) ? NONE : v;
			case _: v;
		}
	}

	static final ZERO = [Dimension(0, "px")];
	static final NONE = [Keyword("none")];

	function positioned():Bool
		return keyword("position") == "absolute" || keyword("position") == "fixed";

	// (a value that is one keyword: it; else null)
	function keyword(p:String):Null<String>
		return switch get(p) {
			case [Keyword(k)]: k;
			case _: null;
		}

	function blockify(v:Array<CssTerm>):Array<CssTerm> {
		if (pseudo == "marker") return v;
		var root = pseudo == null && element.ownerDocument.documentElement == element;
		if (!root && !positioned() && keyword("float") == "none" && !inFlexOrGrid()) return v;
		var text = CssText.join(v, CssText.term);
		if (root && text == "contents") return BLOCK;
		var to = BLOCKIFIED.get(text);
		return to == null ? v : [for (w in to.split(" ")) Keyword(w)];
	}

	static final BLOCK = [Keyword("block")];

	// (a flex or grid container's child, its parent box past display: contents)
	function inFlexOrGrid():Bool {
		var p = parent;
		while (p != null && p.keyword("display") == "contents") p = p.parent;
		return p != null && p.blocksChildren();
	}

	var blocks = -1;

	function blocksChildren():Bool {
		if (blocks < 0) blocks = ~/(^|[ -])(flex|grid|grid-lanes)$/.match(CssText.join(get("display"), CssText.term)) ? 1 : 0;
		return blocks == 1;
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

	// The computed value as getComputedStyle writes it (a shorthand's from
	// its longhands; a custom property's as substituted).
	public function text(property:String):String {
		if (StringTools.startsWith(property, "--")) {
			var v = custom(property);
			return v == null ? "" : StringTools.trim(Css.serialize(v));
		}
		var name = Css.lower(property);
		var p = CssGrammars.property(name);
		if (p == null) return "";
		if (p.alias != null) name = p.alias;
		if (CssShorthands.isShorthand(name)) {
			var ls = CssShorthands.longhands(name);
			var texts = [for (l in ls) l => text(l)];
			var initials = [for (l in ls) l => CssValues.written(l, initial(l), context(l, true))];
			return CssShorthands.serialize(name, texts, true, initials);
		}
		return CssValues.written(name, get(name), context(name, true));
	}

	// The line height in px (lh's); null for normal, the first available
	// font's metrics, which wait on fonts.
	public function lineHeight():Null<Float>
		return switch get("line-height") {
			case [Dimension(v, "px")]: v;
			case [Number(n, _)]: n * fontSize();
			case _: null;
		}

	// The font size in px (what em is for every property but font-size).
	public function fontSize():Float
		return switch get("font-size") {
			case [Dimension(v, "px")]: v;
			case _: 16;
		}

	// ---- the cascade's value

	function value(p:String, from:Int):Array<CssTerm> {
		var cands = cascaded.get(p);
		if (cands == null || from >= cands.length) return defaulted(p);
		var c = cands[from];
		return wide(p, c.d.value, cands, from) ?? switch c.d.value {
			case Unresolved(_):
				var v = substitute(c.d.values ?? []);
				// (invalid at computed-value time: as unset)
				if (v == null) return defaulted(p);
				var spec = c.d.shorthand != null ? fromShorthand(c.d.shorthand, p, v) : read(p, v);
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
	function wide(p:String, v:CssSpecified, cands:Array<RefCandidate>, from:Int):Null<Array<CssTerm>> {
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

	static function below(cands:Array<RefCandidate>, from:Int, ok:RefCandidate->Bool):Int {
		for (k in from + 1...cands.length) if (ok(cands[k])) return k;
		return -1;
	}

	// (0 UA, 1 user, 2 author, whatever the importance)
	static function origin(rank:Int):Int
		return rank <= 2 ? rank : 5 - rank;

	// (a substituted value read once for every element that has it)
	static function read(p:String, v:Array<CssValue>):Null<CssSpecified> {
		var key = p + ":" + Css.serialize(v);
		if (READS.exists(key)) return READS.get(key);
		var s = CssValues.read(p, v);
		READS.set(key, s);
		return s;
	}

	static final READS = new Map<String, Null<CssSpecified>>();

	function fromShorthand(shorthand:String, p:String, v:Array<CssValue>):Null<CssSpecified> {
		var s = read(shorthand, v);
		return switch s {
			case Terms(t):
				var parts = CssShorthands.expand(shorthand, t);
				parts == null || !parts.exists(p) ? null : Terms(parts[p]);
			case Wide(_): s;
			case _: null;
		}
	}

	function defaulted(p:String):Array<CssTerm>
		return inherits(p) ? inherit(p) : initial(p);

	function inherit(p:String):Array<CssTerm>
		return parent != null ? parent.get(p) : initial(p);

	function initial(p:String):Array<CssTerm> {
		table();
		var id = ids.get(p);
		if (id != null && fixed[id] != null) return fixed[id];
		var t = CssShorthands.initialTerms(p);
		if (t == null) return [];
		var c = compute(p, t);
		// (an initial value that no context changes, computed once for every element)
		if (id != null && fixedness[id] == 0)
			fixedness[id] = !CONTEXTUAL.contains(p) && !~/\d(em|ex|ch|ic|cap|lh|rem|rlh|vw|vh|vi|vb|vmin|vmax)\b|currentcolor/.match(CssText.join(t, CssText.term)) ? 1 : 2;
		if (id != null && fixedness[id] == 1) fixed[id] = c;
		return c;
	}
	static final DEPENDENT = ["border-top-width", "border-right-width", "border-bottom-width", "border-left-width", "outline-width", "float", "display", "content"];
	static final CONTEXTUAL = ["justify-items", "overflow-x", "overflow-y", "text-align-all", "color", "font-size", "line-height"];

	static function inherits(p:String):Bool {
		var i = INHERITED.get(p);
		if (i == null) {
			var d = CssGrammars.property(p);
			INHERITED.set(p, i = d != null && d.inherited == true);
		}
		return i;
	}

	static final INHERITED = new Map<String, Bool>();

	function compute(p:String, t:Array<CssTerm>):Array<CssTerm> {
		switch [p, t] {
			// (legacy alone: the parent's legacy with a direction, else normal, Align 3 §6.1)
			case ["justify-items", [Keyword("legacy")]]:
				var from = parent == null ? [] : parent.get(p);
				return from.length == 2 && from[0].match(Keyword("legacy")) ? from : [Keyword("normal")];
			// (match-parent: the parent's, start and end as its direction's sides)
			case ["text-align-all", [Keyword("match-parent")]]:
				if (parent == null) return [Keyword("start")];
				var from = parent.get(p);
				var rtl = parent.text("direction") == "rtl";
				return switch from {
					case [Keyword("start")]: [Keyword(rtl ? "right" : "left")];
					case [Keyword("end")]: [Keyword(rtl ? "left" : "right")];
					case _: from;
				}
			// (visible beside a scrolling axis computes to auto, Overflow 3 §3; browsers keep clip)
			case ["overflow-x" | "overflow-y", [Keyword("visible")]] if (!pairing):
				// (the other axis's own value, before its pairing)
				pairing = true;
				var other = value(p == "overflow-x" ? "overflow-y" : "overflow-x", 0);
				pairing = false;
				if (other.length == 1 && !other[0].match(Keyword("visible" | "clip"))) return [Keyword("auto")];
			case _:
		}
		// (bolder and lighter: from the parent's weight, Fonts 4 §2.2's table)
		if (p == "font-weight") switch t {
			case [Keyword(k = "bolder" | "lighter")]:
				var w = switch parent?.get(p) {
					case [Number(v, _)]: v;
					case _: 400;
				}
				return [Number(k == "bolder" ? bolder(w) : lighter(w), false)];
			case _:
		}
		// (currentcolor in color itself is the inherited colour, Color 4 §3.3)
		if (p == "color" && Lambda.exists(t, x -> switch x {
			case Color(c): c.keyword == "currentcolor";
			case _: false;
		})) return inherit(p);
		return CssComputed.terms(p, CssCanonical.terms(p, t), context(p, false));
	}

	static function bolder(w:Float):Float
		return w < 350 ? 400 : w < 550 ? 700 : w < 900 ? 900 : w;

	static function lighter(w:Float):Float
		return w < 100 ? w : w < 550 ? 100 : w < 750 ? 400 : 700;

	// (color: what text needs for currentcolor; computing doesn't)
	function context(p:String, color:Bool):CssComputeContext {
		var parentSize = parent != null ? parent.fontSize() : 16;
		var media = styles.media;
		// (color's em and font-size's colour are their parent's: neither depends on the
		// other; em in the font properties is the parent's, Values 4 §6.1.1)
		var own = p != "font-size" && p != "color";
		// (lh and rlh in font-size and line-height are the parent's and the
		// initial value's, Values 4 §6.1.1; color's the parent's too)
		var metric = p == "font-size" || p == "line-height";
		// (the root's rem and rlh are its own, but in font-size, initial's)
		var root = parent == null;
		return {
			fontSize: own && !StringTools.startsWith(p, "font-") ? fontSize() : parentSize,
			parentFontSize: parentSize,
			rootFontSize: !root ? styles.rootFontSize() : p == "font-size" ? 16 : fontSize(),
			lineHeight: !metric && p != "color" ? lineHeight() : parent?.lineHeight(),
			rootLineHeight: !root ? styles.rootLineHeight() : metric ? null : lineHeight(),
			viewport: {width: media.width, height: media.height},
			color: !color ? null : own ? text("color") : parent != null ? parent.text("color") : "rgb(0, 0, 0)"
		};
	}

	// ---- custom properties

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

	function customValue(name:String, from:Int):Null<Array<CssValue>> {
		var cands = cascaded.get(name);
		if (cands == null || from >= cands.length) return parent != null ? parent.custom(name) : null;
		var c = cands[from];
		var values = c.d.values ?? [];
		var keyword = switch [for (v in values) if (!v.match(Token(_.kind => Whitespace))) v] {
			case [Token(_.kind => Ident(w))]: Css.lower(w);
			case _: null;
		}
		return switch keyword {
			case "initial": null;
			case "inherit" | "unset": parent != null ? parent.custom(name) : null;
			case "revert":
				var next = below(cands, from, x -> origin(x.rank) != origin(c.rank));
				next < 0 ? (parent != null ? parent.custom(name) : null) : customValue(name, next);
			case "revert-layer":
				var next = below(cands, from, x -> x.rank != c.rank || x.layer != c.layer);
				next < 0 ? (parent != null ? parent.custom(name) : null) : customValue(name, next);
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
					case "inherit" | "unset": parent != null ? parent.custom(name) : null;
					case "revert":
						var next = below(cands, from, x -> origin(x.rank) != origin(c.rank));
						next < 0 ? (parent != null ? parent.custom(name) : null) : customValue(name, next);
					case _:
						var next = below(cands, from, x -> x.rank != c.rank || x.layer != c.layer);
						next < 0 ? (parent != null ? parent.custom(name) : null) : customValue(name, next);
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
		return StringTools.startsWith(name, "safe-area-") ? Css.values("0px") : null;
}
