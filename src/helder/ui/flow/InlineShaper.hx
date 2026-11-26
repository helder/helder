package helder.ui.flow;

import haxe.ds.Vector;
import helder.text.FontFile;
import helder.text.FontSet;
import helder.text.TextLayout;

// The shaped-word cache: a word (a run of text between break opportunities
// in one font, direction and spacing) shaped once and kept by its font's
// number (InlineFonts), direction, letter and word spacing and text, as
// Blink's CachingWordShaper keeps them. TextLayout shapes a word it has not
// seen (helder's shaping, or the platform's for the complex scripts), its
// glyphs copied into flat columns: an entry is its glyphStart to
// glyphStart + glyphCount, in visual order (a right-to-left word's from
// its left), each glyph's cluster its first UTF-16 unit in the word.
// Looked up without allocating: a hash of the key, then the entries' text
// compared in place. Past MAX_GLYPHS it is emptied (generation counts:
// InlineContent shapes again what it shaped before).
class InlineShaper {
	public static final shared = new InlineShaper();
	public static inline var MAX_GLYPHS = 1 << 20;
	public static inline var RTL = 1;

	public var generation(default, null) = 0;
	public var entries(default, null) = 0;
	public var glyphs(default, null) = 0;

	// (entries: the key, then the glyphs and width)
	var eFont = new Vector<Int>(256);
	var eFlags = new Vector<Int>(256);
	var eLetter = new Vector<Float>(256);
	var eWord = new Vector<Float>(256);
	var eHash = new Vector<Int>(256);
	var eText = new Vector<String>(256);
	var eStart = new Vector<Int>(256);
	var eCount = new Vector<Int>(256);
	var eWidth = new Vector<Float>(256);
	// (glyphs)
	var gFace = new Vector<Int>(1024);
	var gId = new Vector<Int>(1024);
	var gAdvance = new Vector<Float>(1024);
	var gDx = new Vector<Float>(1024);
	var gDy = new Vector<Float>(1024);
	var gCluster = new Vector<Int>(1024);
	public final faces:Array<FontFile> = [];
	// (the open-addressed table: an entry + 1, 0 empty)
	var slots = new Vector<Int>(1024);
	var layout:Null<TextLayout> = null;
	var fontGeneration = FontFile.generation;

	public function new() {
		for (i in 0...slots.length)
			slots[i] = 0;
	}

	// the entry of text[start...end] in fonts (InlineFonts' set id), rtl,
	// with letter and word spacing (pixels)
	public function shape(fonts:FontSet, id:Int, text:String, start:Int, end:Int, flags:Int, letter:Float, word:Float):Int {
		if (fontGeneration != FontFile.generation) clear();
		var h = hash(id, flags, letter, word, text, start, end), mask = slots.length - 1, s = h & mask;
		while (true) {
			var e = slots[s] - 1;
			if (e < 0) break;
			if (eHash[e] == h && eFont[e] == id && eFlags[e] == flags && eLetter[e] == letter && eWord[e] == word && same(eText[e], text, start, end)) return e;
			s = (s + 1) & mask;
		}
		if (glyphs > MAX_GLYPHS) {
			clear();
			return shape(fonts, id, text, start, end, flags, letter, word);
		}
		var e = add(fonts, id, text.substring(start, end), flags, letter, word, h);
		slots[s] = e + 1;
		if (entries * 2 > slots.length) rehash();
		return e;
	}

	public inline function glyphStart(e:Int):Int
		return eStart[e];

	public inline function glyphCount(e:Int):Int
		return eCount[e];

	public inline function width(e:Int):Float
		return eWidth[e];

	public inline function font(e:Int):Int
		return eFont[e];

	public inline function rtl(e:Int):Bool
		return eFlags[e] & RTL != 0;

	public inline function face(g:Int):FontFile
		return faces[gFace[g]];

	public inline function faceIndex(g:Int):Int
		return gFace[g];

	public inline function id(g:Int):Int
		return gId[g];

	public inline function advance(g:Int):Float
		return gAdvance[g];

	public inline function dx(g:Int):Float
		return gDx[g];

	public inline function dy(g:Int):Float
		return gDy[g];

	public inline function cluster(g:Int):Int
		return gCluster[g];

	// the advance of the word's units from..to (its clusters there: a
	// ligature's by its characters' equal parts)
	public function advanceOf(e:Int, from:Int, to:Int):Float {
		var s = eStart[e], n = eCount[e], w = 0.0;
		var len = eText[e].length;
		for (g in s...s + n) {
			var c = gCluster[g];
			// (the cluster's end: the next cluster above it, in either direction)
			var next = len;
			for (k in s...s + n)
				if (gCluster[k] > c && gCluster[k] < next) next = gCluster[k];
			var a = gAdvance[g];
			if (c >= from && next <= to) w += a else if (next > from && c < to) {
				var lo = c > from ? c : from, hi = next < to ? next : to;
				w += a * (hi - lo) / (next - c);
			}
		}
		return w;
	}

	public function clear() {
		generation++;
		entries = 0;
		glyphs = 0;
		faces.resize(0);
		for (i in 0...slots.length)
			slots[i] = 0;
		fontGeneration = FontFile.generation;
	}

	static inline function same(a:String, text:String, start:Int, end:Int):Bool {
		if (a.length != end - start) return false;
		var ok = true;
		for (i in 0...a.length)
			if (StringTools.fastCodeAt(a, i) != StringTools.fastCodeAt(text, start + i)) {
				ok = false;
				break;
			}
		return ok;
	}

	// (FNV-1a over the key)
	static function hash(id:Int, flags:Int, letter:Float, word:Float, text:String, start:Int, end:Int):Int {
		var h = 0x811C9DC5;
		inline function mix(v:Int)
			h = (h ^ v) * 0x01000193;
		mix(id);
		mix(flags);
		mix(Std.int(letter * 64));
		mix(Std.int(word * 64));
		for (i in start...end)
			mix(StringTools.fastCodeAt(text, i));
		return h & 0x3FFFFFFF;
	}

	function rehash() {
		var n = slots.length * 2, w = new Vector<Int>(n), mask = n - 1;
		for (i in 0...n)
			w[i] = 0;
		for (e in 0...entries) {
			var s = eHash[e] & mask;
			while (w[s] != 0)
				s = (s + 1) & mask;
			w[s] = e + 1;
		}
		slots = w;
	}

	function add(fonts:FontSet, id:Int, word:String, flags:Int, letter:Float, space:Float, h:Int):Int {
		var base = flags & RTL != 0 ? 1 : 0;
		if (layout == null) layout = new TextLayout(word, fonts, 1, Math.NaN, null, 0, letter, space, base) else layout.reset(word, fonts, 1, Math.NaN, null, 0,
			letter, space, base);
		var l = layout;
		var e = entries++;
		if (e == eFont.length) growEntries();
		var n = l.glyphCount;
		if (glyphs + n > gId.length) growGlyphs(glyphs + n);
		var w = 0.0, at = glyphs;
		for (i in 0...n) {
			var g = at + i, f = l.glyphFont(i);
			var k = faces.indexOf(f);
			if (k < 0) {
				k = faces.length;
				faces.push(f);
			}
			gFace[g] = k;
			gId[g] = l.glyphHidden(i) ? -1 : l.glyphId(i);
			gAdvance[g] = l.glyphAdvance(i);
			gDx[g] = l.glyphOffsetX(i);
			gDy[g] = l.glyphOffsetY(i);
			gCluster[g] = l.glyphCluster(i);
			w += gAdvance[g];
		}
		glyphs += n;
		eFont[e] = id;
		eFlags[e] = flags;
		eLetter[e] = letter;
		eWord[e] = space;
		eHash[e] = h;
		eText[e] = word;
		eStart[e] = at;
		eCount[e] = n;
		eWidth[e] = w;
		return e;
	}

	function growEntries() {
		var n = eFont.length * 2;
		eFont = ints(eFont, n);
		eFlags = ints(eFlags, n);
		eHash = ints(eHash, n);
		eStart = ints(eStart, n);
		eCount = ints(eCount, n);
		eLetter = floats(eLetter, n);
		eWord = floats(eWord, n);
		eWidth = floats(eWidth, n);
		var t = new Vector<String>(n);
		Vector.blit(eText, 0, t, 0, eText.length);
		eText = t;
	}

	function growGlyphs(need:Int) {
		var n = gId.length * 2;
		while (n < need)
			n *= 2;
		gFace = ints(gFace, n);
		gId = ints(gId, n);
		gCluster = ints(gCluster, n);
		gAdvance = floats(gAdvance, n);
		gDx = floats(gDx, n);
		gDy = floats(gDy, n);
	}

	static function ints(v:Vector<Int>, n:Int):Vector<Int> {
		var w = new Vector<Int>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}

	static function floats(v:Vector<Float>, n:Int):Vector<Float> {
		var w = new Vector<Float>(n);
		Vector.blit(v, 0, w, 0, v.length);
		return w;
	}
}
