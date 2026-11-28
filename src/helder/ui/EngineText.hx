package helder.ui;

import helder.ui.box.Box;
import helder.ui.box.BoxStyle;
import helder.ui.box.BoxTexts;
import helder.ui.box.FontMatch;
import helder.ui.box.Fragments;
import helder.ui.draw.RunParagraph;
import helder.ui.flow.BlockFlow;
import helder.ui.flow.InlineBasicStyle;
import helder.ui.flow.Space;

// helder.ui's text laid out by the CSS engine's inline layout (the switch's
// step 3): a TextNode's text, its spans inline boxes in it, a block of
// lines BlockFlow breaks; the glyphs placed as a RunParagraph's, which the
// Renderer draws; carets, hits and selections from its lines (BoxTexts).
// A TextEngine as DrawText is: what a Ui is made with.
class EngineText implements TextEngine {
	final fonts:FontMatch;
	final flow = new BlockFlow();
	final fragments = new Fragments();
	// (the paragraph whose layout the fragments hold, for its carets and hits)
	var holding:Null<EngineParagraph> = null;
	// (the styles made, by what they read: one for all text styled alike)
	final styles = new Map<String, BoxStyle>();

	public function new(?system:helder.text.SystemFonts)
		fonts = new FontMatch(system);

	public function generation():Int
		return helder.text.FontFile.generation;

	public function layout(text:String, font:Font, maxWidth:Float, ?spans:Array<TextSpan>, maxLines:Int = 0, justify:Bool = false, base:Int = -1, cut:Float = -1,
			?into:Paragraph):Paragraph {
		var wrap = !Math.isNaN(maxWidth) && cut < 0;
		// (a text with no right-to-left in it: left to right, no bidi to resolve, its base direction aside)
		if (base < 0 && !rtl(text)) base = 0;
		// (no spans, no limit, no ellipsis: its boxes shared by its layouts at every width, shaped once (the engine's
		// lines kept on its root, BlockLines); one line per hard break shared whole, as DrawText shares them)
		var plain = spans == null && maxLines == 0 && !justify && cut < 0;
		var key = plain ? text + "\u0000" + base + "\u0000" + keyOf(font) : null;
		if (plain && (shapedIn != helder.text.FontFile.generation || plainCount >= 4096)) {
			shapedIn = helder.text.FontFile.generation;
			shared.clear();
			trees.clear();
			plainCount = 0;
		}
		if (plain && !wrap) {
			var kept = shared.get(key);
			if (kept != null) return kept;
		}
		// (one line per hard break: wrapping, as wide as it likes; cut with an ellipsis: not wrapping)
		var t = plain ? trees.get(key) : null;
		if (t == null) {
			t = tree(text, font, spans, cut < 0, maxLines, justify, base, cut);
			if (plain) {
				trees.set(key, t);
				plainCount++;
			}
		}
		var p = new EngineParagraph(this, t.root, text, t.boxes, t.starts, t.spans, wrap ? maxWidth : cut >= 0 ? cut : Math.POSITIVE_INFINITY, font.size,
			oneFont(font, spans));
		// (its min-content width: its widest word as CSS's min-content has it (not broken where overflow-wrap
		// alone would), whether it wraps or not)
		var root = t.root;
		// (an empty text's none: its line's zero-width space aside)
		p.measure = text == "" ? () -> 0.0 : () -> minOf(cut < 0 ? root : tree(text, font, spans, true, maxLines, justify, base, -1).root);
		if (plain && !wrap) shared.set(key, p);
		return p;
	}

	final trees = new Map<String, {root:Box, boxes:Array<Box>, starts:Array<Int>, spans:Array<Int>}>();
	final shared = new Map<String, EngineParagraph>();
	var plainCount = 0;
	var shapedIn = helder.text.FontFile.generation;

	// (a text and its spans as boxes: a block, its text boxes, a span's in an inline box)
	function tree(text:String, font:Font, spans:Null<Array<TextSpan>>, wrap:Bool, maxLines:Int, justify:Bool, base:Int,
			cut:Float):{root:Box, boxes:Array<Box>, starts:Array<Int>, spans:Array<Int>} {
		var root = new Box(Block, styleOf(font, wrap, maxLines, justify, base, cut, true), null);
		var boxes:Array<Box> = [], starts:Array<Int> = [], spanOf:Array<Int> = [];
		function add(start:Int, end:Int, span:Int, ?shown:String) {
			if (end <= start && shown == null) return;
			var t = new Box(Text, span < 0 ? root.style : styleOf(spans[span].font, wrap, maxLines, justify, base, cut, false), null);
			t.text = shown ?? (start == 0 && end == text.length ? text : text.substring(start, end));
			if (span < 0) root.append(t) else {
				var holder = new Box(Inline, t.style, null);
				holder.append(t);
				root.append(holder);
			}
			boxes.push(t);
			starts.push(start);
			spanOf.push(span);
		}
		var at = 0;
		if (spans != null)
			for (k in 0...spans.length) {
				var s = spans[k];
				add(at, s.start, -1);
				add(s.start, s.end, k);
				at = s.end;
			}
		add(at, text.length, -1);
		// (an empty text: a line of its height, a caret's, as a zero-width space's)
		if (boxes.length == 0) add(0, 0, -1, "\u200B");
		return {root: root, boxes: boxes, starts: starts, spans: spanOf};
	}

	static function rtl(text:String):Bool {
		for (i in 0...text.length) {
			var c = StringTools.fastCodeAt(text, i);
			// (Hebrew, Arabic, Syriac... and their presentation forms; a surrogate pair: checked as one)
			if (c >= 0x0590 && c <= 0x08FF || c >= 0xFB1D && c <= 0xFDFF || c >= 0xFE70 && c <= 0xFEFF || c >= 0xD800 && c <= 0xDBFF) return true;
		}
		return false;
	}

	function minOf(root:Box):Float {
		if (!Math.isNaN(root.minContent)) return root.minContent;
		flow.intrinsic(root, new Space(fragments, fonts, Math.POSITIVE_INFINITY, Math.NaN));
		return root.minContent;
	}

	// (a paragraph's boxes laid out into the fragments at room, its root's fragment; again only when another one
	// holds them)
	@:allow(helder.ui.EngineParagraph)
	function lay(root:Box, room:Float):Int {
		if (holding != null && holding.root == root && holding.room == room) return holding.fragment;
		// (its own arena cleared: its boxes' layouts let go with it, not every box's (Box.forgetFragments would
		// let the window's tree's go too))
		fragments.clear();
		var b:Null<Box> = root;
		while (b != null) {
			b.uncache();
			b = b.first != null ? b.first : b.next != null ? b.next : b.parent != null && b.parent != root ? b.parent.next : null;
		}
		holding = null;
		// (unbounded, its lines not from the left (right to left, its own direction, justified): as wide as its
		// widest line, its max-content, not an infinite line's other end)
		var t = root.style.text;
		if (room == Math.POSITIVE_INFINITY && (t.dir == Rtl || t.bidi == Plaintext || t.align == Justify)) {
			root.maxContent = Math.NaN;
			flow.intrinsic(root, new Space(fragments, fonts, room, Math.NaN));
			room = root.maxContent;
		}
		var space = new Space(fragments, fonts, room, Math.NaN);
		if (room < Math.POSITIVE_INFINITY) space.fixedWidth = room;
		return flow.layout(root, space);
	}

	@:allow(helder.ui.EngineParagraph)
	function holdBy(p:EngineParagraph, id:Int) {
		p.fragment = id;
		holding = p;
	}

	@:allow(helder.ui.EngineParagraph)
	inline function inlines():helder.ui.flow.InlineFonts
		return fonts.inlines;

	@:allow(helder.ui.EngineParagraph)
	inline function frags():Fragments
		return fragments;

	// (a font as the engine's inline style: its face, size, line height, spacing, breaking; the block's, wrapping
	// or not, its lines at most maxLines, justified, in a direction, cut with an ellipsis)
	function styleOf(font:Font, wrap:Bool, maxLines:Int, justify:Bool, base:Int, cut:Float, block:Bool):BoxStyle {
		var flags = (wrap ? 1 : 0) | (justify ? 2 : 0) | (cut >= 0 ? 4 : 0) | (block ? 8 : 0) | ((base + 1) << 4) | (maxLines << 6);
		// (the font asked for last, most text has its neighbour's)
		if (font == lastFont && flags == lastFlags) return lastStyle;
		var key = keyOf(font) + "|" + flags;
		var made = styles.get(key);
		if (made != null) {
			lastFont = font;
			lastFlags = flags;
			return lastStyle = made;
		}
		var t = new InlineBasicStyle();
		t.families = [familyOf(font)];
		// (a variable face's optical size axis left at its default, as helder.text draws it: DrawText's widths)
		t.opticalSizing = false;
		// (its OpenType features, as DrawText's: tabular figures, a stylistic set)
		if (font.features != "") t.features = helder.text.FontFeature.parse(font.features);
		t.size = font.size;
		t.weight = font.weight;
		t.style = font.italic ? Italic : Normal;
		t.height = font.lineHeight * font.size;
		t.letters = font.letterSpacing;
		t.words = font.wordSpacing;
		t.overflow = switch font.overflowWrap {
			case Anywhere: Anywhere;
			case BreakWord: BreakWord;
			case _: Normal;
		}
		t.breakWord = switch font.wordBreak {
			case BreakAll: BreakAll;
			case KeepAll: KeepAll;
			case _: Normal;
		}
		t.hyphen = switch font.hyphens {
			case None: None;
			case Auto: Auto;
			case _: Manual;
		}
		t.language = font.lang;
		// (its spaces and line breaks kept, as helder.ui's text has them; wrapped at its width unless none)
		t.collapse = Preserve;
		t.wrap = wrap ? Wrap : NoWrap;
		t.dir = base == 1 ? Rtl : Ltr;
		if (base < 0) t.bidi = Plaintext;
		t.align = justify ? Justify : Start;
		t.clamp = maxLines;
		t.textOverflowEnd = cut >= 0 ? Ellipsis : Clip;
		var s = new BoxStyle();
		@:privateAccess {
			s.textPart = t;
			s.displayRead = true;
			s.displayOuter = block ? BoxStyle.BLOCK : BoxStyle.INLINE;
			s.displayInner = BoxStyle.FLOW;
			s.layoutRead = true;
			s.traits = BoxStyle.VISIBLE | BoxStyle.COLLAPSE | BoxStyle.WRAPS | (cut >= 0 ? BoxStyle.CLIPS | BoxStyle.CUTS : 0) | (base == 1 ? BoxStyle.RTL : 0);
			s.opacityValue = 1;
		}
		styles.set(key, s);
		lastFont = font;
		lastFlags = flags;
		return lastStyle = s;
	}

	var lastFont:Null<Font> = null;
	var lastFlags = -1;
	var lastStyle:Null<BoxStyle> = null;

	// (the face DrawText would draw it in, SystemFonts.match's, by its own family name: a generic one
	// (system-ui, sans-serif) the same face as before on every system, the engine's matching not another's)
	function familyOf(font:Font):String {
		var face = fonts.system.match(font.family, font.weight, font.italic);
		return face == null ? font.family : face.family;
	}

	// (its spans, if any, in its own font: colours a CodeView's tokens have)
	static function oneFont(font:Font, spans:Null<Array<TextSpan>>):Bool {
		if (spans == null) return true;
		var key = keyOf(font);
		for (s in spans) if (s.font != font && keyOf(s.font) != key) return false;
		return true;
	}

	static function keyOf(font:Font):String
		return font.family + "|" + font.size + "|" + font.weight + "|" + font.italic + "|" + font.lineHeight + "|" + font.letterSpacing + "|"
			+ font.wordSpacing + "|" + font.overflowWrap + "|" + font.wordBreak + "|" + font.hyphens + "|" + font.lang + "|" + font.features;
}

// A paragraph the engine laid out: its lines' glyphs placed (RunParagraph's,
// drawn as they are), its boxes kept to lay it out again for a caret, a hit
// or a selection (EngineText holds one layout at a time).
@:allow(helder.ui.EngineText)
class EngineParagraph extends RunParagraph {
	final engine:EngineText;
	@:allow(helder.ui.EngineText) final root:Box;
	final text:String;
	// (its text boxes, where each starts in the text, which span each is (-1: none))
	final boxes:Array<Box>;
	final starts:Array<Int>;
	final spanOf:Array<Int>;
	final room:Float;
	var fragment = -1;
	var minContent = Math.NaN;
	// (its min-content width, measured when asked: EngineText.layout's)
	var measure:Null<Void->Float> = null;

	function new(engine:EngineText, root:Box, text:String, boxes:Array<Box>, starts:Array<Int>, spanOf:Array<Int>, room:Float, size:Float, oneFont:Bool) {
		var id = engine.lay(root, room), f = engine.frags();
		var lines:Array<RunLine> = [];
		var widest = 0.0, first = Math.NaN;
		var k = f.first(id);
		while (k >= 0) {
			if (f.kind(k) == Fragments.LINE) {
				var top = f.y(k), base = f.baseline(k);
				if (Math.isNaN(first)) first = top + base;
				var w = lineWidth0(f, k);
				widest = Math.max(widest, w);
				lines.push({top: top, baseline: base, width: w, height: f.height(k), start: 0, end: 0});
			}
			k = f.next(k);
		}
		// (one font: drawn at its exact baseline, its face's ascent and descent unrounded, as DrawText draws it, so
		// that a text scaled is the larger one's; the lines' boxes the engine's, Blink's rounded metrics)
		if (oneFont && lines.length > 0) {
			var t = root.style.text, fonts = engine.inlines(), font = fonts.idOf(t);
			var a = fonts.ascent(font, true), d = fonts.descent(font, true);
			var lh = Math.isNaN(t.height) ? fonts.normalLineHeight(font, true) : t.height;
			var shift = (lh - (a + d)) / 2 + a - lines[0].baseline;
			if (Math.abs(shift) < 1)
				for (l in lines) l.baseline += shift;
			first += shift;
		}
		super(widest, f.height(id), Math.NaN, Math.isNaN(first) ? 0 : first, size, lines);
		this.engine = engine;
		this.root = root;
		this.text = text;
		this.boxes = boxes;
		this.starts = starts;
		this.spanOf = spanOf;
		this.room = room;
		engine.holdBy(this, id);
	}

	var placedYet = false;

	// (its glyphs placed when it is first drawn: a paragraph measured alone (a width asked for) places none)
	override public function ready() {
		if (placedYet) return;
		placedYet = true;
		var id = engine.lay(root, room), f = engine.frags();
		engine.holdBy(this, id);
		var k = f.first(id), n = 0;
		while (k >= 0) {
			if (f.kind(k) == Fragments.LINE && n < lines.length) {
				var l = lines[n++];
				l.start = ids.length;
				collect(f, k, 0, f.baseline(k), this, size, boxes, spanOf);
				l.end = ids.length;
			}
			k = f.next(k);
		}
	}

	// (each glyph's characters: its text box and their range in it)
	final glyphBox:Array<Int> = [];
	final glyphFrom:Array<Int> = [];
	final glyphTo:Array<Int> = [];

	// (its glyphs as runs, a document writer's: placed first, each glyph its characters (a ligature's all))
	override public function runs(width:Float, align:TextAlign):Array<GlyphRun> {
		ready();
		var out = super.runs(width, align), i = 0;
		for (l in lines)
			for (g in l.start...l.end) {
				var b = glyphBox[g];
				glyphText[g] = b < 0 ? "" : boxes[b].text.substring(glyphFrom[g], glyphTo[g]);
			}
		for (r in out)
			for (k in 0...r.text.length) r.text[k] = glyphText[i++];
		return out;
	}

	final glyphText:Array<String> = [];

	static inline function blank(c:Int):Bool
		return c == " ".code || c == "\t".code || c == "\n".code || c == 0x200B;

	// (a line's content width: its last text's end, where that is no space; else where its last glyph but a space
	// ends, its trailing spaces hanging, as DrawText's)
	static function lineWidth0(f:Fragments, line:Int):Float {
		var right = 0.0, lastText = -1;
		function walk(id:Int, x:Float) {
			var k = f.first(id);
			while (k >= 0) {
				var kx = x + f.x(k);
				if (f.kind(k) == Fragments.TEXT) {
					right = Math.max(right, kx + f.width(k));
					lastText = k;
				} else walk(k, kx);
				k = f.next(k);
			}
		}
		walk(line, 0);
		if (lastText < 0) return right;
		var b = f.box(lastText), end = f.end(lastText);
		if (b == null || end <= 0 || !blank(b.text.charCodeAt(end - 1))) return right;
		right = 0.0;
		function glyphs(id:Int, x:Float) {
			var k = f.first(id);
			while (k >= 0) {
				var kx = x + f.x(k);
				if (f.kind(k) == Fragments.TEXT) {
					var run = f.glyphs(k), bk = f.box(k);
					if (run != null && bk != null)
						for (g in 0...run.count) if (!blank(bk.text.charCodeAt(run.start(g))))
							right = Math.max(right, kx + (g + 1 < run.count ? run.x(g + 1) : f.width(k)));
				} else glyphs(k, kx);
				k = f.next(k);
			}
		}
		glyphs(line, 0);
		return right;
	}

	// (the glyphs of the line's text fragments, through its spans, x from the line's left, y from its baseline)
	static function collect(f:Fragments, id:Int, x:Float, lineBase:Float, out:RunParagraph, size:Float, boxes:Array<Box>, spanOf:Array<Int>) {
		var k = f.first(id);
		while (k >= 0) {
			var kx = x + f.x(k);
			if (f.kind(k) == Fragments.TEXT) {
				var run = f.glyphs(k);
				if (run != null) {
					var i = boxes.length == 1 ? 0 : boxes.indexOf(f.box(k)), span = i < 0 ? -1 : spanOf[i];
					var chars = Std.downcast(out, EngineParagraph);
					var dy = f.y(k) + f.baseline(k) - lineBase, oblique = run.skew != 0;
					// (a span's glyphs its own: its colour, its size)
					var mark = span >= 0 ? span : run.size != size ? 0 : -1;
					for (n in 0...run.count) {
						out.faces.push(run.face);
						out.ids.push(run.id(n));
						out.xs.push(kx + run.x(n));
						out.dys.push(dy + run.y(n));
						out.sizes.push(run.size);
						out.obliques.push(oblique);
						out.spans.push(mark);
						if (chars != null) {
							chars.glyphBox.push(i);
							chars.glyphFrom.push(run.start(n));
							chars.glyphTo.push(run.end(n));
						}
					}
				}
			} else collect(f, k, kx, lineBase - f.y(k), out, size, boxes, spanOf);
			k = f.next(k);
		}
	}

	override function get_minWidth():Float {
		if (Math.isNaN(minContent)) minContent = measure == null ? width : measure();
		return minContent;
	}

	// (a text index as a box and its offset, and back)
	function at(i:Int):BoxPosition {
		var k = boxes.length - 1;
		while (k > 0 && starts[k] > i) k--;
		return {box: boxes[k], offset: Std.int(Math.max(0, Math.min(i - starts[k], boxes[k].text.length)))};
	}

	function indexOf(p:Null<BoxPosition>):Int {
		if (p == null) return 0;
		var k = boxes.indexOf(p.box);
		return k < 0 ? (p.offset <= 0 ? 0 : text.length) : starts[k] + p.offset;
	}

	function texts():BoxTexts {
		var id = engine.lay(root, room);
		engine.holdBy(this, id);
		return new BoxTexts(engine.frags(), root);
	}

	override public function caret(i:Int):{x:Float, y:Float, height:Float} {
		var c = texts().caret(at(i));
		return c == null ? {x: 0, y: 0, height: height} : c;
	}

	override public function hit(x:Float, y:Float):Int
		return indexOf(texts().position(x, y));

	// (as DrawText's, TextLayout.decoration: its thickness a tenth of the size, an underline under the baseline, a
	// line-through a third of the ascent over it, an overline over the ascent; trailing spaces not decorated)
	override public function decoration(start:Int, end:Int, kind:TextDecoration, scale:Float, ?thickness:Float, ?offset:Float):Array<{
		x:Float,
		y:Float,
		width:Float,
		height:Float,
		lineWidth:Float
	}> {
		var out = [];
		if (end <= start || faces.length == 0) return out;
		var face = faces[0], sz = size * scale;
		var t = Math.max(1, Math.round(thickness == null || Math.isNaN(thickness) ? sz / 10 : thickness * scale)), ascent = face.ascender * sz / face.unitsPerEm;
		for (r in selection(start, end)) {
			var line:Null<RunLine> = null;
			for (l in lines) if (Math.abs(l.top - r.y) < 1e-6) line = l;
			if (line == null) continue;
			var x0 = r.x, x1 = Math.min(r.x + r.width, line.width);
			if (x1 <= x0) continue;
			var b = Math.round((line.top + line.baseline) * scale);
			var top = switch kind {
				case LineThrough: Math.round(b - ascent / 3 - t / 2);
				case Overline: Math.round(b - ascent - t);
				case _: offset == null || Math.isNaN(offset) ? b + Math.max(1, Math.ceil(t / 2)) : b + Math.round(offset * scale);
			}
			out.push({x: x0, y: top / scale, width: x1 - x0, height: t / scale, lineWidth: line.width});
		}
		return out;
	}

	override public function selection(start:Int, end:Int):Array<{x:Float, y:Float, width:Float}> {
		if (end <= start) return [];
		return [for (r in texts().rects(at(start), at(end))) {x: r.x, y: r.y, width: r.width}];
	}
}

