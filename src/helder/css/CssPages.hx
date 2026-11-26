package helder.css;

import helder.css.CssResolver;
import helder.css.CssSheet;

// A page's style and its descriptors (Paged Media 3 §5, §7): the page
// context's computed style (its margins, counters, fonts...), the page
// box's size in px (auto: A4), bleed in px, marks, orientation.
class CssPage {
	public final style:CssStyle;
	public final width:Float;
	public final height:Float;
	public final bleed:Float;
	public final crop:Bool;
	public final cross:Bool;
	// upright, rotate-left, rotate-right
	public final orientation:String;

	@:allow(helder.css)
	function new(style:CssStyle, width:Float, height:Float, bleed:Float, crop:Bool, cross:Bool, orientation:String) {
		this.style = style;
		this.width = width;
		this.height = height;
		this.bleed = bleed;
		this.crop = crop;
		this.cross = cross;
		this.orientation = orientation;
	}
}

// The @page cascade (Paged Media 3 §4.4, §5): a page matches the rules
// whose selectors its context does, ranked by origin and importance, then
// specificity (page type, then :first and :blank, then :left and :right),
// then order; the page context inherits from the root element, a margin
// box from its page, with Paged Media 3 §6.2's alignments beneath its own
// rules. Pages alike (first or not, type, side, blank) share their style.
@:allow(helder.css)
class CssPages {
	final styles:CssStyles;
	final pages = new Map<String, CssPage>();
	final margins = new Map<String, CssStyle>();

	public function new(styles:CssStyles)
		this.styles = styles;

	public function page(index:Int, name:Null<String>, left:Bool, blank:Bool):CssPage {
		var key = '${index == 0} $name $left $blank';
		var p = pages.get(key);
		if (p != null) return p;
		var matched = matching(index, name, left, blank);
		var out = [];
		for (m in matched) {
			var k = 0;
			for (d in m.rule.declarations) out.push(CssStyles.candidate(d, m.rule.origin, false, UNLAYERED, m.specificity, m.rule.order * 4096 + k++));
		}
		var style = styles.cascaded(out, root(), "@page", false, false);
		p = descriptors(style, matched);
		pages.set(key, p);
		return p;
	}

	public function margin(index:Int, name:Null<String>, left:Bool, blank:Bool, box:String):Null<CssStyle> {
		var align = ALIGN.get(box);
		if (align == null) return null;
		var key = '${index == 0} $name $left $blank $box';
		var s = margins.get(key);
		if (s != null) return s;
		var out = [], k = 0;
		for (d in CssSheet.attribute('text-align: ${align[0]}; vertical-align: ${align[1]}')) out.push(CssStyles.candidate(d, UserAgent, false, UNLAYERED, 0, -1000000 + k++));
		for (m in matching(index, name, left, blank)) {
			var own = m.rule.margins.get(box);
			if (own == null) continue;
			k = 0;
			for (d in own) out.push(CssStyles.candidate(d, m.rule.origin, false, UNLAYERED, m.specificity, m.rule.order * 4096 + k++));
		}
		s = styles.cascaded(out, page(index, name, left, blank).style, "@" + box, false, false);
		margins.set(key, s);
		return s;
	}

	static inline var UNLAYERED = 1 << 20;

	function root():Null<CssStyle> {
		var r = styles.document.documentElement;
		return r == null ? null : styles.computed(r);
	}

	// (the rules a selector of which matches, with that selector's specificity, the best)
	function matching(index:Int, name:Null<String>, left:Bool, blank:Bool):Array<{rule:CssPageRule, specificity:Int}> {
		var out = [];
		for (rule in styles.pages) {
			var best = -1;
			if (rule.selectors.length == 0) best = 0;
			for (s in rule.selectors) {
				var ok = s.name == null || s.name == name;
				var f = s.name == null ? 0 : 1, g = 0, h = 0;
				for (p in s.pseudos) switch p {
					case "first":
						g++;
						if (index != 0) ok = false;
					case "blank":
						g++;
						if (!blank) ok = false;
					case "left":
						h++;
						if (!left) ok = false;
					case "right":
						h++;
						if (left) ok = false;
					case _: ok = false;
				}
				var spec = (f << 20) | (Std.int(Math.min(g, 1023)) << 10) | Std.int(Math.min(h, 1023));
				if (ok && spec > best) best = spec;
			}
			if (best >= 0) out.push({rule: rule, specificity: best});
		}
		return out;
	}

	// (size, bleed, marks and page-orientation: each the best declaration of a valid value)
	function descriptors(style:CssStyle, matched:Array<{rule:CssPageRule, specificity:Int}>):CssPage {
		var found = new Map<String, {value:Array<CssValue>, rank:Int, specificity:Int, order:Int}>();
		for (m in matched) {
			var o = switch m.rule.origin {
				case UserAgent: 0;
				case User: 1;
				case Author: 2;
			}
			var k = 0;
			for (d in m.rule.descriptors) {
				var n = Css.lower(d.name);
				var v = [for (x in d.value) if (!x.match(Token(_.kind => Whitespace))) x];
				var ok = switch n {
					case "size": size(v, style) != null;
					case "bleed": bleed(v, style) != null || keyword(v) == "auto";
					case "marks": marks(v) != null;
					case "page-orientation": ["upright", "rotate-left", "rotate-right"].contains(keyword(v));
					case _: false;
				}
				var order = m.rule.order * 4096 + k++;
				if (!ok) continue;
				var rank = d.important ? 5 - o : o;
				var was = found.get(n);
				if (was == null || rank > was.rank || rank == was.rank && (m.specificity > was.specificity || m.specificity == was.specificity && order > was.order))
					found.set(n, {value: v, rank: rank, specificity: m.specificity, order: order});
			}
		}
		var dims = found.exists("size") ? size(found["size"].value, style) : null;
		if (dims == null) dims = SIZES["a4"];
		var m = found.exists("marks") ? marks(found["marks"].value) : null;
		var crop = m != null && m.crop, cross = m != null && m.cross;
		// (bleed: auto is 6pt with crop marks, else 0)
		var b = found.exists("bleed") ? bleed(found["bleed"].value, style) : null;
		var orientation = found.exists("page-orientation") ? keyword(found["page-orientation"].value) : "upright";
		return new CssPage(style, dims[0], dims[1], b ?? (crop ? 8 : 0), crop, cross, orientation);
	}

	// (<length [0,∞]>{1,2} | auto | [ <page-size> || [ portrait | landscape ] ])
	static function size(v:Array<CssValue>, style:CssStyle):Null<Array<Float>> {
		if (v.length == 1 && keyword(v) == "auto") return SIZES["a4"];
		var lengths = [for (x in v) length(x, style)];
		if (v.length >= 1 && v.length <= 2 && !lengths.contains(null)) {
			for (l in lengths) if (l < 0) return null;
			return [lengths[0], lengths[lengths.length - 1]];
		}
		var page:Null<Array<Float>> = null, orientation:Null<String> = null;
		for (x in v) switch x {
			case Token(_.kind => Ident(w)):
				var k = Css.lower(w);
				if (SIZES.exists(k) && page == null) page = SIZES[k] else if ((k == "portrait" || k == "landscape") && orientation == null) orientation = k else return null;
			case _: return null;
		}
		if (page == null && orientation == null) return null;
		var d = page ?? SIZES["a4"];
		var w = Math.min(d[0], d[1]), h = Math.max(d[0], d[1]);
		return orientation == "landscape" ? [h, w] : orientation == "portrait" ? [w, h] : d;
	}

	static function bleed(v:Array<CssValue>, style:CssStyle):Null<Float>
		return v.length == 1 ? length(v[0], style) : null;

	static function marks(v:Array<CssValue>):Null<{crop:Bool, cross:Bool}> {
		if (v.length == 1 && keyword(v) == "none") return {crop: false, cross: false};
		var crop = false, cross = false;
		for (x in v) switch x {
			case Token(_.kind => Ident(w)) if (Css.lower(w) == "crop" && !crop): crop = true;
			case Token(_.kind => Ident(w)) if (Css.lower(w) == "cross" && !cross): cross = true;
			case _: return null;
		}
		return crop || cross ? {crop: crop, cross: cross} : null;
	}

	static function keyword(v:Array<CssValue>):Null<String>
		return v.length == 1 ? switch v[0] {
			case Token(_.kind => Ident(w)): Css.lower(w);
			case _: null;
		} : null;

	// (a length in px: absolute units, em and rem against the page's font size)
	static function length(v:CssValue, style:CssStyle):Null<Float>
		return switch v {
			case Token(_.kind => Dimension(n, _, _, unit)):
				var c = CssCalc.canonical(n, Css.lower(unit), {fontSize: style.fontSize(), rootFontSize: style.fontSize()});
				c != null && c.unit == "px" ? c.value : null;
			case Token(_.kind => Number(0, _, _)): 0;
			case _: null;
		}

	// (Paged Media 3 §7.1's page sizes, portrait, in px)
	static final SIZES:Map<String, Array<Float>> = [
		"a5" => mm(148, 210), "a4" => mm(210, 297), "a3" => mm(297, 420), "b5" => mm(176, 250), "b4" => mm(250, 353), "jis-b5" => mm(182, 257),
		"jis-b4" => mm(257, 364), "letter" => [8.5 * 96, 11 * 96], "legal" => [8.5 * 96, 14 * 96], "ledger" => [11 * 96, 17 * 96]
	];

	static function mm(w:Float, h:Float):Array<Float>
		return [w * 96 / 25.4, h * 96 / 25.4];

	// (Paged Media 3 §6.2: each margin box's text-align and vertical-align)
	static final ALIGN:Map<String, Array<String>> = [
		"top-left-corner" => ["right", "middle"], "top-left" => ["left", "middle"], "top-center" => ["center", "middle"],
		"top-right" => ["right", "middle"], "top-right-corner" => ["left", "middle"], "left-top" => ["center", "top"],
		"left-middle" => ["center", "middle"], "left-bottom" => ["center", "bottom"], "right-top" => ["center", "top"],
		"right-middle" => ["center", "middle"], "right-bottom" => ["center", "bottom"], "bottom-left-corner" => ["right", "middle"],
		"bottom-left" => ["left", "middle"], "bottom-center" => ["center", "middle"], "bottom-right" => ["right", "middle"],
		"bottom-right-corner" => ["left", "middle"]
	];
}
