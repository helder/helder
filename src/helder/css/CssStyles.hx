package helder.css;

import helder.css.CssMedia;
import helder.css.CssSelector;
import helder.css.CssSheet;
import helder.css.CssStyle;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.Node;

using StringTools;

// A document's styles: its sheets' rules indexed by their rightmost
// compound (an id, a class, a type, else any), each element's cascade
// made when its style is first asked, and the at-rules' data for the
// later stages (@page, @font-face, @counter-style).
class CssStyles {
	public final document:Document;
	public final media:CssMediaContext;
	public final pages:Array<CssPageRule> = [];
	public final fontFaces:Array<CssFontFace> = [];
	public final counterStyles:Array<CssCounterStyle> = [];

	final hints:Null<Element->Array<CssDeclared>>;
	final index = new Index();
	final pseudos = new Map<String, Index>();
	final cache = new Map<Element, CssStyle>();
	final pseudoCache = new Map<Element, Map<String, CssStyle>>();
	final quirks:Bool;
	var order = 0;
	// (layer names in order of first appearance, per origin)
	final layers = new Map<String, Int>();
	var root:Null<CssStyle>;

	@:allow(helder.css.CssCascade)
	function new(document:Document, sheets:Array<{sheet:CssSheet, media:Null<CssMedia>}>, media:CssMediaContext, hints:Null<Element->Array<CssDeclared>>,
			?hintSheet:CssSheet) {
		this.document = document;
		this.media = media;
		this.hints = hints;
		quirks = document.mode == Quirks;
		// (HTML's hints written as CSS: author rules of specificity zero before the author's own)
		if (hintSheet != null) {
			var start = order;
			order = -1000000;
			add(hintSheet.rules, Author, null, true);
			order = start;
		}
		// (layers' order first, over every sheet, then the rules)
		for (s in sheets) if (s.media == null || s.media.matches(media)) declareLayers(s.sheet.rules, s.sheet.origin);
		for (s in sheets) if (s.media == null || s.media.matches(media)) add(s.sheet.rules, s.sheet.origin, null);
	}

	// The element's style, or one of its pseudo-elements' ("before", "after", "marker").
	public function computed(el:Element, ?pseudo:String):CssStyle {
		if (pseudo != null) {
			var m = pseudoCache.get(el);
			if (m == null) pseudoCache.set(el, m = new Map());
			var s = m.get(pseudo);
			if (s == null) m.set(pseudo, s = new CssStyle(this, el, pseudo, computed(el), cascade(el, pseudo)));
			return s;
		}
		var s = cache.get(el);
		if (s != null) return s;
		var p = el.parentNode;
		var parent = p != null && p.nodeType == Node.ELEMENT_NODE ? computed(cast p) : null;
		s = new CssStyle(this, el, null, parent, cascade(el, null));
		cache.set(el, s);
		return s;
	}

	// (rem's and rlh's: the root element's font size and line height)
	@:allow(helder.css.CssStyle)
	function rootFontSize():Float {
		var r = rootStyle();
		return r == null ? 16 : r.fontSize();
	}

	@:allow(helder.css.CssStyle)
	function rootLineHeight():Null<Float> {
		var r = rootStyle();
		return r == null ? null : r.lineHeight();
	}

	function rootStyle():Null<CssStyle> {
		var r = document.documentElement;
		if (r != null && root == null) root = computed(r);
		return root;
	}

	// ---- building the index

	function key(origin:CssOrigin, name:String):String
		return '${origin.getIndex()} $name';

	function declareLayers(rules:Array<CssSheetRule>, origin:CssOrigin)
		for (r in rules) switch r {
			case Layer(name, inner):
				if (name != null && !layers.exists(key(origin, name))) layers.set(key(origin, name), Lambda.count(layers));
				if (inner != null) declareLayers(inner, origin);
			case Media(m, inner) if (m.matches(media)): declareLayers(inner, origin);
			case Import(sheet, m, layer, _) if (m.matches(media)):
				if (layer != null && !layers.exists(key(origin, layer))) layers.set(key(origin, layer), Lambda.count(layers));
				declareLayers(sheet.rules, origin);
			case _:
		}

	function add(rules:Array<CssSheetRule>, origin:CssOrigin, layer:Null<String>, zero = false) {
		for (r in rules) switch r {
			case Style(selectors, declarations):
				var o = order++;
				var l = layer == null ? UNLAYERED : layers.get(key(origin, layer));
				for (s in selectors) {
					var rule = {selector: s, declarations: declarations, origin: origin, layer: l, order: o, zero: zero};
					switch s.pseudo {
						case null: index.add(rule, quirks);
						case p:
							var name = pseudoName(p);
							if (name == null) continue;
							var i = pseudos.get(name);
							if (i == null) pseudos.set(name, i = new Index());
							i.add(rule, quirks);
					}
				}
			case Media(m, inner): if (m.matches(media)) add(inner, origin, layer, zero);
			case Layer(name, inner): if (inner != null) add(inner, origin, name, zero);
			case Import(sheet, m, l, _): if (m.matches(media)) add(sheet.rules, origin, l ?? layer, zero);
			case Page(p):
				p.order = order++;
				pages.push(p);
			case FontFace(f): fontFaces.push(f);
			case CounterStyle(c): counterStyles.push(c);
		}
	}

	static inline var UNLAYERED = 1 << 20;

	static function pseudoName(p:CssPseudoElement):Null<String>
		return switch p {
			case Before: "before";
			case After: "after";
			case Marker: "marker";
			case FirstLine: "first-line";
			case FirstLetter: "first-letter";
			case FootnoteCall: "footnote-call";
			case FootnoteMarker: "footnote-marker";
			case _: null;
		}

	// ---- an element's cascade

	function cascade(el:Element, pseudo:Null<String>):Map<String, Array<CssCandidate>> {
		var out:Array<CssCandidate> = [];
		var idx = pseudo == null ? index : pseudos.get(pseudo);
		if (idx != null) for (rule in idx.candidates(el, quirks)) if (CssMatcher.matches(rule.selector, el)) {
			var spec = rule.zero ? 0 : rule.selector.specificity.toInt();
			var k = 0;
			for (d in rule.declarations) out.push(candidate(d, rule.origin, false, rule.layer, spec, rule.order * 4096 + k++));
		}
		if (pseudo == null) {
			// (presentational hints: author, specificity zero, before the author's rules)
			if (hints != null) {
				var k = 0;
				for (d in hints(el)) out.push(candidate(d, Author, false, UNLAYERED, 0, -1000000 + k++));
			}
			var style = el.getAttribute("style");
			if (style != null) {
				var k = 0;
				for (d in CssSheet.attribute(style)) out.push(candidate(d, Author, true, UNLAYERED, 0, k++));
			}
		}
		// best first: rank, then attached, layer, specificity, order
		out.sort((a, b) -> {
			if (a.rank != b.rank) return b.rank - a.rank;
			if (a.attached != b.attached) return a.attached ? -1 : 1;
			if (a.layer != b.layer) return b.layer - a.layer;
			if (a.specificity != b.specificity) return b.specificity > a.specificity ? 1 : -1;
			return b.order - a.order;
		});
		var by = new Map<String, Array<CssCandidate>>();
		for (c in out) {
			var l = by.get(c.d.property);
			if (l == null) by.set(c.d.property, l = []);
			l.push(c);
		}
		return by;
	}

	static function candidate(d:CssDeclared, origin:CssOrigin, attached:Bool, layer:Int, specificity:Int, order:Int):CssCandidate {
		var o = switch origin {
			case UserAgent: 0;
			case User: 1;
			case Author: 2;
		}
		// (important: author, user, UA; layers reversed, unlayered last)
		return {
			d: d,
			rank: d.important ? 5 - o : o,
			attached: attached,
			layer: d.important ? -layer : layer,
			specificity: specificity,
			order: order
		};
	}
}

private typedef Rule = {selector:CssSelector, declarations:Array<CssDeclared>, origin:CssOrigin, layer:Int, order:Int, zero:Bool}

// (rules by their rightmost compound's id, else class, else type, else
// attribute; :is() of types and links by their types, :root apart; a rule
// that can never match, :hover's or :visited's, left out; the rest any)
private class Index {
	final ids = new Map<String, Array<Rule>>();
	final classes = new Map<String, Array<Rule>>();
	final types = new Map<String, Array<Rule>>();
	final attributes = new Map<String, Array<Rule>>();
	final root:Array<Rule> = [];
	final any:Array<Rule> = [];
	var attributed = false;

	public function new() {}

	public function add(rule:Rule, quirks:Bool) {
		for (c in rule.selector.compounds) for (x in c) if (x.match(Pseudo(Never(_)))) return;
		var last = rule.selector.compounds[rule.selector.compounds.length - 1];
		var id = null, cls = null, type = null, attr = null, kinds:Null<Array<String>> = null, isRoot = false;
		for (s in last) switch s {
			case Id(n): id = n;
			case Class(n): if (cls == null) cls = n;
			case Type(n, _): type = n.toLowerCase();
			case Attribute(n, _, _, _, _): if (attr == null) attr = n.toLowerCase();
			case Pseudo(Link | AnyLink): kinds = ["a", "area"];
			case Pseudo(Root): isRoot = true;
			case Pseudo(Is(list)) if (kinds == null):
				var ts = [];
				for (x in list) switch x.compounds {
					case [[Type(n, _)]] if (x.pseudo == null): ts.push(n.toLowerCase());
					case _:
						ts = null;
						break;
				}
				if (ts != null && ts.length > 0) kinds = ts;
			case _:
		}
		if (id != null) push(ids, quirks ? id.toLowerCase() : id, rule) else if (cls != null) push(classes, quirks ? cls.toLowerCase() : cls,
			rule) else if (type != null) push(types, type, rule) else if (kinds != null) for (k in kinds) push(types, k, rule) else if (isRoot) root.push(rule) else if (attr != null)
		{
			push(attributes, attr, rule);
			attributed = true;
		} else any.push(rule);
	}

	static function push(m:Map<String, Array<Rule>>, k:String, r:Rule) {
		var l = m.get(k);
		if (l == null) m.set(k, l = []);
		l.push(r);
	}

	public function candidates(el:Element, quirks:Bool):Array<Rule> {
		var out = any.copy();
		var id = el.getAttribute("id");
		if (id != null) for (r in ids.get(quirks ? id.toLowerCase() : id) ?? []) out.push(r);
		var cls = el.getAttribute("class");
		if (cls != null) {
			var seen = new Map<String, Bool>();
			for (c in ~/[ \t\n\r\x0C]+/g.split(cls)) {
				if (c == "") continue;
				var k = quirks ? c.toLowerCase() : c;
				if (seen.exists(k)) continue;
				seen.set(k, true);
				for (r in classes.get(k) ?? []) out.push(r);
			}
		}
		for (r in types.get(el.localName.toLowerCase()) ?? []) out.push(r);
		if (attributed) for (a in el.attributes) for (r in attributes.get(a.localName.toLowerCase()) ?? []) out.push(r);
		if (root.length > 0 && el.ownerDocument.documentElement == el) for (r in root) out.push(r);
		return out;
	}
}
