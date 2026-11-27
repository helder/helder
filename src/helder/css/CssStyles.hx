package helder.css;

import haxe.ds.IntMap;
import haxe.ds.ObjectMap;
import helder.css.CssCalc.CssCalcNode;
import helder.css.CssDisplay;
import helder.css.CssFontMetrics;
import helder.css.CssMedia;
import helder.css.CssPages;
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

// A document's styles: each element's first a recent sibling's or
// cousin's, before matching (the style-sharing cache, below); else its
// sheets' rules matched through a CssRuleIndex (by their rightmost
// compound, the ancestors' Bloom filter moved to each element matched)
// and the style made before for the same parent style and cascade (rules,
// style attribute, hints, its place: the root, a flex or grid item) taken,
// else worked out (CssResolver) and its groups interned. A rule that can never match (:visited's) is left out;
// :hover's and the like match the element's state, off on a page. And the
// at-rules' data for the later stages (@page, @font-face,
// @counter-style).
class CssStyles {
	public final document:Document;
	public var media(default, null):CssMediaContext;
	var viewportSize:Null<{width:Float, height:Float}> = null;
	// (the cascade's own viewport: not the media's size)
	var fixedViewport = false;
	// (the elements a declaration with a viewport unit styled: what another size styles again)
	final viewported = new ObjectMap<Element, Bool>();

	// What viewport units resolve against: the cascade's `viewport`, else
	// on print the first page's area (its @page size less its margins),
	// else the media's size.
	public function viewport():{width:Float, height:Float} {
		if (viewportSize != null) return viewportSize;
		viewportSize = {width: media.width, height: media.height};
		if (media.type != "print" || printArea == null) return viewportSize;
		// (the first page, index 0, :first's; its style inherits the root's, worked out meanwhile at the media's size)
		return viewportSize = printArea(this);
	}

	// (a printed viewport's: the first page's area, CssPages'; installed by
	// CssCascade.styles, so that an app's themed cascade links no @page
	// cascade; without it, the media's size)
	@:allow(helder.css) static var printArea:Null<CssStyles->{width:Float, height:Float}> = null;
	public final pages:Array<CssPageRule> = [];
	public final fontFaces:Array<CssFontFace> = [];
	public final counterStyles:Array<CssCounterStyle> = [];
	public final fontPaletteValues:Array<CssFontPaletteValues> = [];
	// the first available font's metrics for a style (ex, ch, cap, ic, line-height: normal):
	// what an engine with fonts installs; null, they stay as written
	public var metrics:Null<CssFontQuery->CssFontMetrics> = null;

	// (the metrics of a font's computed values: an element's, a resolver's on the way)
	@:allow(helder.css)
	function fontMetrics(get:CssProperty->Array<CssTerm>, size:Float):Null<CssFontMetrics> {
		var m = metrics;
		return m == null ? null : m({
			family: get(FontFamily),
			size: size,
			weight: get(FontWeight),
			style: get(FontStyle),
			stretch: get(FontWidth),
			variations: get(FontVariationSettings),
			opticalSizing: get(FontOpticalSizing)
		});
	}
	@:allow(helder.css) final intern = new CssIntern();

	final hints:Null<Element->Array<CssDeclared>>;
	// (a style attribute's declarations; null: style attributes not read, no parser linked)
	final declarations:Null<String->Array<CssDeclared>>;
	var index = new CssRuleIndex<Rule>();
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
	// (the style-sharing cache: recent elements whose style a sibling or
	// cousin may take before matching, most recent first; each element that
	// took one's equivalent, for its children's cousins; the attributes a
	// local selector reads)
	final candidates:Array<Candidate> = [];
	final twins = new ObjectMap<Element, Element>();
	// (true: a selector reads its value; false: its presence alone)
	final watched = new Map<String, Bool>();
	// (the ids some selector names: an element with another id may share)
	final ids = new Map<String, Bool>();
	// (every selector of the rules added, pseudo-elements' too: what a
	// restyle tracker's invalidation sets are made of; the media queries the
	// cascade read, and whether any declaration has a viewport unit: what
	// another viewport size changes)
	final ruleSelectors:Array<CssSelector> = [];
	final queries:Array<CssMedia> = [];
	var viewportUnits = false;
	public static inline var CANDIDATES = 32;
	// (a candidate with more selectors to match again is not kept: cheaper to match)
	static inline var REVALIDATE = 16;
	static final NO_SELECTORS:Array<CssSelector> = [];
	static final NO_RESULTS:Array<Bool> = [];
	var sharing = true;
	// (how styles came: shared from a sibling or cousin before matching, a
	// cascade seen before, or worked out; distinct styles)
	public var shares(default, null) = 0;
	public var hits(default, null) = 0;
	public var misses(default, null) = 0;
	public var distinct(default, null) = 0;

	@:allow(helder.css.CssCascade)
	function new(document:Document, sheets:Array<{sheet:CssSheet, media:Null<CssMedia>}>, media:CssMediaContext, declarations:Null<String->Array<CssDeclared>>,
			hints:Null<Element->Array<CssDeclared>>, ?hintSheet:CssSheet) {
		this.document = document;
		this.media = media;
		this.declarations = declarations;
		this.hints = hints;
		this.sheets = sheets;
		this.hintSheet = hintSheet;
		indexRules();
	}

	final sheets:Array<{sheet:CssSheet, media:Null<CssMedia>}>;
	final hintSheet:Null<CssSheet>;

	// (the rules in effect in the media, indexed)
	function indexRules() {
		// (HTML's hints written as CSS: author rules of specificity zero before the author's own)
		if (hintSheet != null) {
			var start = order;
			order = -1000000;
			add(hintSheet.rules, Author, null, true);
			order = start;
		}
		// (layers' order first, over every sheet, then the rules)
		for (s in sheets) if (s.media != null) queries.push(s.media);
		for (s in sheets) if (s.media == null || s.media.matches(media)) declareLayers(s.sheet.rules, s.sheet.origin);
		for (s in sheets) if (s.media == null || s.media.matches(media)) add(s.sheet.rules, s.sheet.origin, null);
	}

	// Whether a rule for the pseudo-element ("first-letter", "first-line",
	// "before", "after", "marker"...) matches the element. The sheets'
	// rules are indexed by pseudo-element as they are added, so a name no
	// sheet uses is false without matching anything.
	public function hasPseudo(el:Element, name:String):Bool {
		var idx = pseudos.get(name);
		if (idx == null) return false;
		var found:Array<CssIndexed<Rule>> = [];
		bloom.moveTo(el);
		idx.matching(el, found, bloom, null, hasCache);
		return found.length > 0;
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

	// The element's style if it was worked out and not forgotten since; null: not asked for.
	public function cached(el:Element):Null<CssStyle>
		return cache.get(el);

	// A page's computed style (Paged Media 3 §5): the @page rules that match
	// it (its index for :first, its page type's name, its side, whether
	// it's blank), by their specificity, inheriting from the root element's;
	// with its size, bleed, marks and orientation.
	public function pageStyle(index:Int, name:Null<String>, left:Bool, blank:Bool):CssPage
		return (paged ??= new CssPages(this)).page(index, name, left, blank);

	// One of a page's 16 margin boxes' style ("top-left", ..., "bottom-right-corner"),
	// inheriting from the page's; null for a name that isn't one.
	public function marginBoxStyle(index:Int, name:Null<String>, left:Bool, blank:Bool, box:String):Null<CssStyle>
		return (paged ??= new CssPages(this)).margin(index, name, left, blank, box);

	var paged:Null<CssPages>;

	// The styles of elements a change made stale (CssRestyle's marked) let
	// go, made again when next asked. The sharing cache's candidates and
	// twins go too: what made two elements equivalent may have changed.
	public function forget(elements:Iterable<Element>) {
		for (el in elements) {
			cache.remove(el);
			pseudoCache.remove(el);
		}
		candidates.resize(0);
		twins.clear();
		bloom.reset();
		hasCache.clear();
	}

	// An element's style let go, made again when next asked, the sharing
	// cache kept: within a restyle that forget began (the document as it
	// was then), what it is styled again with.
	public function drop(el:Element) {
		cache.remove(el);
		pseudoCache.remove(el);
	}

	// Every selector of the rules in effect (pseudo-elements' too), for a
	// restyle tracker's invalidation sets (CssInvalidation.of).
	public function selectors():Array<CssSelector>
		return ruleSelectors;

	// Whether these styles hold in another media context (a window
	// resized): every media query the cascade read matches it as it
	// matched this one's, and, at another size, no declaration has a
	// viewport unit.
	public function holds(other:CssMediaContext):Bool {
		if (other.type != media.type || other.resolution != media.resolution || other.color != media.color) return false;
		if (viewportUnits && (other.width != media.width || other.height != media.height)) return false;
		for (q in queries) if (q.matches(other) != q.matches(media)) return false;
		return true;
	}

	// These styles made good for another size (a window resized): the
	// elements whose styles may change there, to work out again (forget,
	// then computed; what inherits from them is the caller's), those whose
	// cascade has a viewport unit and, where a sheet's media query matches
	// it as it didn't this one (or the other way; a sheet's own too), those
	// a rule inside it matches, the rules indexed again for it. Null where
	// it can't be: another media type, the root's font size or line height
	// changed (rem everywhere): a cascade of its own then.
	public function resize(other:CssMediaContext, ?skip:Element->Bool):Null<Array<Element>> {
		if (other.type != media.type || other.resolution != media.resolution || other.color != media.color || media.type == "print") return null;
		// (the rules inside the queries that change: what they match is styled again)
		var changed = new CssRuleIndex<Bool>(), n = 0;
		function within(rules:Array<CssSheetRule>, flips:Bool)
			for (r in rules) switch r {
				case Style(selectors, _) if (flips):
					for (sel in selectors) if (!never(sel)) {
						changed.add(sel, true);
						n++;
					}
				case Media(m, inner): within(inner, flips || m.matches(other) != m.matches(media));
				case Layer(_, inner) if (inner != null): within(inner, flips);
				case Import(sheet, m, _, _): within(sheet.rules, flips || m.matches(other) != m.matches(media));
				case _:
			}
		if (hintSheet != null) within(hintSheet.rules, false);
		for (s in sheets) within(s.sheet.rules, s.media != null && s.media.matches(other) != s.media.matches(media));
		var out = new ObjectMap<Element, Bool>();
		if (n > 0) changed.walk(document, (el, found) -> if (found.length > 0) out.set(el, true), null, skip);
		var r = document.documentElement, was = r == null ? null : cache.get(r);
		media = other;
		if (!fixedViewport) viewportSize = null;
		if (n > 0) reindex();
		// (the root styled again: its font size and line height what rem and rlh read everywhere, the same or a
		// cascade of its own)
		if (r != null && was != null && (viewported.exists(r) || out.exists(r))) {
			forget([r]);
			root = null;
			var now = computed(r);
			if (now.fontSize() != was.fontSize() || now.lineHeight() != was.lineHeight()) return null;
			cache.set(r, was);
			out.set(r, true);
		}
		// (the cascades seen at the old size whose viewport units resolved against it)
		for (k => bucket in shared) {
			var kept = [for (x in bucket) if (!x.viewport) x];
			if (kept.length != bucket.length) shared.set(k, kept);
		}
		for (el in viewported.keys()) out.set(el, true);
		var list = [for (el in out.keys()) if (cache.exists(el)) el];
		for (el in list) viewported.remove(el);
		return list;
	}

	// (the rules indexed again for the media: the styles worked out so far kept, those of the elements the
	// changed rules match let go by the caller)
	function reindex() {
		index = new CssRuleIndex<Rule>();
		pseudos.clear();
		order = 0;
		ruleCount = 0;
		layers.clear();
		ruleSelectors.resize(0);
		queries.resize(0);
		viewportUnits = false;
		watched.clear();
		ids.clear();
		pages.resize(0);
		fontFaces.resize(0);
		counterStyles.resize(0);
		fontPaletteValues.resize(0);
		paged = null;
		indexRules();
	}

	// The groups made so far, per group, and the distinct styles.
	public function counts():{groups:Map<String, Int>, styles:Int} {
		var out = new Map<String, Int>();
		for (k in 0...CssGroups.COUNT) out.set(CssProperties.groups[k], intern.counts[k]);
		return {groups: out, styles: distinct};
	}

	// ---- an element's style

	function style(el:Element, pseudo:Null<String>, parent:Null<CssStyle>, isRoot:Bool):CssStyle {
		var attribute = pseudo == null && declarations != null ? el.getAttribute("style") : null;
		var hinted = pseudo == null && hints != null ? hints(el) : null;
		var lists = pseudo == null ? CssHints.lists(el) : null;
		if (lists != null) hinted = hinted == null ? lists : hinted.concat(lists);
		var hintKey = hinted == null || hinted.length == 0 ? "" : Std.string([for (d in hinted) [d.property, Std.string(d.value)]]);
		// (a sibling's or cousin's style, before matching)
		var sig = sharing && pseudo == null && !isRoot ? signature(el) : null;
		if (sig != null) {
			var c = share(el, parent, attribute, hintKey, sig);
			if (c != null) {
				shares++;
				if (c.viewport) viewported.set(el, true);
				// (a twin is for its children's cousins: a leaf needs none; one given children later shares less, never wrongly)
				if (el.firstElementChild != null) twins.set(el, twins.get(c.el) ?? c.el);
				return c.style;
			}
		}
		var idx = pseudo == null ? index : pseudos.get(pseudo);
		var found:Array<CssIndexed<Rule>> = [];
		if (idx != null) {
			bloom.moveTo(el);
			idx.matching(el, found, bloom, null, hasCache);
		}
		// (what a sharer must match alike: the selectors that are not local this element tried, and their results)
		var reval = idx == null || idx.revalidate.length == 0 ? NO_SELECTORS : idx.revalidate.copy();
		var results = idx == null || idx.revalidated.length == 0 ? NO_RESULTS : idx.revalidated.copy();
		var local = reval.length <= REVALIDATE;
		var matched = [for (m in found) m.value];
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
				if (x.viewport) viewported.set(el, true);
				if (sig != null && local) remember(el, parent, attribute, hintKey, sig, x.style, reval, results, x.viewport);
				return x.style;
			}
		misses++;
		var s = resolve(el, pseudo, parent, isRoot, item, matched, attribute, hinted);
		var viewport = attribute != null && viewportText(attribute);
		for (r in matched) if (r.viewport) viewport = true;
		if (hinted != null) for (d in hinted) if (viewportRelative(d)) viewport = true;
		if (viewport) viewported.set(el, true);
		if (sig != null && local) remember(el, parent, attribute, hintKey, sig, s, reval, results, viewport);
		bucket.push({
			viewport: viewport,
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

	// (the style-sharing cache, as Stylo's and WebKit's: an element takes a
	// recent element's style when its parent is that element's parent or
	// that parent's equivalent (a twin: an element that took its style from
	// the cache, the same way, so their ancestors match alike), and its tag,
	// namespace, classes, style attribute, hints, state and the attributes
	// local selectors read are the same, it has no id a selector names, and
	// the selectors that are not local (CssSelector.local) the recent element
	// tried match it alike (Stylo's revalidation): every rule then matches
	// both alike)
	function share(el:Element, parent:Null<CssStyle>, attribute:Null<String>, hintKey:String, sig:String):Null<Candidate> {
		var p = el.parentElement, cls = el.getAttributeNS(null, "class"), state = el.state;
		var rp = p == null ? null : twins.get(p) ?? p;
		memo.resize(0);
		memoed.resize(0);
		for (k in 0...candidates.length) {
			var c = candidates[k];
			if (c.parent != parent || c.tag != el.localName || c.ns != el.namespaceURI || c.cls != cls || c.attribute != attribute || c.state != state
				|| c.sig != sig || c.hints != hintKey) continue;
			var cp = c.el.parentElement;
			if (cp != p && (cp == null ? null : twins.get(cp) ?? cp) != rp) continue;
			if (!revalidates(c, el)) continue;
			if (k > 0) {
				candidates.splice(k, 1);
				candidates.unshift(c);
			}
			return c;
		}
		return null;
	}

	// (the candidate's selectors that are not local match el as they matched
	// it; each matched once on el however many candidates ask, those with
	// :has() last, the costliest)
	function revalidates(c:Candidate, el:Element):Bool {
		for (pass in 0...2)
			for (k in 0...c.reval.length) {
				var sel = c.reval[k];
				if ((pass == 1) != heavy(sel)) continue;
				var i = memo.indexOf(sel), yes;
				if (i >= 0) yes = memoed[i] else {
					yes = CssMatcher.matches(sel, el, null, hasCache);
					memo.push(sel);
					memoed.push(yes);
				}
				if (yes != c.results[k]) return false;
			}
		return true;
	}

	final memo:Array<CssSelector> = [];
	final hasCache = new CssMatcher.CssHasCache();
	final memoed:Array<Bool> = [];

	// (whether a selector has :has(), anywhere)
	static function heavy(s:CssSelector):Bool {
		for (c in s.compounds)
			for (x in c)
				switch x {
					case Pseudo(Has(_)): return true;
					case Pseudo(Is(l) | Where(l) | Not(l)): for (i in l) if (heavy(i)) return true;
					case Pseudo(NthChild(_, l) | NthLastChild(_, l)) if (l != null): for (i in l) if (heavy(i)) return true;
					default:
				}
		return false;
	}

	function remember(el:Element, parent:Null<CssStyle>, attribute:Null<String>, hintKey:String, sig:String, style:CssStyle, reval:Array<CssSelector>,
			results:Array<Bool>, viewport:Bool) {
		candidates.unshift({
			viewport: viewport,
			reval: reval,
			results: results,
			el: el,
			parent: parent,
			tag: el.localName,
			ns: el.namespaceURI,
			cls: el.getAttributeNS(null, "class"),
			attribute: attribute,
			state: el.state,
			sig: sig,
			hints: hintKey,
			style: style
		});
		if (candidates.length > CANDIDATES) candidates.pop();
	}

	// (the attributes local selectors read, as one string: their values, or
	// their presence where no selector reads a value; null: no sharing, an id
	// some selector names, as WebKit's)
	function signature(el:Element):Null<String> {
		var id = el.getAttributeNS(null, "id");
		if (id != null && ids.exists(Css.lower(id))) return null;
		if (!el.hasAttributes()) return "";
		var b:Null<StringBuf> = null;
		for (n in el.getAttributeNames()) {
			var k = Css.lower(n), value = watched.get(k);
			if (value == null) continue;
			if (b == null) b = new StringBuf();
			b.add(k);
			if (value) {
				b.add("=");
				b.add(el.getAttribute(n));
			}
			b.add("\x00");
		}
		return b == null ? "" : b.toString();
	}

	// (the attributes a selector reads, into watched; the ids it names, into ids)
	function watch(s:CssSelector)
		for (c in s.compounds)
			for (x in c)
				switch x {
					case Id(n): ids.set(Css.lower(n), true);
					case Attribute(n, _, Exists, _, _): mark(n, false);
					case Attribute(n, _, _, _, _): mark(n, true);
					case Pseudo(Is(l) | Where(l) | Not(l) | Has(l)): for (i in l) watch(i);
					case Pseudo(NthChild(_, l) | NthLastChild(_, l)) if (l != null): for (i in l) watch(i);
					case Pseudo(Link | AnyLink): mark("href", false);
					case Pseudo(Lang(_)):
						mark("lang", true);
						mark("xml:lang", true);
					case Pseudo(Dir(_)): mark("dir", true);
					case Pseudo(Default):
						for (n in ["selected", "checked"]) mark(n, false);
						mark("type", true);
					case Pseudo(Required | Optional): mark("required", false);
					case Pseudo(Indeterminate): mark("value", false);
					default:
				}

	// (an attribute read, by its value or its presence: its value wins)
	function mark(name:String, value:Bool) {
		var k = Css.lower(name);
		if (value || !watched.exists(k)) watched.set(k, value || watched.get(k) == true);
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
			for (d in declarations(attribute)) out.push(candidate(d, Author, true, UNLAYERED, 0, k++));
		}
		return cascaded(out, parent, pseudo, isRoot, item);
	}

	// (a style of these candidates: sorted, mapped, worked out, its groups interned)
	@:allow(helder.css)
	function cascaded(out:Array<CssCandidate>, parent:Null<CssStyle>, pseudo:Null<String>, isRoot:Bool, item:Bool):CssStyle {
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
			if (g == BOX && r.unblockified != null) @:privateAccess (cast copy : CssGroups.CssBoxGroup).display = intern.display(r.get(Display), r.unblockified);
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
		if (g == CONTENT) return pseudo == "before" || pseudo == "after" || pseudo != null && pseudo.charAt(0) == "@" && pseudo != "@page";
		if (g == CONTAINER) return parent != null && parent.container.justifyItems.length == 2;
		return false;
	}

	static final BOX = CssProperties.groups.indexOf("box");
	static final CONTENT = CssProperties.groups.indexOf("content");
	static final CONTAINER = CssProperties.groups.indexOf("container");

	// (values another property changes: worked out again whenever their group is)
	static function dependent(p:CssProperty):Bool
		return switch p {
			case Float | Display | Content | JustifyItems | OverflowX |
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

	@:allow(helder.css)
	function rootMetrics():Null<CssFontMetrics> {
		var r = rootStyle();
		return r == null ? null : r.fontMetrics();
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
				var o = order++, viewport = false;
				for (d in declarations) if (viewportRelative(d)) viewport = true;
				if (viewport) viewportUnits = true;
				var l = layer == null ? UNLAYERED : layers.get(key(origin, layer));
				for (s in selectors) {
					var rule = {
						selector: s,
						declarations: declarations,
						origin: origin,
						layer: l,
						order: o,
						zero: zero,
						index: ruleCount++,
						viewport: viewport
					};
					ruleSelectors.push(s);
					switch s.pseudo {
						case _ if (never(s)):
						case null:
							index.add(s, rule);
							watch(s);
						case p:
							var name = pseudoName(p);
							if (name == null) continue;
							var i = pseudos.get(name);
							if (i == null) pseudos.set(name, i = new CssRuleIndex());
							i.add(s, rule);
					}
				}
			case Media(m, inner):
				queries.push(m);
				if (m.matches(media)) add(inner, origin, layer, zero) else skip(inner);
			case Layer(name, inner): if (inner != null) add(inner, origin, name, zero);
			case Import(sheet, m, l, _):
				queries.push(m);
				if (m.matches(media)) add(sheet.rules, origin, l ?? layer, zero) else skip(sheet.rules);
			case Page(p):
				p.order = order++;
				pages.push(p);
			case FontFace(f): fontFaces.push(f);
			case CounterStyle(c): counterStyles.push(c);
			case FontPaletteValues(p): fontPaletteValues.push(p);
		}
	}

	// (rules a query leaves out numbered as if they were in: the others' numbers the same at any size, the
	// cascades seen by them still good after resize)
	function skip(rules:Array<CssSheetRule>)
		for (r in rules) switch r {
			case Style(selectors, _):
				order++;
				ruleCount += selectors.length;
			case Media(_, inner): skip(inner);
			case Layer(_, inner) if (inner != null): skip(inner);
			case Import(sheet, _, _, _): skip(sheet.rules);
			case Page(_): order++;
			case _:
		}

	static inline var UNLAYERED = 1 << 20;

	// (a declaration with vw, vh, vi, vb, vmin or vmax, of any viewport: s, l, d)
	static function viewportRelative(d:CssDeclared):Bool {
		if (d.values != null && viewportValues(d.values)) return true;
		return switch d.value {
			case Terms(t): viewportTerms(t);
			case _: false;
		}
	}

	// (a style attribute's text that may have a viewport unit: told apart from vw's own letters loosely, more not less)
	static function viewportText(text:String):Bool {
		var t = text.toLowerCase();
		return t.indexOf("vw") >= 0 || t.indexOf("vh") >= 0 || t.indexOf("vi") >= 0 || t.indexOf("vb") >= 0 || t.indexOf("vmin") >= 0
			|| t.indexOf("vmax") >= 0;
	}

	static function viewportUnit(unit:String):Bool {
		var u = unit.toLowerCase();
		if (u.length > 2 && (u.charAt(0) == "s" || u.charAt(0) == "l" || u.charAt(0) == "d")) u = u.substr(1);
		return u == "vw" || u == "vh" || u == "vi" || u == "vb" || u == "vmin" || u == "vmax";
	}

	static function viewportTerms(terms:Array<CssTerm>):Bool {
		for (t in terms) switch t {
			case Dimension(_, unit): if (viewportUnit(unit)) return true;
			case Calc(c, _, _): if (viewportCalc(c)) return true;
			case Func(_, args) | Brackets(_, args) | Part(_, args): if (viewportTerms(args)) return true;
			case _:
		}
		return false;
	}

	static function viewportCalc(c:CssCalcNode):Bool
		return switch c {
			case Value(_, unit): viewportUnit(unit);
			case Sum(items) | Product(items) | Fn(_, items): Lambda.exists(items, viewportCalc);
			case Negate(item) | Invert(item): viewportCalc(item);
			case Word(_): false;
		}

	static function viewportValues(values:Array<CssValue>):Bool {
		for (v in values) switch v {
			case Token(t): switch t.kind {
					case Dimension(_, _, _, unit): if (viewportUnit(unit)) return true;
					case _:
				}
			case Function(_, inner, _, _) | Block(_, inner, _): if (viewportValues(inner)) return true;
			case _:
		}
		return false;
	}

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

	@:allow(helder.css)
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

private typedef Candidate = {
	viewport:Bool,
	el:Element,
	reval:Array<CssSelector>,
	results:Array<Bool>,
	parent:Null<CssStyle>,
	tag:String,
	ns:Null<String>,
	cls:Null<String>,
	attribute:Null<String>,
	state:Int,
	sig:String,
	hints:String,
	style:CssStyle
}

private typedef Rule = {selector:CssSelector, declarations:Array<CssDeclared>, origin:CssOrigin, layer:Int, order:Int, zero:Bool, index:Int, viewport:Bool}

private typedef Shared = {
	viewport:Bool,
	parent:Null<CssStyle>,
	pseudo:Null<String>,
	root:Bool,
	item:Bool,
	attribute:Null<String>,
	hints:String,
	rules:Array<Int>,
	style:CssStyle
}
