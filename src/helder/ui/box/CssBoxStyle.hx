package helder.ui.box;

import helder.css.CssColors;
import helder.css.CssContain;
import helder.css.CssLength;
import helder.css.CssProperties;
import helder.css.CssRgba;
import helder.css.CssShorthands;
import helder.css.CssStyle;
import helder.css.CssTerm;
import helder.ui.box.BoxStyle.BackgroundParts;
import helder.ui.box.BoxStyle.BoxShadow;
import helder.ui.box.Len;
import helder.ui.box.Len.Lens;

using StringTools;

// A box's style read from the cascade's computed style (helder.css's
// CssStyle): the one place that knows how helder.css stores it (its typed
// reads by property id: lengths, colours, display, numbers; terms for the
// rest), each BoxStyle part read from it when first asked. Its readers by
// a property's CSS name are the DOM side's (BoxTree, DocumentView,
// PagedView); each name is the property's id once. An anonymous box's
// style is its parent's inherited values and the initial ones (CSS 2.1
// §9.2.1.1).
class CssBoxStyle extends BoxStyle {
	final computed:CssStyle;

	public function new(css:CssStyle, anonymous = false) {
		super(anonymous);
		computed = css;
	}

	override function get_css():Null<CssStyle>
		return computed;

	// (a style's: the cascade's, as it was made of one)
	public static inline function of(s:BoxStyle):CssBoxStyle
		return cast s;

	override public function anonymousChild():BoxStyle
		return new CssBoxStyle(computed, true);

	// The same box's style from another computed style (a live document
	// restyled): an anonymous table part's display kept.
	public function restyled(next:CssStyle):CssBoxStyle {
		var s = new CssBoxStyle(next, anonymous);
		if (anonymous && displayRead) {
			s.displayRead = true;
			s.displayNone = displayNone;
			s.displayContents = displayContents;
			s.displayList = displayList;
			s.displayOuter = displayOuter;
			s.displayInner = displayInner;
			s.displayPart = displayPart;
		}
		return s;
	}

	override public function anonymousTable(inner:Int, part:Int, outer = BoxStyle.BLOCK):BoxStyle {
		var s = new CssBoxStyle(computed, true);
		s.displayRead = true;
		s.displayInner = inner;
		s.displayPart = part;
		s.displayOuter = outer;
		return s;
	}

	public function terms(p:String):Array<CssTerm> {
		var id = idOf(p);
		if (id < 0) return [];
		if (anonymous && !CssProperties.inherits(cast id)) return CssShorthands.initialTerms(p) ?? [];
		return computed.terms(cast id);
	}

	// (names to ids, once each; -1: not a property in scope)
	static final ids = new Map<String, Int>();

	static function idOf(p:String):Int {
		var id = ids.get(p);
		if (id == null) {
			var found = CssProperties.of(p);
			ids.set(p, id = found == null ? -1 : (cast found : Int));
		}
		return id;
	}

	// (the typed reads where the value is the element's own; an anonymous box's reset ones are initial)
	inline function typed(p:String):Bool
		return !anonymous || CssProperties.inherits(cast idOf(p));

	public function keyword(p:String):String {
		// (keywords the groups keep as an index, read without terms made for them)
		if (!anonymous) {
			var k:Int = switch p {
				case "white-space-collapse": cast computed.inheritedText.whiteSpaceCollapse;
				case "text-wrap-mode": cast computed.inheritedText.textWrapMode;
				case "word-break": cast computed.inheritedText.wordBreak;
				case "line-break": cast computed.inheritedText.lineBreak;
				case "overflow-wrap": cast computed.inheritedText.overflowWrap;
				case "hyphens": cast computed.inheritedText.hyphens;
				case "direction": cast computed.inheritedText.direction;
				case "text-align-last": cast computed.inheritedText.textAlignLast;
				case "font-kerning": cast computed.font.fontKerning;
				case "list-style-position": cast computed.list.listStylePosition;
				case "visibility": cast computed.ui.visibility;
				case "pointer-events": cast computed.ui.pointerEvents;
				case "float": cast computed.box.float;
				case "box-sizing": cast computed.box.boxSizing;
				case "overflow-x": cast computed.box.overflowX;
				case "overflow-y": cast computed.box.overflowY;
				case "unicode-bidi": cast computed.box.unicodeBidi;
				case "position": cast computed.position.position;
				case "outline-style": cast computed.outline.outlineStyle;
				case "text-decoration-style": cast computed.decoration.textDecorationStyle;
				case _: -2;
			}
			if (k >= 0) return CssProperties.keywords(cast idOf(p))[k];
		}
		return switch terms(p) {
			case [Keyword(k)] | [Ident(k)]: k;
			case [Part(_, [Keyword(k)])]: k;
			case _: "";
		}
	}

	public function px(p:String):Float {
		if (!typed(p)) return 0;
		var id = idOf(p);
		if (id < 0) return 0;
		if (unstyled(p)) return 0;
		var l = lengthOf(p, id);
		return switch l.kind {
			case Px | Plain: l.value;
			case Relative: relative(l);
			// (a property its group keeps as terms: text-indent's)
			case Other: switch termLen(terms(p)) {
					case Px(v): v;
					case _: 0;
				}
			case _: 0;
		}
	}

	// (a border's or outline's used width under a none or hidden style: 0,
	// Borders 4 §4.3; its computed one, helder.css's, is as written)
	function unstyled(p:String):Bool {
		var style = switch p {
			case "border-top-width": "border-top-style";
			case "border-right-width": "border-right-style";
			case "border-bottom-width": "border-bottom-style";
			case "border-left-width": "border-left-style";
			case "outline-width": "outline-style";
			case _: return false;
		}
		var k = keyword(style);
		return k == "none" || k == "hidden" && p != "outline-width";
	}

	// (the groups' typed fields where layout reads often: CssStyle.length interns its terms again)
	function lengthOf(p:String, id:Int):CssLength
		return switch p {
			case "margin-top": computed.spacing.marginTop;
			case "margin-right": computed.spacing.marginRight;
			case "margin-bottom": computed.spacing.marginBottom;
			case "margin-left": computed.spacing.marginLeft;
			case "padding-top": computed.spacing.paddingTop;
			case "padding-right": computed.spacing.paddingRight;
			case "padding-bottom": computed.spacing.paddingBottom;
			case "padding-left": computed.spacing.paddingLeft;
			case "border-top-width": computed.border.borderTopWidth;
			case "border-right-width": computed.border.borderRightWidth;
			case "border-bottom-width": computed.border.borderBottomWidth;
			case "border-left-width": computed.border.borderLeftWidth;
			case "width": computed.box.width;
			case "height": computed.box.height;
			case "min-width": computed.box.minWidth;
			case "min-height": computed.box.minHeight;
			case "max-width": computed.box.maxWidth;
			case "max-height": computed.box.maxHeight;
			case "letter-spacing": computed.inheritedText.letterSpacing;
			case "word-spacing": computed.inheritedText.wordSpacing;
			case "line-height": computed.font.lineHeight;
			case "font-size": computed.font.fontSize;
			case "outline-width": computed.outline.outlineWidth;
			case "outline-offset": computed.outline.outlineOffset;
			case _: computed.length(cast id);
		}

	// (a length from terms, a font-relative unit resolved)
	function termLen(t:Array<CssTerm>):Len
		return switch BoxRare.toLen(t) {
			case Px(v):
				var unit = "px";
				for (x in t) switch x {
					case Dimension(_, u): unit = u;
					case _:
				}
				unit == "px" ? Px(v) : Px(unitPx(v, unit));
			case l: l;
		}

	// (a length in a font's unit helder.css leaves to layout: ex and ch as half an em, cap and ic
	// as 0.7 and 1, until the fonts' own metrics come here)
	function relative(l:CssLength):Float
		return unitPx(l.value, l.unit);

	function unitPx(value:Float, unit:String):Float {
		var em = computed.fontSize();
		return value * switch unit {
			case "ex" | "ch": em / 2;
			case "cap": em * 0.7;
			case "ic" | "em": em;
			case "lh": computed.lineHeight() ?? em * 1.2;
			case _: 0;
		}
	}

	public function len(p:String):Len {
		if (!typed(p)) return BoxRare.toLen(terms(p));
		var id = idOf(p);
		if (id < 0) return Auto;
		if (unstyled(p)) return Px(0);
		var l = lengthOf(p, id);
		return switch l.kind {
			case Px | Plain: Px(l.value);
			case Relative: Px(relative(l));
			case Other: termLen(terms(p));
			case Percent: Percent(l.value);
			case Mixed if (l.calc != null): Calc(l.calc);
			case _: Auto;
		}
	}

	public function number(p:String, fallback = 0.0):Float {
		if (!typed(p)) return switch terms(p) {
			case [Number(v, _)]: v;
			case _: fallback;
		}
		var id = idOf(p);
		var v = id < 0 ? Math.NaN : computed.number(cast id);
		return Math.isNaN(v) ? fallback : v;
	}

	// The colour as 0xAARRGGBB; currentcolor is the color property's.
	public function color(p:String):Int {
		if (!typed(p)) return 0;
		var id = idOf(p);
		return id < 0 ? 0 : rgba(computed.color(cast id));
	}

	static function rgba(c:CssRgba):Int {
		inline function byte(x:Float):Int {
			var v = Math.round((Math.isNaN(x) ? 0 : x) * 255);
			return v < 0 ? 0 : v > 255 ? 255 : v;
		}
		// (system colours: the light scheme's, CssColors.system)
		if (c.keyword != null && c.keyword != "currentcolor") switch c.keyword {
			case "transparent": return 0;
			case k:
				var s = CssColors.system(k);
				if (s != null) return (byte(c.a * s[3]) << 24) | (Std.int(s[0]) << 16) | (Std.int(s[1]) << 8) | Std.int(s[2]);
		}
		return (byte(c.a) << 24) | (byte(c.r) << 16) | (byte(c.g) << 8) | byte(c.b);
	}

	// ---- the parts, read from it

	override function readDisplay() {
		if (anonymous) return;
		var d = computed.display;
		originalOuter = computed.originalDisplay.outer == Inline ? BoxStyle.INLINE : BoxStyle.BLOCK;
		switch d.outer {
			case None: displayNone = true;
			case Contents: displayContents = true;
			case Inline: displayOuter = BoxStyle.INLINE;
			case _: displayOuter = BoxStyle.BLOCK;
		}
		displayList = d.listItem;
		displayInner = switch d.inner {
			case FlowRoot: BoxStyle.FLOW_ROOT;
			case Table: BoxStyle.TABLE;
			case Flex: BoxStyle.FLEX;
			case Grid | GridLanes: BoxStyle.GRID;
			case TableRowGroup | TableHeaderGroup | TableFooterGroup | TableRow | TableCell | TableColumnGroup | TableColumn | TableCaption: BoxStyle.TABLE_PART;
			case _: BoxStyle.FLOW;
		}
		displayPart = switch d.inner {
			case TableRowGroup: BoxStyle.ROW_GROUP;
			case TableHeaderGroup: BoxStyle.HEADER_GROUP;
			case TableFooterGroup: BoxStyle.FOOTER_GROUP;
			case TableRow: BoxStyle.ROW;
			case TableCell: BoxStyle.CELL;
			case TableColumnGroup: BoxStyle.COLUMN_GROUP;
			case TableColumn: BoxStyle.COLUMN;
			case TableCaption: BoxStyle.CAPTION;
			case _: 0;
		}
		if (d.outer == Internal && displayInner != BoxStyle.TABLE_PART) displayOuter = BoxStyle.BLOCK;
	}

	override function readModel() {
		// (an anonymous box's are all initial: none, zero, auto)
		if (anonymous) {
			for (_ in 0...4) {
				margin.push(Px(0));
				padding.push(Px(0));
				border.push(0);
			}
			return;
		}
		for (s in SIDES) {
			margin.push(len('margin-$s'));
			padding.push(len('padding-$s'));
			border.push(px('border-$s-width'));
		}
		width = len("width");
		height = len("height");
		minWidth = len("min-width");
		minHeight = len("min-height");
		maxWidth = len("max-width");
		maxHeight = len("max-height");
		borderBox = keyword("box-sizing") == "border-box";
		readRatio(terms("aspect-ratio"));
	}

	function readRatio(terms:Array<CssTerm>) {
		var a = Math.NaN, b = 1.0, over = false;
		for (t in terms) switch t {
			case Number(v, _):
				if (over) b = v else a = v;
			case Delim("/"):
				over = true;
			case Part(_, inner):
				readRatio(inner);
				return;
			case _:
		}
		if (Math.isNaN(a)) return;
		ratioAuto = terms[0].match(Keyword("auto")) || terms[terms.length - 1].match(Keyword("auto"));
		var r = a / b;
		if (r > 0 && Math.isFinite(r)) ratio = r;
	}

	override function readText():helder.ui.flow.InlineBasicStyle {
		var t = new helder.ui.flow.InlineBasicStyle();
		t.families = familiesOf(terms("font-family"));
		t.size = computed.fontSize();
		t.weight = Std.int(number("font-weight", 400));
		var fs = terms("font-style");
		t.style = switch keyword("font-style") {
			case "italic": Italic;
			case "oblique": Oblique;
			case _: switch fs {
					case [Keyword("oblique"), _]: Oblique;
					case _: Normal;
				}
		}
		t.angle = switch fs {
			case [Keyword("oblique"), Dimension(v, "deg")]: v;
			case [Keyword("oblique"), Dimension(v, "turn")]: v * 360;
			case [Keyword("oblique"), Dimension(v, "rad")]: v * 180 / Math.PI;
			case [Keyword("oblique"), Dimension(v, "grad")]: v * 0.9;
			case _: 14;
		}
		t.stretch = switch terms("font-width") {
			case [Percentage(p)]: p;
			case [Keyword(k)]: helder.text.FontFaces.FontFaceDescriptors.STRETCH.get(k) ?? 100;
			case _: 100;
		}
		var synthesis = 0;
		if (keyword("font-synthesis-weight") != "none") synthesis |= helder.ui.flow.InlineValues.InlineSynthesis.Weight;
		switch keyword("font-synthesis-style") {
			case "none":
			case "oblique-only": synthesis |= helder.ui.flow.InlineValues.InlineSynthesis.Oblique;
			case _: synthesis |= helder.ui.flow.InlineValues.InlineSynthesis.Style | helder.ui.flow.InlineValues.InlineSynthesis.Oblique;
		}
		t.synthesis = synthesis;
		t.opticalSizing = keyword("font-optical-sizing") != "none";
		t.variations = TextTerms.variations(terms("font-variation-settings"));
		t.features = TextTerms.features(this);
		t.kerning = switch keyword("font-kerning") {
			case "normal": Normal;
			case "none": None;
			case _: Auto;
		}
		t.ligatures = TextTerms.ligatures(terms("font-variant-ligatures"));
		t.emoji = switch keyword("font-variant-emoji") {
			case "text": Text;
			case "emoji": Emoji;
			case "unicode": Unicode;
			case _: Normal;
		}
		t.colour = color("color");
		t.height = switch terms("line-height") {
			case [Dimension(v, "px")]: v;
			case [Number(n, _)]: n * t.size;
			case [Percentage(p)]: p * t.size / 100;
			case _: Math.NaN;
		}
		t.letters = px("letter-spacing");
		t.words = px("word-spacing");
		t.transform = TextTerms.transform(terms("text-transform"));
		t.collapse = switch keyword("white-space-collapse") {
			case "discard": Discard;
			case "preserve": Preserve;
			case "preserve-breaks": PreserveBreaks;
			case "preserve-spaces": PreserveSpaces;
			case "break-spaces": BreakSpaces;
			case _: Collapse;
		}
		t.wrap = keyword("text-wrap-mode") == "nowrap" ? NoWrap : Wrap;
		t.tab = switch terms("tab-size") {
			case [Number(n, _)]: n;
			case [Dimension(v, _)]: -v;
			case _: 8;
		}
		t.breakWord = switch keyword("word-break") {
			case "break-all": BreakAll;
			case "keep-all": KeepAll;
			case "break-word": BreakWord;
			case _: Normal;
		}
		t.overflow = switch keyword("overflow-wrap") {
			case "break-word": BreakWord;
			case "anywhere": Anywhere;
			case _: Normal;
		}
		t.breakLine = switch keyword("line-break") {
			case "loose": Loose;
			case "normal": Normal;
			case "strict": Strict;
			case "anywhere": Anywhere;
			case _: Auto;
		}
		t.hyphen = switch keyword("hyphens") {
			case "none": None;
			case "auto": Auto;
			case _: Manual;
		}
		t.dir = rtl ? Rtl : Ltr;
		t.bidi = switch keyword("unicode-bidi") {
			case "embed": Embed;
			case "isolate": Isolate;
			case "bidi-override": BidiOverride;
			case "isolate-override": IsolateOverride;
			case "plaintext": Plaintext;
			case _: Normal;
		}
		t.align = TextTerms.align(keyword("text-align-all"), Start);
		t.alignLast = TextTerms.align(keyword("text-align-last"), Auto);
		t.justify = switch keyword("text-justify") {
			case "none": None;
			case "inter-word": InterWord;
			case "inter-character": InterCharacter;
			case _: Auto;
		}
		indentLen = len("text-indent");
		var ti = terms("text-indent");
		t.indentEachLine = ti.contains(Keyword("each-line"));
		t.indentHanging = ti.contains(Keyword("hanging"));
		var to = terms("text-overflow");
		t.textOverflowEnd = to.length > 0 && to[to.length - 1].match(Keyword("ellipsis")) ? Ellipsis : Clip;
		t.clamp = switch terms("line-clamp") {
			case [Number(n, _)]: Std.int(n);
			case _: 0;
		}
		var va = verticalAlign();
		t.vertical = TextTerms.vertical(va.kind);
		t.shift = va.kind == "percent" ? va.shift / 100 : va.shift;
		t.decoration = TextTerms.decoration(terms("text-decoration-line"));
		t.decorationStyle = switch keyword("text-decoration-style") {
			case "double": Double;
			case "dotted": Dotted;
			case "dashed": Dashed;
			case "wavy": Wavy;
			case _: Solid;
		}
		t.decorationColour = switch terms("text-decoration-color") {
			case [Color(c)]: BoxStyle.argb(c, t.colour);
			case _: t.colour;
		}
		t.decorationThickness = switch terms("text-decoration-thickness") {
			case [Dimension(v, _)]: v;
			case [Percentage(p)]: p * t.size / 100;
			case _: Math.NaN;
		}
		return t;
	}

	override function readPaint() {
		paintRead = true;
		bgColor = color("background-color");
		var images = BackgroundParts.split(terms("background-image"));
		if (!(images.length == 1 && (images[0].length == 0 || images[0][0].match(Keyword("none"))))) bgParts = new BackgroundParts(images, split(terms("background-clip")), split(terms("background-origin")), split(terms("background-size")),
				split(terms("background-repeat")), split(terms("background-position-x")), split(terms("background-position-y")), split(terms("background-attachment")));
		// (the colour's clip: the bottom layer's)
		var clips = bgParts != null ? bgParts.clips : BackgroundParts.split(terms("background-clip"));
		bgClip = switch clips[(images.length - 1) % clips.length] {
			case [Keyword(k)]: k;
			case _: "border-box";
		}
		var r = [], any = false;
		for (c in CORNERS) switch terms('border-$c-radius') {
			case [a, b]:
				r.push(a);
				r.push(b);
				if (!zero(a) || !zero(b)) any = true;
			case [a]:
				r.push(a);
				r.push(a);
				if (!zero(a)) any = true;
			case _:
				r.push(Number(0, true));
				r.push(Number(0, true));
		}
		if (any) radiusTerms = r;
		for (side in SIDES) {
			sideStyles.push(keyword('border-$side-style'));
			sideColors.push(color('border-$side-color'));
		}
		var shadow = terms("box-shadow");
		if (shadow.length > 0 && !shadow[0].match(Keyword("none"))) {
			var list = [], current = color("color");
			var one = new BoxShadow();
			list.push(one);
			for (t in shadow) switch t {
				case Delim(","):
					one = new BoxShadow();
					list.push(one);
				case Color(c): one.color = BoxStyle.argb(c, current);
				case Keyword("inset"): one.inset = true;
				case Dimension(v, _): one.lengths.push(v);
				case _:
			}
			for (o in list) {
				if (o.color == -1) o.color = current;
				while (o.lengths.length < 4) o.lengths.push(0);
			}
			shadowList = list;
		}
		outlineStyleValue = keyword("outline-style");
		if (outlineStyleValue != "none" && outlineStyleValue != "") {
			outlineWidthValue = px("outline-width");
			outlineOffsetValue = px("outline-offset");
			outlineColorValue = switch terms("outline-color") {
				case [Keyword("auto" | "invert")]: color("color");
				case _: color("outline-color");
			}
		}
	}

	static function zero(t:CssTerm):Bool
		return switch t {
			case Dimension(v, _) | Number(v, _) | Percentage(v): v == 0;
			case _: false;
		}

	static final CORNERS = ["top-left", "top-right", "bottom-right", "bottom-left"];

	static function split(t:Array<CssTerm>):Array<Array<CssTerm>>
		return BackgroundParts.split(t);

	override function readLayout() {
		layoutRead = true;
		orderValue = Std.int(number("order", 0));
		growValue = number("flex-grow", 0);
		shrinkValue = number("flex-shrink", 1);
		basisWord = keyword("flex-basis");
		basisValue = len("flex-basis");
		directionValue = keyword("flex-direction");
		wrapValue = keyword("flex-wrap");
		for (p in ALIGNS) {
			var k = keyword(p);
			aligns.push(k == "" ? helder.css.CssText.join(terms(p), helder.css.CssText.term) : k);
		}
		rowGapValue = keyword("row-gap") == "normal" ? Len.Auto : len("row-gap");
		columnGapValue = keyword("column-gap") == "normal" ? Len.Auto : len("column-gap");
		for (s in SIDES) insets.push(len(s));
		floatValue = keyword("float");
		clearValue = keyword("clear");
	}

	static final ALIGNS = ["justify-content", "align-content", "align-items", "align-self", "justify-items", "justify-self"];

	static final SIDES = ["top", "right", "bottom", "left"];

	override function readTraits():Int {
		positionWord = keyword("position");
		var f = keyword("float"), x = keyword("overflow-x"), y = keyword("overflow-y"), v = keyword("visibility"), c = keyword("white-space-collapse");
		overflowXWord = x;
		overflowYWord = y;
		var positioned = positionWord != "static" && positionWord != "";
		var moved = !anonymous && !(keyword("transform") == "none" && keyword("translate") == "none" && keyword("rotate") == "none" && keyword("scale") == "none");
		// (paint containment clips as overflow does, to the padding box, Contain 2 §3.4)
		var t = (f == "left" || f == "right" ? BoxStyle.FLOATING : 0)
			| ((x != "visible" && x != "") || (y != "visible" && y != "") || containment.has(Paint) ? BoxStyle.CLIPS : 0)
			| (keyword("direction") == "rtl" ? BoxStyle.RTL : 0) | (v != "hidden" && v != "collapse" ? BoxStyle.VISIBLE : 0)
			| (c == "collapse" || c == "" ? BoxStyle.COLLAPSE : 0) | (c != "collapse" ? BoxStyle.BREAKS : 0)
			| (keyword("text-wrap-mode") != "nowrap" ? BoxStyle.WRAPS : 0)
			| (x == "auto" || x == "scroll" || y == "auto" || y == "scroll" ? BoxStyle.SCROLLS : 0) | (x == "hidden" || y == "hidden" ? BoxStyle.HIDDEN_OVERFLOW : 0)
			| (moved ? BoxStyle.MOVED : 0) | (!anonymous && keyword("content-visibility") == "hidden" ? BoxStyle.CONTENT_HIDDEN : 0);
		var stacks = positioned && rare.zIndex != null || opacity < 1 || keyword("transform") != "none" && terms("transform").length > 0
			|| positionWord == "fixed" || containment.stacking;
		return t | (stacks ? BoxStyle.STACKS : 0);
	}

	override function readOpacity():Float
		return number("opacity", 1);

	override function readContainment():Int
		return anonymous ? 0 : computed.containment();

	override function readAlign():{kind:String, shift:Float} {
		switch terms("baseline-shift") {
			case [Keyword(k)] if (k != "baseline"): return {kind: k == "center" ? "middle" : k, shift: 0};
			case [Dimension(v, _)] if (v != 0): return {kind: "length", shift: v};
			case [Percentage(p)] if (p != 0): return {kind: "percent", shift: p};
			case [Calc(_, _, _)]: return {kind: "length", shift: Lens.resolve(len("baseline-shift"), 0, 0)};
			case _:
		}
		return switch keyword("alignment-baseline") {
			case "middle" | "central": {kind: "middle", shift: 0};
			case "text-top" | "text-before-edge": {kind: "text-top", shift: 0};
			case "text-bottom" | "text-after-edge": {kind: "text-bottom", shift: 0};
			case _: {kind: "baseline", shift: 0};
		}
	}

	override function readRare():BoxRare {
		var r = new BoxRare();
		r.widthKeyword = keyword("width");
		r.clip = switch terms("clip") {
			case [Func("rect", [top, Delim(","), right, Delim(","), bottom, Delim(","), left])]: [termLen([top]), termLen([right]), termLen([bottom]), termLen([left])];
			case _: null;
		}
		r.zIndex = switch terms("z-index") {
			case [Number(v, _)]: Std.int(v);
			case _: null;
		}
		function size(p:String):Float {
			for (t in terms(p)) switch t {
				case Dimension(v, _): return v;
				case Number(v, _): return v;
				case _:
			}
			return 0;
		}
		r.intrinsicWidth = size("contain-intrinsic-width");
		r.intrinsicHeight = size("contain-intrinsic-height");
		r.pointerEvents = keyword("pointer-events");
		r.visibility = keyword("visibility");
		r.scrollbarWidth = keyword("scrollbar-width");
		r.contentNormal = keyword("content") == "normal";
		r.listStyleType = keyword("list-style-type");
		r.textAlign = keyword("text-align");
		r.boxDecorationBreak = keyword("box-decoration-break");
		r.breakBefore = keyword("break-before");
		r.breakAfter = keyword("break-after");
		r.breakInside = keyword("break-inside");
		r.pageBreakBefore = keyword("page-break-before");
		r.pageBreakAfter = keyword("page-break-after");
		r.pageBreakInside = keyword("page-break-inside");
		r.page = keyword("page");
		r.orphans = number("orphans", 2);
		r.widows = number("widows", 2);
		r.borderCollapse = keyword("border-collapse") == "collapse";
		r.borderSpacing = switch terms("border-spacing") {
			case [Dimension(a, _), Dimension(b, _)]: [a, b];
			case [Dimension(a, _)]: [a, a];
			case _: [0, 0];
		}
		r.tableLayout = keyword("table-layout");
		r.captionSide = keyword("caption-side");
		r.emptyCells = keyword("empty-cells");
		r.gridTemplateRows = terms("grid-template-rows");
		r.gridTemplateColumns = terms("grid-template-columns");
		r.gridAutoRows = terms("grid-auto-rows");
		r.gridAutoColumns = terms("grid-auto-columns");
		r.gridTemplateAreas = terms("grid-template-areas");
		r.gridAutoFlow = terms("grid-auto-flow");
		r.gridLines = [terms("grid-row-start"), terms("grid-row-end"), terms("grid-column-start"), terms("grid-column-end")];
		r.transform = terms("transform");
		r.transformOrigin = terms("transform-origin");
		r.fontPalette = terms("font-palette");
		r.fromFont = switch terms("text-decoration-thickness") {
			case [Keyword("from-font")]: true;
			case _: false;
		}
		return r;
	}

	public static function familiesOf(terms:Array<CssTerm>):Array<String> {
		var out = [], word = [];
		for (t in terms) switch t {
			case Delim(","):
				if (word.length > 0) out.push(word.join(" "));
				word = [];
			case Str(v) if (helder.ui.flow.InlineFonts.generic(v)): word.push('"$v"');
			case Ident(v) | Str(v) | Keyword(v) | Raw(v): word.push(v);
			case _:
		}
		if (word.length > 0) out.push(word.join(" "));
		return out;
	}

}
