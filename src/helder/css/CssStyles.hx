package helder.css;

import haxe.ds.IntMap;
import haxe.ds.ObjectMap;
import helder.css.CssDisplay;
import helder.css.CssMedia;
import helder.css.CssProperty;
import helder.css.CssResolver;
import helder.css.CssRuleIndex;
import helder.css.CssSelector;
import helder.css.CssSheet;
import helder.css.CssTerm;
import helder.dom.Document;
import helder.dom.Element;
import helder.dom.Node;

using StringTools;

// A document's styles: its sheets' rules in a CssRuleIndex (by their
// rightmost compound, the ancestors' Bloom filter moved to each element
// matched); each element's style the one made before for the same parent
// style and cascade (rules, style attribute, hints, its place: the root,
// a flex or grid item), else worked out (CssResolver) and its groups
// interned. A rule that can never match (:visited's) is left out;
// :hover's and the like match the element's state, off on a page. And the
// at-rules' data for the later stages (@page, @font-face,
// @counter-style).
class CssStyles {
	public final document:Document;
	public final media:CssMediaContext;
	public final pages:Array<CssPageRule> = [];
	public final fontFaces:Array<CssFontFace> = [];
	public final counterStyles:Array<CssCounterStyle> = [];
	@:allow(helder.css) final intern = new CssIntern();

	final hints:Null<Element->Array<CssDeclared>>;
	final index = new CssRuleIndex<Rule>();
	final pseudos = new Map<String, CssRuleIndex<Rule>>();
	final bloom = new CssBloom();
	final cache = new ObjectMap<Element, CssStyle>();
	final pseudoCache = new ObjectMap<Element, Map<String, CssStyle>>();
	final shared = new IntMap<Array<Shared>>();
	final styleTable = new IntMap<Array<CssStyle>>();
	var order = 0;
	var ruleCount = 0;
	// (layer names in order of first appearance, per origin)
	final layers = new Map<String, Int>();
	var root:Null<CssStyle>;
	var initials:Null<Array<CssGroup>>;
	final initialValues = new IntMap<Null<Array<CssTerm>>>();
	final initialComputed = new IntMap<Array<CssTerm>>();
	// (how styles came: a cascade seen before, or worked out; distinct styles)
	public var hits(default, null) = 0;
	public var misses(default, null) = 0;
	public var distinct(default, null) = 0;

	@:allow(helder.css.CssCascade)
	function new(document:Document, sheets:Array<{sheet:CssSheet, media:Null<CssMedia>}>, media:CssMediaContext, hints:Null<Element->Array<CssDeclared>>,
			?hintSheet:CssSheet) {
		this.document = document;
		this.media = media;
		this.hints = hints;
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
			if (s == null) m.set(pseudo, s = style(el, pseudo, computed(el), false));
			return s;
		}
		var s = cache.get(el);
		if (s != null) return s;
		var p = el.parentNode;
		var parent = p != null && p.nodeType == Node.ELEMENT_NODE ? computed(cast p) : null;
		s = style(el, null, parent, document.documentElement == el);
		cache.set(el, s);
		return s;
	}

	// The groups made so far, per group, and the distinct styles.
	public function counts():{groups:Map<String, Int>, styles:Int} {
		var out = new Map<String, Int>();
		for (k in 0...CssGroups.COUNT) out.set(CssProperties.groups[k], intern.counts[k]);
		return {groups: out, styles: distinct};
	}

	// ---- an element's style

	function style(el:Element, pseudo:Null<String>, parent:Null<CssStyle>, isRoot:Bool):CssStyle {
		var idx = pseudo == null ? index : pseudos.get(pseudo);
		var found:Array<CssIndexed<Rule>> = [];
		if (idx != null) {
			bloom.moveTo(el);
			idx.matching(el, found, bloom);
		}
		var matched = [for (m in found) m.value];
		var attribute = pseudo == null ? el.getAttribute("style") : null;
		var hinted = pseudo == null && hints != null ? hints(el) : null;
		var hintKey = hinted == null || hinted.length == 0 ? "" : Std.string([for (d in hinted) [d.property, Std.string(d.value)]]);
		var item = item(pseudo == null ? el.parentNode : el);
		// (the same parent style and cascade: the same style)
		var h = parent == null ? 1 : parent.id;
		h = h * 31 + (pseudo == null ? 0 : pseudo.length);
		h = h * 31 + (isRoot ? 1 : 0) + (item ? 2 : 0);
		for (r in matched) h = h * 31 + r.index;
		if (attribute != null) h = h * 31 + hash(attribute);
		if (hintKey != "") h = h * 31 + hash(hintKey);
		var bucket = shared.get(h);
		if (bucket == null) shared.set(h, bucket = []);
		for (x in bucket)
			if (x.parent == parent && x.pseudo == pseudo && x.root == isRoot && x.item == item && x.attribute == attribute && x.hints == hintKey
				&& same(x.rules, matched)) {
				hits++;
				return x.style;
			}
		misses++;
		var s = resolve(el, pseudo, parent, isRoot, item, matched, attribute, hinted);
		bucket.push({
			parent: parent,
			pseudo: pseudo,
			root: isRoot,
			item: item,
			attribute: attribute,
			hints: hintKey,
			rules: [for (r in matched) r.index],
			style: s
		});
		return s;
	}

	static function same(a:Array<Int>, b:Array<Rule>):Bool {
		if (a.length != b.length) return false;
		for (k in 0...a.length) if (a[k] != b[k].index) return false;
		return true;
	}

	static function hash(s:String):Int {
		var h = 0;
		for (k in 0...s.length) h = h * 31 + StringTools.fastCodeAt(s, k);
		return h;
	}

	// (the box's parent past display: contents is a flex or grid container)
	function item(n:Null<Node>):Bool {
		while (n != null && n.nodeType == Node.ELEMENT_NODE) {
			var d = computed(cast n).box.display;
			if (d.outer != Contents) return d.outer != None && (d.inner == Flex || d.inner == Grid || d.inner == GridLanes);
			n = n.parentNode;
		}
		return false;
	}

	function resolve(el:Element, pseudo:Null<String>, parent:Null<CssStyle>, isRoot:Bool, item:Bool, matched:Array<Rule>, attribute:Null<String>,
			hinted:Null<Array<CssDeclared>>):CssStyle {
		var out:Array<CssCandidate> = [];
		for (rule in matched) {
			var spec = rule.zero ? 0 : rule.selector.specificity.toInt();
			var k = 0;
			for (d in rule.declarations) out.push(candidate(d, rule.origin, false, rule.layer, spec, rule.order * 4096 + k++));
		}
		// (presentational hints: author, specificity zero, before the author's rules)
		if (hinted != null) {
			var k = 0;
			for (d in hinted) out.push(candidate(d, Author, false, UNLAYERED, 0, -1000000 + k++));
		}
		if (attribute != null) {
			var k = 0;
			for (d in CssSheet.attribute(attribute)) out.push(candidate(d, Author, true, UNLAYERED, 0, k++));
		}
		// best first: rank, then attached, layer, specificity, order
		out.sort((a, b) -> {
			if (a.rank != b.rank) return b.rank - a.rank;
			if (a.attached != b.attached) return a.attached ? -1 : 1;
			if (a.layer != b.layer) return b.layer - a.layer;
			if (a.specificity != b.specificity) return b.specificity > a.specificity ? 1 : -1;
			return b.order - a.order;
		});
		var r = new CssResolver(this, parent, pseudo, isRoot, item);
		// (direction first, with the custom properties it may use: the logical
		// properties map by it, Logical 1 §4; what working it out computed
		// before the rest was there, forgotten)
		for (c in out) {
			var id = c.d.id;
			if (id == -1) {
				var l = r.customCandidates.get(c.d.property);
				if (l == null) r.customCandidates.set(c.d.property, l = []);
				l.push(c);
			} else if (id == (Direction : Int)) push(r.cascaded, id, c);
		}
		var rtl = r.keyword(Direction) == "rtl";
		r.forget();
		for (c in out) {
			var id = c.d.id;
			if (id >= 0 && id != (Direction : Int)) push(r.cascaded, CssProperties.physical(cast id, rtl), c);
		}
		var groups = [];
		var base = initialGroups();
		for (g in 0...CssGroups.COUNT) {
			var from = CssGroups.inherited(g) && parent != null ? @:privateAccess parent.group(g) : base[g];
			var members = CssProperties.members[g];
			var touched = extra(g, r, parent, pseudo, isRoot, item);
			if (!touched) for (p in members) if (r.declares(cast p)) {
				touched = true;
				break;
			}
			if (!touched) {
				groups.push(from);
				continue;
			}
			var copy = @:privateAccess from.copy();
			for (i in members) {
				var p:CssProperty = cast i;
				if (r.declares(p) || dependent(p)) @:privateAccess copy.set(p, r.get(p), intern);
			}
			groups.push(intern.group(g, copy));
		}
		return made(groups, r.allCustoms());
	}

	static inline function push(m:IntMap<Array<CssCandidate>>, id:Int, c:CssCandidate) {
		var l = m.get(id);
		if (l == null) m.set(id, l = []);
		l.push(c);
	}

	// (a group whose values depend on more than its declarations: box's
	// display, at the root, in a flex or grid container, beside a float or
	// absolute position; ::before's and ::after's content; justify-items'
	// legacy, the parent's)
	function extra(g:Int, r:CssResolver, parent:Null<CssStyle>, pseudo:Null<String>, isRoot:Bool, item:Bool):Bool {
		if (g == BOX) return isRoot || item || r.declares(Position) && r.positioned();
		if (g == CONTENT) return pseudo == "before" || pseudo == "after";
		if (g == CONTAINER) return parent != null && parent.container.justifyItems.length == 2;
		return false;
	}

	static final BOX = CssProperties.groups.indexOf("box");
	static final CONTENT = CssProperties.groups.indexOf("content");
	static final CONTAINER = CssProperties.groups.indexOf("container");

	// (values another property changes: worked out again whenever their group is)
	static function dependent(p:CssProperty):Bool
		return switch p {
			case BorderTopWidth | BorderRightWidth | BorderBottomWidth | BorderLeftWidth | OutlineWidth | Float | Display | Content | JustifyItems | OverflowX |
				OverflowY: true;
			case _: false;
		}

	// (a style of these groups made before: it, else a new one)
	function made(groups:Array<CssGroup>, customs:Map<String, Null<Array<CssValue>>>):CssStyle {
		var h = 17;
		for (g in groups) h = h * 31 + g.id;
		var bucket = styleTable.get(h);
		if (bucket == null) styleTable.set(h, bucket = []);
		for (s in bucket) {
			if (s.customs != customs) continue;
			var ok = true;
			for (k in 0...groups.length) if (@:privateAccess s.group(k) != groups[k]) {
				ok = false;
				break;
			}
			if (ok) return s;
		}
		var s = new CssStyle(this, groups, customs);
		s.id = distinct++;
		bucket.push(s);
		return s;
	}

	// (every group's initial values, as an element with nothing declared has them)
	function initialGroups():Array<CssGroup> {
		if (initials != null) return initials;
		var r = new CssResolver(this, null, null, false, false);
		var out = [];
		for (g in 0...CssGroups.COUNT) {
			var group = CssGroups.make(g);
			for (i in CssProperties.members[g]) {
				var p:CssProperty = cast i;
				@:privateAccess group.set(p, r.get(p), intern);
			}
			out.push(intern.group(g, group));
		}
		return initials = out;
	}

	// The property's initial value, as specified.
	@:allow(helder.css)
	function initialTerms(p:CssProperty):Null<Array<CssTerm>> {
		if (initialValues.exists(p)) return initialValues.get(p);
		var t = CssShorthands.initialTerms(CssProperties.name(p));
		initialValues.set(p, t);
		return t;
	}

	// (a shorthand's longhand's initial value, written as the style writes
	// its values: what serializing the shorthand leaves out)
	@:allow(helder.css)
	function initialText(longhand:String, style:CssStyle):String {
		var p = CssProperties.of(longhand);
		if (p == null) return "";
		var t = initialComputed.get(p);
		if (t == null) {
			var r = new CssResolver(this, null, null, false, false);
			initialComputed.set(p, t = @:privateAccess r.initial(p));
		}
		return CssValues.written(longhand, t, style.context());
	}

	// (rem's and rlh's: the root element's font size and line height)
	@:allow(helder.css)
	function rootFontSize():Float {
		var r = rootStyle();
		return r == null ? 16 : r.fontSize();
	}

	@:allow(helder.css)
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
					var rule = {
						selector: s,
						declarations: declarations,
						origin: origin,
						layer: l,
						order: o,
						zero: zero,
						index: ruleCount++
					};
					switch s.pseudo {
						case _ if (never(s)):
						case null: index.add(s, rule);
						case p:
							var name = pseudoName(p);
							if (name == null) continue;
							var i = pseudos.get(name);
							if (i == null) pseudos.set(name, i = new CssRuleIndex());
							i.add(s, rule);
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

	// (a compound with :visited and the like: never)
	static function never(s:CssSelector):Bool {
		for (c in s.compounds)
			for (x in c)
				if (x.match(Pseudo(Never(_)))) return true;
		return false;
	}

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

private typedef Rule = {selector:CssSelector, declarations:Array<CssDeclared>, origin:CssOrigin, layer:Int, order:Int, zero:Bool, index:Int}

private typedef Shared = {
	parent:Null<CssStyle>,
	pseudo:Null<String>,
	root:Bool,
	item:Bool,
	attribute:Null<String>,
	hints:String,
	rules:Array<Int>,
	style:CssStyle
}
